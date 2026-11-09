-- Turnos perdidos (decisión 2026-11-09): al llegar a settings.max_missed_turns el pase se
-- cancela solo; public.expire_turns() vence turnos sin esperar a tick(); y al cambiar de
-- salón el baño sin lugar por grupo no manda a nadie a "espera de su grupo".
do $$
declare
  t uuid := '00000000-0000-4000-f800-000000000001';
  an uuid := '00000000-0000-4000-f800-000000000002';
  g1 uuid; g2 uuid; g3 uuid; g4 uuid; g5 uuid;
  b1 uuid; b2 uuid; b3 uuid; b4 uuid; b5 uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid;
  v_section uuid;
  v_period uuid;
  v_ts timestamptz;
  v_weekday int := extract(isodow from now() at time zone 'America/Mexico_City')::int;
begin
  perform pg_temp.make_staff(t, 'perdido.t@test.mx', array['teacher']);
  perform pg_temp.make_anon(an);
  g1 := pg_temp.make_group('W1'); g2 := pg_temp.make_group('W2'); g3 := pg_temp.make_group('W3');
  g4 := pg_temp.make_group('W4'); g5 := pg_temp.make_group('W5');
  b1 := pg_temp.make_student(g1, 1, 'H');
  b2 := pg_temp.make_student(g2, 1, 'H');
  b3 := pg_temp.make_student(g3, 1, 'H');
  b4 := pg_temp.make_student(g4, 1, 'H');
  b5 := pg_temp.make_student(g5, 1, 'H');

  -- 1. Primer turno perdido: segundo lugar. Segundo turno perdido: se cancela solo.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  p3 := pg_temp.req(b3);
  p4 := pg_temp.req(b4);
  perform public.mark_returned(p1);
  assert pg_temp.st(p2) = 'called', '1: turno de P2';
  perform pg_temp.logout();

  update public.passes set called_at = called_at - interval '3 minutes' where id = p2;
  perform private.tick();
  assert pg_temp.st(p2) = 'queued' and pg_temp.st(p3) = 'called', '1: P2 al segundo lugar, turno de P3';
  assert (select payload ->> 'missed' from public.pass_events
           where pass_id = p2 and type = 'turn_expired') = '1', '1: primer turno perdido';

  perform pg_temp.login(t);
  perform public.confirm_turn(p3);
  perform public.mark_returned(p3);
  assert pg_temp.st(p2) = 'called' and pg_temp.st(p4) = 'queued', '1: P2 recibe turno otra vez';
  perform pg_temp.logout();

  update public.passes set called_at = called_at - interval '3 minutes' where id = p2;
  perform private.tick();
  assert pg_temp.st(p2) = 'cancelled', '1: al segundo turno perdido se cancela';
  assert pg_temp.st(p4) = 'called', '1: se llama al siguiente';
  assert (select ended_at is not null from public.passes where id = p2), '1: queda cerrado';
  assert exists (select 1 from public.pass_events
                  where pass_id = p2 and type = 'cancelled' and actor_id is null
                    and payload ->> 'auto' = 'sin_confirmar' and payload ->> 'from' = 'called'),
    '1: evento cancelled del sistema';

  -- 2. Con max_missed_turns = 1 se cancela al primero.
  perform pg_temp.reset_engine();
  update public.settings set max_missed_turns = 1 where id = 1;
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  p3 := pg_temp.req(b3);
  perform public.mark_returned(p1);
  perform pg_temp.logout();
  update public.passes set called_at = called_at - interval '3 minutes' where id = p2;
  perform private.tick();
  assert pg_temp.st(p2) = 'cancelled' and pg_temp.st(p3) = 'called', '2: cancelado al primer turno perdido';

  -- 3. Si no hay nadie más formado sigue siendo su turno, aunque ya haya perdido uno.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  p3 := pg_temp.req(b3);
  perform public.mark_returned(p1);
  perform pg_temp.logout();
  update public.passes set called_at = called_at - interval '3 minutes' where id = p2;
  perform private.tick();                       -- P2 pierde uno; turno de P3
  perform pg_temp.login(t);
  perform public.cancel_pass(p3);               -- P2 queda solo y recibe turno
  perform pg_temp.logout();
  assert pg_temp.st(p2) = 'called', '3: turno de P2';
  update public.passes set called_at = called_at - interval '10 minutes' where id = p2;
  perform private.tick();
  assert pg_temp.st(p2) = 'called', '3: sin nadie más, sigue siendo su turno';

  -- 4. expire_turns(): no toca un turno vigente; vence el que ya pasó; pide acceso.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  p3 := pg_temp.req(b3);
  perform public.mark_returned(p1);
  perform public.expire_turns();
  assert pg_temp.st(p2) = 'called', '4: turno vigente, no se toca';
  perform pg_temp.logout();
  update public.passes set called_at = called_at - interval '2 minutes 1 second' where id = p2;
  perform pg_temp.login(t);
  perform public.expire_turns();
  assert pg_temp.st(p2) = 'queued' and pg_temp.st(p3) = 'called', '4: vence al momento';
  perform pg_temp.logout();
  perform pg_temp.login(an, true);
  begin
    perform public.expire_turns();
    raise exception 'un anónimo sin equipo no debía poder' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  -- 5. Baño de hombres sin lugar por grupo: al cambiar de salón sigue en la fila con su
  --    lugar; y quien tiene turno no lo pierde.
  if v_weekday between 1 and 5 then
    perform pg_temp.reset_engine();
    update public.destinations set uses_group_slot = false where id = 'bath_h';
    insert into public.periods (weekday, starts, ends) values (v_weekday, '00:00', '23:59:59')
    on conflict (weekday, starts, ends) do update set starts = excluded.starts
    returning id into v_period;
    -- Inglés en el salón de W1: ahí están b4 y b5 (de W4 y W5).
    insert into public.schedule_entries (group_id, period_id, subject, teacher_id)
    values (g1, v_period, 'Inglés básico', t);
    insert into public.class_sections (room_group_id, subject) values (g1, 'Inglés básico')
    returning id into v_section;
    insert into public.class_section_students values (v_section, b4), (v_section, b5);

    perform pg_temp.login(t);
    p1 := pg_temp.req(b1);       -- fuera
    p4 := pg_temp.req(b4);       -- en fila, salón W1
    p2 := pg_temp.req(b2);       -- en fila
    p5 := pg_temp.req(b5);       -- en fila, salón W1
    perform pg_temp.logout();
    assert pg_temp.st(p4) = 'queued' and pg_temp.st(p5) = 'queued', '5: en fila';
    perform pg_temp.login(t);
    perform public.mark_returned(p1);
    perform pg_temp.logout();
    assert pg_temp.st(p4) = 'called', '5: turno de P4';
    select queue_ts into v_ts from public.passes where id = p5;

    -- Termina Inglés: b4 y b5 regresan a sus salones.
    delete from public.schedule_entries where group_id = g1 and period_id = v_period;
    perform private.follow_student_room();
    assert pg_temp.st(p4) = 'called', '5: no pierde su turno';
    assert pg_temp.st(p5) = 'queued', '5: sigue en la fila, sin espera de grupo';
    assert (select queue_ts from public.passes where id = p5) = v_ts, '5: conserva su lugar';
    assert (select room_group_id from public.passes where id = p5) = g5, '5: el pase lo sigue';
    assert not exists (select 1 from public.pass_events
                        where pass_id in (p4, p5) and type = 'room_changed'
                          and payload ->> 'to' = 'group_wait'), '5: nadie a espera de grupo';
  else
    raise notice 'fin de semana: se omite la parte de cambio de salón';
  end if;

  raise notice 'turnos perdidos, vencer al momento y cambio de salón: ok';
end;
$$;
