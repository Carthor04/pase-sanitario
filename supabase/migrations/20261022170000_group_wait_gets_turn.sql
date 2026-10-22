-- Quien esperaba a su grupo ya no sale directo cuando regresa su compañero: entra a la fila
-- con la hora en que se pidió su pase y recibe turno, que su maestro confirma (decisión
-- 2026-10-22). Así toda la lista se atiende igual, por turno y en orden de solicitud.

create or replace function private.advance(p_destination text, a private.actor) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  d public.destinations;
  r record;
  v_changed boolean;
  v_next uuid;
begin
  select * into d from public.destinations where id = p_destination;
  if d.kind <> 'bathroom' then
    return;
  end if;
  -- En pausa: la fila no avanza hasta que se reanude.
  if private.paused_since(d.id) is not null then
    return;
  end if;

  -- 1. El group_wait más antiguo de cada salón con lugar libre pasa a la fila con la hora
  --    en que se pidió su pase. Nunca sale directo: recibe turno en el paso 2.
  loop
    v_changed := false;
    for r in
      select distinct on (coalesce(p.room_group_id, p.group_id)) p.id,
             coalesce(p.room_group_id, p.group_id) as slot
        from public.passes p
       where p.destination_id = d.id and p.status = 'group_wait'
       order by coalesce(p.room_group_id, p.group_id), p.requested_at
    loop
      continue when private.group_slot_taken(d, r.slot);
      -- Los que se formaron mientras esperaba a su grupo no se le adelantan.
      update public.passes set status = 'queued', queue_ts = requested_at where id = r.id;
      perform private.log_pass_event(r.id, 'promoted', a, '{"to":"queued"}');
      v_changed := true;
    end loop;
    exit when not v_changed;
  end loop;

  -- 2. Mientras haya lugar, el primero de la fila pasa a "called".
  loop
    exit when not private.has_room(d);
    select id into v_next from public.passes
     where destination_id = d.id and status = 'queued'
     order by queue_ts, requested_at
     limit 1;
    exit when v_next is null;
    update public.passes set status = 'called', called_at = clock_timestamp() where id = v_next;
    perform private.log_pass_event(v_next, 'called', a);
  end loop;
end;
$$;
