-- Fase 5 · Notificaciones push (INTEGRATIONS §1). WhatsApp queda preparado pero apagado.
-- Flujo: un trigger en `alerts` escribe en notifications_outbox según notification_rules;
-- al insertar, pg_net llama a la Edge Function send-push (y un cron cada minuto la vuelve
-- a llamar por si algo falló). La URL y el secreto de la función viven en Vault.

create extension if not exists pg_net with schema extensions;

alter table public.settings
  add column vapid_public_key text,
  add column whatsapp_enabled boolean not null default false;

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------
create table public.notification_rules (
  role text not null check (role in ('current_teacher', 'authorizing_teacher', 'prefect', 'coordinator', 'director')),
  channel text not null check (channel in ('app', 'push', 'whatsapp')),
  enabled boolean not null default true,
  primary key (role, channel)
);

-- Valores por defecto del mockup de Configuración.
insert into public.notification_rules (role, channel, enabled) values
  ('current_teacher', 'app', true), ('current_teacher', 'push', false), ('current_teacher', 'whatsapp', false),
  ('authorizing_teacher', 'app', true), ('authorizing_teacher', 'push', false), ('authorizing_teacher', 'whatsapp', false),
  ('prefect', 'app', true), ('prefect', 'push', true), ('prefect', 'whatsapp', true),
  ('coordinator', 'app', true), ('coordinator', 'push', true), ('coordinator', 'whatsapp', true),
  ('director', 'app', true), ('director', 'push', true), ('director', 'whatsapp', true);

create table public.notifications_outbox (
  id bigserial primary key,
  channel text not null check (channel in ('push', 'whatsapp')),
  kind text not null check (kind in ('alert', 'escalated', 'acknowledged', 'resolved', 'test')),
  recipient_staff_id uuid references public.staff (id),  -- null = grupo de WhatsApp
  pass_id uuid references public.passes (id),
  body text not null,
  payload jsonb not null default '{}',
  created_at timestamptz not null default clock_timestamp(),
  claimed_at timestamptz,
  attempts int not null default 0,
  sent_at timestamptz,
  error text
);
create index notifications_outbox_pending on public.notifications_outbox (channel, created_at)
  where sent_at is null;

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff (id),
  endpoint text unique not null,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  last_success_at timestamptz,
  last_error text
);
create index push_subscriptions_staff on public.push_subscriptions (staff_id);

alter table public.notification_rules enable row level security;
alter table public.notifications_outbox enable row level security;
alter table public.push_subscriptions enable row level security;

grant select on public.notification_rules to authenticated;
grant update (enabled) on public.notification_rules to authenticated;
create policy notification_rules_select on public.notification_rules for select to authenticated
  using ((select private.current_staff_id()) is not null);
create policy notification_rules_update on public.notification_rules for update to authenticated
  using ((select private.can_manage())) with check ((select private.can_manage()));

-- La bandeja la ve coordinación (para revisar envíos y errores).
grant select on public.notifications_outbox to authenticated;
create policy notifications_outbox_select on public.notifications_outbox for select to authenticated
  using ((select private.can_manage()));

-- Cada quien ve sus propias suscripciones; se escriben solo por RPC.
grant select on public.push_subscriptions to authenticated;
create policy push_subscriptions_select on public.push_subscriptions for select to authenticated
  using (staff_id = (select private.current_staff_id()));

-- ---------------------------------------------------------------------------
-- Encolar notificaciones
-- ---------------------------------------------------------------------------
create function private.rule_on(p_role text, p_channel text) returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce((select enabled from public.notification_rules
                    where role = p_role and channel = p_channel), false);
$$;

