-- Aviso push al maestro cuando a su alumno le toca el turno.
do $$
declare
  t1 uuid := '00000000-0000-4000-f800-000000000001';  -- pidió el pase del que está fuera
  t2 uuid := '00000000-0000-4000-f800-000000000002';  -- pidió el pase del que está en fila
  t3 uuid := '00000000-0000-4000-f800-000000000003';  -- otro maestro
  g1 uuid; g2 uuid;
  b1 uuid; b2 uuid;
  p1 uuid; p2 uuid;
begin
  perform pg_temp.make_staff(t1, 'turno1@test.mx', array['teacher']);
  perform pg_temp.make_staff(t2, 'turno2@test.mx', array['teacher']);
  perform pg_temp.make_staff(t3, 'turno3@test.mx', array['teacher']);
  g1 := pg_temp.make_group('U1'); g2 := pg_temp.make_group('U2');
  b1 := pg_temp.make_student(g1, 1, 'H');
  b2 := pg_temp.make_student(g2, 1, 'H');
  perform pg_temp.reset_engine();
  update public.notification_rules set enabled = true
   where channel = 'push' and role = 'authorizing_teacher';
  insert into public.push_subscriptions (staff_id, endpoint, p256dh, auth)
  select x, 'https://push.example/' || x, 'k', 'a' from unnest(array[t1, t2, t3]) x;

  perform pg_temp.login(t1);
  p1 := pg_temp.req(b1);
  perform pg_temp.logout();
  perform pg_temp.login(t2);
  p2 := pg_temp.req(b2);
  perform pg_temp.logout();
  assert pg_temp.st(p2) = 'queued', 'en fila';
  assert not exists (select 1 from public.notifications_outbox where pass_id = p2 and kind = 'turn'),
    'en fila todavía no hay aviso';

  -- Regresa el primero: le toca a P2 y se avisa a quien pidió su pase.
  perform pg_temp.login(t1);
  perform public.mark_returned(p1);
  perform pg_temp.logout();
  assert pg_temp.st(p2) = 'called', 'le tocó el turno';
  assert exists (select 1 from public.notifications_outbox
                  where pass_id = p2 and kind = 'turn' and recipient_staff_id = t2
                    and body like '🔔 Turno de Alumno 1H (U2) · Baño hombres. Confirma su salida en 2 min%'
                    and payload ->> 'url' like '/grupo?g=%'), 'aviso al maestro que pidió el pase';
  assert not exists (select 1 from public.notifications_outbox
                      where pass_id = p2 and kind = 'turn' and recipient_staff_id in (t1, t3)),
    'a nadie más';

  -- Con la regla apagada, no hay aviso aunque le toque el turno.
  perform pg_temp.login(t2);
  perform public.confirm_turn(p2);
  perform pg_temp.logout();
  update public.notification_rules set enabled = false
   where channel = 'push' and role in ('authorizing_teacher', 'current_teacher');
  perform pg_temp.login(t1);
  p1 := pg_temp.req(b1);                 -- en fila detrás de P2
  perform pg_temp.logout();
  assert pg_temp.st(p1) = 'queued', 'en fila otra vez';
  perform pg_temp.login(t2);
  perform public.mark_returned(p2);
  perform pg_temp.logout();
  assert pg_temp.st(p1) = 'called', 'le tocó el turno con la regla apagada';
  assert not exists (select 1 from public.notifications_outbox where pass_id = p1 and kind = 'turn'),
    'regla apagada: sin aviso';

  raise notice 'aviso push de turno al maestro: ok';
end;
$$;
