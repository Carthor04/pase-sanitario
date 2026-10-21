-- Clases por nivel (Inglés básico/intermedio/avanzado): los alumnos de un grado se reparten
-- por nivel y cada nivel se da en el salón de un grupo. En esas horas el horario de ese salón
-- (schedule_entries del grupo) dice "Inglés básico" con su docente, y la lista del salón es la
-- de la sección, no la del grupo. La sección está "en clase" cuando el horario de su salón
-- tiene su materia.
--
-- El lugar del grupo en el baño (1 niño y 1 niña por grupo) sigue siendo por grupo base.

create table public.class_sections (
  id uuid primary key default gen_random_uuid(),
  room_group_id uuid not null references public.groups (id),
  subject text not null,
  created_at timestamptz not null default now(),
  unique (room_group_id, subject)
);

create table public.class_section_students (
  section_id uuid not null references public.class_sections (id),
  student_id uuid not null references public.students (id),
  primary key (section_id, student_id)
);
create index class_section_students_by_student on public.class_section_students (student_id);

alter table public.class_sections enable row level security;
alter table public.class_section_students enable row level security;
create policy class_sections_select on public.class_sections for select to authenticated
  using ((select private.current_staff_id()) is not null);
create policy class_section_students_select on public.class_section_students for select to authenticated
  using ((select private.current_staff_id()) is not null);
grant select on public.class_sections, public.class_section_students to authenticated;

-- Salón donde estaba el alumno al pedir el pase (el de su grupo o el de su sección).
alter table public.passes add column room_group_id uuid references public.groups (id);
update public.passes set room_group_id = group_id where room_group_id is null;

-- ---------------------------------------------------------------------------
-- Dónde está cada quien
-- ---------------------------------------------------------------------------

-- Sección que se da en un salón a esa hora (o ninguna).
create function private.room_section_at(p_room uuid, p_at timestamptz) returns uuid
language sql stable security definer set search_path = ''
as $$
  select cs.id from public.class_sections cs
    join public.classes_at(p_at) c on c.group_id = cs.room_group_id and c.subject = cs.subject
   where cs.room_group_id = p_room
   limit 1;
$$;

-- Alumnos que están en un salón a esa hora: los de la sección que se da ahí o, si no hay,
-- los del grupo.
create function private.room_students_at(p_room uuid, p_at timestamptz) returns setof uuid
language sql stable security definer set search_path = ''
as $$
  with sec as (select private.room_section_at(p_room, p_at) as id)
  select m.student_id from public.class_section_students m
    join public.students s on s.id = m.student_id and s.active
   where m.section_id = (select id from sec)
  union all
  select s.id from public.students s
   where s.group_id = p_room and s.active and (select id from sec) is null;
$$;

-- Dónde está un alumno a esa hora: salón, sección (si está en una), materia y docente.
create function private.student_room_at(p_student uuid, p_at timestamptz)
returns table (room_group_id uuid, section_id uuid, subject text, teacher_id uuid, teacher_name text)
language sql stable security definer set search_path = ''
as $$
  select x.room_group_id, x.section_id, x.subject, x.teacher_id, x.teacher_name from (
    select cs.room_group_id, cs.id as section_id, c.subject, c.teacher_id, c.teacher_name, 0 as o
      from public.class_section_students m
      join public.class_sections cs on cs.id = m.section_id
      join public.classes_at(p_at) c on c.group_id = cs.room_group_id and c.subject = cs.subject
     where m.student_id = p_student
    union all
    select st.group_id, null, c.subject, c.teacher_id, c.teacher_name, 1
      from public.students st
      left join public.classes_at(p_at) c on c.group_id = st.group_id
     where st.id = p_student
  ) x
  order by o
  limit 1
$$;

-- Maestro con quien está ahora el alumno de un pase (para alertas y avisos).
create function private.pass_teacher_now(p_pass uuid) returns uuid
language sql stable security definer set search_path = ''
as $$
  select r.teacher_id from public.passes p, private.student_room_at(p.student_id, now()) r
   where p.id = p_pass;
$$;

-- ¿Puede la computadora de este salón operar al alumno? Sí si está en el salón ahora o si
-- el pase salió de este salón.
create function private.device_may_operate(a private.actor, p_student uuid, p_room uuid default null)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select a.device_group_id is null
      or coalesce(p_room = a.device_group_id, false)
      or exists (select 1 from private.room_students_at(a.device_group_id, now()) s
                  where s = p_student);
