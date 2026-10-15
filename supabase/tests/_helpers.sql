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
