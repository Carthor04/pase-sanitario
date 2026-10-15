-- Fase 4 · Alertas, prefectura y enfermería (SPEC §7).
-- tick() crea la alerta cuando un pase lleva alert_minutes en "out" (en enfermería solo
-- cuenta el trayecto) y la escala si nadie la atiende en escalate_minutes. La alerta se
-- resuelve sola cuando el pase regresa, se libera o llega a enfermería (trigger), y se
-- reabre si se deshace el regreso.

alter table public.pass_events drop constraint pass_events_type_check;
alter table public.pass_events add constraint pass_events_type_check check (type in (
  'requested', 'promoted', 'called', 'confirmed', 'ceded', 'turn_expired',
  'arrived', 'returned', 'released', 'cancelled', 'undo', 'alert', 'escalated',
  'alert_ack', 'note'));

create table public.alerts (
  id uuid primary key default gen_random_uuid(),
  pass_id uuid not null references public.passes (id),
  level int not null default 1 check (level in (1, 2)),
  created_at timestamptz not null default clock_timestamp(),
  escalated_at timestamptz,
  acknowledged_by uuid references public.staff (id),
  acknowledged_at timestamptz,
  resolved_at timestamptz,
  resolution text check (resolution in ('returned', 'released', 'arrived'))
);
create unique index alerts_one_per_pass on public.alerts (pass_id);
create index alerts_open on public.alerts (created_at) where resolved_at is null;

create table public.nurse_notes (
  id bigserial primary key,
  pass_id uuid not null references public.passes (id),
  author_id uuid not null references public.staff (id),
  body text not null check (btrim(body) <> '' and length(body) <= 500),
  created_at timestamptz not null default clock_timestamp()
);
create index nurse_notes_by_pass on public.nurse_notes (pass_id, id desc);

alter table public.alerts enable row level security;
alter table public.nurse_notes enable row level security;

grant select on public.alerts to authenticated;
create policy alerts_select on public.alerts for select to authenticated
  using ((select private.current_staff_id()) is not null);

-- La nota interna la ven enfermería, coordinación y dirección (no los maestros).
grant select on public.nurse_notes to authenticated;
create policy nurse_notes_select on public.nurse_notes for select to authenticated
  using ((select private.has_any_role(array['nurse', 'coordinator', 'director', 'admin'])));

alter publication supabase_realtime add table public.alerts;

-- ---------------------------------------------------------------------------
-- Resolver / reabrir alertas cuando cambia el pase
-- ---------------------------------------------------------------------------
create function private.sync_alert_on_pass_change() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.status in ('returned', 'released', 'arrived') then
    update public.alerts
       set resolved_at = clock_timestamp(), resolution = new.status::text
     where pass_id = new.id and resolved_at is null;
  elsif old.status = 'returned' and new.status in ('out', 'arrived') then
    -- Se deshizo el regreso: la alerta vuelve a estar abierta.
    update public.alerts set resolved_at = null, resolution = null
     where pass_id = new.id and resolution = 'returned';
  end if;
  return new;
end;
$$;

create trigger passes_sync_alert
  after update of status on public.passes
  for each row when (old.status is distinct from new.status)
  execute function private.sync_alert_on_pass_change();

-- ---------------------------------------------------------------------------
-- tick(): vence turnos, crea y escala alertas, registra autobloqueos.
-- ---------------------------------------------------------------------------
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

  -- Alerta: alert_minutes fuera del salón. En enfermería solo el trayecto ("out").
  for r in
    insert into public.alerts (pass_id)
    select ps.id from public.passes ps
     where ps.status = 'out'
       and ps.started_at < clock_timestamp() - make_interval(mins => s.alert_minutes)
       and not exists (select 1 from public.alerts a where a.pass_id = ps.id)
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

