-- EJEMPLO: datos ficticios para desarrollo y pruebas. NO son alumnos ni personal reales
-- (salvo la cuenta del desarrollador, para poder probar el login).
-- 9 grupos × 30 alumnos, horario de lunes a viernes (7 módulos + receso) y personal de prueba.
-- Es idempotente: si ya hay grupos, solo asegura la cuenta del desarrollador.

-- Personal de ejemplo (correos ficticios en colegio.edu.mx).
insert into public.staff (full_name, email, roles, whatsapp)
values
  ('Soporte técnico', 'carthorca@gmail.com', array['admin', 'coordinator', 'teacher'], null),
  ('Miguel Soto', 'miguel.soto@colegio.edu.mx', array['teacher'], null),
  ('Laura Ramírez', 'laura.ramirez@colegio.edu.mx', array['teacher'], null),
  ('Patricia Luna', 'patricia.luna@colegio.edu.mx', array['teacher'], null),
  ('Jorge Villalobos', 'jorge.villalobos@colegio.edu.mx', array['teacher'], null),
  ('Sofía Cárdenas', 'sofia.cardenas@colegio.edu.mx', array['teacher'], null),
  ('Ricardo Méndez', 'ricardo.mendez@colegio.edu.mx', array['teacher'], null),
  ('Mónica Aguilar', 'monica.aguilar@colegio.edu.mx', array['teacher'], null),
  ('Héctor Navarro', 'hector.navarro@colegio.edu.mx', array['teacher'], null),
  ('Juan Pérez', 'juan.perez@colegio.edu.mx', array['prefect'], '4770000000'),
  ('Rosa Elena Campos', 'rosa.campos@colegio.edu.mx', array['nurse'], null),
  ('Claudia Herrera', 'claudia.herrera@colegio.edu.mx', array['coordinator', 'teacher'], '4770000001'),
  ('Arturo Medina', 'arturo.medina@colegio.edu.mx', array['director'], '4770000002')
on conflict ((lower(email))) do update set roles = excluded.roles, active = true
  where public.staff.email = 'carthorca@gmail.com';

do $$
declare
  v_first_h text[] := array['Luis', 'Diego', 'Bruno', 'Fernando', 'Hugo', 'Javier', 'Pedro',
    'Mateo', 'Santiago', 'Emiliano', 'Sebastián', 'Leonardo', 'Iker', 'Rodrigo', 'Adrián'];
  v_first_m text[] := array['Ana', 'Carla', 'Elena', 'Gabriela', 'Isabel', 'Karla', 'Lucía',
    'Natalia', 'Valeria', 'Ximena', 'Regina', 'Camila', 'Renata', 'Paula', 'Fernanda'];
  v_last text[] := array['Torres', 'Cázares', 'Domínguez', 'Esparza', 'Fuentes', 'García',
    'Gómez', 'Hernández', 'Ibarra', 'Juárez', 'López', 'Medina', 'Navarro', 'Martínez',
    'Quiroz', 'Ruiz', 'Salinas', 'Vela', 'León', 'Zamora', 'Ortiz', 'Rangel', 'Pacheco'];
  -- Una materia por maestro; carthorca@gmail.com da Matemáticas para tener clase a toda hora.
  v_teachers text[] := array['carthorca@gmail.com', 'miguel.soto@colegio.edu.mx',
    'laura.ramirez@colegio.edu.mx', 'patricia.luna@colegio.edu.mx',
    'jorge.villalobos@colegio.edu.mx', 'sofia.cardenas@colegio.edu.mx',
    'ricardo.mendez@colegio.edu.mx', 'monica.aguilar@colegio.edu.mx',
    'claudia.herrera@colegio.edu.mx'];
  v_subjects text[] := array['Matemáticas', 'Español', 'Ciencias', 'Historia', 'Geografía',
    'Inglés', 'Formación Cívica', 'Artes', 'Tecnología'];
  v_modules time[][] := array[
    array['07:30', '08:20'], array['08:20', '09:10'], array['09:10', '10:00'],
    array['10:00', '10:50'], -- receso 10:50–11:20
    array['11:20', '12:10'], array['12:10', '13:00'], array['13:00', '13:50']]::time[][];
  g int;
  n int;
  d int;
  m int;
  t int;
  v_group uuid;
  v_sex text;
  v_period uuid;
  v_teacher uuid;
begin
  if exists (select 1 from public.groups) then
    return;
  end if;

  for g in 0..8 loop
    insert into public.groups (name, room, sort)
    values (format('%s°%s', g / 3 + 1, chr(65 + g % 3)), format('Salón %s', g + 1), g + 1)
    returning id into v_group;

    for n in 1..30 loop
      v_sex := case when (n + g) % 2 = 0 then 'M' else 'H' end;
      insert into public.students (group_id, list_number, full_name, sex)
      values (
        v_group, n,
        format('%s %s %s',
          case when v_sex = 'H' then v_first_h[1 + (n * 7 + g * 3) % 15]
               else v_first_m[1 + (n * 5 + g * 2) % 15] end,
          v_last[1 + (n * 3 + g) % 23],
          v_last[1 + (n * 11 + g * 5) % 23]),
        v_sex);
    end loop;
  end loop;

  for d in 1..5 loop
    for m in 1..7 loop
      insert into public.periods (weekday, starts, ends)
      values (d, v_modules[m][1], v_modules[m][2])
      returning id into v_period;

      -- (g + m + d) mod 9 es una permutación por módulo: ningún maestro está en dos grupos a la vez.
      for g in 0..8 loop
        t := 1 + (g + m + d) % 9;
        select id into v_teacher from public.staff where email = v_teachers[t];
        insert into public.schedule_entries (group_id, period_id, subject, teacher_id)
        select id, v_period, v_subjects[t], v_teacher
          from public.groups where sort = g + 1;
      end loop;
    end loop;
  end loop;
end;
$$;
