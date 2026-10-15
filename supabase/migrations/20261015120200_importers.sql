-- Fase 1 · Importación de CSV (plantillas en data/templates/).
-- Cada función recibe un arreglo JSON de filas con las columnas de la plantilla y
-- `_row` (número de línea en el archivo). Primero valida todo; si hay algún error,
-- no cambia nada y devuelve {ok:false, errors:[{row, message}]}. Si todo está bien,
-- aplica los cambios y devuelve {ok:true, summary:{...}}.

create function private.require_manager() returns void
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not private.can_manage() then
    raise exception 'Solo coordinación, dirección o admin' using errcode = '42501';
  end if;
end;
$$;

-- Texto normalizado para comparar nombres: minúsculas, sin acentos, espacios simples.
create function private.norm(p text) returns text
language sql immutable set search_path = ''
as $$
  select translate(lower(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g')),
                   'áéíóúüñàèìòù', 'aeiouunaeiou');
$$;

create function private.clean(p text) returns text
language sql immutable set search_path = ''
as $$
  select nullif(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g'), '');
$$;

create function private.import_error(p_errors jsonb) returns jsonb
language sql immutable set search_path = ''
as $$
  select jsonb_build_object('ok', false, 'errors', p_errors);
$$;

-- ---------------------------------------------------------------------------
-- grupos.csv: grupo, salon, orden
-- ---------------------------------------------------------------------------
create function public.import_groups(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  v_errors jsonb := '[]';
  v_seen text[] := '{}';
  v_name text;
  v_inserted int := 0;
  v_updated int := 0;
begin
  perform private.require_manager();

  for r in select e.value as v, coalesce((e.value ->> '_row')::int, e.ordinality::int + 1) as line
             from jsonb_array_elements(p_rows) with ordinality e loop
    v_name := private.clean(r.v ->> 'grupo');
    if v_name is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Falta el grupo');
      continue;
    end if;
    if private.norm(v_name) = any (v_seen) then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', format('El grupo %s está repetido', v_name));
    end if;
    v_seen := v_seen || private.norm(v_name);
    if private.clean(r.v ->> 'orden') is not null and private.clean(r.v ->> 'orden') !~ '^\d{1,4}$' then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'El orden debe ser un número');
    end if;
  end loop;

  if jsonb_array_length(v_errors) > 0 then
    return private.import_error(v_errors);
  end if;

  for r in select e.value as v from jsonb_array_elements(p_rows) e loop
    v_name := private.clean(r.v ->> 'grupo');
    update public.groups
       set name = v_name,
           room = private.clean(r.v ->> 'salon'),
           sort = private.clean(r.v ->> 'orden')::int
     where private.norm(name) = private.norm(v_name);
    if found then
      v_updated := v_updated + 1;
    else
      insert into public.groups (name, room, sort)
      values (v_name, private.clean(r.v ->> 'salon'), private.clean(r.v ->> 'orden')::int);
      v_inserted := v_inserted + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'summary',
    jsonb_build_object('inserted', v_inserted, 'updated', v_updated));
end;
$$;

-- ---------------------------------------------------------------------------
-- personal.csv: nombre_completo, correo, roles (separados por ; o ,), whatsapp
-- No da de baja a quien no venga en el archivo (eso se hace en Personal y PIN).
-- ---------------------------------------------------------------------------
create function public.import_staff(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  v_errors jsonb := '[]';
  v_seen text[] := '{}';
  v_email text;
  v_roles text[];
  v_bad text[];
  v_inserted int := 0;
  v_updated int := 0;
  c_valid constant text[] := array['teacher', 'prefect', 'nurse', 'coordinator', 'director', 'admin'];
begin
  perform private.require_manager();

  for r in select e.value as v, coalesce((e.value ->> '_row')::int, e.ordinality::int + 1) as line
             from jsonb_array_elements(p_rows) with ordinality e loop
    if private.clean(r.v ->> 'nombre_completo') is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Falta el nombre');
    end if;

    v_email := lower(private.clean(r.v ->> 'correo'));
    if v_email is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Falta el correo');
    elsif v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', format('Correo no válido: %s', v_email));
    elsif v_email = any (v_seen) then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', format('El correo %s está repetido', v_email));
    else
      v_seen := v_seen || v_email;
    end if;

    v_roles := array(
      select distinct lower(btrim(x))
        from regexp_split_to_table(coalesce(r.v ->> 'roles', ''), '[;,]') x
       where btrim(x) <> '');
    v_bad := array(select x from unnest(v_roles) x where not x = any (c_valid));
    if cardinality(v_roles) = 0 then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
        'Faltan los roles (teacher, prefect, nurse, coordinator, director, admin)');
    elsif cardinality(v_bad) > 0 then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
        format('Rol desconocido: %s', array_to_string(v_bad, ', ')));
    end if;

    if private.clean(r.v ->> 'whatsapp') is not null
       and regexp_replace(r.v ->> 'whatsapp', '\D', '', 'g') !~ '^\d{10,13}$' then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'WhatsApp debe tener 10 a 13 dígitos');
    end if;
  end loop;

  if jsonb_array_length(v_errors) > 0 then
    return private.import_error(v_errors);
  end if;

  for r in select e.value as v from jsonb_array_elements(p_rows) e loop
    v_email := lower(private.clean(r.v ->> 'correo'));
    v_roles := array(
      select distinct lower(btrim(x))
        from regexp_split_to_table(r.v ->> 'roles', '[;,]') x
       where btrim(x) <> '');
    update public.staff
       set full_name = private.clean(r.v ->> 'nombre_completo'),
           roles = v_roles,
           whatsapp = nullif(regexp_replace(coalesce(r.v ->> 'whatsapp', ''), '\D', '', 'g'), ''),
           active = true
     where lower(email) = v_email;
    if found then
      v_updated := v_updated + 1;
    else
      insert into public.staff (full_name, email, roles, whatsapp)
      values (private.clean(r.v ->> 'nombre_completo'), v_email, v_roles,
              nullif(regexp_replace(coalesce(r.v ->> 'whatsapp', ''), '\D', '', 'g'), ''));
      v_inserted := v_inserted + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'summary',
    jsonb_build_object('inserted', v_inserted, 'updated', v_updated));
