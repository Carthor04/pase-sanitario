-- Vinculación de equipos de salón con código de 6 dígitos.
do $$
declare
  t uuid := '00000000-0000-4000-c000-000000000001';
  c uuid := '00000000-0000-4000-c000-000000000002';
  pc1 uuid := '00000000-0000-4000-c000-000000000003';
  pc2 uuid := '00000000-0000-4000-c000-000000000004';
  g uuid;
  g_other uuid;
  v jsonb;
  v_code text;
  v_dev uuid;
  n int;
  i int;
begin
  perform pg_temp.make_staff(t, 'dev.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(c, 'dev.c@test.mx', array['coordinator']);
  perform pg_temp.make_anon(pc1);
  perform pg_temp.make_anon(pc2);
  insert into public.groups (name, sort) values ('D1', 911) returning id into g;
  insert into public.groups (name, sort) values ('D2', 912) returning id into g_other;
  insert into public.students (group_id, list_number, full_name, sex)
  values (g, 1, 'Del grupo', 'H'), (g_other, 1, 'De otro grupo', 'M');

  -- Solo coordinación genera códigos.
  perform pg_temp.login(t);
  begin
    perform public.create_device_pairing(g, 'Equipo D1');
    raise exception 'maestro no debe generar códigos' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  -- Un usuario con cuenta de Google no puede reclamar un código.
  assert public.claim_device_pairing('000000') ->> 'error' = 'not_anonymous', 'staff no reclama';
  perform pg_temp.logout();

  perform pg_temp.login(c);
  v := public.create_device_pairing(g, 'Equipo D1');
  v_code := v ->> 'code';
  assert v_code ~ '^\d{6}$', v::text;
  assert (v ->> 'expires_at')::timestamptz between now() + interval '14 minutes' and now() + interval '16 minutes',
    'vence en 15 min (settings.pairing_code_minutes)';
  perform pg_temp.logout();

  -- Código equivocado → invalid_code; correcto → equipo vinculado al grupo.
  perform pg_temp.login(pc1, true);
  assert public.claim_device_pairing(case when v_code = '999999' then '999998' else '999999' end)
    ->> 'error' = 'invalid_code', 'código equivocado';
  v := public.claim_device_pairing(v_code);
  assert (v ->> 'ok')::boolean and v #>> '{device,group_name}' = 'D1', v::text;
  v_dev := (v #>> '{device,id}')::uuid;
  v := public.me();
  assert v ->> 'kind' = 'device' and (v ->> 'group_id')::uuid = g, v::text;
  -- El equipo ve a los alumnos de su grupo y no los de otros.
  select count(*) into n from public.students where group_id in (g, g_other);
  assert n = 1, format('el equipo ve %s alumnos', n);
  assert (select count(*) from public.devices) = 1, 'el equipo se ve a sí mismo';
  assert public.claim_device_pairing(v_code) ->> 'error' = 'already_linked', 'ya vinculado';
  perform pg_temp.logout();

  -- El código es de un solo uso.
  perform pg_temp.login(pc2, true);
  assert public.claim_device_pairing(v_code) ->> 'error' = 'invalid_code', 'código ya usado';
  -- Límite de intentos por equipo.
  for i in 1..4 loop
    perform public.claim_device_pairing('000001');
  end loop;
  assert public.claim_device_pairing('000002') ->> 'error' = 'rate_limited', 'límite de intentos';
  perform pg_temp.logout();

  -- Código vencido no sirve.
  perform pg_temp.login(c);
  v_code := public.create_device_pairing(g, null) ->> 'code';
  perform pg_temp.logout();
  update public.device_pairings set expires_at = now() - interval '1 second' where code = v_code;
  delete from public.security_attempts where auth_user_id = pc2;
  perform pg_temp.login(pc2, true);
  assert public.claim_device_pairing(v_code) ->> 'error' = 'invalid_code', 'código vencido';
  perform pg_temp.logout();

  -- Revocar: el equipo deja de tener acceso.
  perform pg_temp.login(c);
  perform public.revoke_device(v_dev);
  perform pg_temp.logout();
  perform pg_temp.login(pc1, true);
  assert public.me() ->> 'kind' = 'none', 'equipo revocado';
  select count(*) into n from public.students;
  assert n = 0, 'equipo revocado no ve alumnos';
  perform pg_temp.logout();

  raise notice 'vinculación de equipos: ok';
end;
$$;
