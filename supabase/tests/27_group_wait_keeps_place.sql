-- Quien espera a su grupo conserva su lugar frente a los que se forman después.
do $$
declare
  t uuid := '00000000-0000-4000-fa00-000000000001';
  g uuid; g2 uuid; g3 uuid;
  a1 uuid; a2 uuid; b1 uuid; c1 uuid; c2 uuid;
  pa1 uuid; pa2 uuid; pb1 uuid; pc1 uuid; pc2 uuid;
  v jsonb;
begin
  perform pg_temp.make_staff(t, 'lugar.t@test.mx', array['teacher']);
  g := pg_temp.make_group('L1'); g2 := pg_temp.make_group('L2'); g3 := pg_temp.make_group('L3');
  a1 := pg_temp.make_student(g, 1, 'H');
  a2 := pg_temp.make_student(g, 2, 'H');
  b1 := pg_temp.make_student(g2, 1, 'H');
  c1 := pg_temp.make_student(g3, 1, 'H');
  c2 := pg_temp.make_student(g3, 2, 'H');
  perform pg_temp.reset_engine();   -- baño de hombres: cupo 1

  perform pg_temp.login(t);
  pc1 := pg_temp.req(c1);   -- L3 está dentro
  pa1 := pg_temp.req(a1);   -- L1 en fila
  pa2 := pg_temp.req(a2);   -- L1 ya tiene a alguien formado: espera a su grupo
  pb1 := pg_temp.req(b1);   -- L2 se forma después de a2
  assert pg_temp.st(pc1) = 'out' and pg_temp.st(pa1) = 'queued'
     and pg_temp.st(pa2) = 'group_wait' and pg_temp.st(pb1) = 'queued', 'estado inicial';

  -- c1 regresa: entra a1 (primero de la fila).
  perform public.mark_returned(pc1);
  assert pg_temp.st(pa1) = 'called', 'turno de a1';
  perform public.confirm_turn(pa1);
  -- Otro de L3 se forma mientras a2 sigue esperando a su grupo.
  pc2 := pg_temp.req(c2);
  assert pg_temp.st(pc2) = 'queued', 'c2 en fila';

  -- a1 regresa: a2 pasa a la fila con su hora de solicitud, antes que b1 y c2.
  perform public.mark_returned(pa1);
  assert pg_temp.st(pa2) = 'called', 'a2 conserva su lugar: ' || pg_temp.st(pa2) || ' / b1 ' || pg_temp.st(pb1);
  assert pg_temp.st(pb1) = 'queued' and pg_temp.st(pc2) = 'queued', 'los demás siguen en fila';

  v := public.bathrooms_status();
  assert (select string_agg(q ->> 'full_name', ',' order by ord)
            from jsonb_array_elements(v -> 'bathrooms') b,
                 jsonb_array_elements(b -> 'queue') with ordinality as x(q, ord)
           where b ->> 'id' = 'bath_h') = 'Alumno 1H,Alumno 2H', 'fila: b1 y luego c2 ' || v::text;
  perform pg_temp.logout();

  raise notice 'la espera del grupo conserva su lugar en la fila: ok';
end;
$$;
