-- Notificaciones en la computadora del salón: suscripción del equipo, prueba y avisos de su salón.
do $$
declare
  t uuid := '00000000-0000-4000-f900-000000000001';
  co uuid := '00000000-0000-4000-f900-000000000002';
  pc uuid := '00000000-0000-4000-f900-000000000003';  -- computadora del salón de D1
  g uuid; g2 uuid;
  b1 uuid; b2 uuid;
  p uuid;
  v jsonb;
  v_code text;
  v_device uuid;
begin
  perform pg_temp.make_staff(t, 'dp.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(co, 'dp.co@test.mx', array['coordinator']);
  perform pg_temp.make_anon(pc);
  g := pg_temp.make_group('D1'); g2 := pg_temp.make_group('D2');
  b1 := pg_temp.make_student(g, 1, 'H');
  b2 := pg_temp.make_student(g2, 1, 'H');
  perform pg_temp.reset_engine();
  update public.settings set alert_minutes = 10 where id = 1;

  perform pg_temp.login(co);
  v_code := public.create_device_pairing(g, null) ->> 'code';
  perform pg_temp.logout();
  perform pg_temp.login(pc, true);
  perform public.claim_device_pairing(v_code);
  select id into v_device from public.devices where auth_user_id = pc;

  -- 1. Sin suscripción, la prueba avisa; con suscripción se encola para el equipo.
  assert not (public.send_test_push() ->> 'ok')::boolean, '1: sin suscripción';
  perform public.save_push_subscription('https://push.example/dp-1', 'k', 'a', 'Chrome');
  assert (public.send_test_push() ->> 'ok')::boolean, '1: prueba encolada';
  perform pg_temp.logout();
  assert (select device_id from public.push_subscriptions where endpoint = 'https://push.example/dp-1') = v_device,
    '1: suscripción del equipo';
  assert exists (select 1 from public.notifications_outbox where kind = 'test' and recipient_device_id = v_device
                  and payload ->> 'url' = '/salon'), '1: prueba para el equipo';

  -- 2. Una alerta de un alumno que salió de ese salón llega al equipo; la de otro salón no.
  perform pg_temp.login(t);
  p := pg_temp.req(b1);
  perform pg_temp.req(b2);
  perform pg_temp.logout();
  update public.passes set started_at = clock_timestamp() - interval '11 minutes'
   where student_id in (b1, b2) and status = 'out';
  perform private.tick();
  assert exists (select 1 from public.notifications_outbox where kind = 'alert' and pass_id = p
                  and recipient_device_id = v_device), '2: alerta al equipo del salón';
  assert (select count(*) from public.notifications_outbox where recipient_device_id = v_device
           and kind = 'alert') = 1, '2: solo la de su salón';

  -- 3. El envío reparte a la suscripción del equipo.
  v := (select to_jsonb(b) from public.claim_push_batch(500) b
         where b.id = (select max(id) from public.notifications_outbox where recipient_device_id = v_device));
  assert v -> 'subscriptions' -> 0 ->> 'endpoint' = 'https://push.example/dp-1', '3: ' || coalesce(v::text, 'null');

  -- 4. Desactivar quita la suscripción del equipo.
  perform pg_temp.login(pc, true);
  perform public.delete_push_subscription('https://push.example/dp-1');
  perform pg_temp.logout();
  assert not exists (select 1 from public.push_subscriptions where endpoint = 'https://push.example/dp-1'),
    '4: suscripción quitada';

  raise notice 'notificaciones en la computadora del salón: ok';
end;
$$;
