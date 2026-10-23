-- Clases por nivel (Inglés): el pase que todavía no sale sigue al alumno a su salón. Al
-- terminar la clase, el alumno regresa a su salón y su pase en espera, en fila o con turno
-- se muestra y se avisa ahí, no en el salón donde se pidió. Si en el salón nuevo ya hay
-- alguien de su sexo con el lugar ocupado, pasa a "espera de su grupo" conservando la hora
-- en que se pidió (al volver a la fila no pierde su lugar). Lo revisa tick() cada 30 s.

alter table public.pass_events drop constraint pass_events_type_check;
alter table public.pass_events add constraint pass_events_type_check check (type in (
  'requested', 'promoted', 'called', 'confirmed', 'ceded', 'turn_expired', 'arrived', 'sent_back',
  'returned', 'released', 'cancelled', 'undo', 'alert', 'escalated', 'alert_ack', 'note',
  'forced_out', 'room_changed'));

create function private.follow_student_room(p_at timestamptz default clock_timestamp()) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  d record;
  r record;
  v_to public.pass_status;
  v_system private.actor;  -- todo en null: lo hizo el sistema
begin
  for d in select id from public.destinations where kind = 'bathroom' order by id loop
    perform 1 from public.destinations where id = d.id for update;
    for r in
      select p.id, p.status, p.destination_id, coalesce(p.room_group_id, p.group_id) as from_room,
             x.room_group_id as to_room
        from public.passes p
        cross join lateral (select room_group_id from private.student_room_at(p.student_id, p_at) limit 1) x
       where p.destination_id = d.id and p.status in ('group_wait', 'queued', 'called')
         and x.room_group_id is not null
         and x.room_group_id <> coalesce(p.room_group_id, p.group_id)
       order by p.requested_at
    loop
      v_to := r.status;
      if r.status in ('queued', 'called') and exists (
           select 1 from public.passes o
            where o.destination_id = r.destination_id and o.id <> r.id
              and coalesce(o.room_group_id, o.group_id) = r.to_room
              and o.status in ('queued', 'called', 'out')) then
        v_to := 'group_wait';
      end if;
      update public.passes
         set room_group_id = r.to_room,
             status = v_to,
             queue_ts = case when v_to = 'group_wait' then null else queue_ts end,
             called_at = case when v_to = 'group_wait' then null else called_at end
       where id = r.id;
      perform private.log_pass_event(r.id, 'room_changed', v_system, jsonb_build_object(
        'from_room', r.from_room, 'to_room', r.to_room, 'from', r.status, 'to', v_to));
    end loop;
    perform private.advance(d.id, v_system);
  end loop;
end;
$$;
revoke all on function private.follow_student_room(timestamptz) from public, anon, authenticated;

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
  perform private.follow_student_room();

  for d in select id from public.destinations where kind = 'bathroom' order by id loop
    perform 1 from public.destinations where id = d.id for update;
    for p in
      select * from public.passes
       where destination_id = d.id and status = 'called'
         -- En pausa no corre el tiempo; al reanudar vuelve a contar desde cero.
         and private.paused_since(d.id) is null
         and greatest(called_at, private.last_resume(d.id))
               < clock_timestamp() - make_interval(mins => s.confirm_turn_minutes)
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
