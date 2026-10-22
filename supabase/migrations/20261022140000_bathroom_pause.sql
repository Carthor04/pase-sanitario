-- Pausar un baño (limpieza u otro motivo): mientras está en pausa no se piden pases a ese
-- baño, nadie avanza en la fila, no se confirma turno ni se autoriza la salida, y el tiempo
-- para confirmar turno no corre. Quien ya está dentro sigue con su cronómetro y su alerta.
-- Al reanudar, la fila sigue en el mismo orden. Cada pausa queda en bathroom_pauses.

create table public.bathroom_pauses (
  id bigint generated always as identity primary key,
  destination_id text not null references public.destinations (id),
  paused_at timestamptz not null default clock_timestamp(),
  paused_by uuid references public.staff (id),
  reason text,
  resumed_at timestamptz,
  resumed_by uuid references public.staff (id)
);
create unique index bathroom_pauses_open on public.bathroom_pauses (destination_id)
  where resumed_at is null;
alter table public.bathroom_pauses enable row level security;

-- Lectura para personal y equipos de salón (para que Realtime avise al pausar o reanudar).
-- Escritura: solo por las RPC de abajo.
grant select on public.bathroom_pauses to authenticated;
create policy bathroom_pauses_select on public.bathroom_pauses for select to authenticated
  using ((select private.is_member()));
alter publication supabase_realtime add table public.bathroom_pauses;

-- Desde cuándo está en pausa (null si no lo está).
create function private.paused_since(p_destination text) returns timestamptz
language sql stable security definer set search_path = ''
as $$
  select paused_at from public.bathroom_pauses
   where destination_id = p_destination and resumed_at is null;
$$;

-- Última vez que se reanudó (el tiempo para confirmar turno cuenta desde ahí).
create function private.last_resume(p_destination text) returns timestamptz
language sql stable security definer set search_path = ''
as $$
  select max(resumed_at) from public.bathroom_pauses where destination_id = p_destination;
$$;

-- Para las pantallas: desde cuándo, quién y por qué; null si no está en pausa.
create function private.pause_json(p_destination text) returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('since', bp.paused_at, 'by', s.full_name, 'reason', bp.reason)
    from public.bathroom_pauses bp left join public.staff s on s.id = bp.paused_by
   where bp.destination_id = p_destination and bp.resumed_at is null;
$$;

-- Error para quien intenta mover la fila de un baño en pausa.
create function private.require_not_paused(p_destination text) returns void
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_label text;
  v_reason text;
begin
  select d.label, bp.reason into v_label, v_reason
    from public.bathroom_pauses bp join public.destinations d on d.id = bp.destination_id
   where bp.destination_id = p_destination and bp.resumed_at is null;
  if found then
    raise exception '% está en pausa%. Intenta cuando se reanude.',
      v_label, coalesce(' (' || v_reason || ')', '') using errcode = 'P0001';
  end if;
end;
$$;
revoke all on function private.paused_since(text) from public, anon, authenticated;
revoke all on function private.last_resume(text) from public, anon, authenticated;
revoke all on function private.pause_json(text) from public, anon, authenticated;
revoke all on function private.require_not_paused(text) from public, anon, authenticated;