$$;

revoke all on function private.room_section_at(uuid, timestamptz) from public, anon, authenticated;
revoke all on function private.room_students_at(uuid, timestamptz) from public, anon, authenticated;
revoke all on function private.student_room_at(uuid, timestamptz) from public, anon, authenticated;
revoke all on function private.pass_teacher_now(uuid) from public, anon, authenticated;
revoke all on function private.device_may_operate(private.actor, uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Lista del salón (celular y computadora del salón)
-- ---------------------------------------------------------------------------
create function public.room_roster(p_group_id uuid) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_device_group uuid := private.current_device_group_id();
  v_section uuid := private.room_section_at(p_group_id, now());
begin
  if private.current_staff_id() is null
     and (v_device_group is null or v_device_group <> p_group_id) then
    raise exception 'Sin acceso a este grupo' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'section', (
      select jsonb_build_object('id', cs.id, 'subject', cs.subject,
        'teacher_name', c.teacher_name, 'starts', c.starts, 'ends', c.ends)
        from public.class_sections cs
        left join public.classes_at(now()) c on c.group_id = cs.room_group_id and c.subject = cs.subject
       where cs.id = v_section),
    'students', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'list_number', s.list_number, 'full_name', s.full_name, 'sex', s.sex,
        'group_id', s.group_id, 'group_name', g.name)
        order by s.full_name, g.name)
        from public.students s join public.groups g on g.id = s.group_id
       where s.id in (select private.room_students_at(p_group_id, now()))), '[]'::jsonb));
end;
$$;
revoke all on function public.room_roster(uuid) from public, anon;
grant execute on function public.room_roster(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Importar secciones (secciones.csv: salon_grupo, materia, grupo, numero_lista)
-- Reemplaza la lista de cada sección que venga en el archivo. No borra alumnos.
-- ---------------------------------------------------------------------------
create function public.import_sections(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  v_errors jsonb := '[]';
  v_room uuid;
  v_student uuid;
  v_section uuid;
  v_sections uuid[] := '{}';
  v_seen text[] := '{}';
  v_inserted int := 0;
  v_removed int := 0;
begin
  perform private.require_manager();

  for r in select e.value as v, coalesce((e.value ->> '_row')::int, e.ordinality::int + 1) as line
             from jsonb_array_elements(p_rows) with ordinality e loop
    v_room := null; v_student := null;
    select id into v_room from public.groups where private.norm(name) = private.norm(r.v ->> 'salon_grupo');
    if v_room is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
        format('No existe el grupo del salón %s', coalesce(private.clean(r.v ->> 'salon_grupo'), '(vacío)')));
    end if;
    if private.clean(r.v ->> 'materia') is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Falta la materia');
    end if;
    if coalesce(btrim(r.v ->> 'numero_lista'), '') ~ '^\d{1,2}$' then
      select s.id into v_student from public.students s join public.groups g on g.id = s.group_id
       where private.norm(g.name) = private.norm(r.v ->> 'grupo')
         and s.list_number = btrim(r.v ->> 'numero_lista')::int and s.active;
    end if;
    if v_student is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
        format('No hay alumno activo #%s en %s', coalesce(btrim(r.v ->> 'numero_lista'), '?'),
               coalesce(private.clean(r.v ->> 'grupo'), '(vacío)')));
    elsif v_student::text || private.norm(r.v ->> 'materia') = any (v_seen) then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Alumno repetido en la misma materia');
    else
      v_seen := v_seen || (v_student::text || private.norm(r.v ->> 'materia'));
    end if;
  end loop;

  if jsonb_array_length(v_errors) > 0 then
    return private.import_error(v_errors);
  end if;

  for r in select e.value as v from jsonb_array_elements(p_rows) e loop
    select id into v_room from public.groups where private.norm(name) = private.norm(r.v ->> 'salon_grupo');
    insert into public.class_sections (room_group_id, subject)
    values (v_room, private.clean(r.v ->> 'materia'))
    on conflict (room_group_id, subject) do update set subject = excluded.subject
    returning id into v_section;
    if not v_section = any (v_sections) then
      with d as (delete from public.class_section_students where section_id = v_section returning 1)
      select v_removed + count(*) into v_removed from d;
      v_sections := v_sections || v_section;
    end if;
    select s.id into v_student from public.students s join public.groups g on g.id = s.group_id
     where private.norm(g.name) = private.norm(r.v ->> 'grupo')
       and s.list_number = btrim(r.v ->> 'numero_lista')::int and s.active;
    insert into public.class_section_students (section_id, student_id) values (v_section, v_student);
    v_inserted := v_inserted + 1;
  end loop;

  return jsonb_build_object('ok', true, 'summary',
    jsonb_build_object('sections', cardinality(v_sections), 'students', v_inserted, 'replaced', v_removed));
