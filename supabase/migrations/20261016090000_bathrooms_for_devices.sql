-- La computadora del salón también ve el estado de los baños en vivo (solo nombres de
-- grupo y tiempos, nunca nombres de alumnos), aunque esté bloqueada.
create or replace function public.bathrooms_status() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not private.is_member() then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'now', clock_timestamp(),
    'bathrooms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'label', d.label, 'sex', d.sex, 'capacity', d.capacity,
        'occupants', coalesce((
          select jsonb_agg(jsonb_build_object('group_name', g.name, 'status', p.status,
                   'since', coalesce(p.started_at, p.called_at)) order by coalesce(p.started_at, p.called_at))
            from public.passes p join public.groups g on g.id = p.group_id
           where p.destination_id = d.id and p.status in ('called', 'out')), '[]'::jsonb),
        'queue', coalesce((
          select jsonb_agg(jsonb_build_object('group_name', g.name, 'since', p.queue_ts)
                   order by p.queue_ts, p.requested_at)
            from public.passes p join public.groups g on g.id = p.group_id
           where p.destination_id = d.id and p.status = 'queued'), '[]'::jsonb),
        'group_wait', (select count(*) from public.passes p
                        where p.destination_id = d.id and p.status = 'group_wait')
      ) order by d.sex)
        from public.destinations d where d.kind = 'bathroom'), '[]'::jsonb),
    'nurse', (select count(*) from public.passes p join public.destinations d on d.id = p.destination_id
               where d.kind = 'nurse' and p.status in ('out', 'arrived')));
end;
$$;
