-- Login restringido a personal activo, me() y RLS por rol.
do $$
declare
  t uuid := '00000000-0000-4000-a000-000000000001';
  c uuid := '00000000-0000-4000-a000-000000000002';
  x uuid := '00000000-0000-4000-a000-000000000003';
  a uuid := '00000000-0000-4000-a000-000000000004';
  g1 uuid;
  g2 uuid;
  v jsonb;
  n int;
begin
  perform pg_temp.make_staff(t, 'maestra.prueba@test.mx', array['teacher']);
  perform pg_temp.make_staff(c, 'coord.prueba@test.mx', array['coordinator']);

  -- Un correo que no es de personal no puede crear usuario.
  begin
    insert into auth.users (id, email, aud, role) values (x, 'intruso@gmail.com', 'authenticated', 'authenticated');
    raise exception 'debió rechazar al intruso' using errcode = 'TF001';
  exception when sqlstate 'P0001' then
    assert sqlerrm like 'Correo no registrado%', sqlerrm;
  end;

  -- Personal dado de baja tampoco.
  insert into public.staff (full_name, email, roles, active) values ('Baja', 'baja@test.mx', array['teacher'], false);
  begin
    insert into auth.users (id, email, aud, role) values (x, 'BAJA@test.mx', 'authenticated', 'authenticated');
    raise exception 'debió rechazar al personal inactivo' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;

  -- El trigger vincula staff.auth_user_id (sin importar mayúsculas).
  assert (select auth_user_id from public.staff where id = t) = t, 'no vinculó auth_user_id';

  -- Usuario anónimo (equipo de salón) sí se crea, pero no es nadie todavía.
  perform pg_temp.make_anon(a);

  insert into public.groups (name, sort) values ('T1', 901) returning id into g1;
  insert into public.groups (name, sort) values ('T2', 902) returning id into g2;
  insert into public.students (group_id, list_number, full_name, sex)
  values (g1, 1, 'Alumno Uno', 'H'), (g2, 1, 'Alumna Dos', 'M');

  -- me()
  perform pg_temp.login(t);
  v := public.me();
  assert v ->> 'kind' = 'staff' and v -> 'roles' = '["teacher"]'::jsonb, v::text;
  assert (v ->> 'has_pin')::boolean = false, 'has_pin';

  -- Maestro: lee alumnos de todos los grupos, no escribe catálogos ni ve hashes.
  select count(*) into n from public.students where group_id in (g1, g2);
  assert n = 2, format('maestro ve %s alumnos', n);
  begin
    insert into public.groups (name) values ('X1');
    raise exception 'maestro no debe crear grupos' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.staff_pins;
    raise exception 'staff_pins debe estar cerrado' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.staff set pin_set_at = now() where id = t;
    raise exception 'pin_set_at solo cambia por función' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  update public.students set full_name = 'Hackeado' where group_id = g1;
  get diagnostics n = row_count;
  assert n = 0, 'maestro no debe editar alumnos';
  select count(*) into n from public.devices;
  assert n = 0, 'maestro no ve equipos';
  perform pg_temp.logout();

  -- Coordinación: escribe catálogos.
  perform pg_temp.login(c);
  insert into public.groups (name, sort) values ('T3', 903);
  update public.settings set alert_minutes = 11 where id = 1;
  get diagnostics n = row_count;
  assert n = 1, 'coordinación debe poder cambiar settings';
  perform pg_temp.logout();

  -- Anónimo sin vincular: no ve nada.
  perform pg_temp.login(a, true);
  v := public.me();
  assert v ->> 'kind' = 'none', v::text;
  select count(*) into n from public.students;
  assert n = 0, 'anónimo no debe ver alumnos';
  select count(*) into n from public.staff;
  assert n = 0, 'anónimo no debe ver personal';
  select count(*) into n from public.groups;
  assert n = 0, 'anónimo no debe ver grupos';
  perform pg_temp.logout();

  -- Dar de baja a alguien lo saca: me() ya no lo reconoce.
  update public.staff set active = false where id = t;
  perform pg_temp.login(t);
  assert public.me() ->> 'kind' = 'none', 'personal inactivo no debe tener acceso';
  select count(*) into n from public.students;
  assert n = 0, 'personal inactivo no debe ver alumnos';
  perform pg_temp.logout();

  raise notice 'login, me() y RLS por rol: ok';
end;
$$;
