-- Fase 2 · Motor de pases (SPEC §4 y §5).
-- Todas las reglas de cupo y fila viven aquí. Cada operación sobre un baño toma primero
-- el candado de su fila en `destinations` (FOR UPDATE), así dos maestros que piden el
-- último lugar al mismo tiempo quedan en serie: uno sale y el otro queda en fila.
-- Nada se borra: cada cambio de estado escribe en pass_events.
-- Los tiempos de los pases usan clock_timestamp() para que el orden FIFO sea exacto
-- incluso dentro de una misma transacción.

alter table public.settings
  add column unlock_without_class_minutes int not null default 15
    check (unlock_without_class_minutes > 0);

alter table public.device_unlocks drop constraint device_unlocks_lock_reason_check;
alter table public.device_unlocks add constraint device_unlocks_lock_reason_check
  check (lock_reason in ('manual', 'auto', 'pin_change', 'revoked', 'replaced'));

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------
create type public.pass_status as enum
  ('group_wait', 'queued', 'called', 'out', 'arrived', 'returned', 'released', 'cancelled');

create table public.passes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students (id),
  group_id uuid not null references public.groups (id),
  destination_id text not null references public.destinations (id),
  status public.pass_status not null,
  requested_at timestamptz not null default clock_timestamp(),
  queue_ts timestamptz,
  called_at timestamptz,
  started_at timestamptz,
  arrived_at timestamptz,
  ended_at timestamptz,
  opened_by uuid references public.staff (id),
  closed_by uuid references public.staff (id),
  device_id uuid references public.devices (id),
  source text not null default 'manual' check (source in ('manual', 'rfid')),
  period_subject text,
  release_reason text
);
create unique index one_active_pass_per_student on public.passes (student_id)
  where status in ('group_wait', 'queued', 'called', 'out', 'arrived');
create index passes_active_by_destination on public.passes (destination_id, status, queue_ts)
  where status in ('group_wait', 'queued', 'called', 'out', 'arrived');
create index passes_by_group on public.passes (group_id, requested_at desc);

create table public.pass_events (
  id bigserial primary key,
  pass_id uuid not null references public.passes (id),
  type text not null check (type in (
    'requested', 'promoted', 'called', 'confirmed', 'ceded', 'turn_expired',
    'arrived', 'returned', 'released', 'cancelled', 'undo', 'alert', 'escalated')),
  actor_id uuid references public.staff (id),
  device_id uuid references public.devices (id),
  at timestamptz not null default clock_timestamp(),
  payload jsonb not null default '{}'
);
create index pass_events_by_pass on public.pass_events (pass_id, id desc);

alter table public.passes enable row level security;
alter table public.pass_events enable row level security;

-- Lectura: personal y equipos de salón (los nombres siguen protegidos por students).
-- Escritura: solo por las RPC de abajo.
grant select on public.passes to authenticated;
create policy passes_select on public.passes for select to authenticated
  using ((select private.is_member()));

grant select on public.pass_events to authenticated;
create policy pass_events_select on public.pass_events for select to authenticated
  using ((select private.current_staff_id()) is not null);

alter publication supabase_realtime add table public.passes;

-- ---------------------------------------------------------------------------
-- Quién actúa: personal con Google, o el maestro que desbloqueó el equipo de salón.
-- ---------------------------------------------------------------------------
create type private.actor as (staff_id uuid, roles text[], device_id uuid, device_group_id uuid);

create function private.current_actor() returns private.actor
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor;
  v_device public.devices;
begin
  select s.id, s.roles into a.staff_id, a.roles
    from public.staff s where s.auth_user_id = auth.uid() and s.active;
  if found then
    return a;
  end if;

  select * into v_device from public.devices
   where auth_user_id = auth.uid() and revoked_at is null;
  if not found then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;

  select u.staff_id, s.roles into a.staff_id, a.roles
    from public.device_unlocks u join public.staff s on s.id = u.staff_id
   where u.device_id = v_device.id and u.locked_at is null
     and u.expires_at > clock_timestamp() and s.active
   order by u.unlocked_at desc
   limit 1;
  if not found then
    raise exception 'Equipo bloqueado: ingresa tu PIN' using errcode = '42501';
  end if;

  a.device_id := v_device.id;
  a.device_group_id := v_device.group_id;
  return a;
