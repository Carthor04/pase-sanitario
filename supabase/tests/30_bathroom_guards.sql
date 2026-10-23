-- Guardias del baño: quien está de guardia ve En vivo solo durante su turno.
do $$
declare
  t uuid := '00000000-0000-4000-f800-000000000001';
  t2 uuid := '00000000-0000-4000-f800-000000000002';
  co uuid := '00000000-0000-4000-f800-000000000003';
  v jsonb;
  v_now timestamp := now() at time zone 'America/Mexico_City';
  v_day int := extract(isodow from v_now)::int;
  v_start time := date_trunc('minute', v_now::time - interval '5 minutes');
begin
  perform pg_temp.make_staff(t, 'guardia.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(t2, 'guardia.t2@test.mx', array['teacher']);
  perform pg_temp.make_staff(co, 'guardia.co@test.mx', array['coordinator']);

  -- Solo coordinación, dirección o admin importan y cambian guardias.
  perform pg_temp.login(t);
  begin
    perform public.import_guards('[]'::jsonb);
    raise exception 'un maestro no importa guardias' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  perform pg_temp.login(co);
  v := public.import_guards(jsonb_build_array(
    jsonb_build_object('dia', 'lunes', 'inicio', '07:00', 'fin', '07:45', 'correo_maestro', 'guardia.t@test.mx'),
    jsonb_build_object('dia', 'lunes', 'inicio', '07:00', 'fin', '07:45'),
    jsonb_build_object('dia', 'sábado', 'inicio', '07:00', 'fin', '07:45'),
    jsonb_build_object('dia', 'martes', 'inicio', '07:00', 'fin', '07:45', 'correo_maestro', 'nadie@test.mx')));
  assert not (v ->> 'ok')::boolean and jsonb_array_length(v -> 'errors') = 3, 'errores ' || v::text;

  v := public.import_guards(jsonb_build_array(
    jsonb_build_object('dia', 'lunes', 'inicio', '07:00', 'fin', '07:45', 'correo_maestro', 'guardia.t@test.mx'),
    jsonb_build_object('dia', 'jueves', 'inicio', '10:45', 'fin', '11:30')));
  assert (v ->> 'ok')::boolean and (v -> 'summary' ->> 'guardias')::int = 2
     and (v -> 'summary' ->> 'sin_asignar')::int = 1, 'importa ' || v::text;
  perform pg_temp.logout();

  -- Dentro y fuera del turno (lunes 07:00–07:45, hora de México).
  assert private.on_guard(t, '2026-10-19 07:10:00-06'), 'de guardia el lunes 7:10';
  assert not private.on_guard(t, '2026-10-19 07:45:00-06'), 'termina a las 7:45';
  assert not private.on_guard(t, '2026-10-20 07:10:00-06'), 'el martes no';
  assert not private.on_guard(t2, '2026-10-19 07:10:00-06'), 'otro maestro no';

  -- Cambiar una guardia queda en la bitácora.
  perform pg_temp.login(co);
  perform public.set_bathroom_guard(4, '10:45', t2);
  v := public.bathroom_guards_list();
  assert (select x ->> 'staff_name' from jsonb_array_elements(v) x where (x ->> 'weekday')::int = 4)
         = 'Prueba guardia.t2@test.mx', 'lista ' || v::text;
  perform pg_temp.logout();
  assert exists (select 1 from public.bathroom_guard_changes where weekday = 4 and after = t2 and actor_id = co),
    'bitácora';

  -- Con una guardia ahora mismo, el maestro ve En vivo; sin ella, no.
  if v_day between 1 and 5 and v_start < '23:00' then
    insert into public.bathroom_guards values (v_day, v_start, v_start + interval '45 minutes', t)
    on conflict (weekday, starts) do update set staff_id = excluded.staff_id, ends = excluded.ends;
    perform pg_temp.login(t);
    assert public.me() -> 'tabs' ? 'en-vivo' and (public.me() ->> 'on_guard')::boolean, 'menú con En vivo';
    perform public.live_board();
    perform pg_temp.logout();

    perform pg_temp.login(t2);
    assert not (public.me() -> 'tabs' ? 'en-vivo'), 'sin guardia, sin En vivo';
    begin
      perform public.live_board();
      raise exception 'sin guardia no ve En vivo' using errcode = 'TF001';
    exception when insufficient_privilege then null;
    end;
    perform pg_temp.logout();
  else
    raise notice 'fin de semana: se omite la prueba de En vivo en vivo';
  end if;

  raise notice 'guardias del baño: ok';
end;
$$;
