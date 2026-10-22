-- Quien esperaba a su grupo nunca sale directo: recibe turno aunque haya lugar y no haya fila.
do $$
declare
  t uuid := '00000000-0000-4000-fb00-000000000001';
  g uuid; g2 uuid;
  m1 uuid; m2 uuid; m3 uuid;
  p1 uuid; p2 uuid; p3 uuid;
begin
  perform pg_temp.make_staff(t, 'turno.t@test.mx', array['teacher']);
  g := pg_temp.make_group('T1'); g2 := pg_temp.make_group('T2');
  m1 := pg_temp.make_student(g, 1, 'M');
  m2 := pg_temp.make_student(g, 2, 'M');
  m3 := pg_temp.make_student(g2, 1, 'M');
  perform pg_temp.reset_engine();   -- baño de mujeres: cupo 3, una por grupo

  perform pg_temp.login(t);
  p1 := pg_temp.req(m1);
  p2 := pg_temp.req(m2);
  assert pg_temp.st(p1) = 'out' and pg_temp.st(p2) = 'group_wait', 'estado inicial';

  -- Regresa su compañera: hay lugar y nadie formado, pero recibe turno, no sale directo.
  perform public.mark_returned(p1);
  assert pg_temp.st(p2) = 'called', 'turno, no salida directa: ' || pg_temp.st(p2);
  assert exists (select 1 from public.pass_events where pass_id = p2 and type = 'promoted'
                  and payload ->> 'to' = 'queued'), 'pasó por la fila';

  -- Mientras tiene turno, ocupa el lugar de su grupo; otra de otro grupo sí entra directo.
  p3 := pg_temp.req(m3);
  assert pg_temp.st(p3) = 'out', 'otro grupo con lugar libre entra directo';

  perform public.confirm_turn(p2);
  assert pg_temp.st(p2) = 'out', 'su maestro confirma la salida';
  perform pg_temp.logout();

  raise notice 'la espera del grupo recibe turno: ok';
end;
$$;