-- ---------------------------------------------------------------------------
-- "Yo lo atiendo" y notas de enfermería
-- ---------------------------------------------------------------------------
create function public.acknowledge_alert(p_alert_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  al public.alerts;
begin
  perform private.require_role(a, array['prefect', 'coordinator', 'admin']);
  select * into al from public.alerts where id = p_alert_id for update;
  if not found then
    raise exception 'Alerta no encontrada' using errcode = 'P0002';
  end if;
  if al.resolved_at is not null then
    raise exception 'Esa alerta ya se resolvió' using errcode = 'P0001';
  end if;
  if al.acknowledged_by is not null and al.acknowledged_by <> a.staff_id then
    raise exception 'Ya la atiende %', (select full_name from public.staff where id = al.acknowledged_by)
      using errcode = 'P0001';
  end if;
  update public.alerts set acknowledged_by = a.staff_id, acknowledged_at = clock_timestamp()
   where id = al.id;
  perform private.log_pass_event(al.pass_id, 'alert_ack', a);
  return jsonb_build_object('ok', true);
end;
$$;

create function public.add_nurse_note(p_pass_id uuid, p_body text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_body text := btrim(coalesce(p_body, ''));
begin
  perform private.require_role(a, array['nurse', 'coordinator', 'admin']);
  if v_body = '' then
    raise exception 'Escribe la nota' using errcode = '22023';
  end if;
  if (select d.kind from public.passes p join public.destinations d on d.id = p.destination_id
       where p.id = p_pass_id) is distinct from 'nurse' then
    raise exception 'Solo los pases de enfermería llevan nota' using errcode = 'P0001';
  end if;
  insert into public.nurse_notes (pass_id, author_id, body) values (p_pass_id, a.staff_id, left(v_body, 500));
  perform private.log_pass_event(p_pass_id, 'note', a);
end;
$$;

-- ---------------------------------------------------------------------------
-- Lecturas
-- ---------------------------------------------------------------------------
create function private.alert_json(p_pass uuid) returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'id', al.id, 'level', al.level, 'created_at', al.created_at,
    'acknowledged_by_name', s.full_name, 'acknowledged_at', al.acknowledged_at)
    from public.alerts al left join public.staff s on s.id = al.acknowledged_by
   where al.pass_id = p_pass and al.resolved_at is null;
$$;

-- Monitor en vivo (prefectura, enfermería, coordinación, dirección): todos los pases activos.
create function public.live_board() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_today date := (now() at time zone 'America/Mexico_City')::date;
begin
  perform private.require_role(a, array['prefect', 'nurse', 'coordinator', 'director', 'admin']);
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
        'started_at', p.started_at, 'arrived_at', p.arrived_at,
        'period_subject', p.period_subject, 'opened_by_name', o.full_name,
        'current_teacher_name', (select c.teacher_name from public.classes_at(now()) c
                                  where c.group_id = p.group_id limit 1),
        'alert', private.alert_json(p.id)
      ) order by p.queue_ts nulls last, p.started_at nulls last, p.requested_at)
        from public.passes p
        join public.students s on s.id = p.student_id
        join public.groups g on g.id = p.group_id
        left join public.staff o on o.id = p.opened_by
       where p.status in ('group_wait', 'queued', 'called', 'out', 'arrived')), '[]'::jsonb),
    'stats', jsonb_build_object(
      'exits_today', (select count(*) from public.passes p
                       where p.started_at is not null
                         and (p.started_at at time zone 'America/Mexico_City')::date = v_today),
      'alerts_today', (select count(*) from public.alerts al
                        where (al.created_at at time zone 'America/Mexico_City')::date = v_today))
  );
end;
$$;

-- Alertas abiertas que le tocan a esta persona: es el maestro a cargo del grupo ahora
-- (según horario) o quien autorizó la salida (SPEC §7).
create function public.my_alerts() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_me uuid := private.current_staff_id();
begin
  if v_me is null then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'pass_id', p.id, 'full_name', s.full_name, 'list_number', s.list_number,
      'group_id', p.group_id, 'group_name', g.name, 'status', p.status,
      'destination_label', d.label, 'started_at', p.started_at,
      'period_subject', p.period_subject, 'alert', private.alert_json(p.id)
    ) order by al.created_at)
      from public.alerts al
      join public.passes p on p.id = al.pass_id
      join public.students s on s.id = p.student_id
      join public.groups g on g.id = p.group_id
      join public.destinations d on d.id = p.destination_id
     where al.resolved_at is null
       and (p.opened_by = v_me or exists (
             select 1 from public.classes_at(now()) c
              where c.group_id = p.group_id and c.teacher_id = v_me))), '[]'::jsonb);
end;
$$;

-- Enfermería, hoy: en camino, en enfermería y atendidos, con la última nota.
create function public.nurse_today() returns jsonb
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
        'group_name', g.name, 'status', p.status, 'started_at', p.started_at,
        'arrived_at', p.arrived_at, 'ended_at', p.ended_at, 'opened_by_name', o.full_name,
        'note', (select n.body from public.nurse_notes n where n.pass_id = p.id order by n.id desc limit 1),
        'alert', private.alert_json(p.id)
      ) order by p.started_at desc)
        from public.passes p
        join public.destinations d on d.id = p.destination_id and d.kind = 'nurse'
        join public.students s on s.id = p.student_id
        join public.groups g on g.id = p.group_id
        left join public.staff o on o.id = p.opened_by
       where p.status in ('out', 'arrived')
          or (p.started_at at time zone 'America/Mexico_City')::date = v_today), '[]'::jsonb)
  );
end;
$$;

-- group_board con la alerta de cada pase ("Prefecto Juan Pérez va en camino").
create or replace function public.group_board(p_group_id uuid) returns jsonb
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
           order by w.requested_at limit 1) end,
        'alert', private.alert_json(p.id)
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

revoke all on function private.sync_alert_on_pass_change() from public, anon, authenticated;
revoke all on function private.alert_json(uuid) from public, anon, authenticated;
revoke all on function private.tick() from public, anon, authenticated;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.acknowledge_alert(uuid)', 'public.add_nurse_note(uuid, text)',
    'public.live_board()', 'public.my_alerts()', 'public.nurse_today()']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