-- Personal que recibe un aviso de este pase por este canal (SPEC §7).
create function private.recipients(p_pass uuid, p_channel text) returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select distinct s.id from public.staff s
   where s.active and (
     (private.rule_on('prefect', p_channel) and 'prefect' = any (s.roles))
     or (private.rule_on('coordinator', p_channel) and 'coordinator' = any (s.roles))
     or (private.rule_on('director', p_channel) and 'director' = any (s.roles))
     or (private.rule_on('current_teacher', p_channel) and s.id in (
           select c.teacher_id from public.passes p
             join public.classes_at(now()) c on c.group_id = p.group_id
            where p.id = p_pass))
     or (private.rule_on('authorizing_teacher', p_channel) and s.id in (
           select p.opened_by from public.passes p where p.id = p_pass)));
$$;

create function private.enqueue_alert_notification(p_alert public.alerts, p_kind text) returns void
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
         (select c.teacher_name from public.classes_at(now()) c where c.group_id = ps.group_id limit 1) as teacher
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
    from private.recipients(p.id, 'push') r;

  if (select whatsapp_enabled from public.settings where id = 1) then
    insert into public.notifications_outbox (channel, kind, pass_id, body)
    values ('whatsapp', p_kind, p.id, v_body);
  end if;
end;
$$;

create function private.on_alert_change() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform private.enqueue_alert_notification(new, 'alert');
  else
    if new.level = 2 and old.level = 1 then
      perform private.enqueue_alert_notification(new, 'escalated');
    end if;
    if new.acknowledged_by is not null and old.acknowledged_by is null then
      perform private.enqueue_alert_notification(new, 'acknowledged');
    end if;
    if new.resolved_at is not null and old.resolved_at is null then
      perform private.enqueue_alert_notification(new, 'resolved');
    end if;
  end if;
  return new;
end;
$$;

create trigger alerts_notify
  after insert or update on public.alerts
  for each row execute function private.on_alert_change();

-- ---------------------------------------------------------------------------
-- Disparar send-push (pg_net). URL y secreto en Vault:
--   select vault.create_secret('<url de la función>', 'send_push_url');
--   select vault.create_secret('<secreto>', 'send_push_secret');
-- Si no están configurados, no hace nada (los avisos esperan en la bandeja).
-- ---------------------------------------------------------------------------
create function private.kick_send_push() returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'send_push_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'send_push_secret';
  if v_url is null or v_secret is null then
    return;
  end if;
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000);
end;
$$;

create function private.on_outbox_insert() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform private.kick_send_push();
  return null;
end;
$$;

-- Una llamada por sentencia (un aviso puede tener varios destinatarios).
create trigger outbox_kick_push
  after insert on public.notifications_outbox
  for each statement execute function private.on_outbox_insert();

-- Respaldo: si hay pendientes, vuelve a llamar cada minuto.
select cron.schedule('pase-push', '* * * * *', $cron$
  select private.kick_send_push()
   where exists (select 1 from public.notifications_outbox
                  where channel = 'push' and sent_at is null and attempts < 5
                    and created_at > now() - interval '1 hour')
$cron$);

-- ---------------------------------------------------------------------------
-- Lo que llama send-push (con la llave service_role)
-- ---------------------------------------------------------------------------
-- Reserva un lote de avisos pendientes; un aviso reservado hace menos de 1 min no se
-- vuelve a tomar, así dos llamadas simultáneas no lo mandan dos veces.
create function public.claim_push_batch(p_limit int default 100)
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
    returning o.id, o.recipient_staff_id, o.body, o.payload
  )
  select c.id, c.recipient_staff_id, c.body, c.payload,
         coalesce((select jsonb_agg(jsonb_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth))
                     from public.push_subscriptions s where s.staff_id = c.recipient_staff_id), '[]'::jsonb)
    from claimed c;
$$;