end;
$$;

create function private.require_role(a private.actor, p_roles text[]) returns void
language plpgsql immutable set search_path = ''
as $$
begin
  if not (a.roles && p_roles) then
    raise exception 'No tienes permiso para esta acción' using errcode = '42501';
  end if;
end;
$$;

create function public.current_actor() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
begin
  return jsonb_build_object(
    'staff_id', a.staff_id,
    'full_name', (select full_name from public.staff where id = a.staff_id),
    'device_id', a.device_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Ayudantes del motor
-- ---------------------------------------------------------------------------
create function private.log_pass_event(
  p_pass uuid, p_type text, a private.actor, p_payload jsonb default '{}'
) returns void
language sql security definer set search_path = ''
as $$
  insert into public.pass_events (pass_id, type, actor_id, device_id, payload)
  values (p_pass, p_type, a.staff_id, a.device_id, p_payload);
$$;

-- Lugares ocupados del baño: called reserva lugar (SPEC §4).
create function private.occupancy(p_destination text) returns int
language sql stable security definer set search_path = ''
as $$
  select count(*)::int from public.passes
   where destination_id = p_destination and status in ('called', 'out');
$$;

create function private.has_queue(p_destination text) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.passes where destination_id = p_destination and status = 'queued');
$$;

create function private.has_room(d public.destinations) returns boolean
language sql stable security definer set search_path = ''
as $$
  select d.capacity is null or private.occupancy(d.id) < d.capacity;
$$;