create function public.pause_bathroom(p_destination text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  d public.destinations;
begin
  perform private.require_role(a, array['teacher', 'prefect', 'coordinator', 'director', 'admin']);
  select * into d from public.destinations where id = p_destination for update;
  if not found or d.kind <> 'bathroom' then
    raise exception 'Solo se pausan los baños' using errcode = '22023';
  end if;
  if private.paused_since(d.id) is not null then
    raise exception '% ya está en pausa', d.label using errcode = 'P0001';
  end if;
  insert into public.bathroom_pauses (destination_id, paused_by, reason)
  values (d.id, a.staff_id, nullif(btrim(left(p_reason, 120)), ''));
  return private.pause_json(d.id);
end;
$$;

create function public.resume_bathroom(p_destination text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  d public.destinations;
begin
  perform private.require_role(a, array['teacher', 'prefect', 'coordinator', 'director', 'admin']);
  select * into d from public.destinations where id = p_destination for update;
  if not found or d.kind <> 'bathroom' then
    raise exception 'Solo se pausan los baños' using errcode = '22023';
  end if;
  update public.bathroom_pauses
     set resumed_at = clock_timestamp(), resumed_by = a.staff_id
   where destination_id = d.id and resumed_at is null;
  if not found then
    raise exception '% no está en pausa', d.label using errcode = 'P0001';
  end if;
  -- Avanza la fila con los lugares que se liberaron durante la pausa.
  perform private.advance(d.id, a);
end;
$$;

revoke all on function public.pause_bathroom(text, text) from public, anon;
revoke all on function public.resume_bathroom(text) from public, anon;
grant execute on function public.pause_bathroom(text, text) to authenticated;
grant execute on function public.resume_bathroom(text) to authenticated;

-- Motor y pantallas: lo mismo de antes más la pausa.

create or replace function private.advance(p_destination text, a private.actor) returns void
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
  -- En pausa: la fila no avanza hasta que se reanude.
  if private.paused_since(d.id) is not null then
    return;
  end if;

  -- 1. El group_wait más antiguo de cada salón con lugar libre pasa a la fila (al final)
  --    o sale directo si hay lugar y nadie está formado.
  loop
    v_changed := false;
    for r in
      select distinct on (coalesce(p.room_group_id, p.group_id)) p.id,
             coalesce(p.room_group_id, p.group_id) as slot
        from public.passes p
       where p.destination_id = d.id and p.status = 'group_wait'
       order by coalesce(p.room_group_id, p.group_id), p.requested_at
    loop
      continue when private.group_slot_taken(d, r.slot);
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

create or replace function public.request_pass(p_student_id uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  st public.students;
  d public.destinations;
  v_status public.pass_status;
  v_id uuid;
  v_room record;
  v_slot uuid;
begin
  perform private.require_role(a, array['teacher', 'prefect', 'coordinator', 'admin']);

  select * into st from public.students where id = p_student_id and active;
  if not found then
    raise exception 'Alumno no encontrado' using errcode = 'P0002';
  end if;
  if not private.device_may_operate(a, st.id) then
    raise exception 'Este equipo solo opera alumnos de su salón' using errcode = '42501';
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
  perform private.require_not_paused(d.id);

  -- Dónde estaba: en su sección (con el salón) o con su grupo.
  select r.room_group_id, r.section_id,
         case when r.section_id is not null
              then r.subject || coalesce(' · ' || g.room, '')
              else r.subject end as subject
    into v_room
    from private.student_room_at(st.id, now()) r
    left join public.groups g on g.id = r.room_group_id;

  -- Lugar del grupo: el del salón donde está (en Inglés, el salón del nivel).
  v_slot := coalesce(a.device_group_id, v_room.room_group_id, st.group_id);

  if exists (select 1 from public.passes where student_id = st.id
              and status in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning')) then
    raise exception 'El alumno ya tiene un pase activo' using errcode = 'P0001';
  end if;

  if private.group_slot_taken(d, v_slot) then
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
      opened_by, device_id, period_subject, room_group_id)
    values (
      st.id, st.group_id, d.id, v_status, clock_timestamp(),
      case when v_status = 'queued' then clock_timestamp() end,
      case when v_status = 'out' then clock_timestamp() end,
      a.staff_id, a.device_id, v_room.subject,
      v_slot)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'El alumno ya tiene un pase activo' using errcode = 'P0001';
  end;

  perform private.log_pass_event(v_id, 'requested', a, jsonb_build_object('status', v_status));
  return private.pass_json(v_id);
end;
$$;

create or replace function public.confirm_turn(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
begin
  perform private.require_role(a, array['teacher', 'prefect', 'coordinator', 'admin']);
  p := private.lock_pass(p_pass_id, a);
  if p.status <> 'called' then
    raise exception 'Ese pase ya no está esperando confirmación' using errcode = 'P0001';
  end if;
  perform private.require_not_paused(p.destination_id);
  update public.passes set status = 'out', started_at = clock_timestamp() where id = p.id;
  perform private.log_pass_event(p.id, 'confirmed', a);
  return private.pass_json(p.id);
end;
$$;

create or replace function public.force_out(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
begin
  perform private.require_role(a, array['counselor', 'coordinator', 'director', 'admin']);
  p := private.lock_pass(p_pass_id, a);
  if p.status not in ('group_wait', 'queued', 'called') then
    raise exception 'Ese alumno ya no está esperando' using errcode = 'P0001';
  end if;
  perform private.require_not_paused(p.destination_id);
  update public.passes
     set status = 'out', started_at = clock_timestamp()
   where id = p.id;
  perform private.log_pass_event(p.id, 'forced_out', a, jsonb_build_object('from', p.status));
  -- Si estaba "called", su lugar ya estaba reservado; si venía de la fila, ocupa uno más.
  perform private.advance(p.destination_id, a);
  return private.pass_json(p.id);
end;
$$;

create or replace function private.tick() returns void
language plpgsql security definer set search_path = ''
as $$
declare
  d record;
  p public.passes;
  r record;
  s public.settings;
  v_system private.actor;  -- todo en null: lo hizo el sistema
begin
  select * into s from public.settings where id = 1;

  perform private.auto_close_passes();
  perform private.reset_queues();

  for d in select id from public.destinations where kind = 'bathroom' order by id loop
    perform 1 from public.destinations where id = d.id for update;
    for p in
      select * from public.passes
       where destination_id = d.id and status = 'called'
         -- En pausa no corre el tiempo; al reanudar vuelve a contar desde cero.
         and private.paused_since(d.id) is null
         and greatest(called_at, private.last_resume(d.id))
               < clock_timestamp() - make_interval(mins => s.confirm_turn_minutes)
       order by called_at
    loop
      -- Si no hay nadie más formado, sigue siendo su turno (decisión 2026-10-15).
      if private.send_to_second_place(p) then
        perform private.log_pass_event(p.id, 'turn_expired', v_system);
      end if;
    end loop;
    perform private.advance(d.id, v_system);
  end loop;

  -- Alerta: alert_minutes fuera del salón (en enfermería solo el trayecto de ida) o
  -- alert_minutes de regreso desde enfermería sin que el maestro marque su regreso.
  for r in
    insert into public.alerts (pass_id)
    select ps.id from public.passes ps
     where (ps.status = 'out'
            and ps.started_at < clock_timestamp() - make_interval(mins => s.alert_minutes)
            and not exists (select 1 from public.alerts a where a.pass_id = ps.id))
        or (ps.status = 'returning'
            and ps.left_nurse_at < clock_timestamp() - make_interval(mins => s.alert_minutes)
            and not exists (select 1 from public.alerts a where a.pass_id = ps.id
                             and (a.resolved_at is null or a.created_at >= ps.left_nurse_at)))
    returning pass_id
  loop
    perform private.log_pass_event(r.pass_id, 'alert', v_system);
  end loop;

  -- Escalamiento: nadie la atendió en escalate_minutes.
  for r in
    update public.alerts
       set level = 2, escalated_at = clock_timestamp()
     where level = 1 and acknowledged_at is null and resolved_at is null
       and created_at < clock_timestamp() - make_interval(mins => s.escalate_minutes)
    returning pass_id
  loop
    perform private.log_pass_event(r.pass_id, 'escalated', v_system);
  end loop;

  update public.device_unlocks
     set locked_at = expires_at, lock_reason = 'auto'
   where locked_at is null and expires_at <= clock_timestamp();
end;
$$;

create or replace function public.bathrooms_status() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_staff boolean := private.current_staff_id() is not null;
begin
  if not private.is_member() then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'now', clock_timestamp(),
    'names', v_staff,
    'bathrooms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'label', d.label, 'sex', d.sex, 'capacity', d.capacity,
        'paused', private.pause_json(d.id),
        'occupants', coalesce((
          select jsonb_agg(private.waiting_item(p, v_staff, coalesce(p.started_at, p.called_at))
                   order by coalesce(p.started_at, p.called_at))
            from public.passes p
           where p.destination_id = d.id and p.status in ('called', 'out')), '[]'::jsonb),
        'queue', coalesce((
          select jsonb_agg(private.waiting_item(p, v_staff, p.queue_ts)
                   order by p.queue_ts, p.requested_at)
            from public.passes p
           where p.destination_id = d.id and p.status = 'queued'), '[]'::jsonb),
        'group_wait', (select count(*) from public.passes p
                        where p.destination_id = d.id and p.status = 'group_wait'),
        'group_wait_list', coalesce((
          select jsonb_agg(private.waiting_item(p, v_staff, p.requested_at) order by p.requested_at)
            from public.passes p
           where p.destination_id = d.id and p.status = 'group_wait'), '[]'::jsonb)
      ) order by d.sex)
        from public.destinations d where d.kind = 'bathroom'), '[]'::jsonb),
    -- Enfermería: en camino (lista de espera), en atención y de regreso.
    'nurse', (select count(*) from public.passes p join public.destinations d on d.id = p.destination_id
               where d.kind = 'nurse' and p.status in ('out', 'arrived')),
    'nurse_queue', coalesce((
      select jsonb_agg(private.waiting_item(p, v_staff, p.started_at) order by p.started_at)
        from public.passes p join public.destinations d on d.id = p.destination_id
       where d.kind = 'nurse' and p.status = 'out'), '[]'::jsonb),
    'nurse_care', coalesce((
      select jsonb_agg(private.waiting_item(p, v_staff, p.arrived_at) order by p.arrived_at)
        from public.passes p join public.destinations d on d.id = p.destination_id
       where d.kind = 'nurse' and p.status = 'arrived'), '[]'::jsonb),
    'nurse_returning', coalesce((
      select jsonb_agg(private.waiting_item(p, v_staff, p.left_nurse_at) order by p.left_nurse_at)
        from public.passes p join public.destinations d on d.id = p.destination_id
       where d.kind = 'nurse' and p.status = 'returning'), '[]'::jsonb));
