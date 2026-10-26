-- Enfermería sin límite de tiempo (decisión 2026-10-26): es algo médico, así que un pase de
-- enfermería ya no genera alertas, ni de ida ni de regreso al salón. Las alertas quedan solo
-- para los baños. tick() y ensure_alert() filtran por destino; las alertas de enfermería que
-- sigan abiertas se cierran (sin resolución: no regresó ni se liberó, solo dejó de aplicar).

update public.alerts al
   set resolved_at = clock_timestamp()
  from public.passes p
  join public.destinations d on d.id = p.destination_id
 where al.pass_id = p.id and al.resolved_at is null and d.kind = 'nurse';

create or replace function private.ensure_alert(p public.passes) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_minutes int := (select alert_minutes from public.settings where id = 1);
  v_id uuid;
begin
  select id into v_id from public.alerts where pass_id = p.id and resolved_at is null;
  if v_id is not null then
    return v_id;
  end if;
  if not (p.status = 'out'
          and p.started_at < clock_timestamp() - make_interval(mins => v_minutes)
          and (select kind from public.destinations where id = p.destination_id) = 'bathroom'
          and not exists (select 1 from public.alerts a where a.pass_id = p.id)) then
    return null;
  end if;
  begin
    insert into public.alerts (pass_id) values (p.id) returning id into v_id;
    perform private.log_pass_event(p.id, 'alert', null::private.actor);
  exception when unique_violation then
    -- tick() la acaba de crear.
    select id into v_id from public.alerts where pass_id = p.id and resolved_at is null;
  end;
  return v_id;
end;
$$;

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

revoke all on function private.ensure_alert(public.passes) from public, anon, authenticated;
revoke all on function private.tick() from public, anon, authenticated;
