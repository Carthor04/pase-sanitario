-- Cuántas veces salió hoy cada alumno de un grupo (al baño y a enfermería), para mostrarlo
-- en la lista del grupo. Cuenta las salidas que sí ocurrieron (con started_at) hoy en
-- hora de México; no cuenta pases cancelados antes de salir.
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

  return coalesce((
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
         group by p.student_id) c), '{}'::jsonb);
end;
$$;

revoke all on function public.group_today_counts(uuid) from public, anon;
grant execute on function public.group_today_counts(uuid) to authenticated;
