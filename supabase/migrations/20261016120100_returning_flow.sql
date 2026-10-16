-- Enfermería → salón (2/2). Flujo nuevo:
--   out (en camino) → arrived (llegó) → returning (la enfermera lo manda de regreso; se
--   avisa al maestro) → returned (el maestro marca su regreso).
-- El regreso también tiene alerta: si pasan alert_minutes desde que salió de enfermería y
-- nadie marca su regreso. Puede haber una alerta abierta por pase a la vez (antes una sola
-- por pase), porque el trayecto de ida y el de regreso se alertan por separado.

drop index public.one_active_pass_per_student;
create unique index one_active_pass_per_student on public.passes (student_id)
  where status in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning');
drop index public.passes_active_by_destination;
create index passes_active_by_destination on public.passes (destination_id, status, queue_ts)
  where status in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning');

drop index public.alerts_one_per_pass;
create unique index alerts_one_open_per_pass on public.alerts (pass_id) where resolved_at is null;
create index alerts_by_pass on public.alerts (pass_id);

-- ---------------------------------------------------------------------------
-- La enfermera manda al alumno de regreso al salón
-- ---------------------------------------------------------------------------
create function private.enqueue_returning_notification(p_pass uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p record;
begin
  select ps.id, ps.group_id, st.full_name, g.name as group_name
    into p
    from public.passes ps
    join public.students st on st.id = ps.student_id
    join public.groups g on g.id = ps.group_id
   where ps.id = p_pass;

  -- Al maestro a cargo ahora y al que autorizó la salida (según las reglas de push).
  insert into public.notifications_outbox (channel, kind, recipient_staff_id, pass_id, body, payload)
  select 'push', 'returning', s.id, p.id,
         format('🏫 %s (%s) salió de enfermería y va de regreso al salón. Marca su regreso al llegar.',
                p.full_name, p.group_name),
         jsonb_build_object('title', 'De regreso al salón', 'tag', 'pase-' || p.id,
                            'url', '/grupo?g=' || p.group_id)
    from public.staff s
   where s.active
     and exists (select 1 from public.push_subscriptions ps where ps.staff_id = s.id)
     and ((private.rule_on('current_teacher', 'push') and s.id in (
            select c.teacher_id from public.classes_at(now()) c where c.group_id = p.group_id))
          or (private.rule_on('authorizing_teacher', 'push') and s.id in (
            select ps.opened_by from public.passes ps where ps.id = p.id)));
end;
$$;

create function public.nurse_send_back(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
begin
  perform private.require_role(a, array['nurse', 'coordinator', 'admin']);
  p := private.lock_pass(p_pass_id, a);
  if (select kind from public.destinations where id = p.destination_id) <> 'nurse' then
    raise exception 'Solo los pases de enfermería regresan desde enfermería' using errcode = 'P0001';
  end if;
  if p.status not in ('out', 'arrived') then
    raise exception 'Ese alumno no está en enfermería' using errcode = 'P0001';
  end if;
  update public.passes
     set status = 'returning', left_nurse_at = clock_timestamp(),
         arrived_at = coalesce(arrived_at, clock_timestamp())
   where id = p.id;
  perform private.log_pass_event(p.id, 'sent_back', a, jsonb_build_object('from', p.status));
  perform private.enqueue_returning_notification(p.id);
  return private.pass_json(p.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Marcar regreso: ahora también desde "de regreso al salón".
-- ---------------------------------------------------------------------------
create or replace function public.mark_returned(p_pass_id uuid) returns jsonb
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
  if p.status not in ('out', 'arrived', 'returning') then
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

-- Deshacer: también "Regresa al salón" (la enfermera se equivocó de alumno).
create or replace function public.undo_last(p_pass_id uuid) returns jsonb
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

  if ev.type is null or ev.type not in ('requested', 'returned', 'sent_back') then
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
  elsif ev.type = 'sent_back' then
    update public.passes
       set status = (ev.payload ->> 'from')::public.pass_status, left_nurse_at = null
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

create or replace function private.sync_alert_on_pass_change() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.status in ('returned', 'released', 'arrived') then
    update public.alerts
       set resolved_at = clock_timestamp(), resolution = new.status::text
     where pass_id = new.id and resolved_at is null;
  elsif old.status = 'returned' and new.status in ('out', 'arrived', 'returning') then
    -- Se deshizo el regreso: la última alerta resuelta al regresar vuelve a estar abierta.
    update public.alerts set resolved_at = null, resolution = null
     where id = (select id from public.alerts where pass_id = new.id and resolution = 'returned'
                  order by created_at desc limit 1)
       and not exists (select 1 from public.alerts where pass_id = new.id and resolved_at is null);
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- tick(): la alerta cubre también el regreso de enfermería.
-- ---------------------------------------------------------------------------
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

  for d in select id from public.destinations where kind = 'bathroom' order by id loop
    perform 1 from public.destinations where id = d.id for update;
    for p in
      select * from public.passes
       where destination_id = d.id and status = 'called'
         and called_at < clock_timestamp() - make_interval(mins => s.confirm_turn_minutes)
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

-- La alerta abierta del pase (ahora un pase puede tener varias en su historia).
create or replace function private.alert_json(p_pass uuid) returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'id', al.id, 'level', al.level, 'created_at', al.created_at,
    'acknowledged_by_name', s.full_name, 'acknowledged_at', al.acknowledged_at)
    from public.alerts al left join public.staff s on s.id = al.acknowledged_by
   where al.pass_id = p_pass and al.resolved_at is null
   order by al.created_at desc
   limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Funciones que consideran un pase "activo": ahora incluyen 'returning'.
-- ---------------------------------------------------------------------------
create or replace function public.request_pass(p_student_id uuid, p_kind text) returns jsonb
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
              and status in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning')) then
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

create or replace function public.release_pass(p_pass_id uuid, p_reason text) returns jsonb
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
  if p.status not in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning') then
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
           where w.destination_id = p.destination_id and w.group_id = p.group_id
             and w.status in ('queued', 'called', 'out')
           order by w.requested_at limit 1) end,
        'alert', private.alert_json(p.id)
      ) order by p.requested_at)
        from public.passes p
        join public.students s on s.id = p.student_id
        join public.destinations d on d.id = p.destination_id
        left join public.staff o on o.id = p.opened_by
       where p.group_id = p_group_id
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

