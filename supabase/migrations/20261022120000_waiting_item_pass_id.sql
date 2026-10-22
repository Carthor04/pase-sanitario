-- "Quitar de la fila" desde Baños y En vivo: cualquier maestro cancela (cancel_pass) un pase
-- que todavía no sale, de cualquier grupo. Para eso las listas de bathrooms_status traen el
-- id del pase, solo para el personal; la computadora del salón sigue sin ids ni nombres.
create or replace function private.waiting_item(p public.passes, p_names boolean, p_since timestamptz)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'group_name', (select name from public.groups where id = p.group_id),
    'status', p.status,
    'since', p_since)
  || case when p_names then jsonb_build_object(
       'id', p.id,
       'full_name', st.full_name,
       'list_number', st.list_number,
       'subject', p.period_subject,
       'opened_by', (select full_name from public.staff where id = p.opened_by),
       'current_teacher', (select r.teacher_name from private.student_room_at(p.student_id, now()) r))
     else '{}'::jsonb end
    from public.students st where st.id = p.student_id;
$$;
revoke all on function private.waiting_item(public.passes, boolean, timestamptz) from public, anon, authenticated;
