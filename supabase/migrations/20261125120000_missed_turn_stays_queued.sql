-- Turno perdido: el alumno sigue en la fila (decisión 2026-11-25).
--
-- En la escuela no funcionó que un alumno sin atender desapareciera de la lista: el maestro
-- tenía que volver a pedir el pase. Ahora, cuando su turno vence sin confirmarse:
-- 1. El pase NO se cancela. Vuelve a la fila en segundo lugar (detrás del que recibe el turno
--    ahora) y queda marcado con preferencia (passes.priority_ts). Las pantallas lo pintan de
--    morado con texto ("Preferencia · lugar N").
-- 2. Se avisa al maestro que sigue en la fila con preferencia.
-- 3. settings.max_missed_turns ya no se usa (la columna se queda; nada se borra).
-- Si no hay nadie más formado, sigue siendo su turno, como antes. Ceder no da preferencia.

comment on column public.passes.priority_ts is
  'Tiene preferencia en la fila: perdió su turno (o recuperó el lugar de un pase perdido). '
  'Valor: el lugar que ocupa o recupera.';
comment on column public.settings.max_missed_turns is
  'Sin uso desde 2026-11-25: un turno perdido ya no cancela el pase.';

-- Aviso al maestro: perdió su turno pero sigue en la fila con preferencia.
create or replace function private.enqueue_turn_cancelled_notification(p_pass uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p record;
  v_body text;
begin
  select ps.id, ps.opened_by, st.full_name, g.name as group_name,
         coalesce(ps.room_group_id, ps.group_id) as room
    into p
    from public.passes ps
    join public.students st on st.id = ps.student_id
    join public.groups g on g.id = ps.group_id
   where ps.id = p_pass;
  v_body := format('%s (%s) perdió su turno: nadie lo confirmó. Sigue en la fila con preferencia.',
                   p.full_name, p.group_name);

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

-- Vence los turnos sin confirmar de un baño y avanza su fila. Quien la llama ya tiene el
-- candado del destino.
create or replace function private.expire_turns(p_destination text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p public.passes;
  s public.settings;
  v_missed int;
  v_system private.actor;  -- todo en null: lo hizo el sistema
begin
  select * into s from public.settings where id = 1;
  for p in
    select * from public.passes
     where destination_id = p_destination and status = 'called'
       -- En pausa no corre el tiempo; al reanudar vuelve a contar desde cero.
       and private.paused_since(p_destination) is null
       and greatest(called_at, private.last_resume(p_destination))
             < clock_timestamp() - make_interval(mins => s.confirm_turn_minutes)
     order by called_at
  loop
    -- Si no hay nadie más formado, sigue siendo su turno (decisión 2026-10-15).
    continue when not private.send_to_second_place(p);

    -- Sigue en la fila, con preferencia.
    update public.passes set priority_ts = queue_ts where id = p.id;
    v_missed := 1 + (select count(*) from public.pass_events e
                      where e.pass_id = p.id and e.type = 'turn_expired');
    perform private.log_pass_event(p.id, 'turn_expired', v_system,
      jsonb_build_object('missed', v_missed, 'priority', true));
    perform private.enqueue_turn_cancelled_notification(p.id);
  end loop;
  perform private.advance(p_destination, v_system);
end;
$$;
revoke all on function private.expire_turns(text) from public, anon, authenticated;

-- Los tableros marcan con preferencia todo pase con priority_ts (antes solo priority_from).
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
    'since', case when p.priority_ts is not null and p.status = 'queued'
                  then p.requested_at else p_since end,
    'priority', p.priority_ts is not null)
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
        'priority', p.priority_ts is not null,
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
        'priority', p.priority_ts is not null,
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
                                              'priority', p.priority_ts is not null)
            order by p.queue_ts, p.requested_at)
            from public.passes p join public.groups g on g.id = p.group_id
           where p.destination_id = d.id and p.status = 'queued'), '[]'::jsonb)
      ) order by d.sex)
        from public.destinations d where d.kind = 'bathroom'), '[]'::jsonb)
  );
end;
$$;
