-- Reportes con detalle (al tocar un cuadro, una hora del mapa o un grupo) y horario por
-- docente para Configuración.

-- Alumnos que salieron en el periodo, filtrados por lo que se tocó en el reporte.
create function public.report_detail(
  p_from date,
  p_to date,
  p_destination text default null,   -- 'bath_h' | 'bath_m' | 'nurse' | 'bathroom' (ambos baños)
  p_weekday int default null,         -- 1 = lunes
  p_hour int default null,            -- hora de México (7 = 7:00–7:59)
  p_group uuid default null,
  p_alerts_only boolean default false
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
begin
  perform private.require_role(a, array['coordinator', 'director', 'admin']);
  return coalesce((
    select jsonb_agg(x order by x ->> 'started_at')
      from (
        select jsonb_build_object(
          'id', p.id,
          'full_name', st.full_name, 'list_number', st.list_number, 'group_name', g.name,
          'destination', d.label, 'kind', d.kind,
          'started_at', p.started_at, 'ended_at', p.ended_at, 'status', p.status,
          'minutes', case when p.ended_at is not null and p.status in ('returned', 'released')
                          then round(extract(epoch from (p.ended_at - p.started_at)) / 60, 1) end,
          'subject', p.period_subject, 'opened_by', o.full_name,
          'queued', p.queue_ts is not null,
          'alert', exists (select 1 from public.alerts al where al.pass_id = p.id),
          'release_reason', p.release_reason) as x
          from public.passes p
          join public.students st on st.id = p.student_id
          join public.groups g on g.id = p.group_id
          join public.destinations d on d.id = p.destination_id
          left join public.staff o on o.id = p.opened_by
         where p.started_at is not null
           and (p.started_at at time zone 'America/Mexico_City')::date between p_from and p_to
           and (p_destination is null
                or (p_destination = 'bathroom' and d.kind = 'bathroom')
                or p.destination_id = p_destination)
           and (p_weekday is null
                or extract(isodow from p.started_at at time zone 'America/Mexico_City') = p_weekday)
           and (p_hour is null
                or extract(hour from p.started_at at time zone 'America/Mexico_City') = p_hour)
           and (p_group is null or p.group_id = p_group)
           and (not p_alerts_only or exists (select 1 from public.alerts al where al.pass_id = p.id))
         limit 1000) y), '[]'::jsonb);
end;
$$;

-- Horario semanal de un docente y su clase actual.
create function public.teacher_schedule(p_staff_id uuid) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if private.current_staff_id() is null then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'now', clock_timestamp(),
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'weekday', p.weekday, 'starts', p.starts, 'ends', p.ends,
        'subject', se.subject, 'group_name', g.name, 'room', g.room)
        order by p.weekday, p.starts)
        from public.schedule_entries se
        join public.periods p on p.id = se.period_id
        join public.groups g on g.id = se.group_id
       where se.teacher_id = p_staff_id), '[]'::jsonb),
    'current', (
      select jsonb_build_object('subject', c.subject, 'group_name', g.name, 'room', g.room,
                                'starts', c.starts, 'ends', c.ends)
        from public.classes_at(now()) c join public.groups g on g.id = c.group_id
       where c.teacher_id = p_staff_id
       limit 1));
end;
$$;

-- Clase actual de todos los grupos (Configuración → Horarios).
create function public.current_classes() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if private.current_staff_id() is null then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'now', clock_timestamp(),
    'groups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'group_id', g.id, 'group_name', g.name, 'room', g.room,
        'subject', c.subject, 'teacher_name', c.teacher_name, 'starts', c.starts, 'ends', c.ends)
        order by g.sort nulls last, g.name)
        from public.groups g
        left join public.classes_at(now()) c on c.group_id = g.id), '[]'::jsonb));
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.report_detail(date, date, text, int, int, uuid, boolean)',
    'public.teacher_schedule(uuid)', 'public.current_classes()']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