end;
$$;
revoke all on function public.import_sections(jsonb) from public, anon;
grant execute on function public.import_sections(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Motor: permisos del equipo del salón y salón/clase de salida
-- ---------------------------------------------------------------------------
create or replace function private.lock_pass(p_pass uuid, a private.actor) returns public.passes
language plpgsql security definer set search_path = ''
as $$
declare
  v_dest text;
  v_pass public.passes;
begin
  select destination_id into v_dest from public.passes where id = p_pass;
  if v_dest is null then
    raise exception 'Pase no encontrado' using errcode = 'P0002';
  end if;
  perform 1 from public.destinations where id = v_dest for update;
  select * into v_pass from public.passes where id = p_pass for update;
  if not private.device_may_operate(a, v_pass.student_id, v_pass.room_group_id) then
    raise exception 'Este equipo solo opera pases de su salón' using errcode = '42501';
  end if;
  return v_pass;
end;
$$;

create or replace function public.request_pass(p_student_id uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  st public.students;
  d public.destinations;
  v_status public.pass_status;
  v_id uuid;
  v_room record;
begin
  perform private.require_role(a, array['teacher', 'coordinator', 'admin']);

  select * into st from public.students where id = p_student_id and active;
  if not found then
    raise exception 'Alumno no encontrado' using errcode = 'P0002';
  end if;
  if not private.device_may_operate(a, st.id) then
    raise exception 'Este equipo solo opera alumnos de su salón' using errcode = '42501';
  end if;

  if p_kind = 'bathroom' then
    select * into d from public.destinations
     where kind = 'bathroom' and sex = st.sex order by id limit 1 for update;
  elsif p_kind = 'nurse' then
    select * into d from public.destinations where kind = 'nurse' order by id limit 1 for update;
  else
    raise exception 'Tipo de pase no válido: usa bathroom o nurse' using errcode = '22023';
  end if;
  if not found then
    raise exception 'No hay destino configurado para este pase' using errcode = 'P0002';
  end if;

  if exists (select 1 from public.passes where student_id = st.id
              and status in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning')) then
    raise exception 'El alumno ya tiene un pase activo' using errcode = 'P0001';
  end if;

  if private.group_slot_taken(d, st.group_id) then
    v_status := 'group_wait';
  elsif private.has_room(d) and not private.has_queue(d.id) then
    v_status := 'out';
  elsif d.queue_enabled then
    v_status := 'queued';
  else
    raise exception '% está lleno', d.label using errcode = 'P0001';
  end if;

  -- Dónde estaba: en su sección (con el salón) o con su grupo.
  select r.room_group_id, r.section_id,
         case when r.section_id is not null
              then r.subject || coalesce(' · ' || g.room, '')
              else r.subject end as subject
    into v_room
    from private.student_room_at(st.id, now()) r
    left join public.groups g on g.id = r.room_group_id;

  begin
    insert into public.passes (
      student_id, group_id, destination_id, status, requested_at, queue_ts, started_at,
      opened_by, device_id, period_subject, room_group_id)
    values (
      st.id, st.group_id, d.id, v_status, clock_timestamp(),
      case when v_status = 'queued' then clock_timestamp() end,
      case when v_status = 'out' then clock_timestamp() end,
      a.staff_id, a.device_id, v_room.subject,
      coalesce(a.device_group_id, v_room.room_group_id, st.group_id))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'El alumno ya tiene un pase activo' using errcode = 'P0001';
  end;

  perform private.log_pass_event(v_id, 'requested', a, jsonb_build_object('status', v_status));
  return private.pass_json(v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Pantallas del salón: pases de quien está en el salón o salió de él
-- ---------------------------------------------------------------------------
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
        'group_name', sg.name,
        'status', p.status,
        'destination_id', p.destination_id,
        'destination_kind', d.kind,
        'destination_label', d.label,
        'requested_at', p.requested_at,
        'queue_ts', p.queue_ts,
        'called_at', p.called_at,
        'started_at', p.started_at,
        'arrived_at', p.arrived_at,
        'left_nurse_at', p.left_nurse_at,
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
        join public.groups sg on sg.id = s.group_id
        join public.destinations d on d.id = p.destination_id
        left join public.staff o on o.id = p.opened_by
       where (p.room_group_id = p_group_id
              or p.student_id in (select private.room_students_at(p_group_id, now())))
         and p.status in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning')), '[]'::jsonb),
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

create or replace function public.group_today_counts(p_group_id uuid) returns jsonb
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
           where (p.group_id = p_group_id
                  or p.student_id in (select private.room_students_at(p_group_id, now())))
             and p.started_at is not null
             and (p.started_at at time zone 'America/Mexico_City')::date = v_today
           group by p.student_id) c), '{}'::jsonb));
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
          or not (v_device_group = (select group_id from public.students where id = p_student_id)
                  or p_student_id in (select private.room_students_at(v_device_group, now())))) then
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

