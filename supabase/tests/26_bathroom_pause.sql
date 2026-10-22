-- Pausar un baño: no se piden pases, la fila no avanza ni corre el tiempo de turno.
do $$
declare
  t uuid := '00000000-0000-4000-ff00-000000000001';
  co uuid := '00000000-0000-4000-ff00-000000000002';
  nu uuid := '00000000-0000-4000-ff00-000000000003';
  g uuid; g2 uuid; g3 uuid;
  b1 uuid; b2 uuid; b3 uuid; m1 uuid;
  p1 uuid; p2 uuid;
  v jsonb;
begin
  perform pg_temp.make_staff(t, 'pausa.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(co, 'pausa.co@test.mx', array['coordinator']);
  perform pg_temp.make_staff(nu, 'pausa.nu@test.mx', array['nurse']);
  g := pg_temp.make_group('Z1'); g2 := pg_temp.make_group('Z2'); g3 := pg_temp.make_group('Z3');
  b1 := pg_temp.make_student(g, 1, 'H');
  b2 := pg_temp.make_student(g2, 1, 'H');
  b3 := pg_temp.make_student(g3, 1, 'H');
  m1 := pg_temp.make_student(g3, 2, 'M');
  perform pg_temp.reset_engine();

  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  assert pg_temp.st(p1) = 'out' and pg_temp.st(p2) = 'queued', 'estado inicial';

  -- Un maestro pausa el baño de hombres.
  v := public.pause_bathroom('bath_h', '  Limpieza  ');
  assert v ->> 'reason' = 'Limpieza' and v ->> 'by' = 'Prueba pausa.t@test.mx', 'pausa ' || v::text;
  begin
    perform public.pause_bathroom('bath_h');
    raise exception 'no debía pausar dos veces' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;
  begin
    perform public.pause_bathroom('nurse');
    raise exception 'enfermería no se pausa' using errcode = 'TF001';
  exception when sqlstate '22023' then null;
  end;

  -- No se agregan alumnos a ese baño; el de mujeres sigue normal.
  begin
    perform pg_temp.req(b3);
    raise exception 'no debía pedir pase con el baño en pausa' using errcode = 'TF001';
  exception when sqlstate 'P0001' then
    assert sqlerrm like '%en pausa (Limpieza)%', sqlerrm;
  end;
  assert pg_temp.st(pg_temp.req(m1)) = 'out', 'el baño de mujeres sigue';

  -- Quien estaba dentro regresa, pero la fila no avanza.
  perform public.mark_returned(p1);
  assert pg_temp.st(p2) = 'queued', 'la fila no avanza en pausa';

  v := public.bathrooms_status();
  assert (select b -> 'paused' ->> 'reason' from jsonb_array_elements(v -> 'bathrooms') b
           where b ->> 'id' = 'bath_h') = 'Limpieza', 'Baños muestra la pausa';
  assert (select b -> 'paused' from jsonb_array_elements(v -> 'bathrooms') b
           where b ->> 'id' = 'bath_m') = 'null'::jsonb, 'mujeres sin pausa';
  v := public.group_board(g2);
  assert (select b -> 'paused' from jsonb_array_elements(v -> 'bathrooms') b
           where b ->> 'id' = 'bath_h') <> 'null'::jsonb, 'Mi grupo muestra la pausa';
  perform pg_temp.logout();

  perform pg_temp.login(co);
  v := public.live_board();
  assert (select d -> 'paused' ->> 'reason' from jsonb_array_elements(v -> 'destinations') d
           where d ->> 'id' = 'bath_h') = 'Limpieza', 'En vivo muestra la pausa';
  perform pg_temp.logout();

  -- Enfermería no pausa baños.
  perform pg_temp.login(nu);
  begin
    perform public.resume_bathroom('bath_h');
    raise exception 'enfermería no reanuda' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  -- Al reanudar, el primero de la fila recibe su turno.
  perform pg_temp.login(co);
  perform public.resume_bathroom('bath_h');
  assert pg_temp.st(p2) = 'called', 'turno al reanudar';
  begin
    perform public.resume_bathroom('bath_h');
    raise exception 'no estaba en pausa' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;

  -- En pausa no se confirma turno ni se autoriza la salida, y el tiempo de turno no corre.
  perform public.pause_bathroom('bath_h');
  begin
    perform public.confirm_turn(p2);
    raise exception 'no debía confirmar en pausa' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;
  begin
    perform public.force_out(p2);
    raise exception 'no debía autorizar en pausa' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;
  perform pg_temp.logout();

  update public.passes set called_at = clock_timestamp() - interval '30 minutes' where id = p2;
  perform private.tick();
  assert pg_temp.st(p2) = 'called', 'el turno no vence en pausa';

  perform pg_temp.login(co);
  perform public.resume_bathroom('bath_h');
  perform pg_temp.logout();
  perform private.tick();
  assert pg_temp.st(p2) = 'called', 'al reanudar el tiempo de turno vuelve a empezar';

  perform pg_temp.login(t);
  perform public.confirm_turn(p2);
  perform pg_temp.logout();
  assert pg_temp.st(p2) = 'out', 'confirma ya reanudado';

  assert (select count(*) from public.bathroom_pauses where destination_id = 'bath_h'
           and paused_by in (t, co) and resumed_at is not null) = 2, 'dos pausas en la bitácora';
  assert exists (select 1 from public.bathroom_pauses where paused_by = t and reason = 'Limpieza'
                  and resumed_by = co), 'quién pausó y quién reanudó';

  raise notice 'pausar y reanudar baños: ok';
end;
$$;
