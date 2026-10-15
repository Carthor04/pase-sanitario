-- Fase 5 · Solo se encolan avisos push para personal con al menos un equipo registrado
-- (el personal de ejemplo nunca se suscribe y llenaría la bandeja de avisos imposibles).

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
    from private.recipients(p.id, 'push') r
   -- Solo a quien tiene al menos un equipo registrado: lo demás no se puede entregar.
   where exists (select 1 from public.push_subscriptions ps where ps.staff_id = r);

  if (select whatsapp_enabled from public.settings where id = 1) then
    insert into public.notifications_outbox (channel, kind, pass_id, body)
    values ('whatsapp', p_kind, p.id, v_body);
  end if;
end;
$$;

revoke all on function private.enqueue_alert_notification(public.alerts, text) from public, anon, authenticated;