create or replace function public.live_board() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_today date := (now() at time zone 'America/Mexico_City')::date;
begin
  perform private.require_role(a, array['prefect', 'nurse', 'coordinator', 'director', 'admin']);
  return jsonb_build_object(
    'now', clock_timestamp(),
    'settings', (select jsonb_build_object('alert_minutes', alert_minutes,
      'escalate_minutes', escalate_minutes, 'confirm_turn_minutes', confirm_turn_minutes)
      from public.settings where id = 1),
    'destinations', (select jsonb_agg(jsonb_build_object('id', d.id, 'label', d.label,
      'kind', d.kind, 'sex', d.sex, 'capacity', d.capacity) order by d.kind, d.sex) from public.destinations d),
    'passes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'student_id', p.student_id, 'list_number', s.list_number,
        'full_name', s.full_name, 'sex', s.sex, 'group_id', p.group_id, 'group_name', g.name,
        'status', p.status, 'destination_id', p.destination_id,
        'requested_at', p.requested_at, 'queue_ts', p.queue_ts, 'called_at', p.called_at,
        'started_at', p.started_at, 'arrived_at', p.arrived_at, 'left_nurse_at', p.left_nurse_at,
        'period_subject', p.period_subject, 'opened_by_name', o.full_name,
        'current_teacher_name', (select c.teacher_name from public.classes_at(now()) c
                                  where c.group_id = p.group_id limit 1),
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

create or replace function public.nurse_today() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_today date := (now() at time zone 'America/Mexico_City')::date;
begin
  perform private.require_role(a, array['nurse', 'coordinator', 'director', 'admin']);
  return jsonb_build_object(
    'now', clock_timestamp(),
    'passes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'full_name', s.full_name, 'list_number', s.list_number,
        'group_name', g.name, 'status', p.status, 'started_at', p.started_at,
        'arrived_at', p.arrived_at, 'left_nurse_at', p.left_nurse_at, 'ended_at', p.ended_at, 'opened_by_name', o.full_name,
        'note', (select n.body from public.nurse_notes n where n.pass_id = p.id order by n.id desc limit 1),
        'alert', private.alert_json(p.id)
      ) order by p.started_at desc)
        from public.passes p
        join public.destinations d on d.id = p.destination_id and d.kind = 'nurse'
        join public.students s on s.id = p.student_id
        join public.groups g on g.id = p.group_id
        left join public.staff o on o.id = p.opened_by
       where p.status in ('out', 'arrived', 'returning')
          or (p.started_at at time zone 'America/Mexico_City')::date = v_today), '[]'::jsonb)
  );
end;
$$;

revoke all on function private.enqueue_returning_notification(uuid) from public, anon, authenticated;
revoke all on function private.sync_alert_on_pass_change() from public, anon, authenticated;
revoke all on function private.tick() from public, anon, authenticated;
revoke all on function private.alert_json(uuid) from public, anon, authenticated;
revoke all on function public.nurse_send_back(uuid) from public, anon;
grant execute on function public.nurse_send_back(uuid) to authenticated;
