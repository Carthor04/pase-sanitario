-- Lugar del grupo por salón. Un niño y una niña fuera a la vez por salón: en clases normales
-- el salón es el del grupo (igual que antes); en una clase por nivel (Inglés) es el salón del
-- nivel, aunque sus alumnos sean de varios grupos. La llave es passes.room_group_id (el salón
-- de donde salió); los pases anteriores a esta columna usan su grupo.

-- p_group es el salón (llave del lugar); conserva su nombre original.
create or replace function private.group_slot_taken(d public.destinations, p_group uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select d.uses_group_slot and d.per_group_limit is not null and (
    select count(*) from public.passes
     where destination_id = d.id and coalesce(room_group_id, group_id) = p_group
       and status in ('queued', 'called', 'out')) >= d.per_group_limit;
$$;

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
  perform private.require_role(a, array['teacher', 'coordinator', 'admin']);

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
