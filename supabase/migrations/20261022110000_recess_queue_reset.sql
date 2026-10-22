-- Reinicio de la fila en el receso. A la hora de settings.queue_reset_times (10:05 por omisión,
-- ya empezado el receso de 10:00 a 10:45) se cancelan los pases que esperan: en fila, en
-- espera del grupo o con turno sin confirmar. Quien está fuera sigue igual. No se borra nada:
-- cada pase queda "cancelled" con su evento, hecho por el sistema (payload.auto = 'receso').

alter table public.settings
  add column queue_reset_times time[] not null default '{10:05}',
  add column queue_reset_done_at timestamptz;

create function private.reset_queues(p_at timestamptz default clock_timestamp()) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  s public.settings;
  v_today date := (p_at at time zone 'America/Mexico_City')::date;
  v_due timestamptz;
  d record;
  r record;
  v_system private.actor;  -- todo en null: lo hizo el sistema
begin
  select * into s from public.settings where id = 1 for update;
  -- La hora más reciente de hoy que ya pasó.
  select max((v_today + t) at time zone 'America/Mexico_City') into v_due
    from unnest(s.queue_reset_times) t
   where (v_today + t) at time zone 'America/Mexico_City' <= p_at;
  if v_due is null or coalesce(s.queue_reset_done_at, '-infinity') >= v_due then
    return;
  end if;

  for d in select id from public.destinations where kind = 'bathroom' order by id loop
    perform 1 from public.destinations where id = d.id for update;
    for r in
      with c as (
        select p.id, p.status from public.passes p
         where p.destination_id = d.id and p.status in ('group_wait', 'queued', 'called')
           and p.requested_at < v_due
         for update)
      update public.passes p
         set status = 'cancelled', ended_at = clock_timestamp()
        from c
       where p.id = c.id
      returning p.id, c.status as from_status
    loop
      perform private.log_pass_event(r.id, 'cancelled', v_system,
        jsonb_build_object('from', r.from_status, 'auto', 'receso'));
    end loop;
  end loop;

  update public.settings set queue_reset_done_at = p_at where id = 1;
end;
$$;
revoke all on function private.reset_queues(timestamptz) from public, anon, authenticated;

create or replace function private.tick() returns void
language plpgsql security definer set search_path = ''
as $$
declare
  d record;
  p public.passes;
  r record;
  s public.settings;
  v_system private.actor;  -- todo en null: lo hizo el sistema
begin
  select * into s from public.settings where id = 1;

  perform private.auto_close_passes();
  perform private.reset_queues();

  for d in select id from public.destinations where kind = 'bathroom' order by id loop
    perform 1 from public.destinations where id = d.id for update;
    for p in
      select * from public.passes
       where destination_id = d.id and status = 'called'
         and called_at < clock_timestamp() - make_interval(mins => s.confirm_turn_minutes)
       order by called_at
    loop
      -- Si no hay nadie más formado, sigue siendo su turno (decisión 2026-10-15).
      if private.send_to_second_place(p) then
        perform private.log_pass_event(p.id, 'turn_expired', v_system);
      end if;
    end loop;
    perform private.advance(d.id, v_system);
  end loop;

  -- Alerta: alert_minutes fuera del salón (en enfermería solo el trayecto de ida) o
  -- alert_minutes de regreso desde enfermería sin que el maestro marque su regreso.
  for r in
    insert into public.alerts (pass_id)
    select ps.id from public.passes ps
     where (ps.status = 'out'
            and ps.started_at < clock_timestamp() - make_interval(mins => s.alert_minutes)
            and not exists (select 1 from public.alerts a where a.pass_id = ps.id))
        or (ps.status = 'returning'
            and ps.left_nurse_at < clock_timestamp() - make_interval(mins => s.alert_minutes)
            and not exists (select 1 from public.alerts a where a.pass_id = ps.id
                             and (a.resolved_at is null or a.created_at >= ps.left_nurse_at)))
    returning pass_id
  loop
    perform private.log_pass_event(r.pass_id, 'alert', v_system);
  end loop;

  -- Escalamiento: nadie la atendió en escalate_minutes.
  for r in
    update public.alerts
       set level = 2, escalated_at = clock_timestamp()
     where level = 1 and acknowledged_at is null and resolved_at is null
       and created_at < clock_timestamp() - make_interval(mins => s.escalate_minutes)
    returning pass_id
  loop
    perform private.log_pass_event(r.pass_id, 'escalated', v_system);
  end loop;

  update public.device_unlocks
     set locked_at = expires_at, lock_reason = 'auto'
   where locked_at is null and expires_at <= clock_timestamp();
end;
$$;
