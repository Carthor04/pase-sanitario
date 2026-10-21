-- Prefectura también autoriza salidas desde "Mi grupo" (abrir, confirmar turno, ceder y
-- cancelar), igual que maestros y coordinación. Las reglas de cupo y fila no cambian.

create or replace function public.request_pass(p_student_id uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  st public.students;
  d public.destinations;
  v_status public.pass_status;
  v_id uuid;
  v_room record;
  v_slot uuid;
begin
  perform private.require_role(a, array['teacher', 'prefect', 'coordinator', 'admin']);

  select * into st from public.students where id = p_student_id and active;
  if not found then
    raise exception 'Alumno no encontrado' using errcode = 'P0002';
  end if;
  if not private.device_may_operate(a, st.id) then
    raise exception 'Este equipo solo opera alumnos de su salón' using errcode = '42501';
  end if;

  if p_kind = 'bathroom' then
    select * into d from public.destinations
     where kind = 'bathroom' and sex = st.sex order by id limit 1 for update;
  elsif p_kind = 'nurse' then
    select * into d from public.destinations where kind = 'nurse' order by id limit 1 for update;
  else
    raise exception 'Tipo de pase no válido: usa bathroom o nurse' using errcode = '22023';
  end if;
  if not found then
    raise exception 'No hay destino configurado para este pase' using errcode = 'P0002';
  end if;

  -- Dónde estaba: en su sección (con el salón) o con su grupo.
  select r.room_group_id, r.section_id,
         case when r.section_id is not null
              then r.subject || coalesce(' · ' || g.room, '')
              else r.subject end as subject
    into v_room
    from private.student_room_at(st.id, now()) r
    left join public.groups g on g.id = r.room_group_id;

  -- Lugar del grupo: el del salón donde está (en Inglés, el salón del nivel).
  v_slot := coalesce(a.device_group_id, v_room.room_group_id, st.group_id);

  if exists (select 1 from public.passes where student_id = st.id
              and status in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning')) then
    raise exception 'El alumno ya tiene un pase activo' using errcode = 'P0001';
  end if;

  if private.group_slot_taken(d, v_slot) then
    v_status := 'group_wait';
  elsif private.has_room(d) and not private.has_queue(d.id) then
    v_status := 'out';
  elsif d.queue_enabled then
    v_status := 'queued';
  else
    raise exception '% está lleno', d.label using errcode = 'P0001';
  end if;

  begin
    insert into public.passes (
      student_id, group_id, destination_id, status, requested_at, queue_ts, started_at,
      opened_by, device_id, period_subject, room_group_id)
    values (
      st.id, st.group_id, d.id, v_status, clock_timestamp(),
      case when v_status = 'queued' then clock_timestamp() end,
      case when v_status = 'out' then clock_timestamp() end,
      a.staff_id, a.device_id, v_room.subject,
      v_slot)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'El alumno ya tiene un pase activo' using errcode = 'P0001';
  end;

  perform private.log_pass_event(v_id, 'requested', a, jsonb_build_object('status', v_status));
  return private.pass_json(v_id);
end;
$$;

create or replace function public.confirm_turn(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
begin
  perform private.require_role(a, array['teacher', 'prefect', 'coordinator', 'admin']);
  p := private.lock_pass(p_pass_id, a);
  if p.status <> 'called' then
    raise exception 'Ese pase ya no está esperando confirmación' using errcode = 'P0001';
  end if;
  update public.passes set status = 'out', started_at = clock_timestamp() where id = p.id;
  perform private.log_pass_event(p.id, 'confirmed', a);
  return private.pass_json(p.id);
end;
$$;

create or replace function public.cede_turn(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
begin
  perform private.require_role(a, array['teacher', 'prefect', 'coordinator', 'admin']);
  p := private.lock_pass(p_pass_id, a);
  if p.status <> 'called' then
    raise exception 'Ese pase ya no está esperando confirmación' using errcode = 'P0001';
  end if;
  if not private.send_to_second_place(p) then
    raise exception 'Nadie más en fila: no se puede ceder el turno' using errcode = 'P0001';
  end if;
  perform private.log_pass_event(p.id, 'ceded', a);
  perform private.advance(p.destination_id, a);
  return private.pass_json(p.id);
end;
$$;

create or replace function public.cancel_pass(p_pass_id uuid) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  p public.passes;
begin
  perform private.require_role(a, array['teacher', 'prefect', 'coordinator', 'admin']);
  p := private.lock_pass(p_pass_id, a);
  if p.status not in ('group_wait', 'queued', 'called') then
    raise exception 'Solo se cancela un pase antes de que el alumno salga' using errcode = 'P0001';
  end if;
  update public.passes
     set status = 'cancelled', ended_at = clock_timestamp(), closed_by = a.staff_id
   where id = p.id;
  perform private.log_pass_event(p.id, 'cancelled', a, jsonb_build_object('from', p.status));
  perform private.advance(p.destination_id, a);
  return private.pass_json(p.id);
end;
$$;