end;
$$;

create or replace function public.live_board() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_today date := (now() at time zone 'America/Mexico_City')::date;
begin
  perform private.require_role(a, array['prefect', 'nurse', 'coordinator', 'director', 'admin', 'counselor'] || private.tab_roles('en-vivo'));
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

create or replace function public.group_board(p_group_id uuid) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_device_group uuid := private.current_device_group_id();
begin
  if private.current_staff_id() is null
     and (v_device_group is null or v_device_group <> p_group_id) then
    raise exception 'Sin acceso a este grupo' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'now', clock_timestamp(),
    'settings', (
      select jsonb_build_object(
        'alert_minutes', alert_minutes,
        'confirm_turn_minutes', confirm_turn_minutes,
        'undo_seconds', undo_seconds,
        'auto_lock_after_class_minutes', auto_lock_after_class_minutes)
        from public.settings where id = 1),
    'passes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'student_id', p.student_id,
        'list_number', s.list_number,
        'full_name', s.full_name,
        'sex', s.sex,
        'group_name', sg.name,
        'room_group_id', p.room_group_id,
        'status', p.status,
        'destination_id', p.destination_id,
        'destination_kind', d.kind,
        'destination_label', d.label,
        'requested_at', p.requested_at,
        'queue_ts', p.queue_ts,
        'called_at', p.called_at,
        'started_at', p.started_at,
        'arrived_at', p.arrived_at,
        'left_nurse_at', p.left_nurse_at,
        'period_subject', p.period_subject,
        'opened_by_name', o.full_name,
        'queue_position', case when p.status = 'queued' then (
          select count(*) from public.passes q
           where q.destination_id = p.destination_id and q.status = 'queued'
             and (q.queue_ts, q.requested_at) <= (p.queue_ts, p.requested_at)) end,
        'waiting_for', case when p.status = 'group_wait' then (
          select jsonb_build_object('list_number', ws.list_number, 'full_name', ws.full_name)
            from public.passes w join public.students ws on ws.id = w.student_id
           where w.destination_id = p.destination_id
             and coalesce(w.room_group_id, w.group_id) = coalesce(p.room_group_id, p.group_id)
             and w.status in ('queued', 'called', 'out')
           order by w.requested_at limit 1) end,
        'alert', private.alert_json(p.id)
      ) order by p.requested_at)
        from public.passes p
        join public.students s on s.id = p.student_id
        join public.groups sg on sg.id = s.group_id
        join public.destinations d on d.id = p.destination_id
        left join public.staff o on o.id = p.opened_by
       where (p.room_group_id = p_group_id
              or p.student_id in (select private.room_students_at(p_group_id, now())))
         and p.status in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning')), '[]'::jsonb),
    'bathrooms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'label', d.label,
        'sex', d.sex,
        'capacity', d.capacity,
        'paused', private.pause_json(d.id),
        'occupants', coalesce((
          select jsonb_agg(jsonb_build_object(
            'group_name', g.name, 'own', p.group_id = p_group_id, 'status', p.status,
            'since', coalesce(p.started_at, p.called_at))
            order by coalesce(p.started_at, p.called_at))
            from public.passes p join public.groups g on g.id = p.group_id
           where p.destination_id = d.id and p.status in ('called', 'out')), '[]'::jsonb),
        'queue', coalesce((
          select jsonb_agg(jsonb_build_object('group_name', g.name, 'own', p.group_id = p_group_id)
            order by p.queue_ts, p.requested_at)
            from public.passes p join public.groups g on g.id = p.group_id
           where p.destination_id = d.id and p.status = 'queued'), '[]'::jsonb)
      ) order by d.sex)
        from public.destinations d where d.kind = 'bathroom'), '[]'::jsonb)
  );
end;
$$;
