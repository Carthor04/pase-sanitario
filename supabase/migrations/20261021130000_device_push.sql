-- Notificaciones push en la computadora del salón. Una suscripción es de una persona del
-- personal o de un equipo vinculado. El equipo recibe los avisos de los alumnos que salieron
-- de su salón: turno, alerta (y escalada, atendida, resuelta) y regreso de enfermería.

alter table public.push_subscriptions alter column staff_id drop not null;
alter table public.push_subscriptions add column device_id uuid references public.devices (id);
alter table public.push_subscriptions add constraint push_subscriptions_owner
  check ((staff_id is not null) <> (device_id is not null));
alter table public.notifications_outbox add column recipient_device_id uuid references public.devices (id);

create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_staff uuid := private.current_staff_id();
  v_device uuid := private.current_device_id();
begin
  if v_staff is null and v_device is null then
    raise exception 'Solo el personal y los equipos vinculados reciben notificaciones' using errcode = '42501';
  end if;
  if coalesce(p_endpoint, '') !~ '^https://' then
    raise exception 'Suscripción no válida' using errcode = '22023';
  end if;
  insert into public.push_subscriptions (staff_id, device_id, endpoint, p256dh, auth, user_agent)
  values (v_staff, case when v_staff is null then v_device end, p_endpoint, p_p256dh, p_auth,
          left(p_user_agent, 300))
  on conflict (endpoint) do update
     set staff_id = excluded.staff_id, device_id = excluded.device_id, p256dh = excluded.p256dh,
         auth = excluded.auth, user_agent = excluded.user_agent, last_error = null;
end;
$$;

create or replace function public.delete_push_subscription(p_endpoint text) returns void
language sql security definer set search_path = ''
as $$
  delete from public.push_subscriptions
   where endpoint = p_endpoint
     and (staff_id = private.current_staff_id() or device_id = private.current_device_id());
$$;

create or replace function public.send_test_push() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_staff uuid := private.current_staff_id();
  v_device uuid := private.current_device_id();
  v_subs int;
begin
  if v_staff is null and v_device is null then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  select count(*) into v_subs from public.push_subscriptions
   where (v_staff is not null and staff_id = v_staff)
      or (v_staff is null and device_id = v_device);
  if v_subs = 0 then
    return jsonb_build_object('ok', false, 'error', 'no_subscriptions');
  end if;
  insert into public.notifications_outbox (channel, kind, recipient_staff_id, recipient_device_id, body, payload)
  values ('push', 'test', v_staff, case when v_staff is null then v_device end,
          'Así se verán las alertas en este equipo.',
          jsonb_build_object('title', 'Prueba de Pase Sanitario', 'tag', 'prueba',
                             'url', case when v_staff is null then '/salon' else '/perfil' end));
  return jsonb_build_object('ok', true, 'devices', v_subs);
end;
$$;

-- Aviso a las computadoras del salón de donde salió el alumno (solo las que tienen avisos).
create function private.enqueue_device_push(p_pass uuid, p_kind text, p_title text, p_body text, p_level int default 1)
returns void
language sql security definer set search_path = ''
as $$
  insert into public.notifications_outbox (channel, kind, recipient_device_id, pass_id, body, payload)
  select 'push', p_kind, dv.id, p_pass, p_body,
         jsonb_build_object('title', p_title, 'tag', 'pase-' || p_pass, 'url', '/salon', 'level', p_level)
    from public.passes ps
    join public.devices dv on dv.group_id = coalesce(ps.room_group_id, ps.group_id) and dv.revoked_at is null
   where ps.id = p_pass
     and exists (select 1 from public.push_subscriptions s where s.device_id = dv.id);
$$;
revoke all on function private.enqueue_device_push(uuid, text, text, text, int) from public, anon, authenticated;

create or replace function public.claim_push_batch(p_limit int default 100)
returns table (id bigint, recipient_staff_id uuid, body text, payload jsonb, subscriptions jsonb)
language sql security definer set search_path = ''
as $$
  with picked as (
    select o.id from public.notifications_outbox o
     where o.channel = 'push' and o.sent_at is null and o.attempts < 5
       and o.created_at > now() - interval '1 hour'
       and (o.claimed_at is null or o.claimed_at < now() - interval '1 minute')
     order by o.id
     limit p_limit
     for update skip locked
  ), claimed as (
    update public.notifications_outbox o
       set claimed_at = now(), attempts = o.attempts + 1
      from picked where o.id = picked.id
    returning o.id, o.recipient_staff_id, o.recipient_device_id, o.body, o.payload
  )
  select c.id, c.recipient_staff_id, c.body, c.payload,
         coalesce((select jsonb_agg(jsonb_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth))
                     from public.push_subscriptions s
                    where (c.recipient_staff_id is not null and s.staff_id = c.recipient_staff_id)
                       or (c.recipient_device_id is not null and s.device_id = c.recipient_device_id)), '[]'::jsonb)
    from claimed c;
$$;

create or replace function private.enqueue_alert_notification(p_alert public.alerts, p_kind text) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p record;
  v_min int;
  v_body text;
  v_title text;
