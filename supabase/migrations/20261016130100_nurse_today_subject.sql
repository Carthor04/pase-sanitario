-- nurse_today: también la clase en la que salió el alumno (lista de espera de enfermería).
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
        'group_name', g.name, 'status', p.status, 'period_subject', p.period_subject, 'started_at', p.started_at,
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
