-- Turno perdido con preferencia (decisión 2026-11-24): el pase que se canceló por no
-- confirmar su turno, al pedirse de nuevo, recupera su lugar en la fila una sola vez; el
-- tablero del salón avisa quién perdió su turno.
do $$
declare
  t uuid := '00000000-0000-4000-f900-000000000001';
  g1 uuid; g2 uuid; g3 uuid; g4 uuid; g5 uuid;
  b1 uuid; b2 uuid; b3 uuid; b4 uuid; b5 uuid; b1b uuid; b2b uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid; p2b uuid; p2c uuid; p1b uuid;
  v_board jsonb;
begin
  perform pg_temp.make_staff(t, 'prefer.t@test.mx', array['teacher']);
  g1 := pg_temp.make_group('X1'); g2 := pg_temp.make_group('X2'); g3 := pg_temp.make_group('X3');
  g4 := pg_temp.make_group('X4'); g5 := pg_temp.make_group('X5');
  b1 := pg_temp.make_student(g1, 1, 'H');
  b2 := pg_temp.make_student(g2, 1, 'H');
  b3 := pg_temp.make_student(g3, 1, 'H');
  b4 := pg_temp.make_student(g4, 1, 'H');
  b5 := pg_temp.make_student(g5, 1, 'H');
  b1b := pg_temp.make_student(g1, 2, 'H');
  b2b := pg_temp.make_student(g2, 2, 'H');

  -- 1. P2 pierde su turno (límite 1) y se cancela; el tablero de su salón lo avisa.
  perform pg_temp.reset_engine();
  update public.settings set max_missed_turns = 1 where id = 1;
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
  assert pg_temp.st(p2) = 'cancelled' and pg_temp.st(p3) = 'called', '1: P2 pierde su turno';

  perform pg_temp.login(t);
  v_board := public.group_board(g2);
  assert jsonb_array_length(v_board -> 'lost_turns') = 1
     and v_board -> 'lost_turns' -> 0 ->> 'student_id' = b2::text, '1: el salón ve quién perdió su turno';
  assert jsonb_array_length(public.group_board(g4) -> 'lost_turns') = 0, '1: otro salón no';

  -- 2. Alguien más se forma; P2 vuelve a pedirlo y queda antes que los que llegaron después.
  p5 := pg_temp.req(b5);       -- fila: P4, P5
  p2b := pg_temp.req(b2);
  assert pg_temp.st(p2b) = 'queued', '2: queda en fila';
  assert (select priority_from from public.passes where id = p2b) = p2, '2: ligado al pase perdido';
  assert (public.request_pass(b1b, 'bathroom') is not null), '2: otro alumno sin preferencia';
  assert (select count(*) from public.passes q
           where q.destination_id = 'bath_h' and q.status = 'queued'
             and (q.queue_ts, q.requested_at) <=
                 (select queue_ts, requested_at from public.passes where id = p2b)) = 1,
    '2: P2 recupera el primer lugar';
  v_board := public.group_board(g2);
  assert jsonb_array_length(v_board -> 'lost_turns') = 0, '2: ya no aparece como perdido';
  assert (select (x ->> 'priority')::boolean from jsonb_array_elements(v_board -> 'passes') x
           where x ->> 'id' = p2b::text), '2: el tablero lo marca con preferencia';
  assert (v_board -> 'bathrooms' -> 0 -> 'queue' -> 0 ->> 'priority')::boolean,
    '2: la fila del baño lo marca';
  assert exists (select 1 from public.pass_events where pass_id = p2b and type = 'requested'
                  and payload ->> 'priority_from' = p2::text), '2: queda en la bitácora';

  -- 3. Recibe el siguiente turno.
  perform public.confirm_turn(p3);
  perform public.mark_returned(p3);
  assert pg_temp.st(p2b) = 'called', '3: turno de P2 antes que P4 y P5';
  perform pg_temp.logout();

  -- 4. La preferencia es una sola vez: si la vuelve a perder, va al final.
  update public.passes set called_at = called_at - interval '3 minutes' where id = p2b;
  perform private.tick();
  assert pg_temp.st(p2b) = 'cancelled', '4: la vuelve a perder';
  perform pg_temp.login(t);
  assert jsonb_array_length(public.group_board(g2) -> 'lost_turns') = 0, '4: ya sin aviso';
  p2c := pg_temp.req(b2);
  assert (select priority_from from public.passes where id = p2c) is null, '4: sin preferencia';
  assert (select count(*) from public.passes q
           where q.destination_id = 'bath_h' and q.status = 'queued'
             and q.queue_ts > (select queue_ts from public.passes where id = p2c)) = 0,
    '4: al final de la fila';

  -- 5. Cancelar a mano no da preferencia.
  perform pg_temp.logout();
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  perform public.cancel_pass(p2);
  p2b := pg_temp.req(b2);
  assert (select priority_from from public.passes where id = p2b) is null, '5: cancelado a mano, sin preferencia';

  -- 6. Si tiene que esperar a su grupo, al pasar a la fila recupera su lugar.
  perform pg_temp.logout();
  perform pg_temp.reset_engine();
  update public.settings set max_missed_turns = 1 where id = 1;
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);       -- fuera
  p2 := pg_temp.req(b2);       -- fila 1
  p3 := pg_temp.req(b3);       -- fila 2
  perform public.mark_returned(p1);
  perform pg_temp.logout();
  update public.passes set called_at = called_at - interval '3 minutes' where id = p2;
  perform private.tick();      -- P2 pierde su turno; turno de P3
  assert pg_temp.st(p2) = 'cancelled', '6: P2 pierde su turno';
  perform pg_temp.login(t);
  p4 := pg_temp.req(b4);       -- fila
  p1 := pg_temp.req(b1);       -- fila
  -- Otro niño del salón de P2 ocupa el lugar del grupo.
  p1b := pg_temp.req(b2b);
  p2b := pg_temp.req(b2);
  assert pg_temp.st(p2b) = 'group_wait', '6: espera a su grupo';
  perform public.cancel_pass(p1b);
  assert pg_temp.st(p2b) = 'queued', '6: pasa a la fila';
  assert (select count(*) from public.passes q
           where q.destination_id = 'bath_h' and q.status = 'queued'
             and (q.queue_ts, q.requested_at) <=
                 (select queue_ts, requested_at from public.passes where id = p2b)) = 1,
    '6: con su lugar recuperado';
  perform pg_temp.logout();

  raise notice 'turno perdido con preferencia: ok';
end;
$$;