begin
  select ps.id, ps.status, ps.started_at, ps.ended_at, ps.period_subject, st.full_name,
         g.name as group_name, d.label as place, ps.group_id,
         (select r.teacher_name from private.student_room_at(ps.student_id, now()) r) as teacher
    into p
    from public.passes ps
    join public.students st on st.id = ps.student_id
    join public.groups g on g.id = ps.group_id
    join public.destinations d on d.id = ps.destination_id
   where ps.id = p_alert.pass_id;

  v_min := greatest(0, floor(extract(epoch from (coalesce(p.ended_at, clock_timestamp()) - p.started_at)) / 60))::int;

  case p_kind
    when 'alert' then
      v_title := 'Alerta · ' || v_min || ' min fuera';
      v_body := format('⚠️ %s (%s) lleva %s min fuera · %s%s', p.full_name, p.group_name, v_min, p.place,
        case when p.period_subject is not null
             then ' · Clase: ' || p.period_subject || coalesce(', ' || p.teacher, '') else '' end);
    when 'escalated' then
      v_title := 'Sin atender';
      v_body := format('🔴 SIN ATENDER · %s (%s) · %s min · %s', p.full_name, p.group_name, v_min, p.place);
    when 'acknowledged' then
      v_title := 'Alerta atendida';
      v_body := format('👤 %s atiende a %s (%s)',
        (select full_name from public.staff where id = p_alert.acknowledged_by), p.full_name, p.group_name);
    when 'resolved' then
      v_title := 'Resuelto';
      v_body := format('✅ %s (%s) %s · %s min', p.full_name, p.group_name,
        case p_alert.resolution when 'released' then 'liberado por prefectura'
                                when 'arrived' then 'llegó a enfermería' else 'regresó' end, v_min);
  end case;

  insert into public.notifications_outbox (channel, kind, recipient_staff_id, pass_id, body, payload)
  select 'push', p_kind, r, p.id, v_body,
         jsonb_build_object('title', v_title, 'tag', 'pase-' || p.id, 'url',
           case when exists (select 1 from public.staff s where s.id = r
                              and s.roles && array['prefect', 'coordinator', 'director', 'admin'])
                then '/en-vivo' else '/alertas' end,
           'level', p_alert.level)
    from private.recipients(p.id, 'push') r
   -- Solo a quien tiene al menos un equipo registrado: lo demás no se puede entregar.
   where exists (select 1 from public.push_subscriptions ps where ps.staff_id = r);

  perform private.enqueue_device_push(p.id, p_kind, v_title, v_body, p_alert.level);

  if (select whatsapp_enabled from public.settings where id = 1) then
    insert into public.notifications_outbox (channel, kind, pass_id, body)
    values ('whatsapp', p_kind, p.id, v_body);
  end if;
end;
$$;

create or replace function private.enqueue_returning_notification(p_pass uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p record;
begin
  select ps.id, st.full_name, g.name as group_name,
         coalesce((select r.room_group_id from private.student_room_at(ps.student_id, now()) r),
                  ps.group_id) as room
    into p
    from public.passes ps
    join public.students st on st.id = ps.student_id
    join public.groups g on g.id = ps.group_id
   where ps.id = p_pass;

  -- Al maestro a cargo ahora y al que autorizó la salida (según las reglas de push).
  insert into public.notifications_outbox (channel, kind, recipient_staff_id, pass_id, body, payload)
  select 'push', 'returning', s.id, p.id,
         format('🏫 %s (%s) salió de enfermería y va de regreso al salón. Marca su regreso al llegar.',
                p.full_name, p.group_name),
         jsonb_build_object('title', 'De regreso al salón', 'tag', 'pase-' || p.id,
                            'url', '/grupo?g=' || p.room)
    from public.staff s
   where s.active
     and exists (select 1 from public.push_subscriptions ps where ps.staff_id = s.id)
     and ((private.rule_on('current_teacher', 'push') and s.id = private.pass_teacher_now(p.id))
          or (private.rule_on('authorizing_teacher', 'push') and s.id in (
            select ps.opened_by from public.passes ps where ps.id = p.id)));

  perform private.enqueue_device_push(p.id, 'returning', 'De regreso al salón',
    format('🏫 %s (%s) salió de enfermería y va de regreso al salón.', p.full_name, p.group_name));
end;
$$;

create or replace function private.enqueue_turn_notification(p_pass uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p record;
  v_minutes int;
begin
  select ps.id, ps.opened_by, st.full_name, g.name as group_name, d.label as place,
         coalesce(ps.room_group_id, ps.group_id) as room
    into p
    from public.passes ps
    join public.students st on st.id = ps.student_id
    join public.groups g on g.id = ps.group_id
    join public.destinations d on d.id = ps.destination_id
   where ps.id = p_pass;
  select confirm_turn_minutes into v_minutes from public.settings where id = 1;

  insert into public.notifications_outbox (channel, kind, recipient_staff_id, pass_id, body, payload)
  select 'push', 'turn', s.id, p.id,
         format('🔔 Turno de %s (%s) · %s. Confirma su salida en %s min o pasa al siguiente.',
                p.full_name, p.group_name, p.place, v_minutes),
         jsonb_build_object('title', 'Turno de ' || p.full_name, 'tag', 'pase-' || p.id,
                            'url', '/grupo?g=' || p.room, 'level', 2)
    from public.staff s
   where s.active
     and exists (select 1 from public.push_subscriptions ps where ps.staff_id = s.id)
     and ((private.rule_on('authorizing_teacher', 'push') and s.id = p.opened_by)
          or (private.rule_on('current_teacher', 'push') and s.id = private.pass_teacher_now(p.id)));

  perform private.enqueue_device_push(p.id, 'turn', 'Turno de ' || p.full_name,
    format('🔔 Turno de %s (%s) · %s. Confirma su salida en %s min o pasa al siguiente.',
           p.full_name, p.group_name, p.place, v_minutes), 2);
end;
$$;
