-- "Quitar de la fila" desde Baños y En vivo: cualquier maestro cancela un pase que todavía no
-- sale, de cualquier grupo. bathrooms_status trae el id solo para el personal.
do $$
declare
  t1 uuid := '00000000-0000-4000-fd00-000000000001';
  t2 uuid := '00000000-0000-4000-fd00-000000000002';
  co uuid := '00000000-0000-4000-fd00-000000000003';
  pc uuid := '00000000-0000-4000-fd00-000000000004';
  g uuid; g2 uuid;
  b1 uuid; b2 uuid; b3 uuid;
  p1 uuid; p2 uuid; p3 uuid;
  v jsonb;
  v_code text;
begin
  perform pg_temp.make_staff(t1, 'rq.t1@test.mx', array['teacher']);
  perform pg_temp.make_staff(t2, 'rq.t2@test.mx', array['teacher']);
  perform pg_temp.make_staff(co, 'rq.co@test.mx', array['coordinator']);
  perform pg_temp.make_anon(pc);
  g := pg_temp.make_group('Q1'); g2 := pg_temp.make_group('Q2');
  b1 := pg_temp.make_student(g, 1, 'H');
  b2 := pg_temp.make_student(g, 2, 'H');    -- en espera de su grupo
  b3 := pg_temp.make_student(g2, 1, 'H');   -- en fila (baño lleno)
  perform pg_temp.reset_engine();

  perform pg_temp.login(t1);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  perform pg_temp.logout();
  perform pg_temp.login(t2);
  p3 := pg_temp.req(b3);
  perform pg_temp.logout();
  assert pg_temp.st(p1) = 'out' and pg_temp.st(p2) = 'group_wait' and pg_temp.st(p3) = 'queued',
    'estado inicial';

  -- El personal recibe el id de cada pase en las listas.
  perform pg_temp.login(t1);
  v := public.bathrooms_status();
  assert (select q ->> 'id' from jsonb_array_elements(v -> 'bathrooms') b,
            jsonb_array_elements(b -> 'queue') q where b ->> 'id' = 'bath_h') = p3::text,
    'fila con id ' || v::text;
  assert (select q ->> 'id' from jsonb_array_elements(v -> 'bathrooms') b,
            jsonb_array_elements(b -> 'group_wait_list') q where b ->> 'id' = 'bath_h') = p2::text,
    'espera del grupo con id';

  -- Un maestro de otro grupo quita de la fila al alumno de Q2.
  perform public.cancel_pass(p3);
  assert pg_temp.st(p3) = 'cancelled', 'cancelado';
  assert exists (select 1 from public.pass_events where pass_id = p3 and type = 'cancelled'
                  and actor_id = t1 and payload ->> 'from' = 'queued'),
    'queda en la bitácora con quién lo quitó';

  -- Un pase que ya salió no se cancela (eso es Liberar lugar).
  begin
    perform public.cancel_pass(p1);
    raise exception 'no debía cancelar un pase fuera' using errcode = 'TF001';
  exception when sqlstate 'P0001' then null;
  end;
  assert pg_temp.st(p1) = 'out', 'sigue fuera';
  perform pg_temp.logout();

  -- Otro maestro quita a quien espera a su grupo (de Q1, no es su grupo).
  perform pg_temp.login(t2);
  perform public.cancel_pass(p2);
  perform pg_temp.logout();
  assert pg_temp.st(p2) = 'cancelled', 'espera del grupo cancelada';

  -- La computadora del salón no recibe ids ni nombres.
  perform pg_temp.login(t2);
  p3 := pg_temp.req(b3);
  perform pg_temp.logout();
  assert pg_temp.st(p3) = 'queued', 'otra vez en fila';
  perform pg_temp.login(co);
  v_code := public.create_device_pairing(g, null) ->> 'code';
  perform pg_temp.logout();
  perform pg_temp.login(pc, true);
  perform public.claim_device_pairing(v_code);
  v := public.bathrooms_status();
  assert not (v ->> 'names')::boolean, 'sin nombres';
  assert jsonb_array_length((select b -> 'queue' from jsonb_array_elements(v -> 'bathrooms') b
                              where b ->> 'id' = 'bath_h')) = 1, 've la fila por grupo';
  assert v::text not like '%' || p3::text || '%' and v::text not like '%' || p1::text || '%',
    'sin ids de pases';
  assert not exists (select 1 from jsonb_array_elements(v -> 'bathrooms') b,
                       jsonb_array_elements(b -> 'queue') q where q ? 'id'), 'fila sin id';
  assert v::text not like '%Alumno%', 'sin nombres de alumnos';
  perform pg_temp.logout();

  raise notice 'quitar de la fila desde Baños y En vivo: ok';
end;
$$;
