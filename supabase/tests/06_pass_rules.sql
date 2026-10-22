-- Reglas de cupo y fila (SPEC §4). Se corre como un maestro con Google.
do $$
declare
  t uuid := '00000000-0000-4000-f000-000000000001';
  g1 uuid; g2 uuid; g3 uuid; g4 uuid;
  b1 uuid; b2 uuid; b3 uuid; b4 uuid; b5 uuid;
  m1 uuid; m2 uuid; m3 uuid; m4 uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid;
  v jsonb;
begin
  perform pg_temp.make_staff(t, 'motor.t@test.mx', array['teacher']);
  g1 := pg_temp.make_group('P1'); g2 := pg_temp.make_group('P2');
  g3 := pg_temp.make_group('P3'); g4 := pg_temp.make_group('P4');
  b1 := pg_temp.make_student(g1, 1, 'H'); b3 := pg_temp.make_student(g1, 3, 'H');
  m1 := pg_temp.make_student(g1, 2, 'M');
  b2 := pg_temp.make_student(g2, 1, 'H'); m2 := pg_temp.make_student(g2, 2, 'M');
  b4 := pg_temp.make_student(g3, 1, 'H'); m3 := pg_temp.make_student(g3, 2, 'M');
  b5 := pg_temp.make_student(g4, 1, 'H'); m4 := pg_temp.make_student(g4, 2, 'M');

  -- 1. Hombres capacidad 1: el segundo niño de otro grupo queda en fila.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  assert pg_temp.st(p1) = 'out', '1: primero sale';
  assert (select destination_id from public.passes where id = p1) = 'bath_h', '1: baño según sexo';
  v := public.request_pass(b2, 'bathroom');
  assert v ->> 'status' = 'queued' and (v ->> 'queue_position')::int = 1, '1: segundo en fila ' || v::text;
  p2 := (v ->> 'id')::uuid;

  -- 2. Mismo grupo: el segundo queda en espera del grupo; al regresar el primero
  --    entra AL FINAL de la fila (detrás de P2) y se llama al primero formado.
  p3 := pg_temp.req(b3);
  assert pg_temp.st(p3) = 'group_wait', '2: espera del grupo';
  perform public.mark_returned(p1);
  assert pg_temp.st(p1) = 'returned', '2: regresó';
  assert pg_temp.st(p2) = 'called', '2: se llama al primero de la fila';
  assert pg_temp.st(p3) = 'queued', '2: el de espera del grupo pasa a la fila';
  assert (select queue_ts from public.passes where id = p3) > (select queue_ts from public.passes where id = p2),
    '2: entra al final de la fila';
  v := public.confirm_turn(p2);
  assert v ->> 'status' = 'out' and v ->> 'started_at' is not null, '2: confirmar turno → out';

  -- 2a. Un alumno no puede tener dos pases activos (ni de enfermería).
  begin
    perform public.request_pass(b2, 'nurse');
    raise exception 'debió rechazar el segundo pase' using errcode = 'TF001';
  exception when sqlstate 'P0001' then
    assert sqlerrm = 'El alumno ya tiene un pase activo', sqlerrm;
  end;
  perform pg_temp.logout();

  -- 2b. Mismo grupo con la fila vacía: al regresar el primero, el segundo recibe turno
  --     (no sale directo; decisión 2026-10-22) y su maestro confirma.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p3 := pg_temp.req(b3);
  assert pg_temp.st(p3) = 'group_wait', '2b: espera';
  perform public.mark_returned(p1);
  assert pg_temp.st(p3) = 'called', '2b: recibe turno';
  assert exists (select 1 from public.pass_events where pass_id = p3 and type = 'promoted'
                  and payload ->> 'to' = 'queued'), '2b: evento promoted';
  perform public.confirm_turn(p3);
  assert pg_temp.st(p3) = 'out', '2b: confirma y sale';

  -- 3. Niño y niña del mismo grupo pueden estar fuera a la vez.
  p4 := pg_temp.req(m1);
  assert pg_temp.st(p4) = 'out', '3: niña del mismo grupo sale';
  perform pg_temp.logout();

  -- 4. Mujeres capacidad 3: la cuarta (de otro grupo) queda en fila.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  assert pg_temp.st(pg_temp.req(m1)) = 'out', '4: 1';
  assert pg_temp.st(pg_temp.req(m2)) = 'out', '4: 2';
  assert pg_temp.st(pg_temp.req(m3)) = 'out', '4: 3';
  assert pg_temp.st(pg_temp.req(m4)) = 'queued', '4: la cuarta queda en fila';
  perform pg_temp.logout();

  -- 5. Enfermería no ocupa lugar del grupo ni hace fila.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);                  -- g1 ocupa su lugar de niño y el baño
  p2 := pg_temp.req(b2);                  -- en fila
  p3 := pg_temp.req(b3, 'nurse');         -- mismo grupo que b1
  assert pg_temp.st(p3) = 'out', '5: enfermería sale directo';
  assert (select destination_id from public.passes where id = p3) = 'nurse', '5: destino enfermería';
  p4 := pg_temp.req(b4, 'nurse');
  p5 := pg_temp.req(b5, 'nurse');
  assert pg_temp.st(p4) = 'out' and pg_temp.st(p5) = 'out', '5: sin límite ni fila';
  assert pg_temp.st(p2) = 'queued', '5: la fila del baño no cambia';
  perform public.mark_returned(p3);       -- el maestro marca regreso de enfermería
  assert pg_temp.st(p3) = 'returned', '5: regreso de enfermería';
  begin
    perform public.mark_arrived(p4);
    raise exception 'un maestro no marca llegada' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  -- Cada cambio de estado quedó en la bitácora.
  assert (select count(*) from public.pass_events where pass_id = p1) >= 1, 'bitácora';
  assert (select actor_id from public.pass_events where pass_id = p3 and type = 'returned') = t,
    'bitácora: quién';

  raise notice 'cupo, lugar del grupo, fila FIFO, mujeres cap 3, enfermería, un pase activo: ok';
end;
$$;
