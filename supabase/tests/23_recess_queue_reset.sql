-- Reinicio de la fila en el receso: a las 10:05 se cancelan los que esperan.
do $$
declare
  t uuid := '00000000-0000-4000-fd00-000000000001';
  g uuid; g2 uuid;
  b1 uuid; b2 uuid; b3 uuid; b4 uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid;
  v_day date := (now() at time zone 'America/Mexico_City')::date;
  at10 timestamptz := (v_day + time '10:00') at time zone 'America/Mexico_City';
  at1006 timestamptz := (v_day + time '10:06') at time zone 'America/Mexico_City';
begin
  perform pg_temp.make_staff(t, 'rq.t@test.mx', array['teacher']);
  g := pg_temp.make_group('R1'); g2 := pg_temp.make_group('R2');
  b1 := pg_temp.make_student(g, 1, 'H');   -- fuera
  b2 := pg_temp.make_student(g2, 1, 'H');  -- en fila
  b3 := pg_temp.make_student(g, 2, 'H');   -- espera de su grupo
  b4 := pg_temp.make_student(g2, 2, 'M');
  perform pg_temp.reset_engine();
  update public.settings set queue_reset_times = '{10:05}', queue_reset_done_at = null where id = 1;

  perform pg_temp.login(t);
  p1 := pg_temp.req(b1);
  p2 := pg_temp.req(b2);
  p3 := pg_temp.req(b3);
  perform pg_temp.logout();
  update public.passes set requested_at = at10 where id in (p1, p2, p3);

  -- Antes de las 10:05 no pasa nada.
  perform private.reset_queues(at10);
  assert pg_temp.st(p2) = 'queued' and pg_temp.st(p3) = 'group_wait', 'antes de la hora';

  -- A las 10:06: se cancelan los que esperan; el que está fuera sigue.
  perform private.reset_queues(at1006);
  assert pg_temp.st(p1) = 'out', 'el que está fuera sigue';
  assert pg_temp.st(p2) = 'cancelled' and pg_temp.st(p3) = 'cancelled', 'fila vacía';
  assert exists (select 1 from public.pass_events where pass_id = p2 and type = 'cancelled'
                  and actor_id is null and payload ->> 'auto' = 'receso'), 'evento del sistema';

  -- Una sola vez al día: lo que se pida después ya no se cancela.
  perform pg_temp.login(t);
  p4 := pg_temp.req(b4);
  perform pg_temp.logout();
  update public.passes set status = 'queued', started_at = null, queue_ts = clock_timestamp() where id = p4;
  perform private.reset_queues(at1006 + interval '5 minutes');
  assert pg_temp.st(p4) = 'queued', 'no vuelve a correr el mismo día';

  raise notice 'reinicio de la fila en el receso: ok';
end;
$$;
