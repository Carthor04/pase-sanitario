-- Listas de espera con alumno, grupo y clase para todo el personal.
-- bathrooms_status: el personal (con Google) ve nombre, número de lista, clase en la que
-- salió y quién autorizó; la computadora del salón —a la vista de los alumnos— sigue
-- viendo solo el nombre del grupo. Se agrega la lista de espera de enfermería.
create or replace function public.bathrooms_status() returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_staff boolean := private.current_staff_id() is not null;
begin
  if not private.is_member() then
    raise exception 'Sin acceso' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'now', clock_timestamp(),
    'names', v_staff,
    'bathrooms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'label', d.label, 'sex', d.sex, 'capacity', d.capacity,
        'occupants', coalesce((
          select jsonb_agg(private.waiting_item(p, v_staff, coalesce(p.started_at, p.called_at))
                   order by coalesce(p.started_at, p.called_at))
            from public.passes p
           where p.destination_id = d.id and p.status in ('called', 'out')), '[]'::jsonb),
        'queue', coalesce((
          select jsonb_agg(private.waiting_item(p, v_staff, p.queue_ts)
                   order by p.queue_ts, p.requested_at)
            from public.passes p
           where p.destination_id = d.id and p.status = 'queued'), '[]'::jsonb),
        'group_wait', (select count(*) from public.passes p
                        where p.destination_id = d.id and p.status = 'group_wait'),
        'group_wait_list', coalesce((
          select jsonb_agg(private.waiting_item(p, v_staff, p.requested_at) order by p.requested_at)
            from public.passes p
           where p.destination_id = d.id and p.status = 'group_wait'), '[]'::jsonb)
      ) order by d.sex)
        from public.destinations d where d.kind = 'bathroom'), '[]'::jsonb),
    -- Enfermería: en camino (lista de espera), en atención y de regreso.
    'nurse', (select count(*) from public.passes p join public.destinations d on d.id = p.destination_id
               where d.kind = 'nurse' and p.status in ('out', 'arrived')),
    'nurse_queue', coalesce((
      select jsonb_agg(private.waiting_item(p, v_staff, p.started_at) order by p.started_at)
        from public.passes p join public.destinations d on d.id = p.destination_id
       where d.kind = 'nurse' and p.status = 'out'), '[]'::jsonb),
    'nurse_care', coalesce((
      select jsonb_agg(private.waiting_item(p, v_staff, p.arrived_at) order by p.arrived_at)
        from public.passes p join public.destinations d on d.id = p.destination_id
       where d.kind = 'nurse' and p.status = 'arrived'), '[]'::jsonb),
    'nurse_returning', coalesce((
      select jsonb_agg(private.waiting_item(p, v_staff, p.left_nurse_at) order by p.left_nurse_at)
        from public.passes p join public.destinations d on d.id = p.destination_id
       where d.kind = 'nurse' and p.status = 'returning'), '[]'::jsonb));
end;
$$;

-- Un renglón de lista: siempre grupo, estado y desde cuándo; con nombres solo para personal.
create function private.waiting_item(p public.passes, p_names boolean, p_since timestamptz)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'group_name', (select name from public.groups where id = p.group_id),
    'status', p.status,
    'since', p_since)
  || case when p_names then jsonb_build_object(
       'full_name', st.full_name,
       'list_number', st.list_number,
       'subject', p.period_subject,
       'opened_by', (select full_name from public.staff where id = p.opened_by),
       'current_teacher', (select c.teacher_name from public.classes_at(now()) c
                            where c.group_id = p.group_id limit 1))
     else '{}'::jsonb end
    from public.students st where st.id = p.student_id;
$$;

revoke all on function private.waiting_item(public.passes, boolean, timestamptz) from public, anon, authenticated;

