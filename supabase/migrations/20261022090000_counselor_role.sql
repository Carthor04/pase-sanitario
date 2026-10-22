-- Rol "counselor" (Psicopedagogía): ve el monitor En vivo en solo lectura. No atiende
-- alertas, no libera lugares ni recibe avisos de alerta (no está en notification_rules).

alter table public.staff drop constraint staff_roles_check;
alter table public.staff add constraint staff_roles_check check (
  cardinality(roles) > 0
  and roles <@ array['teacher', 'prefect', 'nurse', 'coordinator', 'director', 'admin', 'counselor']);

create or replace function public.import_staff(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  v_errors jsonb := '[]';
  v_seen text[] := '{}';
  v_email text;
  v_roles text[];
  v_bad text[];
  v_inserted int := 0;
  v_updated int := 0;
  c_valid constant text[] := array['teacher', 'prefect', 'nurse', 'coordinator', 'director', 'admin', 'counselor'];
begin
  perform private.require_manager();

  for r in select e.value as v, coalesce((e.value ->> '_row')::int, e.ordinality::int + 1) as line
             from jsonb_array_elements(p_rows) with ordinality e loop
    if private.clean(r.v ->> 'nombre_completo') is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Falta el nombre');
    end if;

    v_email := lower(private.clean(r.v ->> 'correo'));
    if v_email is null then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'Falta el correo');
    elsif v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', format('Correo no válido: %s', v_email));
    elsif v_email = any (v_seen) then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', format('El correo %s está repetido', v_email));
    else
      v_seen := v_seen || v_email;
    end if;

    v_roles := array(
      select distinct lower(btrim(x))
        from regexp_split_to_table(coalesce(r.v ->> 'roles', ''), '[;,]') x
       where btrim(x) <> '');
    v_bad := array(select x from unnest(v_roles) x where not x = any (c_valid));
    if cardinality(v_roles) = 0 then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
        'Faltan los roles (teacher, prefect, nurse, coordinator, director, admin, counselor)');
    elsif cardinality(v_bad) > 0 then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message',
        format('Rol desconocido: %s', array_to_string(v_bad, ', ')));
    end if;

    if private.clean(r.v ->> 'whatsapp') is not null
       and regexp_replace(r.v ->> 'whatsapp', '\D', '', 'g') !~ '^\d{10,13}$' then
      v_errors := v_errors || jsonb_build_object('row', r.line, 'message', 'WhatsApp debe tener 10 a 13 dígitos');
    end if;
  end loop;

  if jsonb_array_length(v_errors) > 0 then
    return private.import_error(v_errors);
  end if;

  for r in select e.value as v from jsonb_array_elements(p_rows) e loop
    v_email := lower(private.clean(r.v ->> 'correo'));
    v_roles := array(
      select distinct lower(btrim(x))
        from regexp_split_to_table(r.v ->> 'roles', '[;,]') x
       where btrim(x) <> '');
    update public.staff
       set full_name = private.clean(r.v ->> 'nombre_completo'),
           roles = v_roles,
           whatsapp = nullif(regexp_replace(coalesce(r.v ->> 'whatsapp', ''), '\D', '', 'g'), ''),
           active = true
     where lower(email) = v_email;
    if found then
      v_updated := v_updated + 1;
    else
      insert into public.staff (full_name, email, roles, whatsapp)
      values (private.clean(r.v ->> 'nombre_completo'), v_email, v_roles,
              nullif(regexp_replace(coalesce(r.v ->> 'whatsapp', ''), '\D', '', 'g'), ''));
      v_inserted := v_inserted + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'summary',
    jsonb_build_object('inserted', v_inserted, 'updated', v_updated));
end;
$$;

create or replace function public.live_board() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  v_today date := (now() at time zone 'America/Mexico_City')::date;
begin
  perform private.require_role(a, array['prefect', 'nurse', 'coordinator', 'director', 'admin', 'counselor']);
  return jsonb_build_object(
    'now', clock_timestamp(),
    'settings', (select jsonb_build_object('alert_minutes', alert_minutes,
      'escalate_minutes', escalate_minutes, 'confirm_turn_minutes', confirm_turn_minutes)
      from public.settings where id = 1),
    'destinations', (select jsonb_agg(jsonb_build_object('id', d.id, 'label', d.label,
      'kind', d.kind, 'sex', d.sex, 'capacity', d.capacity) order by d.kind, d.sex) from public.destinations d),
    'passes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'student_id', p.student_id, 'list_number', s.list_number,
        'full_name', s.full_name, 'sex', s.sex, 'group_id', p.group_id, 'group_name', g.name,
        'status', p.status, 'destination_id', p.destination_id,
        'requested_at', p.requested_at, 'queue_ts', p.queue_ts, 'called_at', p.called_at,
        'started_at', p.started_at, 'arrived_at', p.arrived_at, 'left_nurse_at', p.left_nurse_at,
        'period_subject', p.period_subject, 'opened_by_name', o.full_name,
        'current_teacher_name', (select r.teacher_name from private.student_room_at(p.student_id, now()) r),
        'alert', private.alert_json(p.id)
      ) order by p.queue_ts nulls last, p.started_at nulls last, p.requested_at)
        from public.passes p
        join public.students s on s.id = p.student_id
        join public.groups g on g.id = p.group_id
        left join public.staff o on o.id = p.opened_by
       where p.status in ('group_wait', 'queued', 'called', 'out', 'arrived', 'returning')), '[]'::jsonb),
    'stats', jsonb_build_object(
      'exits_today', (select count(*) from public.passes p
                       where p.started_at is not null
                         and (p.started_at at time zone 'America/Mexico_City')::date = v_today),
      'alerts_today', (select count(*) from public.alerts al
                        where (al.created_at at time zone 'America/Mexico_City')::date = v_today))
  );
end;
$$;
