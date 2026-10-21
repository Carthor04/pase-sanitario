-- "Yo lo atiendo" por pase. tick() crea las alertas cada 30 s, así que un alumno puede llevar
-- ya el tiempo de alerta sin que su alerta exista todavía. El monitor la muestra en cuanto se
-- cumple el tiempo y prefectura la atiende con acknowledge_pass(): si aún no existe, se crea
-- aquí (mismo criterio que tick) y se atiende en la misma transacción.

-- Crea la alerta del pase si ya le toca y no tiene una abierta. Devuelve la alerta abierta.
create function private.ensure_alert(p public.passes) returns uuid
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
  if not ((p.status = 'out'
           and p.started_at < clock_timestamp() - make_interval(mins => v_minutes)
           and not exists (select 1 from public.alerts a where a.pass_id = p.id))
          or (p.status = 'returning'
              and p.left_nurse_at < clock_timestamp() - make_interval(mins => v_minutes))) then
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

create function public.acknowledge_pass(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_pass public.passes;
  v_alert uuid;
begin
  perform private.require_role(a, array['prefect', 'coordinator', 'admin']);
  select * into v_pass from public.passes where id = p_pass_id for update;
  if not found then
    raise exception 'Pase no encontrado' using errcode = 'P0002';
  end if;
  v_alert := private.ensure_alert(v_pass);
  if v_alert is null then
    raise exception 'Ese alumno no tiene alerta' using errcode = 'P0001';
  end if;
  return public.acknowledge_alert(v_alert);
end;
$$;

revoke all on function private.ensure_alert(public.passes) from public, anon, authenticated;
revoke all on function public.acknowledge_pass(uuid) from public, anon;
grant execute on function public.acknowledge_pass(uuid) to authenticated;
