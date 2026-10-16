-- Aviso push cuando a un alumno le toca su turno (sale de la fila a "called").
-- Va al maestro que pidió el pase y al que tiene la clase ahora (reglas authorizing_teacher
-- y current_teacher de notification_rules), solo a quien tiene equipos registrados.
-- La compu del salón no recibe push: ahí sigue la franja "Turno de…" con sonido.

alter table public.notifications_outbox drop constraint notifications_outbox_kind_check;
alter table public.notifications_outbox add constraint notifications_outbox_kind_check
  check (kind in ('alert', 'escalated', 'acknowledged', 'resolved', 'returning', 'turn', 'test'));

create function private.enqueue_turn_notification(p_pass uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  p record;
  v_minutes int;
begin
  select ps.id, ps.group_id, ps.opened_by, st.full_name, g.name as group_name, d.label as place
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
                            'url', '/grupo?g=' || p.group_id, 'level', 2)
    from public.staff s
   where s.active
     and exists (select 1 from public.push_subscriptions ps where ps.staff_id = s.id)
     and ((private.rule_on('authorizing_teacher', 'push') and s.id = p.opened_by)
          or (private.rule_on('current_teacher', 'push') and s.id in (
                select c.teacher_id from public.classes_at(now()) c where c.group_id = p.group_id)));
end;
$$;

create function private.on_pass_called() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform private.enqueue_turn_notification(new.id);
  return null;
end;
$$;

create trigger passes_turn_push
  after update of status on public.passes
  for each row when (new.status = 'called' and old.status is distinct from 'called')
  execute function private.on_pass_called();

revoke all on function private.enqueue_turn_notification(uuid) from public, anon, authenticated;
revoke all on function private.on_pass_called() from public, anon, authenticated;