create function public.finish_push(p_id bigint, p_error text, p_dead_endpoints text[], p_ok_endpoints text[])
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.notifications_outbox
     set sent_at = case when p_error is null then now() end, error = p_error
   where id = p_id;
  -- Suscripciones vencidas (el navegador ya no existe): se quitan.
  delete from public.push_subscriptions where endpoint = any (coalesce(p_dead_endpoints, '{}'));
  update public.push_subscriptions set last_success_at = now(), last_error = null
   where endpoint = any (coalesce(p_ok_endpoints, '{}'));
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC para la app
-- ---------------------------------------------------------------------------
create function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_staff uuid := private.current_staff_id();
begin
  if v_staff is null then
    raise exception 'Solo el personal recibe notificaciones' using errcode = '42501';
  end if;
  if coalesce(p_endpoint, '') !~ '^https://' then
    raise exception 'Suscripción no válida' using errcode = '22023';
  end if;
  insert into public.push_subscriptions (staff_id, endpoint, p256dh, auth, user_agent)
  values (v_staff, p_endpoint, p_p256dh, p_auth, left(p_user_agent, 300))
  on conflict (endpoint) do update
     set staff_id = excluded.staff_id, p256dh = excluded.p256dh, auth = excluded.auth,
         user_agent = excluded.user_agent, last_error = null;
end;
$$;

create function public.delete_push_subscription(p_endpoint text) returns void
language sql security definer set search_path = ''
as $$
  delete from public.push_subscriptions
   where endpoint = p_endpoint and staff_id = private.current_staff_id();
$$;

create function public.send_test_push() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_staff uuid := private.current_staff_id();
  v_subs int;
begin
  if v_staff is null then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  select count(*) into v_subs from public.push_subscriptions where staff_id = v_staff;
  if v_subs = 0 then
    return jsonb_build_object('ok', false, 'error', 'no_subscriptions');
  end if;
  insert into public.notifications_outbox (channel, kind, recipient_staff_id, body, payload)
  values ('push', 'test', v_staff, 'Así se verán las alertas en este equipo.',
          jsonb_build_object('title', 'Prueba de Pase Sanitario', 'tag', 'prueba', 'url', '/mas'));
  return jsonb_build_object('ok', true, 'devices', v_subs);
end;
$$;

-- Llave pública VAPID para suscribirse (no es secreta).
create function public.push_config() returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('vapid_public_key', vapid_public_key) from public.settings where id = 1;
$$;

-- my_alerts respeta la regla "en la app" de cada destinatario.
create or replace function public.my_alerts() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_me uuid := private.current_staff_id();
begin
  if v_me is null then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'pass_id', p.id, 'full_name', s.full_name, 'list_number', s.list_number,
      'group_id', p.group_id, 'group_name', g.name, 'status', p.status,
      'destination_label', d.label, 'started_at', p.started_at,
      'period_subject', p.period_subject, 'alert', private.alert_json(p.id)
    ) order by al.created_at)
      from public.alerts al
      join public.passes p on p.id = al.pass_id
      join public.students s on s.id = p.student_id
      join public.groups g on g.id = p.group_id
      join public.destinations d on d.id = p.destination_id
     where al.resolved_at is null
       and ((private.rule_on('authorizing_teacher', 'app') and p.opened_by = v_me)
            or (private.rule_on('current_teacher', 'app') and exists (
                  select 1 from public.classes_at(now()) c
                   where c.group_id = p.group_id and c.teacher_id = v_me)))), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.current_staff_id() to authenticated;
grant execute on function private.has_any_role(text[]) to authenticated;
grant execute on function private.can_manage() to authenticated;
grant execute on function private.current_device_id() to authenticated;
grant execute on function private.current_device_group_id() to authenticated;
grant execute on function private.is_member() to authenticated;
grant execute on function private.require_manager() to authenticated;

-- send-push usa service_role; nadie más.
revoke all on function public.claim_push_batch(int) from public, anon, authenticated;
revoke all on function public.finish_push(bigint, text, text[], text[]) from public, anon, authenticated;
grant execute on function public.claim_push_batch(int) to service_role;
grant execute on function public.finish_push(bigint, text, text[], text[]) to service_role;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.save_push_subscription(text, text, text, text)', 'public.delete_push_subscription(text)',
    'public.send_test_push()', 'public.push_config()', 'public.my_alerts()']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
