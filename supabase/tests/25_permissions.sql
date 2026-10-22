-- Permisos: el admin cambia pestañas por rol y roles por persona; nadie más.
do $$
declare
  ad uuid := '00000000-0000-4000-fe00-000000000001';
  co uuid := '00000000-0000-4000-fe00-000000000002';
  t uuid := '00000000-0000-4000-fe00-000000000003';
  pr uuid := '00000000-0000-4000-fe00-000000000004';
  pc uuid := '00000000-0000-4000-fe00-000000000005';
  g uuid;
  v jsonb;
  v_code text;
begin
  perform pg_temp.make_staff(ad, 'perm.ad@test.mx', array['admin']);
  perform pg_temp.make_staff(co, 'perm.co@test.mx', array['coordinator']);
  perform pg_temp.make_staff(t, 'perm.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(pr, 'perm.pr@test.mx', array['prefect']);
  perform pg_temp.make_anon(pc);
  g := pg_temp.make_group('P1');
  delete from public.staff_pins;
  -- Pestañas por omisión, sin importar lo que el admin haya cambiado en la escuela.
  delete from public.role_tabs;
  insert into public.role_tabs (role, tab) values
    ('teacher', 'grupo'), ('teacher', 'banos'), ('teacher', 'alertas'),
    ('prefect', 'en-vivo'), ('prefect', 'grupo'), ('prefect', 'historial'),
    ('nurse', 'enfermeria'), ('nurse', 'historial'),
    ('coordinator', 'en-vivo'), ('coordinator', 'grupo'), ('coordinator', 'reportes'), ('coordinator', 'historial'),
    ('director', 'en-vivo'), ('director', 'reportes'), ('director', 'historial'),
    ('admin', 'en-vivo'), ('admin', 'reportes'), ('admin', 'historial'),
    ('counselor', 'en-vivo');

  -- Menú por omisión: lo mismo que antes estaba fijo en el código.
  perform pg_temp.login(t);
  v := public.me();
  assert v -> 'tabs' = '["alertas", "banos", "grupo"]'::jsonb, 'pestañas del maestro ' || v::text;
  begin
    perform public.live_board();
    raise exception 'el maestro no debía ver En vivo' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.set_role_tabs('teacher', array['en-vivo']);
    raise exception 'un maestro no cambia permisos' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  -- Coordinación tampoco: ni por RPC ni editando la tabla.
  perform pg_temp.login(co);
  begin
    perform public.permissions_overview();
    raise exception 'coordinación no ve permisos' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.set_staff_roles(t, array['teacher', 'coordinator']);
    raise exception 'coordinación no cambia roles' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.staff set roles = array['admin'] where id = t;
    raise exception 'coordinación no edita roles en la tabla' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  -- El admin le da En vivo y Reportes a los maestros.
  perform pg_temp.login(ad);
  v := public.permissions_overview();
  assert v -> 'role_tabs' -> 'counselor' = '["en-vivo"]'::jsonb, 'resumen ' || v::text;
  assert exists (select 1 from jsonb_array_elements(v -> 'staff') s where s ->> 'id' = t::text),
    'personal en el resumen';
  perform public.set_role_tabs('teacher', array['grupo', 'banos', 'alertas', 'en-vivo', 'reportes']);
  -- Quitarle En vivo a prefectura solo lo saca del menú: la pantalla sigue abierta.
  perform public.set_role_tabs('prefect', array['grupo']);
  perform pg_temp.logout();
  assert exists (select 1 from public.permission_changes where kind = 'role_tabs' and target = 'teacher'
                  and actor_id = ad and 'reportes' = any (after) and not 'reportes' = any (before)),
    'queda en la bitácora';

  perform pg_temp.login(t);
  v := public.me();
  assert v -> 'tabs' ? 'en-vivo' and v -> 'tabs' ? 'reportes', 'nuevas pestañas ' || v::text;
  perform public.live_board();
  perform public.report_summary(current_date - 7, current_date);
  begin
    perform public.pass_history(current_date, current_date);
    raise exception 'Historial no se le dio' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  perform pg_temp.login(pr);
  assert public.me() -> 'tabs' = '["grupo"]'::jsonb, 'menú de prefectura';
  perform public.live_board();
  perform pg_temp.logout();

  -- Roles por persona.
  perform pg_temp.login(ad);
  assert public.set_staff_roles(t, array['teacher', 'prefect', 'teacher']) = '["prefect", "teacher"]'::jsonb,
    'roles sin repetir';
  assert (select roles from public.staff where id = t) = array['prefect', 'teacher'], 'roles guardados';
  begin
    perform 1 from public.permission_changes;
    raise exception 'la bitácora no se lee directo' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();
  assert exists (select 1 from public.permission_changes where kind = 'staff_roles' and target = t::text
                  and before = array['teacher']), 'cambio de roles en la bitácora';
  perform pg_temp.login(ad);
  begin
    perform public.set_staff_roles(t, array[]::text[]);
    raise exception 'sin roles no' using errcode = 'TF001';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.set_staff_roles(t, array['jefe']);
    raise exception 'rol inventado no' using errcode = 'TF001';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.set_role_tabs('teacher', array['ajustes']);
    raise exception 'pestaña inventada no' using errcode = 'TF001';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.set_staff_roles(ad, array['teacher']);
    raise exception 'el admin no se quita el rol' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;
  perform public.set_my_pin('5150');
  perform pg_temp.logout();

  -- La compu del salón desbloqueada con el PIN del admin no cambia permisos.
  perform pg_temp.login(co);
  v_code := public.create_device_pairing(g, null) ->> 'code';
  perform pg_temp.logout();
  perform pg_temp.login(pc, true);
  perform public.claim_device_pairing(v_code);
  perform public.unlock_device('5150');
  begin
    perform public.set_role_tabs('teacher', array['grupo']);
    raise exception 'el equipo no cambia permisos' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  raise notice 'permisos por rol y roles por persona, solo admin: ok';
end;
$$;
