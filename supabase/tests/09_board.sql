-- group_board y device_session: lo que ve cada pantalla, sin filtrar nombres de otros grupos.
do $$
declare
  t uuid := '00000000-0000-4000-f300-000000000001';
  c uuid := '00000000-0000-4000-f300-000000000002';
  pc uuid := '00000000-0000-4000-f300-000000000003';
  g uuid; g2 uuid;
  b1 uuid; b2 uuid; b3 uuid;
  p3 uuid;
  v jsonb;
  v_code text;
begin
  perform pg_temp.make_staff(t, 'tablero.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(c, 'tablero.c@test.mx', array['coordinator']);
  perform pg_temp.make_anon(pc);
  g := pg_temp.make_group('B1');
  g2 := pg_temp.make_group('B2');
  b1 := pg_temp.make_student(g, 1, 'H');
  b3 := pg_temp.make_student(g, 3, 'H');
  b2 := pg_temp.make_student(g2, 1, 'H');
  perform pg_temp.reset_engine();
  delete from public.staff_pins;

  perform pg_temp.login(t);
  perform public.set_my_pin('5150');
  perform pg_temp.req(b2);                -- otro grupo ocupa el baño de hombres
  perform pg_temp.req(b1);                -- B1 en fila
  p3 := pg_temp.req(b3);                  -- B1 en espera del grupo
  v := public.group_board(g);
  assert jsonb_array_length(v -> 'passes') = 2, 'dos pases del grupo';
  assert (select x -> 'waiting_for' ->> 'list_number' from jsonb_array_elements(v -> 'passes') x
           where x ->> 'id' = p3::text) = '1', 'espera a #1';
  assert (select x ->> 'queue_position' from jsonb_array_elements(v -> 'passes') x
           where x ->> 'status' = 'queued') = '1', 'posición en fila';
  assert (select x -> 'occupants' -> 0 ->> 'group_name' from jsonb_array_elements(v -> 'bathrooms') x
           where x ->> 'id' = 'bath_h') = 'B2', 'ocupantes por grupo';
  assert (v -> 'settings' ->> 'alert_minutes')::int > 0, 'settings';
  perform pg_temp.logout();

  perform pg_temp.login(c);
  v_code := public.create_device_pairing(g, null) ->> 'code';
  perform pg_temp.logout();

  perform pg_temp.login(pc, true);
  perform public.claim_device_pairing(v_code);
  -- Salidas de hoy por alumno: cuenta las que ocurrieron, no las que esperan en fila.
  v := public.group_today_counts(g) -> 'counts';
  assert v -> b3::text is null, 'en espera del grupo no cuenta';
  assert (v -> b1::text) is null, 'en fila no cuenta';
  assert (public.group_today_counts(g) ->> 'flag')::int = 3, 'límite del día desde settings';
  begin
    perform public.student_today_passes(b2);
    raise exception 'no debe ver salidas de otro grupo' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.group_today_counts(g2);
    raise exception 'no debe ver conteos de otro grupo' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  -- El equipo bloqueado ve su tablero (solo lectura) pero no el de otro grupo.
  v := public.group_board(g);
  assert jsonb_array_length(v -> 'passes') = 2, 'el equipo ve su grupo';
  assert v::text not like '%Alumno 1H%' or exists (
    select 1 from jsonb_array_elements(v -> 'passes') x where x ->> 'full_name' = 'Alumno 1H'),
    'solo nombres del propio grupo';
  begin
    perform public.group_board(g2);
    raise exception 'no debe ver otro grupo' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  v := public.device_session();
  assert not (v ->> 'unlocked')::boolean and v -> 'last_lock' = 'null'::jsonb, 'bloqueado: ' || v::text;
  -- El estado general de los baños también lo ve (solo grupos, sin nombres).
  v := public.bathrooms_status();
  assert jsonb_array_length(v -> 'bathrooms') = 2, 'el equipo ve los baños';
  assert v::text not like '%Alumno%', 'sin nombres de alumnos';
  perform public.unlock_device('5150');
  v := public.device_session();
  assert (v ->> 'unlocked')::boolean and v ->> 'staff_name' = 'Prueba tablero.t@test.mx', v::text;
  perform public.lock_device();
  v := public.device_session();
  assert not (v ->> 'unlocked')::boolean and v -> 'last_lock' ->> 'reason' = 'manual', v::text;
  perform pg_temp.logout();

  -- Conteo del día: dos salidas reales (una al baño y otra a enfermería) y una cancelada.
  perform pg_temp.logout();
  update public.passes set status = 'returned', started_at = now(), ended_at = now()
   where student_id = b1 and status in ('queued', 'called', 'group_wait');
  perform pg_temp.login(t);
  perform public.request_pass(b1, 'nurse');
  v := public.group_today_counts(g) -> 'counts';
  assert v -> b1::text = '{"bathroom": 1, "nurse": 1}'::jsonb, 'conteo del día ' || v::text;
  v := public.student_today_passes(b1);
  assert jsonb_array_length(v) = 2 and v -> 1 ->> 'destination' = 'Enfermería'
     and v -> 1 ->> 'opened_by' = 'Prueba tablero.t@test.mx', 'detalle del día ' || v::text;
  perform pg_temp.logout();
  update public.passes set started_at = now() - interval '1 day' where student_id = b1 and destination_id = 'nurse';
  perform pg_temp.login(t);
  assert public.group_today_counts(g) -> 'counts' -> b1::text = '{"bathroom": 1, "nurse": 0}'::jsonb, 'solo cuenta hoy';
  assert jsonb_array_length(public.student_today_passes(b1)) = 1, 'el detalle también es solo de hoy';
  perform pg_temp.logout();

  -- El nombre del alumno de otro grupo (B2) nunca aparece en el tablero de B1.
  perform pg_temp.login(t);
  v := public.group_board(g);
  assert position((select full_name from public.students where id = b2) in
    (v -> 'bathrooms')::text) = 0, 'sin nombres de otros grupos en baños';
  perform pg_temp.logout();

  raise notice 'tablero del grupo y sesión del equipo: ok';
end;
$$;