end;
$$;

-- ---------------------------------------------------------------------------
-- alumnos.csv: grupo, numero_lista, nombre_completo, sexo (H/M)
-- Reemplaza la lista de cada grupo que venga en el archivo:
--   * mismo número y mismo nombre → se actualiza;
--   * mismo número con otro nombre → el anterior se da de baja y se crea el nuevo;
--   * alumnos del grupo que no vienen en el archivo → se dan de baja (no se borran).
-- ---------------------------------------------------------------------------
create function public.import_students(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  v_errors jsonb := '[]';
  v_seen text[] := '{}';
  v_group_id uuid;
  v_groups uuid[] := '{}';
  v_key text;
  v_num int;
  v_sex text;
  v_name text;
  v_existing public.students;
  v_inserted int := 0;
  v_updated int := 0;
  v_deactivated int := 0;
begin
  perform private.require_manager();

  for r in select e.value as v, coalesce((e.value ->> '_row')::int, e.ordinality::int + 1) as line
             from jsonb_array_elements(p_rows) with ordinality e loop
    v_group_id := null;
    if private.clean(r.v ->> 'grupo') is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Falta el grupo');
    else
      select id into v_group_id from public.groups
       where private.norm(name) = private.norm(r.v ->> 'grupo');
      if v_group_id is null then
        v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
          format('No existe el grupo %s (impórtalo primero en Grupos)', private.clean(r.v ->> 'grupo')));
      end if;
    end if;

    -- plpgsql corta la condición del IF en el primer THEN: nada de CASE aquí.
    v_num := null;
    if coalesce(btrim(r.v ->> 'numero_lista'), '') ~ '^\d{1,2}$' then
      v_num := btrim(r.v ->> 'numero_lista')::int;
    end if;
    if coalesce(v_num, 0) = 0 then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'El número de lista debe ser de 1 a 99');
    elsif v_group_id is not null then
      v_key := v_group_id::text || ':' || btrim(r.v ->> 'numero_lista')::int;
      if v_key = any (v_seen) then
        v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
          format('El número %s de %s está repetido', btrim(r.v ->> 'numero_lista')::int,
                 private.clean(r.v ->> 'grupo')));
      end if;
      v_seen := v_seen || v_key;
    end if;

    if private.clean(r.v ->> 'nombre_completo') is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Falta el nombre');
    end if;

    if upper(coalesce(btrim(r.v ->> 'sexo'), '')) not in ('H', 'M') then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'El sexo debe ser H o M');
    end if;
  end loop;

  if jsonb_array_length(v_errors) > 0 then
    return private.import_error(v_errors);
  end if;

  for r in select e.value as v from jsonb_array_elements(p_rows) e loop
    select id into v_group_id from public.groups where private.norm(name) = private.norm(r.v ->> 'grupo');
    v_num := btrim(r.v ->> 'numero_lista')::int;
    v_sex := upper(btrim(r.v ->> 'sexo'));
    v_name := private.clean(r.v ->> 'nombre_completo');
    if not v_group_id = any (v_groups) then
      v_groups := v_groups || v_group_id;
    end if;

    select * into v_existing from public.students
     where group_id = v_group_id and list_number = v_num and active
     for update;

    if found and private.norm(v_existing.full_name) = private.norm(v_name) then
      update public.students set full_name = v_name, sex = v_sex where id = v_existing.id;
      v_updated := v_updated + 1;
    else
      if found then
        update public.students set active = false where id = v_existing.id;
        v_deactivated := v_deactivated + 1;
      end if;
      insert into public.students (group_id, list_number, full_name, sex)
      values (v_group_id, v_num, v_name, v_sex);
      v_inserted := v_inserted + 1;
    end if;
  end loop;

  with gone as (
    update public.students s set active = false
     where s.active and s.group_id = any (v_groups)
       and not exists (
         select 1 from jsonb_array_elements(p_rows) e
          where (select g.id from public.groups g where private.norm(g.name) = private.norm(e.value ->> 'grupo')) = s.group_id
            and btrim(e.value ->> 'numero_lista')::int = s.list_number)
    returning 1)
  select v_deactivated + count(*) into v_deactivated from gone;

  return jsonb_build_object('ok', true, 'summary',
    jsonb_build_object('inserted', v_inserted, 'updated', v_updated,
                       'deactivated', v_deactivated, 'groups', cardinality(v_groups)));
