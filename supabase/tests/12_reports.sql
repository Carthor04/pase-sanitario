-- Reportes, historial y cambios de reglas en vivo (Fase 6).
-- Usa una semana sin datos reales (6–10 de julio de 2026, vacaciones) moviendo las fechas de los pases.
do $$
declare
  t uuid := '00000000-0000-4000-f600-000000000001';
  co uuid := '00000000-0000-4000-f600-000000000002';
  nu uuid := '00000000-0000-4000-f600-000000000003';
  g1 uuid; g2 uuid;
  b1 uuid; b2 uuid; b3 uuid; m1 uuid;
  p uuid; p_first uuid;
  i int;
  v jsonb;
  x jsonb;
begin
  perform pg_temp.make_staff(t, 'rep.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(co, 'rep.co@test.mx', array['coordinator']);
  perform pg_temp.make_staff(nu, 'rep.nu@test.mx', array['nurse']);
  g1 := pg_temp.make_group('R1'); g2 := pg_temp.make_group('R2');
  b1 := pg_temp.make_student(g1, 1, 'H');
  m1 := pg_temp.make_student(g1, 2, 'M');
  b2 := pg_temp.make_student(g2, 1, 'H');
  b3 := pg_temp.make_student(g2, 2, 'H');
  perform pg_temp.reset_engine();
  update public.settings set review_exits_threshold = 3, review_alerts_threshold = 1 where id = 1;

  -- b1: 4 salidas al baño de 5 min el lunes 5 a las 10:xx; m1: 1 salida de 3 min; b2: enfermería.
  for i in 1..4 loop
    perform pg_temp.login(t);
    p := pg_temp.req(b1);
    perform public.mark_returned(p);
    perform pg_temp.logout();
    update public.passes
       set requested_at = '2026-07-06 10:10:00-06'::timestamptz + make_interval(mins => i),
           started_at = '2026-07-06 10:10:00-06'::timestamptz + make_interval(mins => i),
           ended_at = '2026-07-06 10:15:00-06'::timestamptz + make_interval(mins => i),
           period_subject = 'Química'
     where id = p;
    p_first := coalesce(p_first, p);
  end loop;
  insert into public.alerts (pass_id, created_at) values (p_first, '2026-07-06 10:20:00-06');
  perform pg_temp.login(t);
  p := pg_temp.req(m1);
  perform public.mark_returned(p);
  perform pg_temp.logout();
  update public.passes set requested_at = '2026-07-07 08:30-06', started_at = '2026-07-07 08:30-06',
         ended_at = '2026-07-07 08:33-06' where id = p;
  perform pg_temp.login(t);
  p := pg_temp.req(b2, 'nurse');
  perform pg_temp.logout();
  perform pg_temp.login(nu);
  perform public.mark_arrived(p);
  perform public.add_nurse_note(p, 'Revisión');
  perform pg_temp.logout();
  update public.passes set requested_at = '2026-07-08 09:00-06', started_at = '2026-07-08 09:00-06' where id = p;

  -- Reporte: solo coordinación/dirección/admin.
  perform pg_temp.login(t);
  begin
    perform public.report_summary('2026-07-06', '2026-07-10');
    raise exception 'un maestro no ve reportes' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  -- Baños: cualquier maestro ve el estado general.
  v := public.bathrooms_status();
  assert jsonb_array_length(v -> 'bathrooms') = 2, 'bathrooms_status';
  perform pg_temp.logout();

  perform pg_temp.login(co);
  v := public.report_summary('2026-07-06', '2026-07-10');
  assert (v -> 'totals' ->> 'exits')::int = 6, 'salidas ' || (v -> 'totals')::text;
  assert (v -> 'totals' ->> 'bathroom')::int = 5 and (v -> 'totals' ->> 'nurse')::int = 1, 'baño/enfermería';
  assert (v -> 'totals' ->> 'avg_minutes')::numeric = 4.6, 'promedio ' || (v -> 'totals')::text;
  assert (v -> 'totals' ->> 'avg_minutes_h')::numeric = 5.0, 'promedio hombres';
  assert (v -> 'alerts' ->> 'count')::int = 1, 'alertas';
  assert exists (select 1 from jsonb_array_elements(v -> 'heatmap') h
                  where h ->> 'destination' = 'bath_h' and (h ->> 'weekday')::int = 1
                    and (h ->> 'hour')::int = 10 and (h ->> 'count')::int = 4), 'mapa de calor lunes 10:00';
  select g into x from jsonb_array_elements(v -> 'by_group') g where g ->> 'group_name' = 'R1';
  assert (x ->> 'exits')::int = 5 and (x ->> 'alerts')::int = 1, 'por grupo ' || x::text;
  select r into x from jsonb_array_elements(v -> 'review') r where r ->> 'full_name' = 'Alumno 1H'
     and r ->> 'group_name' = 'R1';
  assert x is not null and (x ->> 'exits')::int = 4 and x ->> 'top_subject' = 'Química', 'a revisar ' || coalesce(x::text, 'null');
  assert not exists (select 1 from jsonb_array_elements(v -> 'review') r where r ->> 'group_name' = 'R1'
                      and r ->> 'full_name' = 'Alumno 2M'), 'una salida no se revisa';
  begin
    perform public.report_summary('2026-07-10', '2026-07-06');
    raise exception 'rango invertido' using errcode = 'TF001';
  exception when sqlstate '22023' then null;
  end;

  -- Historial: búsqueda sin acentos ni mayúsculas, por grupo y bitácora.
  v := public.pass_history('2026-07-06', '2026-07-10', 'alumno 1h');
  assert (select count(*) from jsonb_array_elements(v) h where h ->> 'group_name' in ('R1', 'R2')) = 5,
    'busca por alumno ' || jsonb_array_length(v);
  v := public.pass_history('2026-07-06', '2026-07-10', null, g2);
  assert jsonb_array_length(v) = 1 and v -> 0 ->> 'destination' = 'Enfermería', 'filtra por grupo';
  v := public.pass_timeline(p_first);
  assert v -> 0 ->> 'type' = 'requested' and v -> 0 ->> 'actor' = 'Prueba rep.t@test.mx', 'bitácora';
  perform pg_temp.logout();

  -- Enfermería ve solo su historial.
  perform pg_temp.login(nu);
  v := public.pass_history('2026-07-06', '2026-07-10', null, null);
  assert (select bool_and(h ->> 'kind' = 'nurse') from jsonb_array_elements(v) h), 'enfermería solo ve enfermería';
  perform pg_temp.logout();

  -- Subir la capacidad llama al siguiente de la fila en ese momento.
  perform pg_temp.reset_engine();
  perform pg_temp.login(t);
  perform pg_temp.req(b1);
  p := pg_temp.req(b2);
  perform pg_temp.logout();
  assert pg_temp.st(p) = 'queued', 'en fila';
  update public.destinations set capacity = 2 where id = 'bath_h';
  assert pg_temp.st(p) = 'called', 'al subir la capacidad se llama al siguiente';

  -- Las reglas tienen límites razonables.
  begin
    update public.settings set alert_minutes = 0 where id = 1;
    raise exception 'alerta en 0 min' using errcode = 'TF001';
  exception when check_violation then null;
  end;

  raise notice 'reportes, historial, bitácora y cambios de reglas en vivo: ok';
end;
$$;
