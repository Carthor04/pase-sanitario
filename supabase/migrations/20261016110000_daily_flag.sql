-- Marca para alumnos que ya salieron muchas veces en el día y detalle de sus salidas.

alter table public.settings
  add column daily_exits_flag int not null default 3 check (daily_exits_flag between 1 and 20);

-- Ahora devuelve también el límite: {"flag": 3, "counts": {"<alumno>": {"bathroom": n, "nurse": n}}}.
drop function public.group_today_counts(uuid);
create function public.group_today_counts(p_group_id uuid) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_device_group uuid := private.current_device_group_id();
  v_today date := (now() at time zone 'America/Mexico_City')::date;
begin
  if private.current_staff_id() is null
     and (v_device_group is null or v_device_group <> p_group_id) then
    raise exception 'Sin acceso a este grupo' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'flag', (select daily_exits_flag from public.settings where id = 1),
    'counts', coalesce((
      select jsonb_object_agg(student_id, jsonb_build_object('bathroom', bathroom, 'nurse', nurse))
        from (
          select p.student_id,
                 count(*) filter (where d.kind = 'bathroom') as bathroom,
                 count(*) filter (where d.kind = 'nurse') as nurse
            from public.passes p
            join public.destinations d on d.id = p.destination_id
           where p.group_id = p_group_id
             and p.started_at is not null
             and (p.started_at at time zone 'America/Mexico_City')::date = v_today
           group by p.student_id) c), '{}'::jsonb));
end;
$$;

-- Salidas de hoy de un alumno: horario, destino, clase y quién autorizó.
create function public.student_today_passes(p_student_id uuid) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_device_group uuid := private.current_device_group_id();
  v_today date := (now() at time zone 'America/Mexico_City')::date;
begin
  if private.current_staff_id() is null
     and (v_device_group is null
          or v_device_group <> (select group_id from public.students where id = p_student_id)) then
    raise exception 'Sin acceso a este alumno' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'started_at', p.started_at, 'ended_at', p.ended_at, 'status', p.status,
      'destination', d.label, 'kind', d.kind, 'subject', p.period_subject,
      'opened_by', o.full_name,
      'minutes', case when p.ended_at is not null
                      then round(extract(epoch from (p.ended_at - p.started_at)) / 60) end,
      'alert', exists (select 1 from public.alerts al where al.pass_id = p.id))
      order by p.started_at)
      from public.passes p
      join public.destinations d on d.id = p.destination_id
      left join public.staff o on o.id = p.opened_by
     where p.student_id = p_student_id
       and p.started_at is not null
       and (p.started_at at time zone 'America/Mexico_City')::date = v_today), '[]'::jsonb);
end;
$$;

revoke all on function public.group_today_counts(uuid) from public, anon;
revoke all on function public.student_today_passes(uuid) from public, anon;
grant execute on function public.group_today_counts(uuid) to authenticated;
grant execute on function public.student_today_passes(uuid) to authenticated;
