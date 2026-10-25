-- Permisos de las tablas: RLS en todas y sin TRUNCATE/TRIGGER/REFERENCES para la app.
do $$
declare
  v_bad text;
begin
  select string_agg(c.relname, ', ') into v_bad
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  assert v_bad is null, 'tablas sin RLS: ' || v_bad;

  select string_agg(distinct table_name || ' ' || grantee || ' ' || privilege_type, ', ') into v_bad
    from information_schema.role_table_grants
   where table_schema = 'public' and grantee in ('anon', 'authenticated')
     and privilege_type in ('TRUNCATE', 'TRIGGER', 'REFERENCES');
  assert v_bad is null, 'permisos de más: ' || v_bad;

  -- Lo que la app lee directamente sigue con permiso.
  assert has_table_privilege('authenticated', 'public.passes', 'select')
     and has_table_privilege('authenticated', 'public.students', 'select')
     and has_table_privilege('authenticated', 'public.bathroom_pauses', 'select')
     and has_table_privilege('authenticated', 'public.v_current_class', 'select'), 'lectura de la app';
  assert not has_table_privilege('anon', 'public.passes', 'select'), 'anon no lee pases';

  raise notice 'permisos de las tablas: ok';
end;
$$;
