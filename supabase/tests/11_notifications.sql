-- Notificaciones push: destinatarios según notification_rules y avisos de cada cambio.
do $$
declare
  t uuid := '00000000-0000-4000-f500-000000000001';   -- autorizó
  pr uuid := '00000000-0000-4000-f500-000000000002';
  co uuid := '00000000-0000-4000-f500-000000000003';
  di uuid := '00000000-0000-4000-f500-000000000004';
  nu uuid := '00000000-0000-4000-f500-000000000005';
  mine uuid[];
  g uuid; b1 uuid; p1 uuid;
  v jsonb;
  n int;
begin
  perform pg_temp.make_staff(t, 'nt.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(pr, 'nt.pr@test.mx', array['prefect']);
  perform pg_temp.make_staff(co, 'nt.co@test.mx', array['coordinator']);
  perform pg_temp.make_staff(di, 'nt.di@test.mx', array['director']);
  perform pg_temp.make_staff(nu, 'nt.nu@test.mx', array['nurse']);
  mine := array[t, pr, co, di, nu];
  g := pg_temp.make_group('N1');
  b1 := pg_temp.make_student(g, 1, 'H');
  perform pg_temp.reset_engine();
  update public.settings set whatsapp_enabled = false where id = 1;
  update public.notification_rules set enabled = (role in ('prefect', 'coordinator', 'director'))
   where channel = 'push';

  -- Todos tienen un equipo registrado salvo enfermería.
  insert into public.push_subscriptions (staff_id, endpoint, p256dh, auth)
  select x, 'https://push.example/' || x, 'k', 'a' from unnest(array[t, pr, co, di]) x;

  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  perform pg_temp.logout();

  -- 1. Alerta → push a prefectura, coordinación y dirección; no al maestro ni a enfermería.
  update public.passes set started_at = clock_timestamp() - interval '11 minutes' where id = p1;
  perform private.tick();
  select count(*) into n from public.notifications_outbox
   where pass_id = p1 and kind = 'alert' and channel = 'push' and recipient_staff_id = any (mine);
  assert n = 3, format('1: 3 destinatarios, hubo %s', n);
  assert not exists (select 1 from public.notifications_outbox where pass_id = p1 and recipient_staff_id in (t, nu)),
    '1: ni maestro ni enfermería';
  assert (select body from public.notifications_outbox where pass_id = p1 and recipient_staff_id = pr and kind = 'alert')
    like '⚠️ Alumno 1H (N1) lleva 11 min fuera · Baño hombres%', '1: texto';
  assert (select payload ->> 'url' from public.notifications_outbox where pass_id = p1 and recipient_staff_id = pr limit 1)
    = '/en-vivo', '1: abre el monitor';
  assert not exists (select 1 from public.notifications_outbox where pass_id = p1 and channel = 'whatsapp'),
    '1: WhatsApp apagado';

  -- 2. Escalada, atendida y resuelta generan su aviso.
  update public.alerts set created_at = clock_timestamp() - interval '6 minutes' where pass_id = p1;
  perform private.tick();
  assert exists (select 1 from public.notifications_outbox where pass_id = p1 and kind = 'escalated'
                  and body like '🔴 SIN ATENDER%'), '2: escalada';
  perform pg_temp.login(pr);
  perform public.acknowledge_alert((select id from public.alerts where pass_id = p1));
  perform pg_temp.logout();
  assert exists (select 1 from public.notifications_outbox where pass_id = p1 and kind = 'acknowledged'
                  and body = '👤 Prueba nt.pr@test.mx atiende a Alumno 1H (N1)'), '2: atendida';
  perform pg_temp.login(t);
  perform public.mark_returned(p1);
  perform pg_temp.logout();
  assert exists (select 1 from public.notifications_outbox where pass_id = p1 and kind = 'resolved'
                  and body like '✅ Alumno 1H (N1) regresó · 11 min'), '2: resuelta';

  -- 3. Las reglas mandan: el maestro que autorizó recibe push si se activa; prefectura no si se apaga.
  update public.notification_rules set enabled = true where role = 'authorizing_teacher' and channel = 'push';
  update public.notification_rules set enabled = false where role = 'prefect' and channel = 'push';
  update public.settings set whatsapp_enabled = true where id = 1;
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  perform pg_temp.logout();
  update public.passes set started_at = clock_timestamp() - interval '12 minutes' where id = p1;
  perform private.tick();
  assert exists (select 1 from public.notifications_outbox where pass_id = p1 and recipient_staff_id = t
                  and payload ->> 'url' = '/alertas'), '3: el que autorizó recibe push';
  assert not exists (select 1 from public.notifications_outbox where pass_id = p1 and recipient_staff_id = pr),
    '3: prefectura apagada';
  assert (select count(*) from public.notifications_outbox where pass_id = p1 and channel = 'whatsapp') = 1,
    '3: un mensaje al grupo de WhatsApp';

  -- 3b. "En la app": si se apaga, el maestro deja de ver la alerta en Alertas.
  perform pg_temp.login(t);
  assert jsonb_array_length(public.my_alerts()) = 1, '3b: ve la alerta';
  perform pg_temp.logout();
  update public.notification_rules set enabled = false where role = 'authorizing_teacher' and channel = 'app';
  perform pg_temp.login(t);
  assert jsonb_array_length(public.my_alerts()) = 0, '3b: regla app apagada';

  -- 3c. Sin equipos registrados no se encola push.
  perform pg_temp.logout();
  delete from public.push_subscriptions where staff_id = co;
  update public.notification_rules set enabled = true where channel = 'push';
  perform pg_temp.login(pr);
  perform public.acknowledge_alert((select id from public.alerts where pass_id = p1));
  perform pg_temp.logout();
  assert exists (select 1 from public.notifications_outbox where pass_id = p1 and kind = 'acknowledged' and recipient_staff_id = di),
    '3c: con equipo sí';
  assert not exists (select 1 from public.notifications_outbox where pass_id = p1 and kind = 'acknowledged' and recipient_staff_id = co),
    '3c: sin equipo no';
  delete from public.push_subscriptions where staff_id = t;
  perform pg_temp.login(t);

  -- 4. Suscripciones: cada quien las suyas; prueba solo con equipos registrados.
  assert public.send_test_push() ->> 'error' = 'no_subscriptions', '4: sin equipos';
  perform public.save_push_subscription('https://push.example/abc', 'k', 'a', 'Prueba');
  v := public.send_test_push();
  assert (v ->> 'ok')::boolean and (v ->> 'devices')::int = 1, v::text;
  begin
    perform public.save_push_subscription('http://inseguro', 'k', 'a', null);
    raise exception 'debe exigir https' using errcode = 'TF001';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.claim_push_batch(10);
    raise exception 'solo service_role reserva avisos' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.notifications_outbox;
  exception when others then null;
  end;
  select count(*) into n from public.notifications_outbox;
  assert n = 0, '4: un maestro no lee la bandeja';
  perform pg_temp.logout();
  perform pg_temp.login(nu);
  select count(*) into n from public.push_subscriptions;
  assert n = 0, '4: no ve suscripciones ajenas';
  perform pg_temp.logout();

  -- 5. send-push (service_role, que solo usa estas RPC): reserva, envía y limpia vencidas.
  select id into n from public.notifications_outbox where recipient_staff_id = t and kind = 'test';
  perform set_config('role', 'service_role', true);
  assert (select count(*) from public.claim_push_batch(500) c
           where c.recipient_staff_id = t and c.payload ->> 'tag' = 'prueba'
             and jsonb_array_length(c.subscriptions) = 1) = 1, '5: reserva el aviso con su suscripción';
  assert (select count(*) from public.claim_push_batch(500) c where c.recipient_staff_id = t) = 0,
    '5: no se reserva dos veces';
  perform public.finish_push(n, null, array['https://push.example/abc'], '{}');
  perform set_config('role', 'none', true);
  assert (select sent_at from public.notifications_outbox where recipient_staff_id = t and kind = 'test') is not null,
    '5: marcado como enviado';
  assert not exists (select 1 from public.push_subscriptions where endpoint = 'https://push.example/abc'),
    '5: suscripción vencida eliminada';

  raise notice 'reglas de destinatarios, avisos de alerta/escalada/atendida/resuelta y bandeja: ok';
end;
$$;
