-- Detalle de reportes (al tocar un cuadro) y horario por docente.
-- Usa la semana del 6–10 de julio de 2026 (vacaciones, sin datos reales).
do $$
declare
  t uuid := '00000000-0000-4000-f900-000000000001';
  co uuid := '00000000-0000-4000-f900-000000000002';
  g1 uuid; g2 uuid;
  b1 uuid; b2 uuid;
  p uuid; p_alert uuid;
  per uuid;
  i int;
  v jsonb;
  v_local timestamp := now() at time zone 'America/Mexico_City';
begin
  perform pg_temp.make_staff(t, 'det.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(co, 'det.co@test.mx', array['coordinator']);
  update public.staff set full_name = 'Docente Detalle' where id = t;
  g1 := pg_temp.make_group('D1'); g2 := pg_temp.make_group('D2');
  b1 := pg_temp.make_student(g1, 1, 'H');
  b2 := pg_temp.make_student(g2, 1, 'H');
  perform pg_temp.reset_engine();

  -- b1: 2 salidas lunes 10:xx (Química); b2: 1 salida martes 8:xx.
  for i in 1..2 loop
    perform pg_temp.login(t);
    p := pg_temp.req(b1);
    perform public.mark_returned(p);
    perform pg_temp.logout();
    update public.passes
       set requested_at = '2026-07-06 10:10:00-06'::timestamptz + make_interval(mins => i * 10),
           started_at = '2026-07-06 10:10:00-06'::timestamptz + make_interval(mins => i * 10),
           ended_at = '2026-07-06 10:16:00-06'::timestamptz + make_interval(mins => i * 10),
           period_subject = 'Química'
     where id = p;
    p_alert := coalesce(p_alert, p);
  end loop;
  insert into public.alerts (pass_id, created_at) values (p_alert, '2026-07-06 10:25:00-06');
  perform pg_temp.login(t);
  p := pg_temp.req(b2);
  perform public.mark_returned(p);
  perform pg_temp.logout();
  update public.passes set requested_at = '2026-07-07 08:30-06', started_at = '2026-07-07 08:30-06',
         ended_at = '2026-07-07 08:33-06' where id = p;

  -- Un maestro no ve el detalle.
  perform pg_temp.login(t);
  begin
    perform public.report_detail('2026-07-06', '2026-07-10');
    raise exception 'un maestro no ve el detalle' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  perform pg_temp.login(co);
  v := public.report_detail('2026-07-06', '2026-07-10');
  assert jsonb_array_length(v) = 3, 'todas las salidas ' || v::text;
  v := public.report_detail('2026-07-06', '2026-07-10', 'bath_h', 1, 10);
  assert jsonb_array_length(v) = 2, 'celda lunes 10:00';
  assert v -> 0 ->> 'full_name' = 'Alumno 1H' and v -> 0 ->> 'group_name' = 'D1'
     and v -> 0 ->> 'subject' = 'Química' and (v -> 0 ->> 'minutes')::numeric = 6.0, 'renglón ' || (v -> 0)::text;
  assert (v -> 0 ->> 'alert')::boolean and not (v -> 1 ->> 'alert')::boolean, 'marca de alerta';
  assert jsonb_array_length(public.report_detail('2026-07-06', '2026-07-10', p_alerts_only => true)) = 1,
    'solo con alerta';
  assert jsonb_array_length(public.report_detail('2026-07-06', '2026-07-10', p_group => g2)) = 1, 'por grupo';
  assert jsonb_array_length(public.report_detail('2026-07-06', '2026-07-10', 'nurse')) = 0, 'enfermería vacía';
  assert jsonb_array_length(public.report_detail('2026-07-06', '2026-07-10', 'bathroom')) = 3, 'ambos baños';
  perform pg_temp.logout();

  -- Horario del docente: una clase que abarca este momento (si hoy es entre semana).
  if extract(isodow from v_local) between 1 and 5
     and v_local::time between '00:05' and '23:40' then
    insert into public.periods (weekday, starts, ends)
    values (extract(isodow from v_local)::int, v_local::time - interval '2 minutes',
            v_local::time + interval '15 minutes')
    returning id into per;
    insert into public.schedule_entries (group_id, period_id, subject, teacher_id)
    values (g1, per, 'Física', t);

    perform pg_temp.login(co);
    v := public.teacher_schedule(t);
    assert jsonb_array_length(v -> 'entries') = 1 and v -> 'entries' -> 0 ->> 'group_name' = 'D1', 'horario';
    assert v -> 'current' ->> 'subject' = 'Física', 'en clase ahora ' || v::text;
    v := public.current_classes();
    assert exists (select 1 from jsonb_array_elements(v -> 'groups') x
                    where x ->> 'group_name' = 'D1' and x ->> 'subject' = 'Física'
                      and x ->> 'teacher_name' = 'Docente Detalle'), 'clase actual del grupo';
    assert exists (select 1 from jsonb_array_elements(v -> 'groups') x
                    where x ->> 'group_name' = 'D2' and x ->> 'subject' is null), 'grupo sin clase';
    perform pg_temp.logout();
  end if;

  -- Sin sesión de personal, nada.
  perform pg_temp.make_anon('00000000-0000-4000-f900-0000000000a1');
  perform pg_temp.login('00000000-0000-4000-f900-0000000000a1', true);
  begin
    perform public.teacher_schedule(t);
    raise exception 'anónimo no ve horarios de docentes' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  raise notice 'detalle de reportes y horario por docente: ok';
end;
$$;
