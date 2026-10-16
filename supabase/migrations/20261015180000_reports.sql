-- Fase 6 · Reportes, historial, estado de baños y cambios de reglas en vivo.

-- ---------------------------------------------------------------------------
-- Si coordinación cambia la capacidad o el límite por grupo, la fila avanza en ese
-- momento (p. ej. subir el baño de hombres de 1 a 2 llama al siguiente).
-- ---------------------------------------------------------------------------
create function private.on_destination_rules_change() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_system private.actor;
begin
  perform private.advance(new.id, v_system);
  return null;
end;
$$;

create trigger destinations_rules_changed
  after update of capacity, per_group_limit, uses_group_slot, queue_enabled on public.destinations
  for each row execute function private.on_destination_rules_change();

-- Valores razonables al editar desde Configuración.
alter table public.settings
  add constraint settings_alert_range check (alert_minutes between 1 and 120),
  add constraint settings_escalate_range check (escalate_minutes between 1 and 60),
  add constraint settings_confirm_range check (confirm_turn_minutes between 1 and 15),
  add constraint settings_autolock_range check (auto_lock_after_class_minutes between 0 and 60),
  add constraint settings_undo_range check (undo_seconds between 3 and 60);

-- ---------------------------------------------------------------------------
-- Estado de los baños para cualquier persona del personal (pestaña Baños del maestro).
-- Solo nombres de grupo, como en group_board.
-- ---------------------------------------------------------------------------
create function public.bathrooms_status() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if private.current_staff_id() is null then
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

