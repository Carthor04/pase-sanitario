-- Turno perdido con preferencia (decisiones 2026-11-24 y 2026-11-25): el pase que pierde su
-- turno sigue en la fila, en segundo lugar y marcado con preferencia en los tableros. Un pase
-- cancelado antes por no confirmar (regla anterior) recupera su lugar al pedirse de nuevo.
do $$
declare
  t uuid := '00000000-0000-4000-f900-000000000001';
  pf uuid := '00000000-0000-4000-f900-000000000002';
  g1 uuid; g2 uuid; g3 uuid; g4 uuid; g5 uuid;
  b1 uuid; b2 uuid; b3 uuid; b4 uuid; b5 uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p2b uuid;
  v_board jsonb;
  v_system private.actor;
begin
  perform pg_temp.make_staff(t, 'prefer.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(pf, 'prefer.p@test.mx', array['prefect']);
  g1 := pg_temp.make_group('X1'); g2 := pg_temp.make_group('X2'); g3 := pg_temp.make_group('X3');
  g4 := pg_temp.make_group('X4'); g5 := pg_temp.make_group('X5');
  b1 := pg_temp.make_student(g1, 1, 'H');
  b2 := pg_temp.make_student(g2, 1, 'H');
  b3 := pg_temp.make_student(g3, 1, 'H');
  b4 := pg_temp.make_student(g4, 1, 'H');
  b5 := pg_temp.make_student(g5, 1, 'H');

  -- 1. P2 pierde su turno: sigue en la fila, segundo lugar, con preferencia.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);       -- fuera
  p2 := pg_temp.req(b2);       -- fila 1
  p3 := pg_temp.req(b3);       -- fila 2
  p4 := pg_temp.req(b4);       -- fila 3
  perform public.mark_returned(p1);
  perform pg_temp.logout();
  assert pg_temp.st(p2) = 'called', '1: turno de P2';
  update public.passes set called_at = called_at - interval '3 minutes' where id = p2;
  perform private.tick();
  assert pg_temp.st(p2) = 'queued' and pg_temp.st(p3) = 'called', '1: P2 sigue en la fila';

  perform pg_temp.login(t);
  v_board := public.group_board(g2);
  assert (select (x ->> 'priority')::boolean and (x ->> 'queue_position')::int = 1
            from jsonb_array_elements(v_board -> 'passes') x where x ->> 'id' = p2::text),
    '1: el salón lo ve con preferencia, primero en la fila';
  assert (v_board -> 'bathrooms' -> 0 -> 'queue' -> 0 ->> 'priority')::boolean,
    '1: la fila del baño lo marca';
  assert not (v_board -> 'bathrooms' -> 0 -> 'queue' -> 1 ->> 'priority')::boolean,
    '1: P4 sin preferencia';
  assert jsonb_array_length(v_board -> 'lost_turns') = 0, '1: no aparece como pase perdido';
  perform pg_temp.logout();
  perform pg_temp.login(pf);
  assert (select (x ->> 'priority')::boolean from jsonb_array_elements(public.live_board() -> 'passes') x
           where x ->> 'id' = p2::text), '1: Baños en vivo lo marca';
  perform pg_temp.logout();
  perform pg_temp.login(t);

  -- 2. Recibe el siguiente turno antes que P4.
  perform public.confirm_turn(p3);
  perform public.mark_returned(p3);
  assert pg_temp.st(p2) = 'called' and pg_temp.st(p4) = 'queued', '2: turno de P2 antes que P4';
  perform pg_temp.logout();

  -- 3. Ceder no da preferencia.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  p3 := pg_temp.req(b3);
  perform public.mark_returned(p1);
  perform public.cede_turn(p2);
  assert pg_temp.st(p2) = 'queued', '3: cedió';
  assert (select priority_ts is null from public.passes where id = p2), '3: sin preferencia';
  perform pg_temp.logout();

  -- 4. Pase cancelado con la regla anterior: al pedirlo de nuevo recupera su lugar.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);       -- fuera
  p2 := pg_temp.req(b2);       -- fila 1
  perform pg_temp.req(b3);     -- fila 2
  perform pg_temp.logout();
  update public.passes set status = 'cancelled', ended_at = clock_timestamp() where id = p2;
  perform private.log_pass_event(p2, 'cancelled', v_system,
    '{"from":"queued","auto":"sin_confirmar"}'::jsonb);
  perform pg_temp.login(t);
  assert jsonb_array_length(public.group_board(g2) -> 'lost_turns') = 1, '4: aviso de pase perdido';
  perform pg_temp.req(b5);
  p2b := pg_temp.req(b2);
  assert (select priority_from from public.passes where id = p2b) = p2, '4: ligado al pase perdido';
  assert (select count(*) from public.passes q
           where q.destination_id = 'bath_h' and q.status = 'queued'
             and (q.queue_ts, q.requested_at) <=
                 (select queue_ts, requested_at from public.passes where id = p2b)) = 1,
    '4: recupera el primer lugar';
  perform pg_temp.logout();

  raise notice 'turno perdido con preferencia: ok';
end;
$$;
