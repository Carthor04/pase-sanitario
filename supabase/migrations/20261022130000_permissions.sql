-- Permisos (Ajustes → Permisos, solo admin): el admin cambia los roles de cada persona y qué
-- pestañas ve cada rol. Las acciones dentro de cada pantalla siguen dependiendo del rol.
-- Dar una pestaña a un rol también le abre en Postgres la lectura de esa pantalla; los
-- roles que ya la veían la siguen viendo aunque se les quite del menú. Cada cambio queda en
-- permission_changes (nada se borra).

create table public.role_tabs (
  role text not null check (role in ('teacher', 'prefect', 'nurse', 'coordinator', 'director', 'admin', 'counselor')),
  tab text not null check (tab in ('en-vivo', 'grupo', 'enfermeria', 'banos', 'alertas', 'reportes', 'historial')),
  primary key (role, tab)
);
alter table public.role_tabs enable row level security;

-- Lo mismo que el menú tenía fijo en el código.
insert into public.role_tabs (role, tab) values
  ('teacher', 'grupo'), ('teacher', 'banos'), ('teacher', 'alertas'),
  ('prefect', 'en-vivo'), ('prefect', 'grupo'), ('prefect', 'historial'),
  ('nurse', 'enfermeria'), ('nurse', 'historial'),
  ('coordinator', 'en-vivo'), ('coordinator', 'grupo'), ('coordinator', 'reportes'), ('coordinator', 'historial'),
  ('director', 'en-vivo'), ('director', 'reportes'), ('director', 'historial'),
  ('admin', 'en-vivo'), ('admin', 'reportes'), ('admin', 'historial'),
  ('counselor', 'en-vivo');

create table public.permission_changes (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor_id uuid references public.staff (id),
  kind text not null check (kind in ('role_tabs', 'staff_roles')),
  target text not null,          -- el rol o el id de la persona
  before text[] not null,
  after text[] not null
);
alter table public.permission_changes enable row level security;

-- Roles que tienen esa pestaña.
create function private.tab_roles(p_tab text) returns text[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(role), '{}') from public.role_tabs where tab = p_tab;
$$;

-- Pestañas de una persona según sus roles.
create function private.staff_tabs(p_roles text[]) returns text[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct tab order by tab), '{}') from public.role_tabs where role = any (p_roles);
$$;

-- Solo un admin desde su propia cuenta: la compu del salón desbloqueada con su PIN no cuenta.
create function private.require_admin_account(a private.actor) returns void
language plpgsql immutable set search_path = ''
as $$
begin
  if a.device_id is not null or not (a.roles && array['admin']) then
    raise exception 'Solo el admin, desde su cuenta, cambia permisos' using errcode = '42501';
  end if;
end;
$$;
revoke all on function private.tab_roles(text) from public, anon, authenticated;
revoke all on function private.staff_tabs(text[]) from public, anon, authenticated;
revoke all on function private.require_admin_account(private.actor) from public, anon, authenticated;

-- Para la pestaña Permisos: pestañas de cada rol y el personal con sus roles.
create function public.permissions_overview() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
begin
  perform private.require_admin_account(a);
  return jsonb_build_object(
    'role_tabs', coalesce((
      select jsonb_object_agg(role, tabs) from (
        select role, jsonb_agg(tab order by tab) as tabs from public.role_tabs group by role) t),
      '{}'::jsonb),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'full_name', s.full_name, 'email', s.email, 'roles', to_jsonb(s.roles),
        'active', s.active) order by s.active desc, s.full_name)
        from public.staff s), '[]'::jsonb));
end;
$$;

create function public.set_role_tabs(p_role text, p_tabs text[]) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_before text[];
  v_after text[];
begin
  perform private.require_admin_account(a);
  if p_role is null or p_role not in ('teacher', 'prefect', 'nurse', 'coordinator', 'director', 'admin', 'counselor') then
    raise exception 'Rol no válido' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct t order by t), '{}') into v_after
    from unnest(coalesce(p_tabs, '{}')) t;
  if not v_after <@ array['en-vivo', 'grupo', 'enfermeria', 'banos', 'alertas', 'reportes', 'historial'] then
    raise exception 'Pestaña no válida' using errcode = '22023';
  end if;

  -- Un cambio a la vez por rol.
  perform pg_advisory_xact_lock(hashtext('role_tabs:' || p_role));
  select coalesce(array_agg(tab order by tab), '{}') into v_before from public.role_tabs where role = p_role;
  if v_before = v_after then
    return to_jsonb(v_after);
  end if;
  delete from public.role_tabs where role = p_role and tab <> all (v_after);
  insert into public.role_tabs (role, tab) select p_role, t from unnest(v_after) t
  on conflict do nothing;
  insert into public.permission_changes (actor_id, kind, target, before, after)
  values (a.staff_id, 'role_tabs', p_role, v_before, v_after);
  return to_jsonb(v_after);
end;
$$;

create function public.set_staff_roles(p_staff_id uuid, p_roles text[]) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  s public.staff;
  v_after text[];