-- ---------------------------------------------------------------------------
-- Maestro a cargo ahora = el del salón donde está el alumno (su sección o su grupo)
-- ---------------------------------------------------------------------------
create or replace function private.recipients(p_pass uuid, p_channel text) returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select distinct s.id from public.staff s
   where s.active and (
     (private.rule_on('prefect', p_channel) and 'prefect' = any (s.roles))
     or (private.rule_on('coordinator', p_channel) and 'coordinator' = any (s.roles))
     or (private.rule_on('director', p_channel) and 'director' = any (s.roles))
     or (private.rule_on('current_teacher', p_channel) and s.id = private.pass_teacher_now(p_pass))
     or (private.rule_on('authorizing_teacher', p_channel) and s.id in (
           select p.opened_by from public.passes p where p.id = p_pass)));
$$;

create or replace function public.my_alerts() returns jsonb
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
      'group_id', coalesce(r.room_group_id, p.group_id), 'group_name', g.name, 'status', p.status,
      'destination_label', d.label, 'started_at', p.started_at,
      'period_subject', p.period_subject, 'alert', private.alert_json(p.id)
    ) order by al.created_at)
      from public.alerts al
      join public.passes p on p.id = al.pass_id
      join public.students s on s.id = p.student_id
      join public.groups g on g.id = p.group_id
      join public.destinations d on d.id = p.destination_id
      left join lateral private.student_room_at(p.student_id, now()) r on true
     where al.resolved_at is null
       and ((private.rule_on('authorizing_teacher', 'app') and p.opened_by = v_me)
            or (private.rule_on('current_teacher', 'app') and r.teacher_id = v_me))), '[]'::jsonb);
end;
$$;

create or replace function public.live_board() returns jsonb
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

