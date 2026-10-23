-- Horarios sin baño: no se piden pases ni avanza la fila; solo el admin los cambia.
do $$
declare
  ad uuid := '00000000-0000-4000-f500-000000000001';
  co uuid := '00000000-0000-4000-f500-000000000002';
  t uuid := '00000000-0000-4000-f500-000000000003';
  g uuid; g2 uuid; g3 uuid;
  h1 uuid; h2 uuid; h3 uuid;
  p1 uuid; p2 uuid;
  v jsonb;
  v_now timestamp := now() at time zone 'America/Mexico_City';
  v_day int := extract(isodow from v_now)::int;
begin
  perform pg_temp.make_staff(ad, 'cierre.ad@test.mx', array['admin']);
  perform pg_temp.make_staff(co, 'cierre.co@test.mx', array['coordinator']);
  perform pg_temp.make_staff(t, 'cierre.t@test.mx', array['teacher']);
  g := pg_temp.make_group('K1'); g2 := pg_temp.make_group('K2'); g3 := pg_temp.make_group('K3');
  h1 := pg_temp.make_student(g, 1, 'H');
  h2 := pg_temp.make_student(g2, 1, 'H');
  h3 := pg_temp.make_student(g3, 1, 'H');
  perform pg_temp.reset_engine();   -- sin horarios sin baño

  -- Solo el admin cambia los horarios; se validan.
  perform pg_temp.login(co);
  begin
    perform public.set_bathroom_closures('[]');
    raise exception 'coordinación no cambia horarios' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();
  perform pg_temp.login(ad);
  begin
    perform public.set_bathroom_closures('[{"starts":"10:30","ends":"11:00"},{"starts":"10:45","ends":"11:15"}]');
    raise exception 'no debía aceptar empalmes' using errcode = 'TF001';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.set_bathroom_closures('[{"starts":"11:00","ends":"10:30"}]');
    raise exception 'no debía aceptar fin antes del inicio' using errcode = 'TF001';
  exception when sqlstate '22023' then null;
  end;
  v := public.set_bathroom_closures('[{"starts":"12:10","ends":"12:35"},{"starts":"10:30","ends":"11:00"}]');
  assert jsonb_array_length(v) = 2, 'guardados ' || v::text;
  perform pg_temp.logout();
  assert exists (select 1 from public.bathroom_closure_changes where actor_id = ad
                  and jsonb_array_length(after) = 2), 'bitácora';

  -- Dentro y fuera del horario (jueves 22 de octubre de 2026, hora de México).
  assert exists (select 1 from private.closure_at('2026-10-22 10:40:00-06')), '10:40 cerrado';
  assert not exists (select 1 from private.closure_at('2026-10-22 11:00:00-06')), '11:00 abierto';
  assert exists (select 1 from private.closure_at('2026-10-22 12:20:00-06')), '12:20 cerrado';
  assert not exists (select 1 from private.closure_at('2026-10-24 10:40:00-06')), 'sábado no aplica';

  -- Ahora mismo en horario sin baño (solo entre semana).
  if v_day between 1 and 5 and v_now::time between '00:10' and '23:30' then
    perform pg_temp.login(t);
    p1 := pg_temp.req(h1);
    p2 := pg_temp.req(h2);
    assert pg_temp.st(p1) = 'out' and pg_temp.st(p2) = 'queued', 'antes del cierre';
    perform pg_temp.logout();

    delete from public.bathroom_closures;
    insert into public.bathroom_closures (starts, ends)
    values ((v_now - interval '5 minutes')::time, (v_now + interval '20 minutes')::time);

    perform pg_temp.login(t);
    begin
      perform pg_temp.req(h3);
      raise exception 'no debía pedir pase en horario sin baño' using errcode = 'TF001';
    exception when sqlstate 'P0001' then
      assert sqlerrm like 'Horario sin baño:%abre a las%', sqlerrm;
    end;
    perform public.mark_returned(p1);
    assert pg_temp.st(p2) = 'queued', 'la fila no avanza';
    v := public.bathrooms_status();
    assert (select (b -> 'paused' ->> 'scheduled')::boolean from jsonb_array_elements(v -> 'bathrooms') b
             where b ->> 'id' = 'bath_m'), 'las pantallas lo ven en los dos baños';
    begin
      perform public.resume_bathroom('bath_h');
      raise exception 'el horario no se reanuda a mano' using errcode = 'TF001';
    exception when sqlstate 'P0001' then null;
    end;
    perform pg_temp.logout();

    -- Termina el horario: la fila avanza.
    delete from public.bathroom_closures;
    perform private.tick();
    assert pg_temp.st(p2) = 'called', 'turno al terminar el horario';
  else
    raise notice 'fin de semana: se omite la prueba en vivo del horario sin baño';
  end if;

  raise notice 'horarios sin baño: ok';
end;
$$;
