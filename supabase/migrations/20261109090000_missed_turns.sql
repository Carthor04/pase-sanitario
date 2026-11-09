-- Fila más ágil (decisión 2026-11-09).
--
-- 1. Turnos perdidos: un pase cuyo turno vence sin confirmarse vuelve al segundo lugar, pero
--    solo hasta settings.max_missed_turns (2) veces. En la vez que llega al límite se cancela
--    solo (evento "cancelled" del sistema con payload.auto = 'sin_confirmar') y se avisa al
--    maestro para que lo pida de nuevo. Antes un pase sin atender regresaba al segundo lugar
--    sin fin y dejaba el baño apartado 2 min en cada vuelta. Si no hay nadie más formado
--    sigue siendo su turno, como antes.
-- 2. Vencer al momento: public.expire_turns() la llaman las pantallas cuando su cuenta
--    regresiva llega a cero, para no esperar al siguiente tick() (cada 30 s). La regla y la
--    hora las sigue revisando Postgres.
-- 3. Cambio de salón: follow_student_room usa la regla del lugar del baño
--    (group_slot_taken). El baño de hombres no tiene lugar por grupo y ya no manda a
--    "espera de su grupo" a quien estaba en fila o con turno.

alter table public.settings
  add column max_missed_turns int not null default 2 check (max_missed_turns between 1 and 10);

alter table public.notifications_outbox drop constraint notifications_outbox_kind_check;
alter table public.notifications_outbox add constraint notifications_outbox_kind_check
  check (kind in ('alert', 'escalated', 'acknowledged', 'resolved', 'returning', 'turn',
                  'turn_cancelled', 'test'));

-- Aviso al maestro: el pase se canceló porque nadie confirmó el turno.
create function private.enqueue_turn_cancelled_notification(p_pass uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p record;
  v_body text;
begin
  select ps.id, ps.opened_by, st.full_name, g.name as group_name,
         coalesce(ps.room_group_id, ps.group_id) as room
    into p
    from public.passes ps
    join public.students st on st.id = ps.student_id
    join public.groups g on g.id = ps.group_id
   where ps.id = p_pass;
  v_body := format('Se canceló el pase de %s (%s): nadie confirmó su turno. Pídelo de nuevo cuando esté listo.',
                   p.full_name, p.group_name);

  insert into public.notifications_outbox (channel, kind, recipient_staff_id, pass_id, body, payload)
  select 'push', 'turn_cancelled', s.id, p.id, v_body,
         jsonb_build_object('title', 'Pase cancelado', 'tag', 'pase-' || p.id,
                            'url', '/grupo?g=' || p.room)
    from public.staff s
   where s.active
     and exists (select 1 from public.push_subscriptions ps where ps.staff_id = s.id)
     and ((private.rule_on('authorizing_teacher', 'push') and s.id = p.opened_by)
          or (private.rule_on('current_teacher', 'push') and s.id = private.pass_teacher_now(p.id)));

  perform private.enqueue_device_push(p.id, 'turn_cancelled', 'Pase cancelado', v_body);
end;
$$;
revoke all on function private.enqueue_turn_cancelled_notification(uuid) from public, anon, authenticated;

-- Vence los turnos sin confirmar de un baño y avanza su fila. Quien la llama ya tiene el
-- candado del destino.
create function private.expire_turns(p_destination text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p public.passes;
  s public.settings;
  v_missed int;
  v_system private.actor;  -- todo en null: lo hizo el sistema
begin
  select * into s from public.settings where id = 1;
  for p in
    select * from public.passes
     where destination_id = p_destination and status = 'called'
       -- En pausa no corre el tiempo; al reanudar vuelve a contar desde cero.
       and private.paused_since(p_destination) is null
       and greatest(called_at, private.last_resume(p_destination))
             < clock_timestamp() - make_interval(mins => s.confirm_turn_minutes)
     order by called_at
  loop
    -- Si no hay nadie más formado, sigue siendo su turno (decisión 2026-10-15).
    continue when not exists (
      select 1 from public.passes q
       where q.destination_id = p_destination and q.status = 'queued' and q.id <> p.id);

    v_missed := 1 + (select count(*) from public.pass_events e
                      where e.pass_id = p.id and e.type = 'turn_expired');
    if v_missed >= s.max_missed_turns then
      update public.passes set status = 'cancelled', ended_at = clock_timestamp() where id = p.id;
      perform private.log_pass_event(p.id, 'turn_expired', v_system,
        jsonb_build_object('missed', v_missed));
      perform private.log_pass_event(p.id, 'cancelled', v_system,
        jsonb_build_object('from', 'called', 'auto', 'sin_confirmar', 'missed', v_missed));
      perform private.enqueue_turn_cancelled_notification(p.id);
    else
      perform private.send_to_second_place(p);
      perform private.log_pass_event(p.id, 'turn_expired', v_system,
        jsonb_build_object('missed', v_missed));
    end if;
  end loop;
  perform private.advance(p_destination, v_system);
end;
$$;
revoke all on function private.expire_turns(text) from public, anon, authenticated;

-- Las pantallas la llaman cuando la cuenta regresiva de un turno llega a cero. No decide
-- nada nuevo: aplica la misma regla que tick() con la hora del servidor.
create function public.expire_turns() returns void
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();  -- personal o computadora de salón
  d record;
begin
  for d in select id from public.destinations where kind = 'bathroom' order by id loop
    perform 1 from public.destinations where id = d.id for update;
    -- Solo si hay un turno vencido: lo normal es que no haya nada que hacer.
    if exists (select 1 from public.passes where destination_id = d.id and status = 'called') then
      perform private.expire_turns(d.id);
    end if;
  end loop;
end;
$$;
revoke all on function public.expire_turns() from public, anon;
grant execute on function public.expire_turns() to authenticated;

create or replace function private.follow_student_room(p_at timestamptz default clock_timestamp()) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  d public.destinations;
  r record;
  v_to public.pass_status;
  v_system private.actor;  -- todo en null: lo hizo el sistema
begin
  for d in select * from public.destinations where kind = 'bathroom' order by id loop
    perform 1 from public.destinations where id = d.id for update;
    for r in
      select p.id, p.status, coalesce(p.room_group_id, p.group_id) as from_room,
             x.room_group_id as to_room
        from public.passes p
        cross join lateral (select room_group_id from private.student_room_at(p.student_id, p_at) limit 1) x
       where p.destination_id = d.id and p.status in ('group_wait', 'queued', 'called')
         and x.room_group_id is not null
         and x.room_group_id <> coalesce(p.room_group_id, p.group_id)
       order by p.requested_at
    loop
      v_to := r.status;
      -- La misma regla del lugar que al pedir el pase: el baño sin lugar por grupo (hombres)
      -- nunca manda a "espera de su grupo".
      if r.status in ('queued', 'called') and private.group_slot_taken(d, r.to_room) then
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
    perform private.expire_turns(d.id);
  end loop;

  -- Alerta: alert_minutes fuera en el baño. Enfermería no tiene límite de tiempo.
  for r in
    insert into public.alerts (pass_id)
    select ps.id from public.passes ps
      join public.destinations dn on dn.id = ps.destination_id and dn.kind = 'bathroom'
     where ps.status = 'out'
       and ps.started_at < clock_timestamp() - make_interval(mins => s.alert_minutes)
       and not exists (select 1 from public.alerts a where a.pass_id = ps.id)
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
revoke all on function private.tick() from public, anon, authenticated;
