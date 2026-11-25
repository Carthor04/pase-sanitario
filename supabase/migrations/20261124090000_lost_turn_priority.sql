-- Turno perdido con preferencia (decisión 2026-11-24).
--
-- 1. Si un pase se canceló solo porque nadie confirmó su turno (evento "cancelled" del
--    sistema con payload.auto = 'sin_confirmar'), al pedirlo de nuevo ese mismo día no va al
--    final de la fila: recupera su lugar (el queue_ts del pase perdido). Queda ligado en
--    passes.priority_from. La preferencia se da una sola vez: si el pase con preferencia
--    también pierde su turno, el siguiente va al final como cualquiera. Así un maestro que
--    nunca atiende no aparta el baño todo el día.
-- 2. Los tableros marcan esos pases ("priority") y group_board avisa qué alumnos del salón
--    perdieron su turno y todavía no lo vuelven a pedir ("lost_turns").
-- 3. Fila más ágil: como perder el turno ya no le quita su lugar al alumno, el pase se
--    cancela al primer turno vencido (settings.max_missed_turns = 1, se cambia en
--    Configuración). Antes un pase sin atender apartaba el baño dos veces.

alter table public.passes
  add column priority_from uuid references public.passes (id),
  add column priority_ts timestamptz;

comment on column public.passes.priority_from is
  'Pase que se canceló por no confirmar su turno y le dio preferencia a este.';
comment on column public.passes.priority_ts is
  'Lugar en la fila que recupera (queue_ts del pase perdido).';

-- Solo cambia el valor si sigue el de fábrica: si ya lo ajustaron en Configuración, se respeta.
update public.settings set max_missed_turns = 1 where id = 1 and max_missed_turns = 2;

-- El pase de baño de hoy que le da preferencia al alumno, si lo hay: su último pase de baño
-- del día se canceló solo por no confirmar el turno y no era ya un pase con preferencia.
create function private.lost_turn_pass(p_student uuid) returns public.passes
language sql stable security definer set search_path = ''
as $$
  select l.* from (
    select p.* from public.passes p
      join public.destinations d on d.id = p.destination_id and d.kind = 'bathroom'
     where p.student_id = p_student
       and (p.requested_at at time zone 'America/Mexico_City')::date
           = (now() at time zone 'America/Mexico_City')::date
     order by p.requested_at desc
     limit 1) l
   where l.status = 'cancelled'
     and l.priority_from is null
     and exists (select 1 from public.pass_events e
                  where e.pass_id = l.id and e.type = 'cancelled'
                    and e.payload ->> 'auto' = 'sin_confirmar');
$$;
revoke all on function private.lost_turn_pass(uuid) from public, anon, authenticated;

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
  v_lost public.passes;
  v_prio_ts timestamptz;
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

  -- Perdió su turno hoy: recupera su lugar en la fila (una sola vez).
  if p_kind = 'bathroom' then
    v_lost := private.lost_turn_pass(st.id);
    if v_lost.id is not null then
      v_prio_ts := coalesce(v_lost.queue_ts, v_lost.requested_at);
    end if;
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
      opened_by, device_id, period_subject, room_group_id, priority_from, priority_ts)
    values (
      st.id, st.group_id, d.id, v_status, clock_timestamp(),
      case when v_status = 'queued' then coalesce(v_prio_ts, clock_timestamp()) end,
      case when v_status = 'out' then clock_timestamp() end,
      a.staff_id, a.device_id, v_room.subject,
      v_slot, v_lost.id, v_prio_ts)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'El alumno ya tiene un pase activo' using errcode = 'P0001';
  end;

  perform private.log_pass_event(v_id, 'requested', a,
    jsonb_build_object('status', v_status)
    || case when v_lost.id is not null
            then jsonb_build_object('priority_from', v_lost.id) else '{}'::jsonb end);
  return private.pass_json(v_id);
end;
$$;

-- Igual que antes, pero el group_wait con preferencia entra a la fila en el lugar que
-- recupera, no en la hora en que se pidió.
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

  -- 1. El group_wait más antiguo de cada salón con lugar libre pasa a la fila con la hora
  --    en que se pidió su pase (o el lugar que recupera). Nunca sale directo: recibe turno
  --    en el paso 2.
  loop
    v_changed := false;
    for r in
      select distinct on (coalesce(p.room_group_id, p.group_id)) p.id,
             coalesce(p.room_group_id, p.group_id) as slot
        from public.passes p
       where p.destination_id = d.id and p.status = 'group_wait'
       order by coalesce(p.room_group_id, p.group_id), coalesce(p.priority_ts, p.requested_at)
    loop
      continue when private.group_slot_taken(d, r.slot);
      -- Los que se formaron mientras esperaba a su grupo no se le adelantan.
      update public.passes set status = 'queued', queue_ts = coalesce(priority_ts, requested_at)
       where id = r.id;
      perform private.log_pass_event(r.id, 'promoted', a, '{"to":"queued"}');
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

