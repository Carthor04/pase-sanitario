-- Ayudantes para las pruebas SQL. scripts/db-test.mjs los antepone a cada archivo y
-- corre todo dentro de una transacción que siempre se revierte: no deja datos.

-- Crea personal y su usuario de auth (el trigger los vincula).
create function pg_temp.make_staff(p_id uuid, p_email text, p_roles text[]) returns uuid
language plpgsql as $$
begin
  insert into public.staff (id, full_name, email, roles)
  values (p_id, 'Prueba ' || p_email, p_email, p_roles);
  insert into auth.users (id, email, aud, role, is_anonymous)
  values (p_id, p_email, 'authenticated', 'authenticated', false);
  return p_id;
end;
$$;

create function pg_temp.make_anon(p_id uuid) returns uuid
language plpgsql as $$
begin
  insert into auth.users (id, aud, role, is_anonymous)
  values (p_id, 'authenticated', 'authenticated', true);
  return p_id;
end;
$$;

-- Actúa como ese usuario (rol authenticated + claims del JWT).
create function pg_temp.login(p_uid uuid, p_anon boolean default false) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', p_uid, 'role', 'authenticated', 'is_anonymous', p_anon,
    'email', (select email from auth.users where id = p_uid))::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create function pg_temp.logout() returns void
language plpgsql as $$
begin
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

-- Fase 2 ----------------------------------------------------------------------

create function pg_temp.make_group(p_name text) returns uuid
language sql as $$
  insert into public.groups (name, sort) values (p_name, 990) returning id;
$$;

create function pg_temp.make_student(p_group uuid, p_n int, p_sex text) returns uuid
language sql as $$
  insert into public.students (group_id, list_number, full_name, sex)
  values (p_group, p_n, 'Alumno ' || p_n || p_sex, p_sex) returning id;
$$;

-- Deja el motor en un estado conocido, solo dentro de la transacción de la prueba:
-- aparta los pases activos reales y fija las reglas por defecto.
create function pg_temp.reset_engine() returns void
language plpgsql as $$
begin
  perform set_config('role', 'none', true);
  update public.passes set status = 'cancelled'
   where status in ('group_wait', 'queued', 'called', 'out', 'arrived');
  update public.bathroom_pauses set resumed_at = clock_timestamp() where resumed_at is null;
  delete from public.bathroom_closures;
  update public.destinations
     set capacity = 1, per_group_limit = 1, uses_group_slot = true, queue_enabled = true
   where id = 'bath_h';
  update public.destinations
     set capacity = 3, per_group_limit = 1, uses_group_slot = true, queue_enabled = true
   where id = 'bath_m';
  update public.destinations
     set capacity = null, per_group_limit = null, uses_group_slot = false, queue_enabled = false
   where id = 'nurse';
  update public.settings
     set confirm_turn_minutes = 2, undo_seconds = 10, pin_max_attempts = 5,
         pin_lockout_seconds = 60, auto_lock_after_class_minutes = 5,
         unlock_without_class_minutes = 15
   where id = 1;
end;
$$;

create function pg_temp.st(p_pass uuid) returns text
language sql as $$
  select status::text from public.passes where id = p_pass;
$$;

-- request_pass que devuelve solo el id.
create function pg_temp.req(p_student uuid, p_kind text default 'bathroom') returns uuid
language sql as $$
  select (public.request_pass(p_student, p_kind) ->> 'id')::uuid;
$$;
