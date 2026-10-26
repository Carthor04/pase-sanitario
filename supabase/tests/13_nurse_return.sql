-- Enfermería → de regreso al salón → el maestro marca el regreso.
do $$
declare
  t uuid := '00000000-0000-4000-f700-000000000001';
  nu uuid := '00000000-0000-4000-f700-000000000002';
  g uuid; b1 uuid; p1 uuid;
  v jsonb;
begin
  perform pg_temp.make_staff(t, 'reg.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(nu, 'reg.nu@test.mx', array['nurse']);
  g := pg_temp.make_group('E1');
  b1 := pg_temp.make_student(g, 1, 'H');
  perform pg_temp.reset_engine();
  update public.settings set alert_minutes = 10, escalate_minutes = 5 where id = 1;
  update public.alerts set resolved_at = now() where resolved_at is null;
  update public.notification_rules set enabled = true where channel = 'push'
     and role in ('current_teacher', 'authorizing_teacher');
  insert into public.push_subscriptions (staff_id, endpoint, p256dh, auth)
  values (t, 'https://push.example/reg-t', 'k', 'a');

  perform pg_temp.login(t);
  p1 := pg_temp.req(b1, 'nurse');
  perform pg_temp.logout();

  -- 1. Llega a enfermería y la enfermera lo manda de regreso: el pase sigue abierto.
  perform pg_temp.login(nu);
  perform public.mark_arrived(p1);
  v := public.nurse_send_back(p1);
  assert v ->> 'status' = 'returning' and v ->> 'left_nurse_at' is not null, '1: de regreso ' || v::text;
  perform pg_temp.logout();

  -- 2. Se avisa al maestro que autorizó (push) y el pase sigue activo.
  assert exists (select 1 from public.notifications_outbox where pass_id = p1 and kind = 'returning'
                  and recipient_staff_id = t and payload ->> 'url' like '/grupo?g=%'), '2: aviso al maestro';
  perform pg_temp.login(t);
  begin
    perform public.request_pass(b1, 'bathroom');
    raise exception 'sigue con pase activo' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;
  v := public.group_board(g);
  assert v -> 'passes' -> 0 ->> 'status' = 'returning' and v -> 'passes' -> 0 ->> 'left_nurse_at' is not null,
    '2: el salón lo ve de regreso';
  perform pg_temp.logout();

  -- 3. Enfermería no tiene límite de tiempo: aunque tarde en llegar al salón, no hay alerta.
  update public.passes set left_nurse_at = clock_timestamp() - interval '30 minutes' where id = p1;
  perform private.tick();
  assert not exists (select 1 from public.alerts where pass_id = p1), '3: sin alerta de regreso';

  -- 4. El maestro marca el regreso: se cierra el pase.
  perform pg_temp.login(t);
  v := public.mark_returned(p1);
  assert v ->> 'status' = 'returned', '4: regresó';
  perform pg_temp.logout();
  assert not exists (select 1 from public.alerts where pass_id = p1 and resolved_at is null), '4: sin alerta abierta';

  -- 5. Deshacer "Regresa al salón" (la enfermera se equivocó): vuelve a "en enfermería".
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1, 'nurse');
  perform pg_temp.logout();
  perform pg_temp.login(nu);
  perform public.mark_arrived(p1);
  perform public.nurse_send_back(p1);
  v := public.undo_last(p1);
  assert v ->> 'status' = 'arrived' and v ->> 'left_nurse_at' is null, '5: deshacer ' || v::text;
  perform pg_temp.logout();

  raise notice 'enfermería → de regreso al salón → el maestro marca el regreso: ok';
end;
$$;
