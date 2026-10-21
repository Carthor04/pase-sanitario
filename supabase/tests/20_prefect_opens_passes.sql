-- Prefectura autoriza salidas desde "Mi grupo"; enfermería y dirección no.
do $$
declare
  pr uuid := '00000000-0000-4000-fa00-000000000001';
  nu uuid := '00000000-0000-4000-fa00-000000000002';
  di uuid := '00000000-0000-4000-fa00-000000000003';
  g uuid;
  b1 uuid; b2 uuid; b3 uuid;
  p1 uuid; p2 uuid;
begin
  perform pg_temp.make_staff(pr, 'pp.pr@test.mx', array['prefect']);
  perform pg_temp.make_staff(nu, 'pp.nu@test.mx', array['nurse']);
  perform pg_temp.make_staff(di, 'pp.di@test.mx', array['director']);
  g := pg_temp.make_group('P1');
  b1 := pg_temp.make_student(g, 1, 'H');
  b2 := pg_temp.make_student(g, 2, 'H');  -- queda en espera del grupo
  b3 := pg_temp.make_student(g, 3, 'M');
  perform pg_temp.reset_engine();

  perform pg_temp.login(pr);
  p1 := pg_temp.req(b1);
  assert pg_temp.st(p1) = 'out', 'prefectura abre un pase';
  assert (select opened_by from public.passes where id = p1) = pr, 'a nombre de prefectura';
  p2 := pg_temp.req(b2);
  perform public.cancel_pass(p2);
  assert pg_temp.st(p2) = 'cancelled', 'prefectura cancela';
  perform public.mark_returned(p1);
  assert pg_temp.st(p1) = 'returned', 'prefectura marca el regreso';
  perform pg_temp.logout();

  foreach pr in array array[nu, di] loop
    perform pg_temp.login(pr);
    begin
      perform pg_temp.req(b3);
      raise exception 'no debía abrir pases' using errcode = 'TF001';
    exception when insufficient_privilege then null;
    end;
    perform pg_temp.logout();
  end loop;

  raise notice 'prefectura abre, cancela y cierra pases; enfermería y dirección no: ok';
end;
$$;
