-- "Autorizar salida" desde En vivo: sale aunque el baño esté lleno; solo ciertos roles.
do $$
declare
  t uuid := '00000000-0000-4000-fc00-000000000001';
  co uuid := '00000000-0000-4000-fc00-000000000002';
  pr uuid := '00000000-0000-4000-fc00-000000000003';
  g uuid; g2 uuid;
  b1 uuid; b2 uuid; b3 uuid;
  p1 uuid; p2 uuid; p3 uuid;
begin
  perform pg_temp.make_staff(t, 'fo.t@test.mx', array['teacher']);
  perform pg_temp.make_staff(co, 'fo.co@test.mx', array['coordinator']);
  perform pg_temp.make_staff(pr, 'fo.pr@test.mx', array['prefect']);
  g := pg_temp.make_group('F1'); g2 := pg_temp.make_group('F2');
  b1 := pg_temp.make_student(g, 1, 'H');
  b2 := pg_temp.make_student(g2, 1, 'H');   -- en fila (baño lleno)
  b3 := pg_temp.make_student(g, 2, 'H');    -- en espera de su grupo
  perform pg_temp.reset_engine();

  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  p3 := pg_temp.req(b3);
  -- Un maestro no puede forzar la salida.
  begin
    perform public.force_out(p2);
    raise exception 'un maestro no debía autorizar' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();
  assert pg_temp.st(p1) = 'out' and pg_temp.st(p2) = 'queued' and pg_temp.st(p3) = 'group_wait', 'estado inicial';

  -- Prefectura tampoco (no está en la lista).
  perform pg_temp.login(pr);
  begin
    perform public.force_out(p2);
    raise exception 'prefectura no debía autorizar' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  -- Coordinación saca a los dos aunque el baño de hombres (cupo 1) ya esté ocupado.
  perform pg_temp.login(co);
  perform public.force_out(p2);
  perform public.force_out(p3);
  perform pg_temp.logout();
  assert pg_temp.st(p2) = 'out' and pg_temp.st(p3) = 'out', 'salen los dos';
  assert (select count(*) from public.passes where destination_id = 'bath_h' and status = 'out'
           and id in (p1, p2, p3)) = 3, 'tres niños fuera';
  assert exists (select 1 from public.pass_events where pass_id = p2 and type = 'forced_out' and actor_id = co),
    'queda en la bitácora con quién autorizó';

  -- Un pase que ya salió no se puede forzar otra vez.
  perform pg_temp.login(co);
  begin
    perform public.force_out(p2);
    raise exception 'no debía repetir' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;
  perform pg_temp.logout();

  raise notice 'autorizar salida desde En vivo: ok';
end;
$$;
