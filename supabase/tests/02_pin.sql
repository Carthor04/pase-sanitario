-- PIN de 4 dígitos con hash bcrypt, único entre el personal activo (SPEC §5).
do $$
declare
  t1 uuid := '00000000-0000-4000-b000-000000000001';
  t2 uuid := '00000000-0000-4000-b000-000000000002';
  t3 uuid := '00000000-0000-4000-b000-000000000003';
  c uuid := '00000000-0000-4000-b000-000000000004';
  v jsonb;
  i int;
begin
  perform pg_temp.make_staff(t1, 'pin1@test.mx', array['teacher']);
  perform pg_temp.make_staff(t2, 'pin2@test.mx', array['teacher']);
  perform pg_temp.make_staff(t3, 'pin3@test.mx', array['prefect']);
  perform pg_temp.make_staff(c, 'pinc@test.mx', array['coordinator']);

  perform pg_temp.login(t1);
  assert public.set_my_pin('12a4') ->> 'error' = 'invalid', 'letras';
  assert public.set_my_pin('123') ->> 'error' = 'invalid', 'tres dígitos';
  assert public.set_my_pin('12345') ->> 'error' = 'invalid', 'cinco dígitos';
  v := public.set_my_pin('4821');
  assert (v ->> 'ok')::boolean, v::text;
  assert (public.me() ->> 'has_pin')::boolean, 'has_pin tras definirlo';
  -- Volver a poner el mismo PIN propio está permitido.
  assert (public.set_my_pin('4821') ->> 'ok')::boolean, 'mismo PIN propio';
  -- Un maestro no puede cambiar el PIN de otro.
  begin
    perform public.set_staff_pin(t2, '1111');
    raise exception 'maestro no debe cambiar PIN ajeno' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  -- El hash es bcrypt, no el PIN.
  assert (select pin_hash from public.staff_pins where staff_id = t1) like '$2a$08$%', 'hash bcrypt';

  -- Otro maestro no puede usar el mismo PIN, y la respuesta no dice de quién es.
  perform pg_temp.login(t2);
  v := public.set_my_pin('4821');
  assert v = '{"ok": false, "error": "taken"}'::jsonb, v::text;
  assert (public.set_my_pin('4822') ->> 'ok')::boolean, 'PIN distinto';
  perform pg_temp.logout();

  -- Límite: 5 rechazos en 15 min bloquean nuevos intentos, aunque el PIN sea válido.
  perform pg_temp.login(t3);
  for i in 1..4 loop
    assert public.set_my_pin('4821') ->> 'error' = 'taken', 'intento ' || i;
  end loop;
  assert public.set_my_pin('4822') ->> 'error' = 'taken', 'quinto rechazo';
  assert public.set_my_pin('9999') ->> 'error' = 'rate_limited', 'debe limitar intentos';
  perform pg_temp.logout();

  -- Coordinación define y borra PIN de otros; también respeta la unicidad.
  perform pg_temp.login(c);
  assert public.set_staff_pin(t3, '4822') ->> 'error' = 'taken', 'coordinación también respeta unicidad';
  assert (public.set_staff_pin(t3, '0007') ->> 'ok')::boolean, 'coordinación define PIN';
  perform public.clear_staff_pin(t3);
  perform pg_temp.logout();
  assert (select pin_set_at from public.staff where id = t3) is null, 'clear_staff_pin';
  assert not exists (select 1 from public.staff_pins where staff_id = t3), 'clear borra hash';

  -- Al dar de baja a alguien se libera su PIN.
  update public.staff set active = false where id = t1;
  assert not exists (select 1 from public.staff_pins where staff_id = t1), 'baja borra el PIN';
  perform pg_temp.login(c);
  assert (public.set_staff_pin(t3, '4821') ->> 'ok')::boolean, 'PIN de alguien dado de baja queda libre';
  perform pg_temp.logout();

  raise notice 'PIN: formato, hash, unicidad, límite de intentos y permisos: ok';
end;
$$;
