-- Fase 1 · Funciones de acceso: me(), PIN, vinculación de equipos y clase actual.
-- Las funciones que pueden "fallar" por una regla (PIN repetido, código inválido)
-- devuelven {ok:false, error} en lugar de lanzar excepción: así el intento queda
-- registrado en security_attempts y el límite de intentos funciona.

-- ---------------------------------------------------------------------------
-- me(): quién soy. La app decide la pantalla con esto.
-- ---------------------------------------------------------------------------
create function public.me() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_staff public.staff;
  v_device record;
  v_email text := auth.jwt() ->> 'email';
  v_anon boolean := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
begin
  if auth.uid() is null then
    return jsonb_build_object('kind', 'none');
  end if;

  select * into v_staff from public.staff where auth_user_id = auth.uid();
  if not found and not v_anon and v_email is not null then
    -- Usuario que ya existía en auth antes de darlo de alta en staff.
    update public.staff set auth_user_id = auth.uid()
     where lower(email) = lower(v_email) and auth_user_id is null
    returning * into v_staff;
  end if;

  if v_staff.id is not null and v_staff.active then
    return jsonb_build_object(
      'kind', 'staff',
      'id', v_staff.id,
      'full_name', v_staff.full_name,
      'email', v_staff.email,
      'roles', to_jsonb(v_staff.roles),
      'has_pin', v_staff.pin_set_at is not null
    );
  end if;

  select d.id, d.label, d.group_id, g.name as group_name
    into v_device
    from public.devices d join public.groups g on g.id = d.group_id
   where d.auth_user_id = auth.uid() and d.revoked_at is null;
  if found then
    update public.devices set last_seen_at = now() where id = v_device.id;
    return jsonb_build_object(
      'kind', 'device',
      'id', v_device.id,
      'label', v_device.label,
      'group_id', v_device.group_id,
      'group_name', v_device.group_name
    );
  end if;

  return jsonb_build_object('kind', 'none', 'email', v_email, 'anonymous', v_anon);
end;
$$;

