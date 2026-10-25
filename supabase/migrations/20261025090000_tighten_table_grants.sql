-- Permisos explícitos (Supabase deja de dar permisos por omisión a las tablas nuevas desde
-- el 2026-10-30). Las tablas ya tienen sus grant de lectura/escritura escritos en las
-- migraciones; aquí se quitan los que venían por omisión y nadie usa: TRUNCATE (se salta RLS),
-- TRIGGER y REFERENCES, para anon y authenticated, en las tablas actuales y las futuras.
revoke truncate, trigger, references on all tables in schema public from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke truncate, trigger, references on tables from anon, authenticated;
