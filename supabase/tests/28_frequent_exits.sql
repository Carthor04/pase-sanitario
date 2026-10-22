-- Reportes: alumnos con 3 o más salidas al baño en un mismo día (settings.daily_exits_flag).
-- Usa una semana sin datos reales (13–17 de julio de 2026, vacaciones) moviendo las fechas.
do $$
declare
  t uuid := '00000000-0000-4000-f900-000000000001';
  co uuid := '00000000-0000-4000-f900-000000000002';
  g uuid;
  b1 uuid; b2 uuid; m1 uuid;
  p uuid;
  i int;
  v jsonb;
  r jsonb;
begin
  perform pg_temp.make_staff(t, 'frec.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(co, 'frec.co@test.mx', array['coordinator']);
  g := pg_temp.make_group('F9');
  b1 := pg_temp.make_student(g, 1, 'H');
  b2 := pg_temp.make_student(g, 2, 'H');
  m1 := pg_temp.make_student(g, 3, 'M');
  perform pg_temp.reset_engine();
  update public.settings set daily_exits_flag = 3 where id = 1;

  -- Sale y regresa; luego se mueve la salida a la fecha y hora dada.
  create temp table frec_moves (pass uuid, at timestamptz) on commit drop;
  for i in 1..3 loop   -- b1: 3 salidas el lunes 13
    perform pg_temp.login(t); p := pg_temp.req(b1); perform public.mark_returned(p); perform pg_temp.logout();
    insert into frec_moves values (p, '2026-07-13 09:00:00-06'::timestamptz + make_interval(hours => i));
  end loop;
  for i in 1..2 loop   -- b2: 2 salidas el lunes (no llega) y 2 el martes (tampoco)
    perform pg_temp.login(t); p := pg_temp.req(b2); perform public.mark_returned(p); perform pg_temp.logout();
    insert into frec_moves values (p, '2026-07-13 09:30:00-06'::timestamptz + make_interval(hours => i));
    perform pg_temp.login(t); p := pg_temp.req(b2); perform public.mark_returned(p); perform pg_temp.logout();
    insert into frec_moves values (p, '2026-07-14 09:30:00-06'::timestamptz + make_interval(hours => i));
  end loop;
  for i in 1..4 loop   -- m1: 4 salidas el miércoles 15
    perform pg_temp.login(t); p := pg_temp.req(m1); perform public.mark_returned(p); perform pg_temp.logout();
    insert into frec_moves values (p, '2026-07-15 08:00:00-06'::timestamptz + make_interval(hours => i));
  end loop;
  update public.passes ps
     set requested_at = m.at, started_at = m.at, ended_at = m.at + interval '4 minutes',
         period_subject = 'Historia'
    from frec_moves m where ps.id = m.pass;
  -- Un cuarto pase de b1 que se quedó esperando a su grupo y se canceló: no cuenta.
  perform pg_temp.login(t);
  p := pg_temp.req(b2);              -- b2 fuera hoy (fuera del rango del reporte)
  p := pg_temp.req(b1);              -- b1 espera a su grupo
  assert pg_temp.st(p) = 'group_wait', 'b1 en espera';
  perform public.cancel_pass(p);
  perform pg_temp.logout();
  update public.passes set requested_at = '2026-07-13 13:00:00-06' where id = p;

  -- Un maestro sin la pestaña Reportes no lo ve.
  perform pg_temp.login(t);
  begin
    perform public.frequent_exits('2026-07-13', '2026-07-17');
    raise exception 'el maestro no debía ver reportes' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  perform pg_temp.login(co);
  v := public.frequent_exits('2026-07-13', '2026-07-17');
  perform pg_temp.logout();
  assert (v ->> 'flag')::int = 3, 'límite desde settings';
  assert jsonb_array_length(v -> 'rows') = 2, 'solo b1 y m1 ' || v::text;
  r := v -> 'rows' -> 0;   -- el día más reciente primero
  assert r ->> 'full_name' = 'Alumno 3M' and r ->> 'day' = '2026-07-15' and (r ->> 'count')::int = 4,
    'm1 el miércoles ' || r::text;
  r := v -> 'rows' -> 1;
  assert r ->> 'full_name' = 'Alumno 1H' and (r ->> 'count')::int = 3
     and jsonb_array_length(r -> 'exits') = 3 and r -> 'exits' -> 0 ->> 'subject' = 'Historia'
     and (r -> 'exits' -> 0 ->> 'minutes')::int = 4 and r ->> 'group_name' = 'F9',
    'b1 el lunes con detalle ' || r::text;

  -- Con límite 4 solo queda m1.
  update public.settings set daily_exits_flag = 4 where id = 1;
  perform pg_temp.login(co);
  assert jsonb_array_length(public.frequent_exits('2026-07-13', '2026-07-17') -> 'rows') = 1, 'límite 4';
  perform pg_temp.logout();

  raise notice 'reporte de 3 o más salidas al baño en el día: ok';
end;
$$;
