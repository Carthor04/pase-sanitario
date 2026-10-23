-- Guardias del baño: el docente que está de guardia a esa hora ve "En vivo" mientras dure su
-- turno (menú y lectura del monitor). Las acciones dentro de En vivo siguen dependiendo de su
-- rol. El rol de guardias sale de la hoja "Baños" del horario oficial y se edita en Ajustes.

create table public.bathroom_guards (
  weekday int not null check (weekday between 1 and 5),
  starts time not null,
  ends time not null,
  staff_id uuid references public.staff (id),   -- null = sin asignar
  primary key (weekday, starts),
  check (ends > starts)
);
alter table public.bathroom_guards enable row level security;

-- Cada cambio queda registrado (nada se borra).
create table public.bathroom_guard_changes (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor_id uuid references public.staff (id),
  weekday int not null,
  starts time not null,
  before uuid,
  after uuid
);
alter table public.bathroom_guard_changes enable row level security;

-- ¿Está de guardia esa persona en ese momento (hora de México)?
create function private.on_guard(p_staff uuid, p_at timestamptz default now()) returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_staff is not null and exists (
    select 1 from public.bathroom_guards bg
     where bg.staff_id = p_staff
       and bg.weekday = extract(isodow from p_at at time zone 'America/Mexico_City')::int
       and (p_at at time zone 'America/Mexico_City')::time >= bg.starts
       and (p_at at time zone 'America/Mexico_City')::time < bg.ends);
$$;
revoke all on function private.on_guard(uuid, timestamptz) from public, anon, authenticated;

-- Para Ajustes: las guardias con el nombre del docente.
create function public.bathroom_guards_list() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform private.require_manager();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'weekday', bg.weekday, 'starts', to_char(bg.starts, 'HH24:MI'), 'ends', to_char(bg.ends, 'HH24:MI'),
      'staff_id', bg.staff_id, 'staff_name', s.full_name) order by bg.starts, bg.weekday)
      from public.bathroom_guards bg left join public.staff s on s.id = bg.staff_id), '[]'::jsonb);
end;
$$;

-- Asigna (o deja sin asignar con null) la guardia de un día y hora.
create function public.set_bathroom_guard(p_weekday int, p_starts time, p_staff_id uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_before uuid;
begin
  perform private.require_manager();
  select staff_id into v_before from public.bathroom_guards
   where weekday = p_weekday and starts = p_starts for update;
  if not found then
    raise exception 'No hay guardia ese día a esa hora' using errcode = 'P0002';
  end if;
  if p_staff_id is not null and not exists (select 1 from public.staff where id = p_staff_id and active) then
    raise exception 'Persona no encontrada' using errcode = 'P0002';
  end if;
  if v_before is not distinct from p_staff_id then
    return;
  end if;
  update public.bathroom_guards set staff_id = p_staff_id where weekday = p_weekday and starts = p_starts;
  insert into public.bathroom_guard_changes (actor_id, weekday, starts, before, after)
  values (private.current_staff_id(), p_weekday, p_starts, v_before, p_staff_id);
end;
$$;

-- Importa el rol completo (dia, inicio, fin, correo_maestro opcional) y reemplaza el anterior.
create function public.import_guards(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  v_errors jsonb := '[]';
  v_day int;
  v_start time;
  v_end time;
  v_staff uuid;
  v_email text;
  v_count int := 0;
begin
  perform private.require_manager();
  create temporary table if not exists pg_temp.guards_import (
    weekday int, starts time, ends time, staff_id uuid) on commit drop;
  truncate pg_temp.guards_import;

  for r in select e.value as v, coalesce((e.value ->> '_row')::int, e.ordinality::int + 1) as line
             from jsonb_array_elements(p_rows) with ordinality e loop
    v_day := private.weekday_from_text(r.v ->> 'dia');
    v_start := null; v_end := null; v_staff := null;
    if v_day is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
        format('Día no válido: %s (usa lunes a viernes)', coalesce(private.clean(r.v ->> 'dia'), '(vacío)')));
    end if;
    if coalesce(btrim(r.v ->> 'inicio'), '') ~ '^([01]?\d|2[0-3]):[0-5]\d$'
       and coalesce(btrim(r.v ->> 'fin'), '') ~ '^([01]?\d|2[0-3]):[0-5]\d$'
       and btrim(r.v ->> 'fin')::time > btrim(r.v ->> 'inicio')::time then
      v_start := btrim(r.v ->> 'inicio')::time;
      v_end := btrim(r.v ->> 'fin')::time;
    else
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Las horas deben ir como HH:MM y el fin después del inicio');
    end if;
    v_email := lower(private.clean(r.v ->> 'correo_maestro'));
    if v_email is not null then
      select id into v_staff from public.staff where lower(email) = v_email and active;
      if v_staff is null then
        v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
          format('No hay personal activo con el correo %s', v_email));
      end if;
    end if;
    if v_day is not null and v_start is not null then
      if exists (select 1 from pg_temp.guards_import where weekday = v_day and starts = v_start) then
        v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Esa hora ya tiene guardia en el archivo');
      else
        insert into pg_temp.guards_import values (v_day, v_start, v_end, v_staff);
      end if;
    end if;
  end loop;

  if jsonb_array_length(v_errors) > 0 then
    return jsonb_build_object('ok', false, 'errors', v_errors);
  end if;

  -- Bitácora de lo que cambia, luego se reemplaza el rol completo.
  insert into public.bathroom_guard_changes (actor_id, weekday, starts, before, after)
  select private.current_staff_id(), coalesce(n.weekday, o.weekday), coalesce(n.starts, o.starts),
         o.staff_id, n.staff_id
    from pg_temp.guards_import n
    full join public.bathroom_guards o on o.weekday = n.weekday and o.starts = n.starts
   where o.staff_id is distinct from n.staff_id or o.weekday is null or n.weekday is null;
  delete from public.bathroom_guards;
  insert into public.bathroom_guards select * from pg_temp.guards_import;
  get diagnostics v_count = row_count;
  return jsonb_build_object('ok', true, 'summary', jsonb_build_object(
    'guardias', v_count,
    'sin_asignar', (select count(*) from public.bathroom_guards where staff_id is null)));
