-- El pase en espera sigue al alumno a su salón al terminar la clase por nivel, y el baño
-- de hombres puede funcionar con una sola lista general (sin lugar por grupo).
do $$
declare
  t uuid := '00000000-0000-4000-f700-000000000001';
  g1 uuid; g2 uuid; g3 uuid;
  a uuid; c uuid; d uuid; h1 uuid; h2 uuid; h3 uuid;
  pa uuid; pc uuid; pd uuid; ph1 uuid; ph2 uuid; ph3 uuid;
  v_section uuid;
  v_period uuid;
  v jsonb;
  v_weekday int := extract(isodow from now() at time zone 'America/Mexico_City')::int;
begin
  perform pg_temp.make_staff(t, 'sigue.t@test.mx', array['teacher']);
  g1 := pg_temp.make_group('Y1'); g2 := pg_temp.make_group('Y2'); g3 := pg_temp.make_group('Y3');
  a := pg_temp.make_student(g2, 1, 'M');    -- de Y2; en Inglés va al salón de Y1
  d := pg_temp.make_student(g2, 2, 'M');    -- de Y2; se queda en su salón
  c := pg_temp.make_student(g3, 1, 'M');    -- de Y3
  h1 := pg_temp.make_student(g3, 2, 'H');
  h2 := pg_temp.make_student(g3, 3, 'H');
  h3 := pg_temp.make_student(g3, 4, 'H');
  perform pg_temp.reset_engine();
  update public.destinations set capacity = 1 where id = 'bath_m';

  if v_weekday between 1 and 5 then
    -- Ahora: Inglés básico en el salón de Y1; ahí está "a".
    insert into public.periods (weekday, starts, ends) values (v_weekday, '00:00', '23:59:59')
    on conflict (weekday, starts, ends) do update set starts = excluded.starts
    returning id into v_period;
    insert into public.schedule_entries (group_id, period_id, subject, teacher_id)
    values (g1, v_period, 'Inglés básico', t);
    insert into public.class_sections (room_group_id, subject) values (g1, 'Inglés básico')
    returning id into v_section;
    insert into public.class_section_students values (v_section, a);

    perform pg_temp.login(t);
    pc := pg_temp.req(c);                 -- Y3 ocupa el baño de mujeres (cupo 1)
    pa := pg_temp.req(a);                 -- "a" queda en fila, pedido en el salón de Y1
    pd := pg_temp.req(d);                 -- "d" en fila, en su salón Y2
    perform pg_temp.logout();
    assert pg_temp.st(pa) = 'queued' and pg_temp.st(pd) = 'queued', 'dos en fila';
    assert (select room_group_id from public.passes where id = pa) = g1, 'pedido en el salón de Y1';

    -- Termina la clase: "a" vuelve a Y2. Su pase la sigue; como "d" ya ocupa el lugar de
    -- Y2, queda en espera de su grupo.
    delete from public.schedule_entries where group_id = g1 and period_id = v_period;
    perform private.follow_student_room();
    assert (select room_group_id from public.passes where id = pa) = g2, 'el pase la sigue a Y2';
    assert pg_temp.st(pa) = 'group_wait', 'Y2 ya tenía a alguien: espera a su grupo';
    assert exists (select 1 from public.pass_events where pass_id = pa and type = 'room_changed'
                    and payload ->> 'from' = 'queued' and payload ->> 'to' = 'group_wait'),
      'queda en la bitácora';

    perform pg_temp.login(t);
    v := public.group_board(g1);
    assert not exists (select 1 from jsonb_array_elements(v -> 'passes') x where x ->> 'id' = pa::text),
      'ya no aparece en el salón de Y1';
    v := public.group_board(g2);
    assert exists (select 1 from jsonb_array_elements(v -> 'passes') x where x ->> 'id' = pa::text),
      'aparece en su salón';

    -- Sale "c": le toca a "d" (su lugar en Y2); "a" sigue esperando a "d".
    perform public.mark_returned(pc);
    assert pg_temp.st(pd) = 'called' and pg_temp.st(pa) = 'group_wait', 'turno de d';
    perform pg_temp.logout();
  else
    raise notice 'fin de semana: se omite la parte de clases por nivel';
  end if;

  -- Baño de hombres con lista general: dos del mismo grupo forman fila, nadie espera a su grupo.
  perform pg_temp.login(t);
  ph1 := pg_temp.req(h1);
  ph2 := pg_temp.req(h2);
  assert pg_temp.st(ph1) = 'out' and pg_temp.st(ph2) = 'group_wait', 'con lugar por grupo';
  perform pg_temp.logout();

  update public.destinations set uses_group_slot = false where id = 'bath_h';
  assert pg_temp.st(ph2) = 'queued', 'al quitar el lugar por grupo pasa a la fila';
  assert (select queue_ts = requested_at from public.passes where id = ph2), 'con la hora en que pidió';

  perform pg_temp.login(t);
  ph3 := pg_temp.req(h3);
  assert pg_temp.st(ph3) = 'queued', 'el tercero también a la fila, no a la espera';
  assert (select count(*) from public.passes where destination_id = 'bath_h' and status = 'out'
           and id in (ph1, ph2, ph3)) = 1, 'solo uno fuera';
  perform public.mark_returned(ph1);
  assert pg_temp.st(ph2) = 'called' and pg_temp.st(ph3) = 'queued', 'sigue el orden de la fila';
  v := public.group_board(g3);
  assert (select (b ->> 'uses_group_slot')::boolean from jsonb_array_elements(v -> 'bathrooms') b
           where b ->> 'id' = 'bath_h') = false, 'el panel sabe que no hay lugar por grupo';
  perform pg_temp.logout();

  raise notice 'el pase sigue al alumno y el baño de hombres con lista general: ok';
end;
$$;