-- El aviso al maestro dice que conserva su lugar (si todavía le toca preferencia).
create or replace function private.enqueue_turn_cancelled_notification(p_pass uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p record;
  v_body text;
begin
  select ps.id, ps.opened_by, ps.priority_from, st.full_name, g.name as group_name,
         coalesce(ps.room_group_id, ps.group_id) as room
    into p
    from public.passes ps
    join public.students st on st.id = ps.student_id
    join public.groups g on g.id = ps.group_id
   where ps.id = p_pass;
  v_body := case when p.priority_from is null
    then format('%s (%s) perdió su turno: nadie lo confirmó. Pídelo de nuevo y recupera su lugar en la fila.',
                p.full_name, p.group_name)
    else format('Se canceló el pase de %s (%s): nadie confirmó su turno. Pídelo de nuevo cuando esté listo.',
                p.full_name, p.group_name) end;

  insert into public.notifications_outbox (channel, kind, recipient_staff_id, pass_id, body, payload)
  select 'push', 'turn_cancelled', s.id, p.id, v_body,
         jsonb_build_object('title', 'Perdió su turno', 'tag', 'pase-' || p.id,
                            'url', '/grupo?g=' || p.room)
    from public.staff s
   where s.active
     and exists (select 1 from public.push_subscriptions ps where ps.staff_id = s.id)
     and ((private.rule_on('authorizing_teacher', 'push') and s.id = p.opened_by)
          or (private.rule_on('current_teacher', 'push') and s.id = private.pass_teacher_now(p.id)));

  perform private.enqueue_device_push(p.id, 'turn_cancelled', 'Perdió su turno', v_body);
end;
$$;
revoke all on function private.enqueue_turn_cancelled_notification(uuid) from public, anon, authenticated;

-- Listas de espera de Baños en vivo: marca los pases con preferencia.
create or replace function private.waiting_item(p public.passes, p_names boolean, p_since timestamptz)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'group_name', (select name from public.groups where id = p.group_id),
    'status', p.status,
    -- Con preferencia, la espera cuenta desde que lo volvieron a pedir (su queue_ts es el
    -- lugar que recupera).
    'since', case when p.priority_from is not null and p.status = 'queued'
                  then p.requested_at else p_since end,
    'priority', p.priority_from is not null)
  || case when p_names then jsonb_build_object(
       'id', p.id,
       'full_name', st.full_name,
       'list_number', st.list_number,
       'subject', p.period_subject,
       'opened_by', (select full_name from public.staff where id = p.opened_by),
       'current_teacher', (select r.teacher_name from private.student_room_at(p.student_id, now()) r))
     else '{}'::jsonb end
    from public.students st where st.id = p.student_id;
$$;
revoke all on function private.waiting_item(public.passes, boolean, timestamptz) from public, anon, authenticated;

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
        'priority', p.priority_from is not null,
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
  v_day_start timestamptz :=
    ((now() at time zone 'America/Mexico_City')::date)::timestamp at time zone 'America/Mexico_City';
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
        'priority', p.priority_from is not null,
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
    -- Alumnos del salón que perdieron su turno hoy y todavía no lo vuelven a pedir.
    'lost_turns', coalesce((
      select jsonb_agg(jsonb_build_object('student_id', p.student_id, 'pass_id', p.id,
                                          'at', p.ended_at) order by p.ended_at)
        from public.passes p
       where p.status = 'cancelled'
         and p.ended_at >= v_day_start
         and (p.room_group_id = p_group_id
              or p.student_id in (select private.room_students_at(p_group_id, now())))
         and p.id = (private.lost_turn_pass(p.student_id)).id), '[]'::jsonb),
    'bathrooms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'label', d.label,
        'sex', d.sex,
        'capacity', d.capacity,
        'uses_group_slot', d.uses_group_slot,
        'paused', private.pause_json(d.id),
        'occupants', coalesce((
          select jsonb_agg(jsonb_build_object(
            'group_name', g.name, 'own', p.group_id = p_group_id, 'status', p.status,
            'since', coalesce(p.started_at, p.called_at))
            order by coalesce(p.started_at, p.called_at))
            from public.passes p join public.groups g on g.id = p.group_id
           where p.destination_id = d.id and p.status in ('called', 'out')), '[]'::jsonb),
        'queue', coalesce((
          select jsonb_agg(jsonb_build_object('group_name', g.name, 'own', p.group_id = p_group_id,
                                              'priority', p.priority_from is not null)
            order by p.queue_ts, p.requested_at)
            from public.passes p join public.groups g on g.id = p.group_id
           where p.destination_id = d.id and p.status = 'queued'), '[]'::jsonb)
      ) order by d.sex)
        from public.destinations d where d.kind = 'bathroom'), '[]'::jsonb)
  );
end;
$$;