end;
$$;

revoke all on function public.bathroom_guards_list() from public, anon;
revoke all on function public.set_bathroom_guard(int, time, uuid) from public, anon;
revoke all on function public.import_guards(jsonb) from public, anon;
grant execute on function public.bathroom_guards_list() to authenticated;
grant execute on function public.set_bathroom_guard(int, time, uuid) to authenticated;
grant execute on function public.import_guards(jsonb) to authenticated;

-- En vivo y el menú: quien está de guardia (desde su cuenta, no la compu del salón) lo ve.

create or replace function public.live_board() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_today date := (now() at time zone 'America/Mexico_City')::date;
begin
  if not (a.device_id is null and private.on_guard(a.staff_id)) then
    perform private.require_role(a, array['prefect', 'nurse', 'coordinator', 'director', 'admin', 'counselor'] || private.tab_roles('en-vivo'));
  end if;
  return jsonb_build_object(
    'now', clock_timestamp(),
    'settings', (select jsonb_build_object('alert_minutes', alert_minutes,
      'escalate_minutes', escalate_minutes, 'confirm_turn_minutes', confirm_turn_minutes)
      from public.settings where id = 1),
    'destinations', (select jsonb_agg(jsonb_build_object('id', d.id, 'label', d.label,
      'kind', d.kind, 'sex', d.sex, 'capacity', d.capacity,
      'paused', private.pause_json(d.id)) order by d.kind, d.sex) from public.destinations d),
    'passes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'student_id', p.student_id, 'list_number', s.list_number,
        'full_name', s.full_name, 'sex', s.sex, 'group_id', p.group_id, 'group_name', g.name,
        'status', p.status, 'destination_id', p.destination_id,
        'requested_at', p.requested_at, 'queue_ts', p.queue_ts, 'called_at', p.called_at,
        'started_at', p.started_at, 'arrived_at', p.arrived_at, 'left_nurse_at', p.left_nurse_at,
        'period_subject', p.period_subject, 'opened_by_name', o.full_name,
        'current_teacher_name', (select r.teacher_name from private.student_room_at(p.student_id, now()) r),
        'alert', private.alert_json(p.id)
      ) order by p.queue_ts nulls last, p.started_at nulls last, p.requested_at)
        from public.passes p
        join public.students s on s.id = p.student_id
        join public.groups g on g.id = p.group_id
        left join public.staff o on o.id = p.opened_by
       where p.status in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning')), '[]'::jsonb),
    'stats', jsonb_build_object(
      'exits_today', (select count(*) from public.passes p
                       where p.started_at is not null
                         and (p.started_at at time zone 'America/Mexico_City')::date = v_today),
      'alerts_today', (select count(*) from public.alerts al
                        where (al.created_at at time zone 'America/Mexico_City')::date = v_today))
  );
end;
$$;

create or replace function public.me() returns jsonb
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
      'tabs', to_jsonb(private.staff_tabs(v_staff.roles)
                       || case when private.on_guard(v_staff.id) then array['en-vivo'] else '{}' end),
      'on_guard', private.on_guard(v_staff.id),
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