end;
$$;

-- ---------------------------------------------------------------------------
-- horario.csv: grupo, dia (lunes–viernes), inicio, fin (HH:MM), materia, correo_maestro
-- Reemplaza el horario completo de cada grupo que venga en el archivo.
-- ---------------------------------------------------------------------------
create function private.weekday_from_text(p text) returns int
language sql immutable set search_path = ''
as $$
  select case private.norm(p)
    when 'lunes' then 1 when 'martes' then 2 when 'miercoles' then 3
    when 'jueves' then 4 when 'viernes' then 5
    when '1' then 1 when '2' then 2 when '3' then 3 when '4' then 4 when '5' then 5
  end;
$$;

create function public.import_schedule(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  v_errors jsonb := '[]';
  v_group_id uuid;
  v_groups uuid[] := '{}';
  v_day int;
  v_start time;
  v_end time;
  v_teacher uuid;
  v_email text;
  v_period uuid;
  v_inserted int := 0;
  v_deleted int := 0;
begin
  perform private.require_manager();

  create temporary table if not exists pg_temp.schedule_import (
    line int, group_id uuid, weekday int, starts time, ends time, subject text, teacher_id uuid
  ) on commit drop;
  truncate pg_temp.schedule_import;

  for r in select e.value as v, coalesce((e.value ->> '_row')::int, e.ordinality::int + 1) as line
             from jsonb_array_elements(p_rows) with ordinality e loop
    v_group_id := null; v_day := null; v_start := null; v_end := null; v_teacher := null;

    select id into v_group_id from public.groups where private.norm(name) = private.norm(r.v ->> 'grupo');
    if v_group_id is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
        format('No existe el grupo %s', coalesce(private.clean(r.v ->> 'grupo'), '(vacío)')));
    end if;

    v_day := private.weekday_from_text(r.v ->> 'dia');
    if v_day is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
        format('Día no válido: %s (usa lunes a viernes)', coalesce(private.clean(r.v ->> 'dia'), '(vacío)')));
    end if;

    if coalesce(btrim(r.v ->> 'inicio'), '') ~ '^([01]?\d|2[0-3]):[0-5]\d$'
       and coalesce(btrim(r.v ->> 'fin'), '') ~ '^([01]?\d|2[0-3]):[0-5]\d$' then
      v_start := btrim(r.v ->> 'inicio')::time;
      v_end := btrim(r.v ->> 'fin')::time;
      if v_end <= v_start then
        v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'La hora de fin debe ser después del inicio');
        v_start := null;
      end if;
    else
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Las horas deben ir como HH:MM (07:30)');
    end if;

    if private.clean(r.v ->> 'materia') is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Falta la materia');
    end if;

    v_email := lower(private.clean(r.v ->> 'correo_maestro'));
    if v_email is not null then
      select id into v_teacher from public.staff where lower(email) = v_email and active;
      if v_teacher is null then
        v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
          format('No hay personal activo con el correo %s (impórtalo en Personal)', v_email));
      end if;
    end if;

    if v_group_id is not null and v_day is not null and v_start is not null then
      if exists (select 1 from pg_temp.schedule_import i
                  where i.group_id = v_group_id and i.weekday = v_day
                    and i.starts < v_end and v_start < i.ends) then
        v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
          format('Se empalma con otra clase de %s el mismo día', private.clean(r.v ->> 'grupo')));
      else
        insert into pg_temp.schedule_import
        values (r.line, v_group_id, v_day, v_start, v_end, private.clean(r.v ->> 'materia'), v_teacher);
      end if;
    end if;
  end loop;

  if jsonb_array_length(v_errors) > 0 then
    return private.import_error(v_errors);
  end if;

  select array_agg(distinct group_id) into v_groups from pg_temp.schedule_import;

  with d as (delete from public.schedule_entries where group_id = any (v_groups) returning 1)
  select count(*) into v_deleted from d;

  insert into public.periods (weekday, starts, ends)
  select distinct weekday, starts, ends from pg_temp.schedule_import
  on conflict (weekday, starts, ends) do nothing;

  insert into public.schedule_entries (group_id, period_id, subject, teacher_id)
  select i.group_id, p.id, i.subject, i.teacher_id
    from pg_temp.schedule_import i
    join public.periods p on p.weekday = i.weekday and p.starts = i.starts and p.ends = i.ends;
  get diagnostics v_inserted = row_count;

  delete from public.periods p
   where not exists (select 1 from public.schedule_entries se where se.period_id = p.id);

  return jsonb_build_object('ok', true, 'summary',
    jsonb_build_object('inserted', v_inserted, 'replaced', v_deleted,
                       'groups', coalesce(cardinality(v_groups), 0)));
end;
$$;

revoke all on function private.require_manager() from public, anon;
revoke all on function private.norm(text) from public, anon;
revoke all on function private.clean(text) from public, anon;
revoke all on function private.import_error(jsonb) from public, anon;
revoke all on function private.weekday_from_text(text) from public, anon;
grant execute on function private.require_manager() to authenticated;

revoke all on function public.import_groups(jsonb) from public, anon;
revoke all on function public.import_staff(jsonb) from public, anon;
revoke all on function public.import_students(jsonb) from public, anon;
revoke all on function public.import_schedule(jsonb) from public, anon;
grant execute on function public.import_groups(jsonb) to authenticated;
grant execute on function public.import_staff(jsonb) to authenticated;
grant execute on function public.import_students(jsonb) to authenticated;
grant execute on function public.import_schedule(jsonb) to authenticated;