-- ---------------------------------------------------------------------------
-- Reportes (SPEC §9): Coordinación, Dirección y admin.
-- ---------------------------------------------------------------------------
-- volatile: usa una tabla temporal para no recalcular el rango varias veces.
create function public.report_summary(p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  s public.settings;
begin
  perform private.require_role(a, array['coordinator', 'director', 'admin']);
  if p_to < p_from or p_to - p_from > 370 then
    raise exception 'Rango de fechas no válido' using errcode = '22023';
  end if;
  select * into s from public.settings where id = 1;

  drop table if exists pg_temp.rep_passes;
  -- Pases que salieron en el rango (hora de México).
  create temporary table pg_temp.rep_passes on commit drop as
  select p.id, p.student_id, p.group_id, p.destination_id, d.kind, d.sex, p.status,
         p.started_at, p.ended_at, p.queue_ts, p.called_at, p.period_subject,
         (p.started_at at time zone 'America/Mexico_City') as local_start,
         case when p.ended_at is not null and p.status in ('returned', 'released')
              then extract(epoch from (p.ended_at - p.started_at)) / 60 end as minutes
    from public.passes p join public.destinations d on d.id = p.destination_id
   where p.started_at is not null
     and (p.started_at at time zone 'America/Mexico_City')::date between p_from and p_to;

  return jsonb_build_object(
    'from', p_from, 'to', p_to,
    'thresholds', jsonb_build_object('alerts', s.review_alerts_threshold, 'exits', s.review_exits_threshold),
    'totals', (
      select jsonb_build_object(
        'exits', count(*),
        'bathroom', count(*) filter (where kind = 'bathroom'),
        'nurse', count(*) filter (where kind = 'nurse'),
        'avg_minutes', round(avg(minutes) filter (where kind = 'bathroom')::numeric, 1),
        'avg_minutes_h', round(avg(minutes) filter (where kind = 'bathroom' and sex = 'H')::numeric, 1),
        'avg_minutes_m', round(avg(minutes) filter (where kind = 'bathroom' and sex = 'M')::numeric, 1))
        from pg_temp.rep_passes),
    'alerts', (
      select jsonb_build_object(
        'count', count(*),
        'acknowledged_fast', count(*) filter (where al.acknowledged_at < al.created_at + interval '3 minutes'),
        'escalated', count(*) filter (where al.level = 2))
        from public.alerts al
       where (al.created_at at time zone 'America/Mexico_City')::date between p_from and p_to),
    -- Fila máxima: cuántos estuvieron formados a la vez (aprox. desde queue_ts hasta su turno).
    'max_queue', (
      select jsonb_build_object('size', x.n, 'destination', x.label, 'at', x.queue_ts)
        from (
          select q.queue_ts, d.label,
                 (select count(*) from public.passes o
                   where o.destination_id = q.destination_id and o.queue_ts is not null
                     and o.queue_ts <= q.queue_ts
                     and coalesce(o.called_at, o.started_at, o.ended_at, 'infinity') > q.queue_ts) as n
            from public.passes q join public.destinations d on d.id = q.destination_id
           where q.queue_ts is not null
             and (q.queue_ts at time zone 'America/Mexico_City')::date between p_from and p_to
           order by n desc, q.queue_ts
           limit 1) x),
    'heatmap', coalesce((
      select jsonb_agg(jsonb_build_object('destination', destination_id, 'weekday', wd, 'hour', hr, 'count', n))
        from (select destination_id, extract(isodow from local_start)::int wd,
                     extract(hour from local_start)::int hr, count(*) n
                from pg_temp.rep_passes where kind = 'bathroom'
               group by 1, 2, 3) h), '[]'::jsonb),
    'queued_slots', coalesce((
      select jsonb_agg(jsonb_build_object('destination', destination_id, 'weekday', wd, 'hour', hr))
        from (select distinct destination_id, extract(isodow from local_start)::int wd,
                     extract(hour from local_start)::int hr
                from pg_temp.rep_passes where kind = 'bathroom' and queue_ts is not null) q), '[]'::jsonb),
    'by_group', coalesce((
      select jsonb_agg(jsonb_build_object(
        'group_id', g.id, 'group_name', g.name,
        'exits', coalesce(r.exits, 0), 'avg_minutes', r.avg_minutes,
        'alerts', (select count(*) from public.alerts al join public.passes p on p.id = al.pass_id
                    where p.group_id = g.id
                      and (al.created_at at time zone 'America/Mexico_City')::date between p_from and p_to))
        order by g.sort nulls last, g.name)
        from public.groups g
        left join (select group_id, count(*) exits,
                          round(avg(minutes) filter (where kind = 'bathroom')::numeric, 1) avg_minutes
                     from pg_temp.rep_passes group by group_id) r on r.group_id = g.id), '[]'::jsonb),
    'review', coalesce((
      select jsonb_agg(x order by (x ->> 'alerts')::int desc, (x ->> 'exits')::int desc)
        from (
          select jsonb_build_object(
            'student_id', st.id, 'full_name', st.full_name, 'list_number', st.list_number,
            'group_name', g.name, 'exits', r.exits, 'nurse', r.nurse,
            'avg_minutes', r.avg_minutes, 'alerts', r.alerts,
            'top_subject', r.top_subject) as x
            from (
              select rp.student_id,
                     count(*) filter (where rp.kind = 'bathroom') exits,
                     count(*) filter (where rp.kind = 'nurse') nurse,
                     round(avg(rp.minutes) filter (where rp.kind = 'bathroom')::numeric, 1) avg_minutes,
                     (select count(*) from public.alerts al join public.passes p on p.id = al.pass_id
                       where p.student_id = rp.student_id
                         and (al.created_at at time zone 'America/Mexico_City')::date between p_from and p_to) alerts,
                     mode() within group (order by rp.period_subject) top_subject
                from pg_temp.rep_passes rp group by rp.student_id) r
            join public.students st on st.id = r.student_id
            join public.groups g on g.id = st.group_id
           where r.alerts >= s.review_alerts_threshold
              or r.exits > s.review_exits_threshold
              or r.nurse >= 3) y(x)), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Historial con búsqueda (SPEC §9). Enfermería sin otros roles ve solo enfermería.
-- ---------------------------------------------------------------------------
create function public.pass_history(
  p_from date, p_to date, p_query text default null, p_group uuid default null,
  p_limit int default 100, p_offset int default 0
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_nurse_only boolean;
  v_q text := nullif(private.norm(p_query), '');
begin
  perform private.require_role(a, array['prefect', 'nurse', 'coordinator', 'director', 'admin']);
  v_nurse_only := not (a.roles && array['prefect', 'coordinator', 'director', 'admin']);

  return coalesce((
    select jsonb_agg(row_to_json(h)::jsonb order by h.requested_at desc)
      from (
        select p.id, p.requested_at, p.started_at, p.ended_at, p.status, p.period_subject,
               p.release_reason,
               case when p.ended_at is not null and p.started_at is not null
                    then round(extract(epoch from (p.ended_at - p.started_at)) / 60, 1) end as minutes,
               st.full_name, st.list_number, g.name as group_name, d.label as destination, d.kind,
               o.full_name as opened_by, c.full_name as closed_by, (p.device_id is not null) as from_device,
               (select jsonb_build_object('level', al.level, 'acknowledged_by', ack.full_name)
                  from public.alerts al left join public.staff ack on ack.id = al.acknowledged_by
                 where al.pass_id = p.id) as alert
          from public.passes p
          join public.students st on st.id = p.student_id
          join public.groups g on g.id = p.group_id
          join public.destinations d on d.id = p.destination_id
          left join public.staff o on o.id = p.opened_by
          left join public.staff c on c.id = p.closed_by
         where (p.requested_at at time zone 'America/Mexico_City')::date between p_from and p_to
           and (p_group is null or p.group_id = p_group)
           and (not v_nurse_only or d.kind = 'nurse')
           and (v_q is null
                or private.norm(st.full_name) like '%' || v_q || '%'
                or private.norm(g.name) like '%' || v_q || '%'
                or private.norm(coalesce(o.full_name, '')) like '%' || v_q || '%')
         order by p.requested_at desc
         limit least(p_limit, 500) offset p_offset) h), '[]'::jsonb);
end;
$$;

-- Bitácora de un pase (quién, desde dónde, cuándo).
create function public.pass_timeline(p_pass_id uuid) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
begin
  perform private.require_role(a, array['prefect', 'nurse', 'coordinator', 'director', 'admin']);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', e.type, 'at', e.at, 'actor', s.full_name, 'from_device', e.device_id is not null,
      'payload', e.payload) order by e.id)
      from public.pass_events e left join public.staff s on s.id = e.actor_id
     where e.pass_id = p_pass_id), '[]'::jsonb);
end;
$$;

-- Horario de un grupo (Configuración → Horarios).
create function public.group_schedule(p_group_id uuid) returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'weekday', p.weekday, 'starts', p.starts, 'ends', p.ends, 'subject', se.subject,
    'teacher_name', s.full_name) order by p.starts, p.weekday), '[]'::jsonb)
    from public.schedule_entries se
    join public.periods p on p.id = se.period_id
    left join public.staff s on s.id = se.teacher_id
   where se.group_id = p_group_id and private.current_staff_id() is not null;
$$;

revoke all on function private.on_destination_rules_change() from public, anon, authenticated;
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.bathrooms_status()', 'public.report_summary(date, date)',
    'public.pass_history(date, date, text, uuid, int, int)', 'public.pass_timeline(uuid)',
    'public.group_schedule(uuid)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