create or replace function private.enqueue_alert_notification(p_alert public.alerts, p_kind text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p record;
  v_min int;
  v_body text;
  v_title text;
begin
  select ps.id, ps.status, ps.started_at, ps.ended_at, ps.period_subject, st.full_name,
         g.name as group_name, d.label as place, ps.group_id,
         (select r.teacher_name from private.student_room_at(ps.student_id, now()) r) as teacher
    into p
    from public.passes ps
    join public.students st on st.id = ps.student_id
    join public.groups g on g.id = ps.group_id
    join public.destinations d on d.id = ps.destination_id
   where ps.id = p_alert.pass_id;

  v_min := greatest(0, floor(extract(epoch from (coalesce(p.ended_at, clock_timestamp()) - p.started_at)) / 60))::int;

  case p_kind
    when 'alert' then
      v_title := 'Alerta · ' || v_min || ' min fuera';
      v_body := format('⚠️ %s (%s) lleva %s min fuera · %s%s', p.full_name, p.group_name, v_min, p.place,
        case when p.period_subject is not null
             then ' · Clase: ' || p.period_subject || coalesce(', ' || p.teacher, '') else '' end);
    when 'escalated' then
      v_title := 'Sin atender';
      v_body := format('🔴 SIN ATENDER · %s (%s) · %s min · %s', p.full_name, p.group_name, v_min, p.place);
    when 'acknowledged' then
      v_title := 'Alerta atendida';
      v_body := format('👤 %s atiende a %s (%s)',
        (select full_name from public.staff where id = p_alert.acknowledged_by), p.full_name, p.group_name);
    when 'resolved' then
      v_title := 'Resuelto';
      v_body := format('✅ %s (%s) %s · %s min', p.full_name, p.group_name,
        case p_alert.resolution when 'released' then 'liberado por prefectura'
                                when 'arrived' then 'llegó a enfermería' else 'regresó' end, v_min);
  end case;

  insert into public.notifications_outbox (channel, kind, recipient_staff_id, pass_id, body, payload)
  select 'push', p_kind, r, p.id, v_body,
         jsonb_build_object('title', v_title, 'tag', 'pase-' || p.id, 'url',
           case when exists (select 1 from public.staff s where s.id = r
                              and s.roles && array['prefect', 'coordinator', 'director', 'admin'])
                then '/en-vivo' else '/alertas' end,
           'level', p_alert.level)
    from private.recipients(p.id, 'push') r
   -- Solo a quien tiene al menos un equipo registrado: lo demás no se puede entregar.
   where exists (select 1 from public.push_subscriptions ps where ps.staff_id = r);

  if (select whatsapp_enabled from public.settings where id = 1) then
    insert into public.notifications_outbox (channel, kind, pass_id, body)
    values ('whatsapp', p_kind, p.id, v_body);
  end if;
end;
$$;

create or replace function private.enqueue_returning_notification(p_pass uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p record;
begin
  select ps.id, st.full_name, g.name as group_name,
         coalesce((select r.room_group_id from private.student_room_at(ps.student_id, now()) r),
                  ps.group_id) as room
    into p
    from public.passes ps
    join public.students st on st.id = ps.student_id
    join public.groups g on g.id = ps.group_id
   where ps.id = p_pass;

  -- Al maestro a cargo ahora y al que autorizó la salida (según las reglas de push).
  insert into public.notifications_outbox (channel, kind, recipient_staff_id, pass_id, body, payload)
  select 'push', 'returning', s.id, p.id,
         format('🏫 %s (%s) salió de enfermería y va de regreso al salón. Marca su regreso al llegar.',
                p.full_name, p.group_name),
         jsonb_build_object('title', 'De regreso al salón', 'tag', 'pase-' || p.id,
                            'url', '/grupo?g=' || p.room)
    from public.staff s
   where s.active
     and exists (select 1 from public.push_subscriptions ps where ps.staff_id = s.id)
     and ((private.rule_on('current_teacher', 'push') and s.id = private.pass_teacher_now(p.id))
          or (private.rule_on('authorizing_teacher', 'push') and s.id in (
            select ps.opened_by from public.passes ps where ps.id = p.id)));
end;
$$;

create or replace function private.enqueue_turn_notification(p_pass uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p record;
  v_minutes int;
begin
  select ps.id, ps.opened_by, st.full_name, g.name as group_name, d.label as place,
         coalesce(ps.room_group_id, ps.group_id) as room
    into p
    from public.passes ps
    join public.students st on st.id = ps.student_id
    join public.groups g on g.id = ps.group_id
    join public.destinations d on d.id = ps.destination_id
   where ps.id = p_pass;
  select confirm_turn_minutes into v_minutes from public.settings where id = 1;

  insert into public.notifications_outbox (channel, kind, recipient_staff_id, pass_id, body, payload)
  select 'push', 'turn', s.id, p.id,
         format('🔔 Turno de %s (%s) · %s. Confirma su salida en %s min o pasa al siguiente.',
                p.full_name, p.group_name, p.place, v_minutes),
         jsonb_build_object('title', 'Turno de ' || p.full_name, 'tag', 'pase-' || p.id,
                            'url', '/grupo?g=' || p.room, 'level', 2)
    from public.staff s
   where s.active
     and exists (select 1 from public.push_subscriptions ps where ps.staff_id = s.id)
     and ((private.rule_on('authorizing_teacher', 'push') and s.id = p.opened_by)
          or (private.rule_on('current_teacher', 'push') and s.id = private.pass_teacher_now(p.id)));
end;
$$;

create or replace function private.waiting_item(p public.passes, p_names boolean, p_since timestamptz)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'group_name', (select name from public.groups where id = p.group_id),
    'status', p.status,
    'since', p_since)
  || case when p_names then jsonb_build_object(
       'full_name', st.full_name,
       'list_number', st.list_number,
       'subject', p.period_subject,
       'opened_by', (select full_name from public.staff where id = p.opened_by),
       'current_teacher', (select r.teacher_name from private.student_room_at(p.student_id, now()) r))
     else '{}'::jsonb end
    from public.students st where st.id = p.student_id;
$$;
