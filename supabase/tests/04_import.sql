-- Importación de CSV: validación por fila (todo o nada) y reemplazo sin borrar alumnos.
do $$
declare
  c uuid := '00000000-0000-4000-d000-000000000001';
  t uuid := '00000000-0000-4000-d000-000000000002';
  v jsonb;
  g uuid;
  n int;
begin
  perform pg_temp.make_staff(c, 'imp.c@test.mx', array['coordinator']);
  perform pg_temp.make_staff(t, 'imp.t@test.mx', array['teacher']);

  -- Solo coordinación/dirección/admin importan.
  perform pg_temp.login(t);
  begin
    perform public.import_groups('[{"grupo":"Z1"}]');
    raise exception 'maestro no debe importar' using errcode = 'TF001';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.logout();

  perform pg_temp.login(c);

  -- Grupos
  v := public.import_groups('[{"_row":2,"grupo":"Z1","salon":"Salón Z","orden":"x"},{"_row":3,"grupo":" z1 "}]');
  assert not (v ->> 'ok')::boolean, v::text;
  assert v -> 'errors' @> '[{"row":2,"message":"El orden debe ser un número"}]', v::text;
  assert v -> 'errors' @> '[{"row":3,"message":"El grupo z1 está repetido"}]', v::text;
  assert not exists (select 1 from public.groups where name = 'Z1'), 'con errores no aplica nada';
  v := public.import_groups('[{"_row":2,"grupo":"Z1","salon":"Salón Z","orden":"950"},{"_row":3,"grupo":"Z2","orden":"951"}]');
  assert v = '{"ok":true,"summary":{"inserted":2,"updated":0}}', v::text;
  v := public.import_groups('[{"_row":2,"grupo":"z1","salon":"Salón 99","orden":"950"}]');
  assert v -> 'summary' ->> 'updated' = '1', v::text;
  select id into g from public.groups where name = 'z1';
  assert (select room from public.groups where id = g) = 'Salón 99', 'actualiza salón';

  -- Personal
  v := public.import_staff('[{"_row":2,"nombre_completo":"Ana","correo":"ana@","roles":"teacher"},
                             {"_row":3,"nombre_completo":"Beto","correo":"beto@test.mx","roles":"maestro"},
                             {"_row":4,"nombre_completo":"","correo":"c@test.mx","roles":""},
                             {"_row":5,"nombre_completo":"Dora","correo":"d@test.mx","roles":"nurse","whatsapp":"12"}]');
  assert not (v ->> 'ok')::boolean, v::text;
  assert v -> 'errors' @> '[{"row":2,"message":"Correo no válido: ana@"}]', v::text;
  assert v -> 'errors' @> '[{"row":3,"message":"Rol desconocido: maestro"}]', v::text;
  assert v -> 'errors' @> '[{"row":4,"message":"Falta el nombre"}]', v::text;
  assert v -> 'errors' @> '[{"row":5,"message":"WhatsApp debe tener 10 a 13 dígitos"}]', v::text;
  v := public.import_staff('[{"_row":2,"nombre_completo":"Eva Prueba","correo":"EVA@test.mx","roles":"coordinator; teacher","whatsapp":"477 000 0009"},
                             {"_row":3,"nombre_completo":"Imp T","correo":"imp.t@test.mx","roles":"teacher;prefect"}]');
  assert v = '{"ok":true,"summary":{"inserted":1,"updated":1}}', v::text;
  assert (select roles from public.staff where email = 'eva@test.mx') @> array['coordinator', 'teacher'], 'roles';
  assert (select whatsapp from public.staff where email = 'eva@test.mx') = '4770000009', 'whatsapp limpio';
  assert (select roles @> array['prefect', 'teacher'] and cardinality(roles) = 2 from public.staff where id = t), 'actualiza roles';

  -- Alumnos
  v := public.import_students(format('[
      {"_row":2,"grupo":"NoExiste","numero_lista":"1","nombre_completo":"A","sexo":"H"},
      {"_row":3,"grupo":"Z1","numero_lista":"0","nombre_completo":"B","sexo":"H"},
      {"_row":4,"grupo":"Z1","numero_lista":"2","nombre_completo":"C","sexo":"X"},
      {"_row":5,"grupo":"Z1","numero_lista":"3","nombre_completo":"D","sexo":"m"},
      {"_row":6,"grupo":"Z1","numero_lista":"03","nombre_completo":"E","sexo":"H"}]')::jsonb);
  assert not (v ->> 'ok')::boolean, v::text;
  assert jsonb_array_length(v -> 'errors') = 4, v::text;
  assert v -> 'errors' @> '[{"row":2}]' and v -> 'errors' @> '[{"row":3}]'
     and v -> 'errors' @> '[{"row":4}]' and v -> 'errors' @> '[{"row":6}]', v::text;
  assert not exists (select 1 from public.students where group_id = g), 'con errores no aplica nada';

  v := public.import_students('[
      {"_row":2,"grupo":"Z1","numero_lista":"1","nombre_completo":"Ana Torres","sexo":"M"},
      {"_row":3,"grupo":"Z1","numero_lista":"2","nombre_completo":"Bruno Cázares","sexo":"H"},
      {"_row":4,"grupo":"Z1","numero_lista":"3","nombre_completo":"Carla Vela","sexo":"m"}]');
  assert v -> 'summary' = '{"inserted":3,"updated":0,"deactivated":0,"groups":1}', v::text;

  -- Re-importar: #1 igual (acentos/mayúsculas no cuentan), #2 cambia de alumno, #3 ya no viene.
  v := public.import_students('[
      {"_row":2,"grupo":"Z1","numero_lista":"1","nombre_completo":"ANA  TÓRRES","sexo":"M"},
      {"_row":3,"grupo":"Z1","numero_lista":"2","nombre_completo":"Diego Esparza","sexo":"H"}]');
  assert v -> 'summary' = '{"inserted":1,"updated":1,"deactivated":2,"groups":1}', v::text;
  select count(*) into n from public.students where group_id = g;
  assert n = 4, 'nada se borra';
  select count(*) into n from public.students where group_id = g and active;
  assert n = 2, 'quedan 2 activos';
  assert (select full_name from public.students where group_id = g and list_number = 2 and active) = 'Diego Esparza', '#2 nuevo';

  -- Horario
  v := public.import_schedule('[
      {"_row":2,"grupo":"Z1","dia":"lunes","inicio":"07:30","fin":"08:20","materia":"Español","correo_maestro":"imp.t@test.mx"},
      {"_row":3,"grupo":"Z1","dia":"lunes","inicio":"08:00","fin":"08:50","materia":"Mate","correo_maestro":""},
      {"_row":4,"grupo":"Z1","dia":"sábado","inicio":"07:30","fin":"08:20","materia":"Arte"},
      {"_row":5,"grupo":"Z1","dia":"martes","inicio":"9:10","fin":"09:00","materia":"Arte"},
      {"_row":6,"grupo":"Z1","dia":"martes","inicio":"07:30","fin":"08:20","materia":"Arte","correo_maestro":"nadie@test.mx"},
      {"_row":7,"grupo":"Z1","dia":"martes","inicio":"7.30","fin":"08:20","materia":""}]');
  assert not (v ->> 'ok')::boolean, v::text;
  assert v -> 'errors' @> '[{"row":3,"message":"Se empalma con otra clase de Z1 el mismo día"}]', v::text;
  assert v -> 'errors' @> '[{"row":4,"message":"Día no válido: sábado (usa lunes a viernes)"}]', v::text;
  assert v -> 'errors' @> '[{"row":5,"message":"La hora de fin debe ser después del inicio"}]', v::text;
  assert v -> 'errors' @> '[{"row":6,"message":"No hay personal activo con el correo nadie@test.mx (impórtalo en Personal)"}]', v::text;
  assert v -> 'errors' @> '[{"row":7,"message":"Las horas deben ir como HH:MM (07:30)"}]', v::text;
  assert v -> 'errors' @> '[{"row":7,"message":"Falta la materia"}]', v::text;

  v := public.import_schedule('[
      {"_row":2,"grupo":"Z1","dia":"Miércoles","inicio":"07:30","fin":"08:20","materia":"Español","correo_maestro":"IMP.T@test.mx"},
      {"_row":3,"grupo":"Z1","dia":"miercoles","inicio":"08:20","fin":"09:10","materia":"Mate"},
      {"_row":4,"grupo":"Z2","dia":"jueves","inicio":"7:30","fin":"8:20","materia":"Arte"}]');
  assert v -> 'summary' = '{"inserted":3,"replaced":0,"groups":2}', v::text;
  -- Reemplaza el horario de Z1 sin tocar el de Z2.
  v := public.import_schedule('[{"_row":2,"grupo":"Z1","dia":"viernes","inicio":"07:30","fin":"08:20","materia":"Historia"}]');
  assert v -> 'summary' = '{"inserted":1,"replaced":2,"groups":1}', v::text;
  select count(*) into n from public.schedule_entries se join public.groups gg on gg.id = se.group_id
   where gg.name in ('z1', 'Z2');
  assert n = 2, format('quedan %s clases', n);
  assert (select teacher_id from public.schedule_entries where group_id = g) is null, 'maestro opcional';

  perform pg_temp.logout();
  raise notice 'importación de grupos, personal, alumnos y horario: ok';
end;
$$;
