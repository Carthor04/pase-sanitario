-- "Autorizar salida" desde En vivo: psicopedagogía, coordinación, dirección y admin pueden
-- sacar de la fila (o de la espera del grupo) a un alumno para que salga ya, aunque el baño
-- esté lleno o ya haya alguien de su grupo fuera. Es una excepción explícita: queda en la
-- bitácora como "forced_out" con quién la autorizó. Mientras el baño esté arriba de su
-- capacidad, advance() no llama a nadie más.

alter table public.pass_events drop constraint pass_events_type_check;
alter table public.pass_events add constraint pass_events_type_check check (type in (
  'requested', 'promoted', 'called', 'confirmed', 'ceded', 'turn_expired', 'arrived', 'sent_back',
  'returned', 'released', 'cancelled', 'undo', 'alert', 'escalated', 'alert_ack', 'note',
  'forced_out'));

create function public.force_out(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
begin
  perform private.require_role(a, array['counselor', 'coordinator', 'director', 'admin']);
  p := private.lock_pass(p_pass_id, a);
  if p.status not in ('group_wait', 'queued', 'called') then
    raise exception 'Ese alumno ya no está esperando' using errcode = 'P0001';
  end if;
  update public.passes
     set status = 'out', started_at = clock_timestamp()
   where id = p.id;
  perform private.log_pass_event(p.id, 'forced_out', a, jsonb_build_object('from', p.status));
  -- Si estaba "called", su lugar ya estaba reservado; si venía de la fila, ocupa uno más.
  perform private.advance(p.destination_id, a);
  return private.pass_json(p.id);
end;
$$;

revoke all on function public.force_out(uuid) from public, anon;
grant execute on function public.force_out(uuid) to authenticated;
