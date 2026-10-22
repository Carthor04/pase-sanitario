-- Reportes: alumnos que en un mismo día salieron al baño settings.daily_exits_flag veces o
-- más (3 por omisión, el mismo límite que marca al alumno en Mi grupo), con el detalle de
-- cada salida. Cuenta las salidas que ocurrieron (started_at), no las que esperaron en fila.
create function public.frequent_exits(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_flag int := (select daily_exits_flag from public.settings where id = 1);
begin
  perform private.require_role(a, array['coordinator', 'director', 'admin'] || private.tab_roles('reportes'));
  if p_to < p_from or p_to - p_from > 370 then
    raise exception 'Rango de fechas no válido' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'flag', v_flag,
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', x.day, 'student_id', x.student_id, 'full_name', st.full_name,
        'list_number', st.list_number, 'group_name', g.name, 'count', x.n, 'exits', x.exits)
        order by x.day desc, x.n desc, g.sort, st.list_number)
        from (
          select (p.started_at at time zone 'America/Mexico_City')::date as day, p.student_id,
                 count(*) as n,
                 jsonb_agg(jsonb_build_object(
                   'started_at', p.started_at,
                   'minutes', case when p.ended_at is not null and not p.auto_closed
                                   then round(extract(epoch from (p.ended_at - p.started_at)) / 60) end,
                   'subject', p.period_subject,
                   'opened_by', o.full_name,
                   'alert', exists (select 1 from public.alerts al where al.pass_id = p.id))
                   order by p.started_at) as exits
            from public.passes p
            join public.destinations d on d.id = p.destination_id and d.kind = 'bathroom'
            left join public.staff o on o.id = p.opened_by
           where p.started_at is not null
             and (p.started_at at time zone 'America/Mexico_City')::date between p_from and p_to
           group by 1, 2
          having count(*) >= v_flag) x
        join public.students st on st.id = x.student_id
        join public.groups g on g.id = st.group_id), '[]'::jsonb));
end;
$$;

revoke all on function public.frequent_exits(date, date) from public, anon;
grant execute on function public.frequent_exits(date, date) to authenticated;
