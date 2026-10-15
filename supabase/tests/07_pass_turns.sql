-- Turnos: vencimiento, ceder, cancelar, liberar, deshacer y reglas desde settings.
do $$
declare
  t uuid := '00000000-0000-4000-f100-000000000001';
  t2 uuid := '00000000-0000-4000-f100-000000000002';
  pr uuid := '00000000-0000-4000-f100-000000000003';
  nu uuid := '00000000-0000-4000-f100-000000000004';
  g1 uuid; g2 uuid; g3 uuid;
  b1 uuid; b2 uuid; b3 uuid;
  p1 uuid; p2 uuid; p3 uuid;
  v jsonb;
begin
  perform pg_temp.make_staff(t, 'turno.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(t2, 'turno.t2@test.mx', array['teacher']);
  perform pg_temp.make_staff(pr, 'turno.pr@test.mx', array['prefect']);
  perform pg_temp.make_staff(nu, 'turno.nu@test.mx', array['nurse']);
  g1 := pg_temp.make_group('Q1'); g2 := pg_temp.make_group('Q2'); g3 := pg_temp.make_group('Q3');
  b1 := pg_temp.make_student(g1, 1, 'H');
  b2 := pg_temp.make_student(g2, 1, 'H');
  b3 := pg_temp.make_student(g3, 1, 'H');

  -- 6. Turno no confirmado en 2 min → segundo lugar; se llama al siguiente.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  p3 := pg_temp.req(b3);
  perform public.mark_returned(p1);
  assert pg_temp.st(p2) = 'called' and pg_temp.st(p3) = 'queued', '6: se llama a P2';
  perform pg_temp.logout();
  update public.passes set called_at = called_at - interval '1 minute' where id = p2;
  perform private.tick();
  assert pg_temp.st(p2) = 'called', '6: a 1 min todavía es su turno';
  update public.passes set called_at = called_at - interval '2 minutes' where id = p2;
  perform private.tick();
  assert pg_temp.st(p3) = 'called', '6: se llama al siguiente';
  assert pg_temp.st(p2) = 'queued', '6: el que no confirmó vuelve a la fila';
  assert exists (select 1 from public.pass_events
                  where pass_id = p2 and type = 'turn_expired' and actor_id is null),
    '6: evento turn_expired del sistema';

  -- 6b. Si no hay nadie más formado, sigue siendo su turno.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  perform public.mark_returned(p1);
  perform pg_temp.logout();
  update public.passes set called_at = called_at - interval '5 minutes' where id = p2;
  perform private.tick();
  assert pg_temp.st(p2) = 'called', '6b: sin nadie más, sigue siendo su turno';

  -- 7. Ceder turno: el que cede queda en segundo lugar.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1); p2 := pg_temp.req(b2); p3 := pg_temp.req(b3);
  perform public.mark_returned(p1);
  v := public.cede_turn(p2);
  assert v ->> 'status' = 'queued' and (v ->> 'queue_position')::int = 1, '7: cede y queda en fila ' || v::text;
  assert pg_temp.st(p3) = 'called', '7: se llama al siguiente';
  -- Un pase en fila no se confirma.
  begin
    perform public.confirm_turn(p2);
    raise exception 'no debía confirmar' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;

  -- 8. Cancelar antes de salir sí; después de salir no.
  perform public.cancel_pass(p3);
  assert pg_temp.st(p3) = 'cancelled', '8: cancelado';
  assert pg_temp.st(p2) = 'called', '8: al cancelar se llama al siguiente';
  -- 7b. Ceder con un solo alumno en fila: no se puede.
  begin
    perform public.cede_turn(p2);
    raise exception 'no debía poder ceder' using errcode = 'TF001';
  exception when sqlstate 'P0001' then
    assert sqlerrm like 'Nadie más en fila%', sqlerrm;
  end;
  perform public.confirm_turn(p2);
  begin
    perform public.cancel_pass(p2);
    raise exception 'no debía cancelar a alguien fuera' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;

  -- 9. Liberar: solo prefectura/coordinación, con motivo.
  begin
    perform public.release_pass(p2, 'tardó mucho');
    raise exception 'un maestro no libera' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();
  perform pg_temp.login(pr);
  begin
    perform public.release_pass(p2, '   ');
    raise exception 'motivo obligatorio' using errcode = 'TF001';
  exception when sqlstate '22023' then null;
  end;
  v := public.release_pass(p2, 'No regresó, se avisó a dirección');
  assert v ->> 'status' = 'released' and v ->> 'release_reason' like 'No regresó%', v::text;
  perform pg_temp.logout();

  -- 10. Deshacer dentro de 10 s revierte; después de 10 s falla.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  v := public.undo_last(p1);
  assert v ->> 'status' = 'cancelled', '10: deshacer abrir pase';
  assert pg_temp.st(p2) = 'called', '10: al deshacer se libera el lugar';
  assert exists (select 1 from public.pass_events where pass_id = p1 and type = 'undo'), '10: evento undo';
  begin
    perform public.undo_last(p1);
    raise exception 'no se deshace dos veces' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;
  perform public.confirm_turn(p2);
  perform public.mark_returned(p2);
  perform pg_temp.logout();
  update public.pass_events set at = at - interval '11 seconds'
   where id = (select max(id) from public.pass_events where pass_id = p2);
  perform pg_temp.login(t);
  begin
    perform public.undo_last(p2);
    raise exception 'debió vencer el deshacer' using errcode = 'TF001';
  exception when sqlstate 'P0001' then
    assert sqlerrm = 'Ya pasó el tiempo para deshacer', sqlerrm;
  end;
  perform pg_temp.logout();

  -- 10b. Solo quien hizo el cambio lo deshace.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  perform pg_temp.logout();
  perform pg_temp.login(t2);
  begin
    perform public.undo_last(p1);
    raise exception 'otro maestro no deshace' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  -- 10c. Deshacer "regresó" cuando ya se llamó al siguiente: se deshace solo el regreso
  --      y el llamado conserva su turno (decisión 2026-10-15).
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1); p2 := pg_temp.req(b2); p3 := pg_temp.req(b3);
  perform public.mark_returned(p1);
  assert pg_temp.st(p2) = 'called', '10c: llamado';
  v := public.undo_last(p1);
  assert v ->> 'status' = 'out' and v ->> 'ended_at' is null, '10c: vuelve a fuera ' || v::text;
  assert pg_temp.st(p2) = 'called', '10c: el llamado conserva su turno';
  assert pg_temp.st(p3) = 'queued', '10c: no se llama a nadie más con el baño lleno';
  perform pg_temp.logout();

  -- 11. Las reglas salen de destinations/settings: con capacidad 2 salen dos niños.
  perform pg_temp.reset_engine();
  update public.destinations set capacity = 2 where id = 'bath_h';
  perform pg_temp.login(t);
  assert pg_temp.st(pg_temp.req(b1)) = 'out' and pg_temp.st(pg_temp.req(b2)) = 'out'
     and pg_temp.st(pg_temp.req(b3)) = 'queued', '11: capacidad desde destinations';
  perform pg_temp.logout();

  -- 12. Enfermería: la enfermera marca llegada y regreso; no toca pases de baño.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  p1 := pg_temp.req(b1, 'nurse');
  p2 := pg_temp.req(b2);
  perform pg_temp.logout();
  perform pg_temp.login(nu);
  assert public.mark_arrived(p1) ->> 'status' = 'arrived', '12: llegó';
  assert public.mark_returned(p1) ->> 'status' = 'returned', '12: la enfermera lo regresa';
  begin
    perform public.mark_returned(p2);
    raise exception 'la enfermera no regresa pases de baño' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  raise notice 'vencer turno, ceder, cancelar, liberar, deshacer, reglas desde settings: ok';
end;
$$;
