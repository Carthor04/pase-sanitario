-- Fase 3 · Lecturas para las pantallas del salón y del celular.
-- group_board() junta en una sola llamada lo que ve un grupo: sus pases activos (con
-- nombres) y el estado de los baños (de los otros grupos solo el nombre del grupo).
-- Así la computadora de un salón nunca recibe nombres de alumnos de otros grupos.

create function public.group_board(p_group_id uuid) returns jsonb
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
           order by w.requested_at limit 1) end
      ) order by p.requested_at)
        from public.passes p
        join public.students s on s.id = p.student_id
        join public.destinations d on d.id = p.destination_id
        left join public.staff o on o.id = p.opened_by
       where p.group_id = p_group_id
         and p.status in ('group_wait', 'queued', 'called', 'out', 'arrived')), '[]'::jsonb),
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

-- Estado de bloqueo de la computadora del salón.
create function public.device_session() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_device uuid := private.current_device_id();
  v_open record;
  v_last record;
begin
  if v_device is null then
    raise exception 'Solo la computadora del salón' using errcode = '42501';
  end if;

  select u.staff_id, s.full_name, u.unlocked_at, u.expires_at into v_open
    from public.device_unlocks u join public.staff s on s.id = u.staff_id
   where u.device_id = v_device and u.locked_at is null
     and u.expires_at > clock_timestamp() and s.active
   order by u.unlocked_at desc limit 1;

  select s.full_name, coalesce(u.locked_at, u.expires_at) as locked_at,
         coalesce(u.lock_reason, 'auto') as reason into v_last
    from public.device_unlocks u join public.staff s on s.id = u.staff_id
   where u.device_id = v_device
     and (u.locked_at is not null or u.expires_at <= clock_timestamp())
   order by coalesce(u.locked_at, u.expires_at) desc limit 1;

  return jsonb_build_object(
    'now', clock_timestamp(),
    'unlocked', v_open.staff_id is not null,
    'staff_id', v_open.staff_id,
    'staff_name', v_open.full_name,
    'unlocked_at', v_open.unlocked_at,
    'expires_at', v_open.expires_at,
    'last_lock', case when v_last.full_name is not null then jsonb_build_object(
      'staff_name', v_last.full_name, 'locked_at', v_last.locked_at, 'reason', v_last.reason) end);
end;
$$;

revoke all on function public.group_board(uuid) from public, anon;
revoke all on function public.device_session() from public, anon;
grant execute on function public.group_board(uuid) to authenticated;
grant execute on function public.device_session() to authenticated;
