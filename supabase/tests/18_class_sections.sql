-- Clases por nivel: lista del salón, equipo del salón, salón de salida y maestro a cargo.
do $$
declare
  te uuid := '00000000-0000-4000-f800-000000000001';  -- Inglés básico (salón de S1)
  ti uuid := '00000000-0000-4000-f800-000000000002';  -- Inglés intermedio (salón de S2)
  co uuid := '00000000-0000-4000-f800-000000000003';
  pc uuid := '00000000-0000-4000-f800-000000000004';  -- computadora del salón de S1
  pr uuid := '00000000-0000-4000-f800-000000000005';
  g1 uuid; g2 uuid;
  a1 uuid; a2 uuid; b1 uuid; b2 uuid; a3 uuid; a4 uuid; b3 uuid;
  q1 uuid; q2 uuid; q3 uuid;
  v_basic uuid; v_inter uuid;
  v_period uuid;
  p uuid;
  v jsonb;
  v_code text;
  v_weekday int := extract(isodow from now() at time zone 'America/Mexico_City')::int;
begin
  if v_weekday not between 1 and 5 then
    raise notice 'clases por nivel: se omite en fin de semana (el horario es de lunes a viernes)';
    return;
  end if;
  perform pg_temp.make_staff(te, 'sec.te@test.mx', array['teacher']);
  perform pg_temp.make_staff(ti, 'sec.ti@test.mx', array['teacher']);
  perform pg_temp.make_staff(co, 'sec.co@test.mx', array['coordinator']);
  perform pg_temp.make_staff(pr, 'sec.pr@test.mx', array['prefect']);
  perform pg_temp.make_anon(pc);
  g1 := pg_temp.make_group('S1'); g2 := pg_temp.make_group('S2');
  a1 := pg_temp.make_student(g1, 1, 'H');   -- S1, básico
  a2 := pg_temp.make_student(g1, 2, 'M');   -- S1, intermedio
  b1 := pg_temp.make_student(g2, 1, 'M');   -- S2, básico
  b2 := pg_temp.make_student(g2, 2, 'H');   -- S2, intermedio
  perform pg_temp.reset_engine();
  delete from public.staff_pins;

  -- Ahora: Inglés básico en el salón de S1 y Inglés intermedio en el de S2.
  insert into public.periods (weekday, starts, ends) values (v_weekday, '00:00', '23:59:59')
  on conflict (weekday, starts, ends) do update set starts = excluded.starts
  returning id into v_period;
  insert into public.schedule_entries (group_id, period_id, subject, teacher_id)
  values (g1, v_period, 'Inglés básico', te), (g2, v_period, 'Inglés intermedio', ti);
  insert into public.class_sections (room_group_id, subject) values (g1, 'Inglés básico') returning id into v_basic;
  insert into public.class_sections (room_group_id, subject) values (g2, 'Inglés intermedio') returning id into v_inter;
  insert into public.class_section_students values (v_basic, a1), (v_basic, b1), (v_inter, a2), (v_inter, b2);

  -- 1. La lista del salón de S1 es la del nivel, con alumnos de los dos grupos.
  perform pg_temp.login(te);
  perform public.set_my_pin('7391');
  v := public.room_roster(g1);
  assert v -> 'section' ->> 'subject' = 'Inglés básico', '1: sección ' || v::text;
  assert v -> 'section' ->> 'teacher_name' = 'Prueba sec.te@test.mx', '1: docente';
  assert (select array_agg(x ->> 'id' order by x ->> 'id') from jsonb_array_elements(v -> 'students') x)
         = (select array_agg(i::text order by i::text) from unnest(array[a1, b1]) i), '1: alumnos del nivel';
  assert (select count(*) from jsonb_array_elements(v -> 'students') x where x ->> 'group_name' = 'S2') = 1,
    '1: con su grupo';
  -- El celular del maestro: su salón de la hora va primero.
  assert (select name from public.my_groups() limit 1) = 'S1', '1: my_groups';
  perform pg_temp.logout();

  -- 2. La computadora del salón de S1 opera a los del nivel, aunque sean de S2.
  perform pg_temp.login(co);
  v_code := public.create_device_pairing(g1, null) ->> 'code';
  perform pg_temp.logout();
  perform pg_temp.login(pc, true);
  perform public.claim_device_pairing(v_code);
  assert (public.unlock_device('7391') ->> 'ok')::boolean, '2: desbloquea';
  p := pg_temp.req(b1);
  assert (select room_group_id from public.passes where id = p) = g1, '2: salió del salón de S1';
  assert (select group_id from public.passes where id = p) = g2, '2: sigue siendo de S2';
  assert (select period_subject from public.passes where id = p) like 'Inglés básico%', '2: clase de salida';
  v := public.group_board(g1);
  assert exists (select 1 from jsonb_array_elements(v -> 'passes') x where x ->> 'id' = p::text
                  and x ->> 'group_name' = 'S2'), '2: el salón ve el pase';
  -- Un alumno de S1 que está en otro salón no lo opera esta computadora.
  begin
    perform pg_temp.req(a2);
    raise exception 'no debía operar a un alumno de otro salón' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.room_roster(g2);
    raise exception 'no debía ver la lista de otro salón' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform public.mark_returned(p);
  assert pg_temp.st(p) = 'returned', '2: marca el regreso';
  perform pg_temp.logout();

  -- 3. La alerta va al maestro con quien está el alumno (el de su nivel).
  perform pg_temp.login(ti);
  p := pg_temp.req(b2);
  perform pg_temp.logout();
  update public.passes set started_at = clock_timestamp() - interval '11 minutes' where id = p;
  update public.settings set alert_minutes = 10 where id = 1;
  perform private.tick();
  perform pg_temp.login(te);
  assert jsonb_array_length(public.my_alerts()) = 0, '3: el de básico no la ve';
  perform pg_temp.logout();
  assert private.pass_teacher_now(p) = ti, '3: maestro a cargo';
  perform pg_temp.login(pr);
  v := public.live_board();
  assert (select x ->> 'current_teacher_name' from jsonb_array_elements(v -> 'passes') x
           where x ->> 'id' = p::text) = 'Prueba sec.ti@test.mx', '3: monitor';
  perform pg_temp.logout();

  -- 4. Sin la clase por nivel, el salón vuelve a la lista de su grupo.
  delete from public.schedule_entries where group_id in (g1, g2);
  perform pg_temp.login(te);
  v := public.room_roster(g1);
  assert v -> 'section' = 'null'::jsonb, '4: sin sección';
  assert (select array_agg(x ->> 'id' order by x ->> 'id') from jsonb_array_elements(v -> 'students') x)
         = (select array_agg(i::text order by i::text) from unnest(array[a1, a2]) i), '4: lista del grupo';
  perform pg_temp.logout();

  -- 5. Importar secciones valida y reemplaza la lista.
  perform pg_temp.login(co);
  v := public.import_sections('[{"salon_grupo":"S1","materia":"Inglés básico","grupo":"S2","numero_lista":"9","_row":2}]');
  assert not (v ->> 'ok')::boolean, '5: alumno inexistente';
  v := public.import_sections('[{"salon_grupo":"S1","materia":"Inglés básico","grupo":"S1","numero_lista":"2","_row":2}]');
  assert (v ->> 'ok')::boolean, '5: ' || v::text;
  assert (select array_agg(student_id) from public.class_section_students where section_id = v_basic) = array[a2],
    '5: lista reemplazada';
  perform pg_temp.logout();

  -- 6. En la clase por nivel el lugar del baño es por salón, no por grupo.
  perform pg_temp.login(ti);
  perform public.mark_returned(p);
  perform pg_temp.logout();
  insert into public.schedule_entries (group_id, period_id, subject, teacher_id)
  values (g1, v_period, 'Inglés básico', te), (g2, v_period, 'Inglés intermedio', ti);
  a3 := pg_temp.make_student(g1, 3, 'H');  -- S1, básico (salón de S1)
  b3 := pg_temp.make_student(g2, 3, 'H');  -- S2, básico (salón de S1)
  a4 := pg_temp.make_student(g1, 4, 'H');  -- S1, intermedio (salón de S2)
  delete from public.class_section_students;
  insert into public.class_section_students values (v_basic, a3), (v_basic, b3), (v_inter, a4);
  perform pg_temp.login(te);
  q1 := pg_temp.req(a3);
  q2 := pg_temp.req(b3);
  q3 := pg_temp.req(a4);
  perform pg_temp.logout();
  assert pg_temp.st(q1) = 'out', '6: el primero sale ' || pg_temp.st(q1);
  assert pg_temp.st(q2) = 'group_wait', '6: otro niño del mismo salón espera aunque sea de otro grupo';
  assert pg_temp.st(q3) = 'queued', '6: un niño del mismo grupo en otro salón no espera al grupo ' || pg_temp.st(q3);
  perform pg_temp.login(te);
  perform public.mark_returned(q1);
  perform pg_temp.logout();
  assert pg_temp.st(q2) in ('queued', 'called', 'out'), '6: al regresar, sigue el del mismo salón';

  raise notice 'clases por nivel: lista del salón, equipo, salida, alertas, importación y lugar por salón: ok';
end;
$$;
