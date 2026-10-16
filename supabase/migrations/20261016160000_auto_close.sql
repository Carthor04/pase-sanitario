-- Cierre automático de pases olvidados (decisión 2026-10-16).
-- Al terminar la última clase del día (la hora de fin más tarde en `periods` para ese día de
-- la semana), los pases que sigan abiertos se liberan con motivo "Cierre automático". También se
-- cierran los que quedaron abiertos de días anteriores (fines de semana, días sin horario o si
-- el cron no corrió). Nada se borra: queda el evento 'released' en la bitácora, hecho por el
-- sistema. Los minutos de esos pases no cuentan en promedios porque no son tiempo real.

alter table public.passes add column auto_closed boolean not null default false;

-- p_at solo para pruebas; el cron usa la hora actual.
create function private.auto_close_passes(p_at timestamptz default clock_timestamp()) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_local timestamp := p_at at time zone 'America/Mexico_City';
  v_today date := (p_at at time zone 'America/Mexico_City')::date;
  v_last_end time;
  d record;
  r record;
  v_system private.actor;  -- todo en null: lo hizo el sistema
begin
  select max(ends) into v_last_end from public.periods
   where weekday = extract(isodow from v_today)::int;

  for d in select id from public.destinations order by id loop
    perform 1 from public.destinations where id = d.id for update;
    for r in
      with c as (
        select p.id, p.status from public.passes p
         where p.destination_id = d.id
           and p.status in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning')
           and ((p.requested_at at time zone 'America/Mexico_City')::date < v_today
                -- Hoy: solo los que se pidieron antes del fin de la última clase, para no
                -- cerrar un pase que se abra después (por ejemplo, en una actividad de la tarde).
                or (v_last_end is not null and v_local::time >= v_last_end
                    and (p.requested_at at time zone 'America/Mexico_City')::date = v_today
                    and (p.requested_at at time zone 'America/Mexico_City')::time < v_last_end))
         for update)
      update public.passes p
         set status = 'released', ended_at = clock_timestamp(), auto_closed = true,
             release_reason = 'Cierre automático'
        from c
       where p.id = c.id
      returning p.id, c.status as from_status
    loop
      perform private.log_pass_event(r.id, 'released', v_system,
        jsonb_build_object('from', r.from_status, 'reason', 'Cierre automático', 'auto', true));
    end loop;
  end loop;
end;
$$;

revoke all on function private.auto_close_passes(timestamptz) from public, anon, authenticated;

-- tick(): primero el cierre automático, luego lo de siempre.
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

  perform private.auto_close_passes();

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
-- Reportes: sin minutos para los pases de cierre automático.
create or replace function public.report_summary(p_from date, p_to date) returns jsonb
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
         case when p.ended_at is not null and p.status in ('returned', 'released') and not p.auto_closed
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
create or replace function public.pass_history(
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
               case when p.ended_at is not null and p.started_at is not null and not p.auto_closed
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
create or replace function public.student_today_passes(p_student_id uuid) returns jsonb
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
      'minutes', case when p.ended_at is not null and not p.auto_closed
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
create or replace function public.report_detail(
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
          'minutes', case when p.ended_at is not null and p.status in ('returned', 'released') and not p.auto_closed
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
