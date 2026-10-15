-- Computadora del salón: PIN, límite de intentos, bloqueo y acciones con unlock vencido.
do $$
declare
  t uuid := '00000000-0000-4000-f200-000000000001';
  c uuid := '00000000-0000-4000-f200-000000000002';
  pc uuid := '00000000-0000-4000-f200-000000000003';
  g uuid; g_other uuid;
  b1 uuid; b_other uuid;
  p1 uuid;
  v jsonb;
  i int;
  v_code text;
begin
  perform pg_temp.make_staff(t, 'salon.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(c, 'salon.c@test.mx', array['coordinator']);
  perform pg_temp.make_anon(pc);
  g := pg_temp.make_group('S1');
  g_other := pg_temp.make_group('S2');
  b1 := pg_temp.make_student(g, 1, 'H');
  b_other := pg_temp.make_student(g_other, 1, 'H');
  perform pg_temp.reset_engine();
  -- Sin otros PIN en juego: la prueba usa uno propio.
  delete from public.staff_pins;

  perform pg_temp.login(t);
  assert (public.set_my_pin('7391') ->> 'ok')::boolean, 'PIN';
  perform pg_temp.logout();
  perform pg_temp.login(c);
  v_code := public.create_device_pairing(g, 'Equipo S1') ->> 'code';
  perform pg_temp.logout();
  perform pg_temp.login(pc, true);
  assert (public.claim_device_pairing(v_code) ->> 'ok')::boolean, 'vinculado';

  -- Equipo bloqueado → error.
  begin
    perform public.request_pass(b1, 'bathroom');
    raise exception 'equipo bloqueado no debe abrir pases' using errcode = 'TF001';
  exception when insufficient_privilege then
    assert sqlerrm like 'Equipo bloqueado%', sqlerrm;
  end;

  -- 5 PIN equivocados → bloqueo.
  for i in 1..4 loop
    v := public.unlock_device('0000');
    assert v ->> 'error' = 'wrong_pin' and (v ->> 'attempts_left')::int = 5 - i, v::text;
  end loop;
  v := public.unlock_device('0000');
  assert v ->> 'error' = 'locked', '5º intento bloquea: ' || v::text;
  v := public.unlock_device('7391');
  assert v ->> 'error' = 'locked', 'bloqueado aun con PIN correcto';
  perform pg_temp.logout();
  update public.security_attempts set at = at - interval '61 seconds'
   where kind = 'unlock' and auth_user_id = pc;
  perform pg_temp.login(pc, true);

  -- PIN correcto → desbloqueado a nombre del maestro.
  v := public.unlock_device('7391');
  assert (v ->> 'ok')::boolean and (v ->> 'staff_id')::uuid = t, v::text;
  assert (v ->> 'expires_at')::timestamptz > now(), 'vence en el futuro';
  assert public.current_actor() ->> 'staff_id' = t::text, 'current_actor = maestro';
  p1 := pg_temp.req(b1);
  assert (select opened_by from public.passes where id = p1) = t, 'pase a nombre de quien desbloqueó';
  assert (select device_id from public.passes where id = p1) is not null, 'desde qué equipo';
  -- La bitácora no la ven los equipos (solo personal).
  assert not exists (select 1 from public.pass_events where pass_id = p1), 'el equipo no lee la bitácora';

  -- Solo pases de su grupo.
  begin
    perform public.request_pass(b_other, 'bathroom');
    raise exception 'no debe operar otro grupo' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;

  -- Unlock vencido → error.
  perform pg_temp.logout();
  assert (select device_id from public.pass_events where pass_id = p1 limit 1) is not null, 'evento con equipo';
  update public.device_unlocks set expires_at = now() - interval '1 second'
   where locked_at is null and staff_id = t;
  perform pg_temp.login(pc, true);
  begin
    perform public.mark_returned(p1);
    raise exception 'unlock vencido no debe operar' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();
  perform private.tick();
  assert exists (select 1 from public.device_unlocks where staff_id = t and lock_reason = 'auto'),
    'tick registra el autobloqueo';

  -- Bloqueo manual.
  perform pg_temp.login(pc, true);
  assert (public.unlock_device('7391') ->> 'ok')::boolean, 'desbloquea otra vez';
  perform public.lock_device();
  begin
    perform public.mark_returned(p1);
    raise exception 'bloqueado a mano no debe operar' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  -- Un maestro con Google no puede usar unlock_device.
  perform pg_temp.logout();
  perform pg_temp.login(t);
  begin
    perform public.unlock_device('7391');
    raise exception 'solo equipos' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  raise notice 'desbloqueo con PIN, límite de intentos, equipo bloqueado y unlock vencido: ok';
end;
$$;