-- ---------------------------------------------------------------------------
-- PIN de 4 dígitos, único entre el personal activo (SPEC §5, decisión 2026-10-15).
-- ---------------------------------------------------------------------------
create function private.set_pin(p_staff_id uuid, p_pin text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_window interval := interval '15 minutes';
  v_max int;
  v_rejected int;
begin
  select pin_max_attempts into v_max from public.settings where id = 1;

  select count(*) into v_rejected
    from public.security_attempts
   where kind = 'set_pin' and auth_user_id = auth.uid() and not ok and at > now() - v_window;
  if v_rejected >= v_max then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;

  if p_pin is null or p_pin !~ '^\d{4}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;

  if not exists (select 1 from public.staff where id = p_staff_id and active) then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;

  -- Serializa los cambios de PIN para que dos personas no elijan el mismo a la vez.
  perform pg_advisory_xact_lock(hashtext('public.staff_pins'));

  if exists (
    select 1
      from public.staff_pins p join public.staff s on s.id = p.staff_id
     where s.active and s.id <> p_staff_id
       and p.pin_hash = extensions.crypt(p_pin, p.pin_hash)
  ) then
    insert into public.security_attempts (kind, auth_user_id, ok) values ('set_pin', auth.uid(), false);
    return jsonb_build_object('ok', false, 'error', 'taken');
  end if;

  insert into public.staff_pins (staff_id, pin_hash, updated_at)
  values (p_staff_id, extensions.crypt(p_pin, extensions.gen_salt('bf', 8)), now())
  on conflict (staff_id) do update set pin_hash = excluded.pin_hash, updated_at = now();

  update public.staff set pin_set_at = now() where id = p_staff_id;

  -- Un PIN nuevo cierra los equipos que esa persona tenga desbloqueados.
  update public.device_unlocks
     set locked_at = now(), lock_reason = 'pin_change'
   where staff_id = p_staff_id and locked_at is null and expires_at > now();

  insert into public.security_attempts (kind, auth_user_id, ok) values ('set_pin', auth.uid(), true);
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function private.set_pin(uuid, text) from public, anon, authenticated;

create function public.set_my_pin(p_pin text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_staff uuid := private.current_staff_id();
begin
  if v_staff is null then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  return private.set_pin(v_staff, p_pin);
end;
$$;

create function public.set_staff_pin(p_staff_id uuid, p_pin text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  if not private.can_manage() then
    raise exception 'Solo coordinación, dirección o admin' using errcode = '42501';
  end if;
  return private.set_pin(p_staff_id, p_pin);
end;
$$;

create function public.clear_staff_pin(p_staff_id uuid) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not private.can_manage() then
    raise exception 'Solo coordinación, dirección o admin' using errcode = '42501';
  end if;
  delete from public.staff_pins where staff_id = p_staff_id;
  update public.staff set pin_set_at = null where id = p_staff_id;
  update public.device_unlocks
     set locked_at = now(), lock_reason = 'pin_change'
   where staff_id = p_staff_id and locked_at is null and expires_at > now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Vinculación de equipos de salón (código de 6 dígitos)
-- ---------------------------------------------------------------------------
create function public.create_device_pairing(p_group_id uuid, p_label text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_code text;
  v_expires timestamptz;
  v_minutes int;
begin
  if not private.can_manage() then
    raise exception 'Solo coordinación, dirección o admin' using errcode = '42501';
  end if;
  if not exists (select 1 from public.groups where id = p_group_id) then
    raise exception 'Grupo no encontrado' using errcode = 'P0002';
  end if;

  select pairing_code_minutes into v_minutes from public.settings where id = 1;
  v_expires := now() + make_interval(mins => v_minutes);

  loop
    v_code := lpad(
      ((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text,
      6, '0');
    exit when not exists (
      select 1 from public.device_pairings
       where code = v_code and claimed_at is null and expires_at > now()
    );
  end loop;

  insert into public.device_pairings (code, group_id, label, created_by, expires_at)
  values (v_code, p_group_id, nullif(btrim(p_label), ''), private.current_staff_id(), v_expires);

  return jsonb_build_object('code', v_code, 'expires_at', v_expires);
end;
$$;

-- La llama la computadora del salón, ya con sesión anónima.
create function public.claim_device_pairing(p_code text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_anon boolean := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
  v_pairing public.device_pairings;
  v_device_id uuid;
  v_group_name text;
begin
  if auth.uid() is null or not v_anon then
    return jsonb_build_object('ok', false, 'error', 'not_anonymous');
  end if;

  -- Límite por equipo (5 fallos en 10 min) y global (30 fallos por minuto).
  if (select count(*) from public.security_attempts
       where kind = 'pair_device' and auth_user_id = auth.uid() and not ok
         and at > now() - interval '10 minutes') >= 5
     or (select count(*) from public.security_attempts
          where kind = 'pair_device' and not ok and at > now() - interval '1 minute') >= 30
  then
    return jsonb_build_object('ok', false, 'error', 'rate_limited');
  end if;

  if exists (select 1 from public.devices where auth_user_id = auth.uid() and revoked_at is null) then
    return jsonb_build_object('ok', false, 'error', 'already_linked');
  end if;

  select * into v_pairing
    from public.device_pairings
   where code = btrim(p_code) and claimed_at is null and expires_at > now()
   order by created_at desc
   limit 1
   for update;

  if not found then
    insert into public.security_attempts (kind, auth_user_id, ok) values ('pair_device', auth.uid(), false);
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;

  insert into public.devices (group_id, label, auth_user_id, created_by, last_seen_at)
  values (v_pairing.group_id, v_pairing.label, auth.uid(), v_pairing.created_by, now())
  returning id into v_device_id;

  update public.device_pairings set claimed_at = now(), device_id = v_device_id where id = v_pairing.id;
  insert into public.security_attempts (kind, auth_user_id, device_id, ok)
  values ('pair_device', auth.uid(), v_device_id, true);

  select name into v_group_name from public.groups where id = v_pairing.group_id;
  return jsonb_build_object(
    'ok', true,
    'device', jsonb_build_object(
      'id', v_device_id, 'label', v_pairing.label,
      'group_id', v_pairing.group_id, 'group_name', v_group_name));
end;
$$;

create function public.revoke_device(p_device_id uuid) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not private.can_manage() then
    raise exception 'Solo coordinación, dirección o admin' using errcode = '42501';
  end if;
  update public.devices set revoked_at = now() where id = p_device_id and revoked_at is null;
  update public.device_unlocks
     set locked_at = now(), lock_reason = 'revoked'
   where device_id = p_device_id and locked_at is null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Clase actual según el horario (hora de México)
-- ---------------------------------------------------------------------------
create function public.classes_at(p_at timestamptz)
returns table (
  group_id uuid,
  period_id uuid,
  subject text,
  teacher_id uuid,
  teacher_name text,
  starts time,
  ends time
)
language sql stable security invoker set search_path = ''
as $$
  select se.group_id, p.id, se.subject, se.teacher_id, s.full_name, p.starts, p.ends
    from public.schedule_entries se
    join public.periods p on p.id = se.period_id
    left join public.staff s on s.id = se.teacher_id
   where p.weekday = extract(isodow from (p_at at time zone 'America/Mexico_City'))::int
     and (p_at at time zone 'America/Mexico_City')::time >= p.starts
     and (p_at at time zone 'America/Mexico_City')::time < p.ends;
$$;

create view public.v_current_class with (security_invoker = true) as
select g.id as group_id, g.name as group_name, c.period_id, c.subject, c.teacher_id,
       c.teacher_name, c.starts, c.ends
  from public.groups g
  join public.classes_at(now()) c on c.group_id = g.id;

grant select on public.v_current_class to authenticated;

-- Grupos para el selector del celular (SPEC §6): primero el de la hora actual,
-- luego los que imparte la persona y después todos los demás.
create function public.my_groups(p_at timestamptz default now())
returns table (
  group_id uuid,
  name text,
  room text,
  rank int,
  subject text,
  teacher_name text,
  starts time,
  ends time
)
language sql stable security invoker set search_path = ''
as $$
  with me as (select private.current_staff_id() as id),
  taught as (
    select distinct se.group_id from public.schedule_entries se
     where se.teacher_id = (select id from me)
  ),
  now_class as (select * from public.classes_at(p_at))
  select g.id, g.name, g.room,
         case
           when nc.teacher_id is not null and nc.teacher_id = (select id from me) then 0
           when t.group_id is not null then 1
           else 2
         end as rank,
         nc.subject, nc.teacher_name, nc.starts, nc.ends
    from public.groups g
    left join now_class nc on nc.group_id = g.id
    left join taught t on t.group_id = g.id
   order by rank, g.sort nulls last, g.name;
$$;

-- ---------------------------------------------------------------------------
-- Permisos: nada para anon; las RPC públicas solo para authenticated.
-- ---------------------------------------------------------------------------
revoke all on function public.me() from public, anon;
revoke all on function public.set_my_pin(text) from public, anon;
revoke all on function public.set_staff_pin(uuid, text) from public, anon;
revoke all on function public.clear_staff_pin(uuid) from public, anon;
revoke all on function public.create_device_pairing(uuid, text) from public, anon;
revoke all on function public.claim_device_pairing(text) from public, anon;
revoke all on function public.revoke_device(uuid) from public, anon;
revoke all on function public.classes_at(timestamptz) from public, anon;
revoke all on function public.my_groups(timestamptz) from public, anon;

grant execute on function public.me() to authenticated;
grant execute on function public.set_my_pin(text) to authenticated;
grant execute on function public.set_staff_pin(uuid, text) to authenticated;
grant execute on function public.clear_staff_pin(uuid) to authenticated;
grant execute on function public.create_device_pairing(uuid, text) to authenticated;
grant execute on function public.claim_device_pairing(text) to authenticated;
grant execute on function public.revoke_device(uuid) to authenticated;
grant execute on function public.classes_at(timestamptz) to authenticated;
grant execute on function public.my_groups(timestamptz) to authenticated;
