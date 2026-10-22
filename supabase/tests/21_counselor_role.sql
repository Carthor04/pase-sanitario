-- Psicopedagogía ve En vivo en solo lectura.
do $$
declare
  cn uuid := '00000000-0000-4000-fb00-000000000001';
  t uuid := '00000000-0000-4000-fb00-000000000002';
  co uuid := '00000000-0000-4000-fb00-000000000003';
  g uuid; b1 uuid; p uuid;
  v jsonb;
begin
  perform pg_temp.make_staff(cn, 'cn.cn@test.mx', array['teacher', 'counselor']);
  perform pg_temp.make_staff(t, 'cn.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(co, 'cn.co@test.mx', array['coordinator']);
  g := pg_temp.make_group('C1');
  b1 := pg_temp.make_student(g, 1, 'H');
  perform pg_temp.reset_engine();
  update public.settings set alert_minutes = 10 where id = 1;

  perform pg_temp.login(t);
  p := pg_temp.req(b1);
  perform pg_temp.logout();
  update public.passes set started_at = clock_timestamp() - interval '11 minutes' where id = p;
  perform private.tick();

  perform pg_temp.login(cn);
  v := public.live_board();
  assert exists (select 1 from jsonb_array_elements(v -> 'passes') x where x ->> 'id' = p::text), 've el monitor';
  begin
    perform public.acknowledge_pass(p);
    raise exception 'no debía atender alertas' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  -- El importador de personal acepta el rol.
  perform pg_temp.login(co);
  v := public.import_staff('[{"nombre_completo":"Orientadora","correo":"cn.new@test.mx","roles":"teacher;counselor","_row":2}]');
  assert (v ->> 'ok')::boolean, v::text;
  perform pg_temp.logout();
  assert (select roles from public.staff where email = 'cn.new@test.mx') @> array['counselor'], 'rol guardado';

  raise notice 'psicopedagogía: monitor en solo lectura e importación: ok';
end;
$$;