begin
  perform private.require_admin_account(a);
  select coalesce(array_agg(distinct r order by r), '{}') into v_after
    from unnest(coalesce(p_roles, '{}')) r;
  if cardinality(v_after) = 0 then
    raise exception 'Elige al menos un rol' using errcode = '22023';
  end if;
  if not v_after <@ array['teacher', 'prefect', 'nurse', 'coordinator', 'director', 'admin', 'counselor'] then
    raise exception 'Rol no válido' using errcode = '22023';
  end if;

  select * into s from public.staff where id = p_staff_id for update;
  if not found then
    raise exception 'Persona no encontrada' using errcode = 'P0002';
  end if;
  if 'admin' = any (s.roles) and not 'admin' = any (v_after) then
    if s.id = a.staff_id then
      raise exception 'No puedes quitarte el rol de admin a ti mismo' using errcode = 'P0001';
    end if;
    if not exists (select 1 from public.staff
                    where active and 'admin' = any (roles) and id <> s.id) then
      raise exception 'Debe quedar al menos un admin activo' using errcode = 'P0001';
    end if;
  end if;
  if (select array_agg(r order by r) from unnest(s.roles) r) = v_after then
    return to_jsonb(v_after);
  end if;

  update public.staff set roles = v_after where id = s.id;
  insert into public.permission_changes (actor_id, kind, target, before, after)
  values (a.staff_id, 'staff_roles', s.id::text, s.roles, v_after);
  return to_jsonb(v_after);
end;
$$;

-- Los roles ya no se cambian editando la tabla: solo con set_staff_roles (admin) o con el
-- importador de personal.
revoke update (roles) on public.staff from authenticated;

revoke all on function public.permissions_overview() from public, anon;
revoke all on function public.set_role_tabs(text, text[]) from public, anon;
revoke all on function public.set_staff_roles(uuid, text[]) from public, anon;
grant execute on function public.permissions_overview() to authenticated;
grant execute on function public.set_role_tabs(text, text[]) to authenticated;
grant execute on function public.set_staff_roles(uuid, text[]) to authenticated;

-- Pantallas de lectura: los roles de siempre más los que tengan esa pestaña.
-- me() agrega las pestañas de la persona para armar el menú.

create or replace function public.live_board() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_today date := (now() at time zone 'America/Mexico_City')::date;
begin
  perform private.require_role(a, array['prefect', 'nurse', 'coordinator', 'director', 'admin', 'counselor'] || private.tab_roles('en-vivo'));
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
        'current_teacher_name', (select r.teacher_name from private.student_room_at(p.student_id, now()) r),
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

create or replace function public.report_summary(p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  s public.settings;
begin
  perform private.require_role(a, array['coordinator', 'director', 'admin'] || private.tab_roles('reportes'));
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
  perform private.require_role(a, array['coordinator', 'director', 'admin'] || private.tab_roles('reportes'));
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
  perform private.require_role(a, array['prefect', 'nurse', 'coordinator', 'director', 'admin'] || private.tab_roles('historial'));
  -- Enfermería sin otro rol ve solo enfermería; un rol al que se le dio Historial ve todo.
  v_nurse_only := not (a.roles && (array['prefect', 'coordinator', 'director', 'admin']
                                   || array_remove(private.tab_roles('historial'), 'nurse')));

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

create or replace function public.pass_timeline(p_pass_id uuid) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
begin
  perform private.require_role(a, array['prefect', 'nurse', 'coordinator', 'director', 'admin'] || private.tab_roles('historial'));
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', e.type, 'at', e.at, 'actor', s.full_name, 'from_device', e.device_id is not null,
      'payload', e.payload) order by e.id)
      from public.pass_events e left join public.staff s on s.id = e.actor_id
     where e.pass_id = p_pass_id), '[]'::jsonb);
end;
$$;

create or replace function public.nurse_today() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_today date := (now() at time zone 'America/Mexico_City')::date;
begin
  perform private.require_role(a, array['nurse', 'coordinator', 'director', 'admin'] || private.tab_roles('enfermeria'));
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

create or replace function public.me() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_staff public.staff;
  v_device record;
  v_email text := auth.jwt() ->> 'email';
  v_anon boolean := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
begin
  if auth.uid() is null then
    return jsonb_build_object('kind', 'none');
  end if;

  select * into v_staff from public.staff where auth_user_id = auth.uid();
  if not found and not v_anon and v_email is not null then
    -- Usuario que ya existía en auth antes de darlo de alta en staff.
    update public.staff set auth_user_id = auth.uid()
     where lower(email) = lower(v_email) and auth_user_id is null
    returning * into v_staff;
  end if;

  if v_staff.id is not null and v_staff.active then
    return jsonb_build_object(
      'kind', 'staff',
      'id', v_staff.id,
      'full_name', v_staff.full_name,
      'email', v_staff.email,
      'roles', to_jsonb(v_staff.roles),
      'tabs', to_jsonb(private.staff_tabs(v_staff.roles)),
      'has_pin', v_staff.pin_set_at is not null
    );
  end if;

  select d.id, d.label, d.group_id, g.name as group_name
    into v_device
    from public.devices d join public.groups g on g.id = d.group_id
   where d.auth_user_id = auth.uid() and d.revoked_at is null;
  if found then
    update public.devices set last_seen_at = now() where id = v_device.id;
    return jsonb_build_object(
      'kind', 'device',
      'id', v_device.id,
      'label', v_device.label,
      'group_id', v_device.group_id,
      'group_name', v_device.group_name
    );
  end if;

  return jsonb_build_object('kind', 'none', 'email', v_email, 'anonymous', v_anon);
end;
$$;
