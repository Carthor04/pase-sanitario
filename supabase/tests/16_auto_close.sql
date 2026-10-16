-- Cierre automático de pases olvidados al terminar la última clase del día.
-- Simula el miércoles 8 de julio de 2026 (vacaciones, sin datos reales).
do $$
declare
  t uuid := '00000000-0000-4000-fa00-000000000001';
  g1 uuid;
  b1 uuid; b2 uuid; m1 uuid; m2 uuid; m3 uuid; n1 uuid;
  p_out uuid; p_queued uuid; p_old uuid; p_late uuid; p_nurse uuid; p_back uuid;
  v_end time;
  v_day timestamp;
  v jsonb;
begin
  perform pg_temp.make_staff(t, 'cierre.t@test.mx', array['teacher']);
  g1 := pg_temp.make_group('C1');
  b1 := pg_temp.make_student(g1, 1, 'H');
  m1 := pg_temp.make_student(g1, 2, 'M');
  m2 := pg_temp.make_student(g1, 3, 'M');
  m3 := pg_temp.make_student(g1, 4, 'M');
  n1 := pg_temp.make_student(g1, 5, 'H');
  b2 := pg_temp.make_student(g1, 6, 'H');
  perform pg_temp.reset_engine();

  -- Fin de la última clase del miércoles (si no hay horario cargado, se crea uno).
  select max(ends) into v_end from public.periods where weekday = 3;
  if v_end is null then
    insert into public.periods (weekday, starts, ends) values (3, '13:00', '14:00');
    v_end := '14:00';
  end if;
  v_day := '2026-07-08'::date + v_end;  -- hora local del fin

  perform pg_temp.login(t);
  p_out := pg_temp.req(b1);            -- fuera
  p_back := pg_temp.req(m1);           -- regresó bien: no se toca
  perform public.mark_returned(p_back);
  p_queued := pg_temp.req(m2);         -- fuera (baño de mujeres)
  p_nurse := pg_temp.req(n1, 'nurse'); -- enfermería
  p_old := pg_temp.req(m3);            -- de un día anterior
  perform pg_temp.logout();

  -- Fechas: todo el 8 de julio antes del fin, menos p_old (7 de julio).
  update public.passes
     set requested_at = (v_day - interval '40 minutes') at time zone 'America/Mexico_City',
         started_at = (v_day - interval '40 minutes') at time zone 'America/Mexico_City'
   where id in (p_out, p_queued, p_nurse, p_back);
  update public.passes
     set ended_at = (v_day - interval '35 minutes') at time zone 'America/Mexico_City'
   where id = p_back;
  update public.passes
     set requested_at = (v_day - interval '1 day 2 hours') at time zone 'America/Mexico_City',
         started_at = (v_day - interval '1 day 2 hours') at time zone 'America/Mexico_City'
   where id = p_old;
  insert into public.alerts (pass_id) values (p_out);

  -- Un minuto antes del fin: solo se cierra el del día anterior.
  perform private.auto_close_passes((v_day - interval '1 minute') at time zone 'America/Mexico_City');
  assert pg_temp.st(p_old) = 'released', 'pase de un día anterior: cerrado';
  assert pg_temp.st(p_out) = 'out' and pg_temp.st(p_nurse) <> 'released', 'antes del fin no se cierra nada de hoy';

  -- Un pase que se abre después de la última clase no se cierra ese día.
  perform pg_temp.login(t);
  p_late := pg_temp.req(b2);
  perform pg_temp.logout();
  assert pg_temp.st(p_late) in ('queued', 'group_wait'), 'el de la tarde espera (el baño sigue ocupado)';
  update public.passes
     set requested_at = (v_day + interval '5 minutes') at time zone 'America/Mexico_City'
   where id = p_late;

  -- Al terminar la última clase: se liberan los abiertos de hoy pedidos antes del fin.
  perform private.auto_close_passes((v_day + interval '10 minutes') at time zone 'America/Mexico_City');
  assert pg_temp.st(p_out) = 'released' and pg_temp.st(p_queued) = 'released'
     and pg_temp.st(p_nurse) = 'released', 'abiertos de hoy: liberados';
  assert pg_temp.st(p_back) = 'returned', 'el que ya regresó no se toca';
  assert pg_temp.st(p_late) <> 'released', 'el pedido después del fin sigue abierto';
  assert (select auto_closed and release_reason = 'Cierre automático' and ended_at is not null
            from public.passes where id = p_out), 'marca y motivo';
  assert exists (select 1 from public.pass_events
                  where pass_id = p_out and type = 'released' and actor_id is null
                    and payload ->> 'reason' = 'Cierre automático' and payload ->> 'from' = 'out'),
    'evento en la bitácora, hecho por el sistema';
  assert (select resolved_at is not null from public.alerts where pass_id = p_out), 'la alerta se cierra';

  -- Volver a correrlo no duplica nada.
  perform private.auto_close_passes((v_day + interval '11 minutes') at time zone 'America/Mexico_City');
  assert (select count(*) from public.pass_events where pass_id = p_out and type = 'released') = 1,
    'un solo evento';

  -- Los minutos de un cierre automático no cuentan en reportes.
  perform pg_temp.make_staff('00000000-0000-4000-fa00-000000000002', 'cierre.co@test.mx', array['coordinator']);
  perform pg_temp.login('00000000-0000-4000-fa00-000000000002');
  v := public.report_detail('2026-07-08', '2026-07-08', p_group => g1);
  assert (select x ->> 'minutes' from jsonb_array_elements(v) x where (x ->> 'id')::uuid = p_out) is null,
    'sin minutos en el detalle';
  assert (select (x ->> 'minutes')::numeric from jsonb_array_elements(v) x where (x ->> 'id')::uuid = p_back) = 5.0,
    'el regreso normal sí cuenta';
  v := public.report_summary('2026-07-08', '2026-07-08');
  assert (v -> 'totals' ->> 'avg_minutes')::numeric = 5.0, 'promedio sin cierres automáticos ' || (v -> 'totals')::text;
  perform pg_temp.logout();

  raise notice 'cierre automático al terminar la última clase: ok';
end;
$$;
