-- Clase actual según horario (hora de México) y orden del selector de grupos del celular.
do $$
declare
  me_ uuid := '00000000-0000-4000-e000-000000000001';
  other uuid := '00000000-0000-4000-e000-000000000002';
  g_now uuid;
  g_taught uuid;
  g_rest uuid;
  p_thu1 uuid;
  p_thu2 uuid;
  v record;
  -- Jueves 15 de octubre de 2026, 08:30 en León (UTC-6, sin horario de verano).
  at_ timestamptz := '2026-10-15 08:30:00-06';
  ranks text;
begin
  perform pg_temp.make_staff(me_, 'clase.yo@test.mx', array['teacher']);
  perform pg_temp.make_staff(other, 'clase.otro@test.mx', array['teacher']);

  -- Grupos con orden alto para no chocar con el seed; los de prueba se filtran por nombre.
  insert into public.groups (name, sort) values ('C-rest', 1) returning id into g_rest;
  insert into public.groups (name, sort) values ('C-taught', 2) returning id into g_taught;
  insert into public.groups (name, sort) values ('C-now', 3) returning id into g_now;

  insert into public.periods (weekday, starts, ends) values (4, '08:20', '09:05') returning id into p_thu1;
  insert into public.periods (weekday, starts, ends) values (4, '09:05', '09:55') returning id into p_thu2;

  insert into public.schedule_entries (group_id, period_id, subject, teacher_id) values
    (g_now, p_thu1, 'Matemáticas', me_),
    (g_taught, p_thu1, 'Español', other),
    (g_taught, p_thu2, 'Matemáticas', me_),
    (g_rest, p_thu1, 'Historia', other);

  -- classes_at: incluye el inicio, excluye el fin; nada en fin de semana.
  select * into v from public.classes_at(at_) c where c.group_id = g_now;
  assert v.subject = 'Matemáticas' and v.teacher_id = me_ and v.starts = '08:20', 'clase de las 08:30';
  assert exists (select 1 from public.classes_at('2026-10-15 08:20:00-06') where group_id = g_now), 'inicio incluido';
  select * into v from public.classes_at('2026-10-15 09:05:00-06') c where c.group_id = g_now;
  assert v is null, 'fin excluido';
  assert (select subject from public.classes_at('2026-10-15 09:05:00-06') where group_id = g_taught) = 'Matemáticas',
    'siguiente módulo';
  assert not exists (select 1 from public.classes_at('2026-10-17 08:30:00-06') where group_id = g_now), 'sábado';
  -- 14:30 UTC = 08:30 en México: la zona horaria se aplica en la BD, no en el cliente.
  assert exists (select 1 from public.classes_at('2026-10-15 14:30:00+00') where group_id = g_now), 'zona horaria';

  -- my_groups: primero el de la hora actual, luego los que imparte, luego el resto.
  perform pg_temp.login(me_);
  select string_agg(name || ':' || rank, ',' order by ord) into ranks
    from (select m.*, row_number() over () as ord from public.my_groups(at_) m) x
   where name like 'C-%';
  assert ranks = 'C-now:0,C-taught:1,C-rest:2', ranks;
  select * into v from public.my_groups(at_) m where m.group_id = g_now;
  assert v.subject = 'Matemáticas' and v.teacher_name = 'Prueba clase.yo@test.mx', 'materia y maestro';
  -- La vista v_current_class existe y respeta RLS.
  perform 1 from public.v_current_class;
  perform pg_temp.logout();

  -- Sin clase en este momento: lo que imparte sigue antes que el resto.
  perform pg_temp.login(me_);
  select string_agg(name || ':' || rank, ',' order by ord) into ranks
    from (select m.*, row_number() over () as ord from public.my_groups('2026-10-15 07:00:00-06') m) x
   where name like 'C-%';
  assert ranks = 'C-taught:1,C-now:1,C-rest:2', ranks;
  perform pg_temp.logout();

  raise notice 'clase actual y orden del selector de grupos: ok';
end;
$$;
