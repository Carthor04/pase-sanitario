-- Alertas (SPEC §7): 10 min fuera, escalamiento, "Yo lo atiendo", cierre y destinatarios.
do $$
declare
  t uuid := '00000000-0000-4000-f400-000000000001';   -- autorizó la salida
  cur uuid := '00000000-0000-4000-f400-000000000002'; -- maestro a cargo ahora
  t3 uuid := '00000000-0000-4000-f400-000000000003';  -- otro maestro
  pr uuid := '00000000-0000-4000-f400-000000000004';
  nu uuid := '00000000-0000-4000-f400-000000000005';
  co uuid := '00000000-0000-4000-f400-000000000006';
  di uuid := '00000000-0000-4000-f400-000000000007';
  g uuid; g2 uuid;
  b1 uuid; m1 uuid; b2 uuid; n1 uuid; n2 uuid;
  p1 uuid; p2 uuid; pn uuid; pn2 uuid;
  v_alert uuid;
  v jsonb;
  v_weekday int := extract(isodow from now() at time zone 'America/Mexico_City')::int;
  v_period uuid;
begin
  perform pg_temp.make_staff(t, 'al.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(cur, 'al.cur@test.mx', array['teacher']);
  perform pg_temp.make_staff(t3, 'al.t3@test.mx', array['teacher']);
  perform pg_temp.make_staff(pr, 'al.pr@test.mx', array['prefect']);
  perform pg_temp.make_staff(nu, 'al.nu@test.mx', array['nurse']);
  perform pg_temp.make_staff(co, 'al.co@test.mx', array['coordinator']);
  perform pg_temp.make_staff(di, 'al.di@test.mx', array['director']);
  g := pg_temp.make_group('A1'); g2 := pg_temp.make_group('A2');
  b1 := pg_temp.make_student(g, 1, 'H');
  m1 := pg_temp.make_student(g, 2, 'M');
  n1 := pg_temp.make_student(g, 3, 'H');
  n2 := pg_temp.make_student(g, 4, 'M');
  b2 := pg_temp.make_student(g2, 1, 'H');
  perform pg_temp.reset_engine();
  update public.settings set alert_minutes = 10, escalate_minutes = 5 where id = 1;
  update public.alerts set resolved_at = now() where resolved_at is null;  -- aparta alertas reales

  -- El grupo tiene clase "ahora" con `cur` (solo entre semana).
  if v_weekday between 1 and 5 then
    insert into public.periods (weekday, starts, ends) values (v_weekday, '00:00', '23:59:59')
    returning id into v_period;
    insert into public.schedule_entries (group_id, period_id, subject, teacher_id)
    values (g, v_period, 'Prueba', cur);
  end if;

  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(m1);
  perform pg_temp.logout();

  -- 1. A los 9 min no hay alerta; a los 10 sí.
  update public.passes set started_at = clock_timestamp() - interval '9 minutes' where id in (p1, p2);
  perform private.tick();
  assert not exists (select 1 from public.alerts where pass_id = p1), '1: 9 min sin alerta';
  update public.passes set started_at = clock_timestamp() - interval '11 minutes' where id in (p1, p2);
  perform private.tick();
  select id into v_alert from public.alerts where pass_id = p1;
  assert v_alert is not null and (select level from public.alerts where id = v_alert) = 1, '1: alerta nivel 1';
  assert exists (select 1 from public.pass_events where pass_id = p1 and type = 'alert'), '1: evento alert';
  perform private.tick();
  assert (select count(*) from public.alerts where pass_id = p1) = 1, '1: una sola alerta por pase';

  -- 2. Destinatarios en la app: quien autorizó y el maestro a cargo ahora; otro maestro no.
  perform pg_temp.login(t);
  assert jsonb_array_length(public.my_alerts()) = 2, '2: quien autorizó ve sus alertas';
  perform pg_temp.logout();
  if v_weekday between 1 and 5 then
    perform pg_temp.login(cur);
    assert jsonb_array_length(public.my_alerts()) = 2, '2: el maestro a cargo ahora las ve';
    perform pg_temp.logout();
  end if;
  perform pg_temp.login(t3);
  assert jsonb_array_length(public.my_alerts()) = 0, '2: otro maestro no';
  perform pg_temp.logout();

  -- 3. Escalamiento a los 5 min sin atender; la atendida no se escala.
  update public.alerts set created_at = clock_timestamp() - interval '4 minutes' where pass_id in (p1, p2);
  perform private.tick();
  assert (select level from public.alerts where pass_id = p1) = 1, '3: a los 4 min no escala';
  perform pg_temp.login(pr);
  v := public.acknowledge_alert((select id from public.alerts where pass_id = p2));
  perform pg_temp.logout();
  update public.alerts set created_at = clock_timestamp() - interval '6 minutes' where pass_id in (p1, p2);
  perform private.tick();
  assert (select level from public.alerts where pass_id = p1) = 2, '3: escala a nivel 2';
  assert (select level from public.alerts where pass_id = p2) = 1, '3: la atendida no escala';
  assert exists (select 1 from public.pass_events where pass_id = p1 and type = 'escalated'), '3: evento';

  -- 4. "Yo lo atiendo": prefectura sí, maestro no; otro no se la quita; todos ven quién.
  perform pg_temp.login(t);
  begin
    perform public.acknowledge_alert(v_alert);
    raise exception 'un maestro no atiende alertas' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  v := public.group_board(g);
  assert (select x -> 'alert' ->> 'level' from jsonb_array_elements(v -> 'passes') x
           where x ->> 'id' = p1::text) = '2', '4: el salón ve la alerta';
  assert (select x -> 'alert' ->> 'acknowledged_by_name' from jsonb_array_elements(v -> 'passes') x
           where x ->> 'id' = p2::text) = 'Prueba al.pr@test.mx', '4: el salón ve quién la atiende';
  begin
    perform public.live_board();
    raise exception 'un maestro no ve el monitor' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();
  perform pg_temp.login(pr);
  assert (public.acknowledge_alert(v_alert) ->> 'ok')::boolean, '4: prefectura atiende';
  perform pg_temp.logout();
  perform pg_temp.login(co);
  begin
    perform public.acknowledge_alert(v_alert);
    raise exception 'ya la atendía otra persona' using errcode = 'TF001';
  exception when sqlstate 'P0001' then
    assert sqlerrm like 'Ya la atiende%', sqlerrm;
  end;
  perform pg_temp.logout();
  perform pg_temp.login(di);
  v := public.live_board();
  assert (select count(*) from jsonb_array_elements(v -> 'passes') x where x -> 'alert' is not null and x -> 'alert' <> 'null') = 2,
    '4: dirección ve el monitor con alertas';
  perform pg_temp.logout();

  -- 5. Marcar regreso resuelve; deshacer la reabre; liberar también resuelve.
  perform pg_temp.login(t);
  perform public.mark_returned(p1);
  assert (select resolution from public.alerts where pass_id = p1) = 'returned', '5: resuelta al regresar';
  perform public.undo_last(p1);
  assert (select resolved_at from public.alerts where pass_id = p1) is null, '5: deshacer la reabre';
  perform public.mark_returned(p1);
  perform pg_temp.logout();
  perform pg_temp.login(pr);
  perform public.release_pass(p2, 'Se le buscó y estaba en dirección');
  perform pg_temp.logout();
  assert (select resolution from public.alerts where pass_id = p2) = 'released', '5: resuelta al liberar';

  -- 6. Enfermería: alerta solo en el trayecto; al llegar se resuelve y ya no corre.
  perform pg_temp.login(t);
  pn := pg_temp.req(n1, 'nurse');
  pn2 := pg_temp.req(n2, 'nurse');
  perform pg_temp.logout();
  perform pg_temp.login(nu);
  perform public.mark_arrived(pn2);                   -- llegó enseguida
  perform pg_temp.logout();
  update public.passes set started_at = clock_timestamp() - interval '30 minutes' where id in (pn, pn2);
  perform private.tick();
  assert exists (select 1 from public.alerts where pass_id = pn and resolved_at is null), '6: en camino 30 min → alerta';
  assert not exists (select 1 from public.alerts where pass_id = pn2), '6: en enfermería no hay alerta';
  perform pg_temp.login(nu);
  perform public.mark_arrived(pn);
  perform pg_temp.logout();
  assert (select resolution from public.alerts where pass_id = pn) = 'arrived', '6: llegó → resuelta';

  -- 7. Nota interna: la escribe enfermería; la leen enfermería y dirección, no maestros.
  perform pg_temp.login(nu);
  perform public.add_nurse_note(pn, 'Dolor de cabeza, agua y reposo');
  begin
    perform public.add_nurse_note(p1, 'no aplica');
    raise exception 'nota solo en enfermería' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;
  v := public.nurse_today();
  assert (select x ->> 'note' from jsonb_array_elements(v -> 'passes') x where x ->> 'id' = pn::text)
    = 'Dolor de cabeza, agua y reposo', '7: nurse_today con nota';
  perform pg_temp.logout();
  perform pg_temp.login(t);
  assert not exists (select 1 from public.nurse_notes where pass_id = pn), '7: el maestro no lee la nota';
  begin
    perform public.add_nurse_note(pn, 'x');
    raise exception 'el maestro no escribe notas' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();
  perform pg_temp.login(di);
  assert exists (select 1 from public.nurse_notes where pass_id = pn), '7: dirección lee la nota';
  perform pg_temp.logout();

  raise notice 'alertas 10 min, escalamiento, atender, cierre, enfermería y notas: ok';
end;
$$;
