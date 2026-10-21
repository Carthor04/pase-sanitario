-- "Yo lo atiendo" por pase: funciona aunque tick() todavía no haya creado la alerta.
do $$
declare
  t uuid := '00000000-0000-4000-f700-000000000001';
  pr uuid := '00000000-0000-4000-f700-000000000002';
  g uuid;
  b1 uuid; m1 uuid;
  p1 uuid; p2 uuid;
  v jsonb;
begin
  perform pg_temp.make_staff(t, 'ack.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(pr, 'ack.pr@test.mx', array['prefect']);
  g := pg_temp.make_group('K1');
  b1 := pg_temp.make_student(g, 1, 'H');
  m1 := pg_temp.make_student(g, 2, 'M');
  perform pg_temp.reset_engine();
  update public.settings set alert_minutes = 10 where id = 1;

  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(m1);
  perform pg_temp.logout();

  -- 1. Con menos del tiempo de alerta no hay nada que atender.
  update public.passes set started_at = clock_timestamp() - interval '9 minutes' where id = p1;
  perform pg_temp.login(pr);
  begin
    perform public.acknowledge_pass(p1);
    raise exception 'no debía haber alerta' using errcode = 'TF001';
  exception when sqlstate 'P0001' then
    assert sqlerrm = 'Ese alumno no tiene alerta', sqlerrm;
  end;
  perform pg_temp.logout();

  -- 2. Ya pasó el tiempo pero tick() no ha corrido: se crea la alerta y se atiende.
  update public.passes set started_at = clock_timestamp() - interval '11 minutes' where id in (p1, p2);
  assert not exists (select 1 from public.alerts where pass_id = p1), '2: sin alerta antes';
  perform pg_temp.login(t);
  begin
    perform public.acknowledge_pass(p1);
    raise exception 'un maestro no atiende alertas' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();
  perform pg_temp.login(pr);
  v := public.acknowledge_pass(p1);
  assert (v ->> 'ok')::boolean, '2: ok';
  perform pg_temp.logout();
  assert (select acknowledged_by from public.alerts where pass_id = p1 and resolved_at is null) = pr,
    '2: atendida por prefectura';
  assert exists (select 1 from public.pass_events where pass_id = p1 and type = 'alert'), '2: evento alert';
  assert exists (select 1 from public.pass_events where pass_id = p1 and type = 'alert_ack'), '2: evento ack';

  -- 3. tick() no la duplica y crea la del otro pase; esa también se puede atender.
  perform private.tick();
  assert (select count(*) from public.alerts where pass_id = p1) = 1, '3: una sola alerta';
  assert exists (select 1 from public.alerts where pass_id = p2 and resolved_at is null), '3: alerta del segundo';
  perform pg_temp.login(pr);
  assert (public.acknowledge_pass(p2) ->> 'ok')::boolean, '3: atiende la segunda';
  perform pg_temp.logout();
  assert (select count(*) from public.alerts where acknowledged_by = pr and resolved_at is null
           and pass_id in (p1, p2)) = 2, '3: las dos atendidas';

  raise notice 'atender por pase, antes y después de tick: ok';
end;
$$;