create function private.group_slot_taken(d public.destinations, p_group uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select d.uses_group_slot and d.per_group_limit is not null and (
    select count(*) from public.passes
     where destination_id = d.id and group_id = p_group
       and status in ('queued', 'called', 'out')) >= d.per_group_limit;
$$;

create function private.pass_json(p_pass uuid) returns jsonb
language sql stable security definer set search_path = ''
as $$
  select to_jsonb(p) || jsonb_build_object(
    'queue_position', case when p.status = 'queued' then (
      select count(*) from public.passes q
       where q.destination_id = p.destination_id and q.status = 'queued'
         and (q.queue_ts, q.requested_at) <= (p.queue_ts, p.requested_at)) end)
    from public.passes p where p.id = p_pass;
$$;

-- Bloquea el destino del pase y luego el pase (mismo orden que request_pass) y valida
-- que un equipo de salón solo opere pases de su grupo.
create function private.lock_pass(p_pass uuid, a private.actor) returns public.passes
language plpgsql security definer set search_path = ''
as $$
declare
  v_dest text;
  v_pass public.passes;
begin
  select destination_id into v_dest from public.passes where id = p_pass;
  if v_dest is null then
    raise exception 'Pase no encontrado' using errcode = 'P0002';
  end if;
  perform 1 from public.destinations where id = v_dest for update;
  select * into v_pass from public.passes where id = p_pass for update;
  if a.device_group_id is not null and v_pass.group_id <> a.device_group_id then
    raise exception 'Este equipo solo opera pases de su grupo' using errcode = '42501';
  end if;
  return v_pass;
end;
$$;

-- Manda un pase "called" al segundo lugar de la fila (detrás del siguiente).
-- Devuelve false si no hay nadie más formado.
create function private.send_to_second_place(v_pass public.passes) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_next_ts timestamptz;
begin
  select queue_ts into v_next_ts from public.passes
   where destination_id = v_pass.destination_id and status = 'queued' and id <> v_pass.id
   order by queue_ts, requested_at
   limit 1;
  if v_next_ts is null then
    return false;
  end if;
  update public.passes
     set status = 'queued', called_at = null, queue_ts = v_next_ts + interval '1 microsecond'
   where id = v_pass.id;
  return true;
end;
$$;

-- advance (SPEC §4): promueve group_wait y llama a la fila mientras haya lugar.
-- Quien la llama ya tiene el candado del destino.
create function private.advance(p_destination text, a private.actor) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  d public.destinations;
  r record;
  v_changed boolean;
  v_next uuid;
begin
  select * into d from public.destinations where id = p_destination;
  if d.kind <> 'bathroom' then
    return;
  end if;

  -- 1. El group_wait más antiguo de cada grupo con lugar libre pasa a la fila (al final)
  --    o sale directo si hay lugar y nadie está formado.
  loop
    v_changed := false;
    for r in
      select distinct on (p.group_id) p.id, p.group_id
        from public.passes p
       where p.destination_id = d.id and p.status = 'group_wait'
       order by p.group_id, p.requested_at
    loop
      continue when private.group_slot_taken(d, r.group_id);
      if private.has_room(d) and not private.has_queue(d.id) then
        update public.passes set status = 'out', started_at = clock_timestamp() where id = r.id;
        perform private.log_pass_event(r.id, 'promoted', a, '{"to":"out"}');
      else
        update public.passes set status = 'queued', queue_ts = clock_timestamp() where id = r.id;
        perform private.log_pass_event(r.id, 'promoted', a, '{"to":"queued"}');
      end if;
      v_changed := true;
    end loop;
    exit when not v_changed;
  end loop;

  -- 2. Mientras haya lugar, el primero de la fila pasa a "called".
  loop
    exit when not private.has_room(d);
    select id into v_next from public.passes
     where destination_id = d.id and status = 'queued'
     order by queue_ts, requested_at
     limit 1;
    exit when v_next is null;
    update public.passes set status = 'called', called_at = clock_timestamp() where id = v_next;
    perform private.log_pass_event(v_next, 'called', a);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC de pases
-- ---------------------------------------------------------------------------
create function public.request_pass(p_student_id uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  st public.students;
  d public.destinations;
  v_status public.pass_status;
  v_id uuid;
begin
  perform private.require_role(a, array['teacher', 'coordinator', 'admin']);

  select * into st from public.students where id = p_student_id and active;
  if not found then
    raise exception 'Alumno no encontrado' using errcode = 'P0002';
  end if;
  if a.device_group_id is not null and st.group_id <> a.device_group_id then
    raise exception 'Este equipo solo opera pases de su grupo' using errcode = '42501';
  end if;

  if p_kind = 'bathroom' then
    select * into d from public.destinations
     where kind = 'bathroom' and sex = st.sex order by id limit 1 for update;
  elsif p_kind = 'nurse' then
    select * into d from public.destinations where kind = 'nurse' order by id limit 1 for update;
  else
    raise exception 'Tipo de pase no válido: usa bathroom o nurse' using errcode = '22023';
  end if;
  if not found then
    raise exception 'No hay destino configurado para este pase' using errcode = 'P0002';
  end if;

  if exists (select 1 from public.passes where student_id = st.id
              and status in ('group_wait', 'queued', 'called', 'out', 'arrived')) then
    raise exception 'El alumno ya tiene un pase activo' using errcode = 'P0001';
  end if;

  if private.group_slot_taken(d, st.group_id) then
    v_status := 'group_wait';
  elsif private.has_room(d) and not private.has_queue(d.id) then
    v_status := 'out';
  elsif d.queue_enabled then
    v_status := 'queued';
  else
    raise exception '% está lleno', d.label using errcode = 'P0001';
  end if;

  begin
    insert into public.passes (
      student_id, group_id, destination_id, status, requested_at, queue_ts, started_at,
      opened_by, device_id, period_subject)
    values (
      st.id, st.group_id, d.id, v_status, clock_timestamp(),
      case when v_status = 'queued' then clock_timestamp() end,
      case when v_status = 'out' then clock_timestamp() end,
      a.staff_id, a.device_id,
      (select c.subject from public.classes_at(now()) c where c.group_id = st.group_id limit 1))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'El alumno ya tiene un pase activo' using errcode = 'P0001';
  end;

  perform private.log_pass_event(v_id, 'requested', a, jsonb_build_object('status', v_status));
  return private.pass_json(v_id);
end;
$$;

create function public.confirm_turn(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
begin
  perform private.require_role(a, array['teacher', 'coordinator', 'admin']);
  p := private.lock_pass(p_pass_id, a);
  if p.status <> 'called' then
    raise exception 'Ese pase ya no está esperando confirmación' using errcode = 'P0001';
  end if;
  update public.passes set status = 'out', started_at = clock_timestamp() where id = p.id;
  perform private.log_pass_event(p.id, 'confirmed', a);
  return private.pass_json(p.id);
end;
$$;

create function public.cede_turn(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
begin
  perform private.require_role(a, array['teacher', 'coordinator', 'admin']);
  p := private.lock_pass(p_pass_id, a);
  if p.status <> 'called' then
    raise exception 'Ese pase ya no está esperando confirmación' using errcode = 'P0001';
  end if;
  if not private.send_to_second_place(p) then
    raise exception 'Nadie más en fila: no se puede ceder el turno' using errcode = 'P0001';
  end if;
  perform private.log_pass_event(p.id, 'ceded', a);
  perform private.advance(p.destination_id, a);
  return private.pass_json(p.id);
end;
$$;

create function public.mark_returned(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
  v_kind text;
begin
  perform private.require_role(a, array['teacher', 'coordinator', 'admin', 'prefect', 'nurse']);
  p := private.lock_pass(p_pass_id, a);
  select kind into v_kind from public.destinations where id = p.destination_id;
  if v_kind <> 'nurse' and not (a.roles && array['teacher', 'coordinator', 'admin', 'prefect']) then
    raise exception 'No tienes permiso para esta acción' using errcode = '42501';
  end if;
  if p.status not in ('out', 'arrived') then
    raise exception 'Ese alumno no está fuera' using errcode = 'P0001';
  end if;
  update public.passes
     set status = 'returned', ended_at = clock_timestamp(), closed_by = a.staff_id
   where id = p.id;
  perform private.log_pass_event(p.id, 'returned', a, jsonb_build_object('from', p.status));
  perform private.advance(p.destination_id, a);
  return private.pass_json(p.id);
end;
$$;

create function public.mark_arrived(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
begin
  perform private.require_role(a, array['nurse', 'coordinator', 'admin']);
  p := private.lock_pass(p_pass_id, a);
  if (select kind from public.destinations where id = p.destination_id) <> 'nurse' then
    raise exception 'Solo los pases de enfermería se marcan como "Llegó"' using errcode = 'P0001';
  end if;
  if p.status <> 'out' then
    raise exception 'Ese alumno no va en camino a enfermería' using errcode = 'P0001';
  end if;
  update public.passes set status = 'arrived', arrived_at = clock_timestamp() where id = p.id;
  perform private.log_pass_event(p.id, 'arrived', a);
  return private.pass_json(p.id);
end;
$$;

create function public.release_pass(p_pass_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  perform private.require_role(a, array['prefect', 'coordinator', 'admin']);
  if v_reason is null then
    raise exception 'Escribe el motivo para liberar el lugar' using errcode = '22023';
  end if;
  p := private.lock_pass(p_pass_id, a);
  if p.status not in ('group_wait', 'queued', 'called', 'out', 'arrived') then
    raise exception 'Ese pase ya está cerrado' using errcode = 'P0001';
  end if;
  update public.passes
     set status = 'released', ended_at = clock_timestamp(), closed_by = a.staff_id,
         release_reason = v_reason
   where id = p.id;
  perform private.log_pass_event(p.id, 'released', a,
    jsonb_build_object('from', p.status, 'reason', v_reason));
  perform private.advance(p.destination_id, a);
  return private.pass_json(p.id);
end;
$$;

create function public.cancel_pass(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
begin
  perform private.require_role(a, array['teacher', 'coordinator', 'admin']);
  p := private.lock_pass(p_pass_id, a);
  if p.status not in ('group_wait', 'queued', 'called') then
    raise exception 'Solo se cancela un pase antes de que el alumno salga' using errcode = 'P0001';
  end if;
  update public.passes
     set status = 'cancelled', ended_at = clock_timestamp(), closed_by = a.staff_id
   where id = p.id;
  perform private.log_pass_event(p.id, 'cancelled', a, jsonb_build_object('from', p.status));
  perform private.advance(p.destination_id, a);
  return private.pass_json(p.id);
end;
$$;

-- Deshacer (SPEC §4): solo "abrir pase" o "marcar regreso", dentro de undo_seconds y por
-- la misma persona. Es un evento nuevo, no un DELETE.
create function public.undo_last(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
  ev public.pass_events;
  v_seconds int;
begin
  perform private.require_role(a, array['teacher', 'coordinator', 'admin', 'prefect', 'nurse']);
  p := private.lock_pass(p_pass_id, a);
  select * into ev from public.pass_events where pass_id = p.id order by id desc limit 1;
  select undo_seconds into v_seconds from public.settings where id = 1;

  if ev.type is null or ev.type not in ('requested', 'returned') then
    raise exception 'No hay nada que deshacer en este pase' using errcode = 'P0001';
  end if;
  if ev.at < clock_timestamp() - make_interval(secs => v_seconds) then
    raise exception 'Ya pasó el tiempo para deshacer' using errcode = 'P0001';
  end if;
  if ev.actor_id is distinct from a.staff_id then
    raise exception 'Solo quien hizo el cambio puede deshacerlo' using errcode = '42501';
  end if;

  if ev.type = 'requested' then
    update public.passes
       set status = 'cancelled', ended_at = clock_timestamp(), closed_by = a.staff_id
     where id = p.id;
  else
    -- Se deshace solo el regreso; quien ya fue llamado conserva su turno (decisión 2026-10-15).
    begin
      update public.passes
         set status = (ev.payload ->> 'from')::public.pass_status, ended_at = null, closed_by = null
       where id = p.id;
    exception when unique_violation then
      raise exception 'El alumno ya tiene otro pase activo' using errcode = 'P0001';
    end;
  end if;

  perform private.log_pass_event(p.id, 'undo', a,
    jsonb_build_object('undone_event_id', ev.id, 'undone_type', ev.type));
  perform private.advance(p.destination_id, a);
  return private.pass_json(p.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Desbloqueo de la computadora del salón con PIN (SPEC §5)
-- ---------------------------------------------------------------------------
create function public.unlock_device(p_pin text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_device public.devices;
  s public.settings;
  v_last_ok timestamptz;
  v_fails int;
  v_last_fail timestamptz;
  v_staff public.staff;
  v_ends time;
  v_expires timestamptz;
  v_local timestamp := now() at time zone 'America/Mexico_City';
begin
  select * into v_device from public.devices where auth_user_id = auth.uid() and revoked_at is null;
  if not found then
    raise exception 'Solo la computadora del salón se desbloquea con PIN' using errcode = '42501';
  end if;
  select * into s from public.settings where id = 1;

  -- Cada pin_max_attempts fallos seguidos bloquean el equipo pin_lockout_seconds.
  select max(at) into v_last_ok from public.security_attempts
   where kind = 'unlock' and device_id = v_device.id and ok;
  select count(*), max(at) into v_fails, v_last_fail from public.security_attempts
   where kind = 'unlock' and device_id = v_device.id and not ok
     and at > coalesce(v_last_ok, '-infinity') and at > clock_timestamp() - interval '1 hour';
  if v_fails > 0 and v_fails % s.pin_max_attempts = 0
     and v_last_fail > clock_timestamp() - make_interval(secs => s.pin_lockout_seconds) then
    return jsonb_build_object('ok', false, 'error', 'locked',
      'retry_after', v_last_fail + make_interval(secs => s.pin_lockout_seconds));
  end if;

  if p_pin ~ '^\d{4}$' then
    select st.* into v_staff
      from public.staff st join public.staff_pins sp on sp.staff_id = st.id
     where st.active and sp.pin_hash = extensions.crypt(p_pin, sp.pin_hash)
     limit 1;
  end if;

  if v_staff.id is null then
    insert into public.security_attempts (kind, auth_user_id, device_id, ok, at)
    values ('unlock', auth.uid(), v_device.id, false, clock_timestamp());
    v_fails := v_fails + 1;
    if v_fails % s.pin_max_attempts = 0 then
      return jsonb_build_object('ok', false, 'error', 'locked',
        'retry_after', clock_timestamp() + make_interval(secs => s.pin_lockout_seconds));
    end if;
    return jsonb_build_object('ok', false, 'error', 'wrong_pin',
      'attempts_left', s.pin_max_attempts - v_fails % s.pin_max_attempts);
  end if;

  insert into public.security_attempts (kind, auth_user_id, device_id, ok, at)
  values ('unlock', auth.uid(), v_device.id, true, clock_timestamp());

  update public.device_unlocks
     set locked_at = clock_timestamp(), lock_reason = 'replaced'
   where device_id = v_device.id and locked_at is null;

  -- Vence al terminar la clase actual + auto_lock_after_class_minutes.
  select c.ends into v_ends from public.classes_at(now()) c where c.group_id = v_device.group_id limit 1;
  if v_ends is not null then
    v_expires := ((v_local::date + v_ends) at time zone 'America/Mexico_City')
                 + make_interval(mins => s.auto_lock_after_class_minutes);
  else
    v_expires := clock_timestamp() + make_interval(mins => s.unlock_without_class_minutes);
  end if;

  insert into public.device_unlocks (device_id, staff_id, unlocked_at, expires_at)
  values (v_device.id, v_staff.id, clock_timestamp(), v_expires);
  update public.devices set last_seen_at = now() where id = v_device.id;

  return jsonb_build_object('ok', true, 'staff_id', v_staff.id,
    'full_name', v_staff.full_name, 'expires_at', v_expires);
end;
$$;

create function public.lock_device() returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_device uuid := private.current_device_id();
begin
  if v_device is null then
    raise exception 'Solo la computadora del salón se bloquea' using errcode = '42501';
  end if;
  update public.device_unlocks
     set locked_at = clock_timestamp(), lock_reason = 'manual'
   where device_id = v_device and locked_at is null;
end;
$$;

-- ---------------------------------------------------------------------------
-- tick(): lo corre pg_cron cada minuto. Vence turnos y registra autobloqueos.
-- (Las alertas de 10 min llegan en la Fase 4.)
-- ---------------------------------------------------------------------------
create function private.tick() returns void
language plpgsql security definer set search_path = ''
as $$
declare
  d record;
  p public.passes;
  v_minutes int;
  v_system private.actor;  -- todo en null: lo hizo el sistema
begin
  select confirm_turn_minutes into v_minutes from public.settings where id = 1;

  for d in select id from public.destinations where kind = 'bathroom' order by id loop
    perform 1 from public.destinations where id = d.id for update;
    for p in
      select * from public.passes
       where destination_id = d.id and status = 'called'
         and called_at < clock_timestamp() - make_interval(mins => v_minutes)
       order by called_at
    loop
      -- Si no hay nadie más formado, sigue siendo su turno (decisión 2026-10-15).
      if private.send_to_second_place(p) then
        perform private.log_pass_event(p.id, 'turn_expired', v_system);
      end if;
    end loop;
    perform private.advance(d.id, v_system);
  end loop;

  update public.device_unlocks
     set locked_at = expires_at, lock_reason = 'auto'
   where locked_at is null and expires_at <= clock_timestamp();
end;
$$;

create extension if not exists pg_cron;
select cron.schedule('pase-tick', '* * * * *', 'select private.tick()');

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public, anon, authenticated;
-- Los ayudantes de RLS de la Fase 1 sí los usan las políticas como authenticated.
grant execute on function private.current_staff_id() to authenticated;
grant execute on function private.has_any_role(text[]) to authenticated;
grant execute on function private.can_manage() to authenticated;
grant execute on function private.current_device_id() to authenticated;
grant execute on function private.current_device_group_id() to authenticated;
grant execute on function private.is_member() to authenticated;
grant execute on function private.require_manager() to authenticated;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.current_actor()', 'public.request_pass(uuid, text)', 'public.confirm_turn(uuid)',
    'public.cede_turn(uuid)', 'public.mark_returned(uuid)', 'public.mark_arrived(uuid)',
    'public.release_pass(uuid, text)', 'public.cancel_pass(uuid)', 'public.undo_last(uuid)',
    'public.unlock_device(text)', 'public.lock_device()']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
