# Modelo de datos (Supabase / Postgres)

Esquema de referencia. Se puede ajustar si se encuentra un problema; cada cambio se explica en este documento.

## Tablas

```sql
-- Personal
create table staff (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id),
  full_name text not null,
  email text unique not null,          -- correo institucional
  roles text[] not null,               -- teacher, prefect, nurse, coordinator, director, admin
  pin_hash text,                       -- crypt(pin, gen_salt('bf')); solo maestros/prefectura
  whatsapp text,                       -- opcional
  active boolean default true
);

create table groups (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,           -- '2°B'
  room text,                           -- 'Salón 12'
  sort int
);

create table students (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id),
  list_number int not null,
  full_name text not null,
  sex char(1) not null check (sex in ('H','M')),
  rfid_tag text unique,                -- futuro
  active boolean default true,
  unique (group_id, list_number)
);

-- Horario
create table periods (                 -- módulos del día
  id uuid primary key default gen_random_uuid(),
  weekday int not null check (weekday between 1 and 5),
  starts time not null,
  ends time not null
);
create table schedule_entries (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id),
  period_id uuid not null references periods(id),
  subject text not null,
  teacher_id uuid references staff(id),
  unique (group_id, period_id)
);

-- Lugares
create table destinations (
  id text primary key,                 -- 'bath_h', 'bath_m', 'nurse'
  label text not null,
  kind text not null check (kind in ('bathroom','nurse')),
  sex char(1),                         -- 'H' / 'M' / null
  capacity int,                        -- null = sin límite
  per_group_limit int,                 -- 1; null = sin límite
  uses_group_slot boolean default true,-- false en enfermería
  queue_enabled boolean default true
);

create table settings (                -- una sola fila
  id int primary key default 1 check (id = 1),
  alert_minutes int default 10,
  escalate_minutes int default 5,
  confirm_turn_minutes int default 2,
  auto_lock_after_class_minutes int default 5,
  undo_seconds int default 10,
  review_alerts_threshold int default 2,
  review_exits_threshold int default 8,
  sheets_spreadsheet_id text,
  sheets_daily_export_time time default '15:00'
);

-- Equipos de salón
create table devices (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id),
  label text,
  auth_user_id uuid unique references auth.users(id), -- usuario técnico del equipo
  last_seen_at timestamptz
);
create table device_unlocks (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references devices(id),
  staff_id uuid not null references staff(id),
  unlocked_at timestamptz default now(),
  expires_at timestamptz not null,     -- fin de la clase + auto_lock_after_class_minutes
  locked_at timestamptz,               -- bloqueo manual
  lock_reason text                     -- 'manual' | 'auto' | 'pin_change'
);

-- Pases
create type pass_status as enum
  ('group_wait','queued','called','out','arrived','returned','released','cancelled');

create table passes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id),
  group_id uuid not null references groups(id),
  destination_id text not null references destinations(id),
  status pass_status not null,
  requested_at timestamptz default now(),
  queue_ts timestamptz,                -- orden en la fila
  called_at timestamptz,
  started_at timestamptz,              -- salió del salón
  arrived_at timestamptz,              -- enfermería
  ended_at timestamptz,
  opened_by uuid references staff(id),
  closed_by uuid references staff(id),
  device_id uuid references devices(id),
  source text default 'manual',        -- 'manual' | 'rfid'
  period_subject text,                 -- materia al salir (para "salió en Matemáticas")
  release_reason text
);
create unique index one_active_pass_per_student on passes(student_id)
  where status in ('group_wait','queued','called','out','arrived');

create table pass_events (             -- bitácora inmutable
  id bigserial primary key,
  pass_id uuid not null references passes(id),
  type text not null,                  -- requested, queued, called, confirmed, ceded, turn_expired,
                                       -- returned, released, cancelled, arrived, undo, alert, escalated
  actor_id uuid references staff(id),
  device_id uuid references devices(id),
  at timestamptz default now(),
  payload jsonb
);

-- Alertas y notificaciones
create table alerts (
  id uuid primary key default gen_random_uuid(),
  pass_id uuid not null references passes(id),
  level int default 1,                 -- 1 = 10 min, 2 = escalada
  created_at timestamptz default now(),
  acknowledged_by uuid references staff(id),
  acknowledged_at timestamptz,
  resolved_at timestamptz
);
create table notification_rules (
  role text not null,                  -- 'current_teacher','authorizing_teacher','prefect','coordinator','director'
  channel text not null,               -- 'app','push','whatsapp'
  enabled boolean default true,
  primary key (role, channel)
);
create table notifications_outbox (
  id bigserial primary key,
  channel text not null,               -- 'push' | 'whatsapp'
  recipient_staff_id uuid,             -- null para el grupo de WhatsApp
  body text not null,
  payload jsonb,
  created_at timestamptz default now(),
  sent_at timestamptz,
  error text
);
create table push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid references staff(id),
  endpoint text unique, p256dh text, auth text,
  created_at timestamptz default now()
);
```

## Funciones RPC (todas `security definer`, validan rol y unlock vigente)

| Función | Qué hace |
|---|---|
| `unlock_device(pin text)` | Llamada por el usuario del equipo. Verifica PIN contra `staff.pin_hash`, limita intentos, crea `device_unlocks` con `expires_at` = fin de la clase actual + minutos de autobloqueo. |
| `lock_device()` | Cierra el unlock vigente (`locked_at`, `lock_reason='manual'`). |
| `current_actor()` | Devuelve el `staff_id` que actúa: el maestro logueado (celular) o el del unlock vigente (equipo de salón). Error si el equipo está bloqueado. |
| `request_pass(student_id uuid, kind text)` | `kind` = `'bathroom'` o `'nurse'`. Aplica las reglas de SPEC §4 con `select … for update` sobre la fila de `destinations`. Devuelve el pase con su estado final. |
| `confirm_turn(pass_id)` | `called` → `out`. |
| `cede_turn(pass_id)` | `called` → `queued` en segundo lugar; `advance`. |
| `mark_returned(pass_id)` | `out`/`arrived` → `returned`; resuelve alerta; `advance`. |
| `mark_arrived(pass_id)` | Enfermería: `out` → `arrived` (rol nurse). |
| `release_pass(pass_id, reason text)` | Prefectura/coordinación: cierra como `released`; `advance`. |
| `cancel_pass(pass_id)` | Antes de `out`. |
| `undo_last(pass_id)` | Revierte la última transición si fue hace ≤ `undo_seconds`. |
| `acknowledge_alert(alert_id)` | "Yo lo atiendo". |
| `advance(destination_id)` | Interna. Promueve `group_wait` y llama al siguiente de la fila. |
| `tick()` | La corre **pg_cron cada minuto**: vence turnos `called`, crea alertas de 10 min, escala alertas sin atender, autobloquea equipos, encola notificaciones. |

## Vistas útiles
- `v_live_board`: pases activos con alumno, grupo, destino, minutos fuera, materia de salida y maestro a cargo ahora.
- `v_current_class(group_id)`: materia y maestro según hora actual de México.
- `v_report_*`: agregados para reportes (por hora/día, por grupo, a revisar).

## RLS (resumen)
- Todo requiere usuario autenticado que exista en `staff` activo o en `devices`.
- Escrituras en `passes`, `pass_events`, `alerts` **solo vía RPC** (sin políticas de insert/update directas).
- `teacher`: lee alumnos y pases de todos los grupos (necesita ver baños y filas), escribe solo vía RPC.
- `coordinator`/`director`/`admin`: lectura completa + escritura en catálogos y `settings`.
- `devices`: lectura de su grupo, de `v_live_board` y de catálogos; acciones vía RPC con unlock vigente.

## Realtime
Publicar cambios de `passes` y `alerts`. El cliente refresca `v_live_board` con TanStack Query al recibir eventos. Cronómetros se calculan en el cliente desde `started_at` (no polling por segundo).

## Ajustes hechos en la Fase 1 (2026-10-15)

Implementado en `supabase/migrations/20261015120000_base_schema.sql` y siguientes. Diferencias con el esquema de arriba:

- **PIN fuera de `staff`:** el hash vive en `staff_pins(staff_id, pin_hash, updated_at)` sin ningún GRANT; `staff.pin_set_at` dice si la persona tiene PIN. Así un `select` sobre `staff` nunca expone hashes. El PIN es único entre el personal activo (`set_my_pin` / `set_staff_pin` comparan con `crypt()` contra todos, bajo un advisory lock) y al dar de baja a alguien se borra su PIN.
- **`students`:** `(group_id, list_number)` es único solo entre activos (índice parcial). El importador da de baja (no borra) a quien ya no viene en el CSV y reutiliza el número.
- **Equipos:** `devices.revoked_at`, `devices.created_by`; tabla `device_pairings` (código de 6 dígitos, vence en `settings.pairing_code_minutes`, un solo uso). La computadora del salón entra como **usuario anónimo** de Supabase Auth y reclama el código con `claim_device_pairing`.
- **`security_attempts`:** bitácora de intentos (`set_pin`, `pair_device`, `unlock`) para limitar abusos. Las RPC que pueden rechazar por regla devuelven `{ok:false, error}` en vez de lanzar excepción, para que el intento quede guardado.
- **`settings`:** más columnas `pin_max_attempts` (5), `pin_lockout_seconds` (60), `pairing_code_minutes` (15).
- **Schema `private`:** ayudantes de RLS (`current_staff_id`, `has_any_role`, `can_manage`, `current_device_id`, …) fuera de la API.
- **Auth:** trigger `before insert on auth.users` que rechaza correos que no son de personal activo (los anónimos pasan, pero no ven nada hasta vincularse) y otro `after insert` que llena `staff.auth_user_id`.
- **RPC de la Fase 1:** `me()`, `set_my_pin`, `set_staff_pin`, `clear_staff_pin`, `create_device_pairing`, `claim_device_pairing`, `revoke_device`, `classes_at(ts)`, `my_groups(ts)`, `import_groups`, `import_staff`, `import_students`, `import_schedule`. Vista `v_current_class` (security invoker).
- **Pruebas SQL:** `supabase/tests/*.sql`, se corren con `npm run test:db` contra la BD vinculada, cada archivo en una transacción que se revierte.

## Ajustes hechos en la Fase 2 (2026-10-15)

Implementado en `supabase/migrations/20261015130000_pass_engine.sql`:

- `passes`, `pass_events` y el enum `pass_status` como arriba. `pass_events.type` tiene CHECK con la lista de tipos, más `promoted` (sale de `group_wait`). Los tiempos usan `clock_timestamp()` para que el FIFO sea exacto.
- **Candado:** toda operación sobre un baño hace `select … for update` en su fila de `destinations` y después en el pase. Así `request_pass` simultáneos quedan en serie (probado con dos conexiones en `scripts/db-test-concurrency.mjs`).
- **Actor:** `private.current_actor()` devuelve `(staff_id, roles, device_id, device_group_id)`; en el equipo de salón usa el `device_unlocks` vigente y falla con "Equipo bloqueado" si no hay. Un equipo solo opera pases de su grupo. `public.current_actor()` lo expone como JSON.
- **Permisos por rol:** abrir/confirmar/ceder/cancelar: teacher, coordinator, admin. Marcar regreso: además prefect, y nurse solo en enfermería. Llegó: nurse (y coordinator/admin). Liberar: prefect, coordinator, admin, con motivo obligatorio. Deshacer: solo quien hizo el cambio.
- **Decisiones del 2026-10-15** (SPEC §4/§7): `group_wait` entra al final de la fila; ceder sin nadie más formado da error ("Nadie más en fila") y un turno vencido sin nadie más sigue llamado; deshacer "regresó" deshace solo el regreso aunque el baño quede arriba de su capacidad.
- **Desbloqueo:** `unlock_device(pin)` devuelve `{ok:false, error:'wrong_pin'|'locked'}`. Cada `pin_max_attempts` fallos seguidos bloquean `pin_lockout_seconds`. El desbloqueo vence al terminar la clase actual + `auto_lock_after_class_minutes`, o en `unlock_without_class_minutes` (nuevo en `settings`, 15) si no hay clase. Un desbloqueo nuevo cierra el anterior (`lock_reason = 'replaced'`).
- **`private.tick()`** con pg_cron (`pase-tick`, cada 30 s desde `20261015170000`): vence turnos `called` después de `confirm_turn_minutes` y registra autobloqueos. Las alertas de 10 min llegan en la Fase 4.
- `passes` está en la publicación `supabase_realtime`. `pass_events` solo la lee el personal; los equipos no.

## Ajustes hechos en la Fase 3 (2026-10-15)

- En lugar de `v_live_board` hay dos RPC de lectura (`20261015140000_board.sql`):
  - `group_board(group_id)`: pases activos del grupo con nombre, número, estado, posición en fila y a quién espera (`waiting_for`), más el estado de cada baño (ocupantes y fila **solo con el nombre del grupo**) y los valores de `settings` que usa la pantalla. La puede llamar el personal (cualquier grupo) o la computadora del salón (solo su grupo, aunque esté bloqueada). Así una compu nunca recibe nombres de alumnos de otros grupos.
  - `device_session()`: si la compu está desbloqueada, por quién y hasta cuándo, y quién la bloqueó la última vez.
- El cliente se suscribe con Realtime a `passes` y vuelve a pedir `group_board` en cada cambio (y cada 30 s como respaldo). Los cronómetros se calculan en el cliente con la hora del servidor (`now`) para corregir relojes desfasados.

## Ajustes hechos en la Fase 4 (2026-10-15)

`supabase/migrations/20261015150000_alerts.sql`:

- `alerts` como arriba, más `escalated_at` y `resolution` (`returned` | `released` | `arrived`); una alerta por pase. Se resuelve sola con un trigger en `passes` cuando el pase regresa, se libera o llega a enfermería, y se reabre si se deshace el regreso.
- `nurse_notes(pass_id, author_id, body, created_at)`: notas internas de enfermería (solo se agregan). Las leen enfermería, coordinación, dirección y admin; los maestros no.
- `private.tick()` ahora también crea alertas (`alert_minutes` en `out`; en enfermería solo el trayecto) y las escala a nivel 2 si nadie las atiende en `escalate_minutes`. Cada una deja evento `alert` / `escalated` en la bitácora.
- RPC: `acknowledge_alert` ("Yo lo atiendo": prefectura, coordinación, admin), `add_nurse_note`, `live_board()` (monitor en vivo para prefectura, enfermería, coordinación, dirección), `my_alerts()` (alertas del maestro a cargo ahora o del que autorizó) y `nurse_today()`. `group_board` incluye la alerta de cada pase.
- `alerts` está en la publicación `supabase_realtime`.
- Las notificaciones push y por WhatsApp (destinatarios configurables por canal) son de la Fase 5; en esta fase las alertas se ven en la app.

## Ajustes hechos en la Fase 5 (2026-10-15)

- `notification_rules`, `notifications_outbox` y `push_subscriptions` como arriba. El outbox suma `kind`, `pass_id`, `claimed_at` y `attempts`; las suscripciones, `user_agent`, `last_success_at` y `last_error`.
- `settings.vapid_public_key` y `settings.whatsapp_enabled` (apagado: no se encolan mensajes de WhatsApp hasta tener el bot).
- La regla "En la app" de `current_teacher` / `authorizing_teacher` filtra `my_alerts()`.
- Detalle del envío en `docs/INTEGRATIONS.md` §1.

## Ajustes hechos en la Fase 6 (2026-10-15)

`20261015180000_reports.sql`:

- Trigger en `destinations`: al cambiar capacidad, límite por grupo o fila, corre `advance()` en ese momento (subir la capacidad llama al siguiente formado).
- Rangos válidos en `settings` (alerta 1–120 min, escalada 1–60, turno 1–15, autobloqueo 0–60, deshacer 3–60 s).
- RPC de lectura en lugar de vistas `v_report_*`: `report_summary(desde, hasta)` (coordinación, dirección, admin: totales, alertas, fila máxima, mapa de calor por baño, por grupo y "a revisar" con los umbrales de `settings`), `pass_history(desde, hasta, búsqueda, grupo)` (prefectura, enfermería —solo pases de enfermería—, coordinación, dirección, admin), `pass_timeline(pase)` (bitácora con quién y desde dónde), `bathrooms_status()` (cualquier personal; solo nombres de grupo) y `group_schedule(grupo)`.
- Pendiente: `export-sheets` (necesita la cuenta de servicio de Google; ver INTEGRATIONS §3).

## Regreso de enfermería (2026-10-16)

`20261016120000_returning_status.sql` y `20261016120100_returning_flow.sql`: nuevo estado `returning` en `pass_status` y columna `passes.left_nurse_at`. `nurse_send_back(pase)` (enfermería) pasa `arrived` → `returning`, deja evento `sent_back` y encola un aviso push `returning` al maestro a cargo y al que autorizó (según `notification_rules`). El maestro cierra con `mark_returned`. `tick()` alerta también el regreso; `alerts` ahora permite una alerta abierta por pase (índice parcial), no una sola en toda su historia. `undo_last` deshace `sent_back`.

## Detalle de reportes y horarios por docente (2026-10-16)

- `report_detail(p_from, p_to, p_destination?, p_weekday?, p_hour?, p_group?, p_alerts_only?)`: los pases que salieron en el periodo con alumno, grupo, clase, destino, minutos y si tuvieron alerta. Lo usa Reportes al tocar un cuadro, una celda del mapa de calor o un grupo. Solo coordinación, dirección y admin. Máximo 1000 renglones.
- `teacher_schedule(p_staff_id)`: horario semanal de un docente y su clase actual (`classes_at(now())`). Cualquier personal.
- `current_classes()`: la clase actual de cada grupo (o null). Cualquier personal.

## Cierre automático (2026-10-16)

- `passes.auto_closed boolean`: el sistema liberó el pase al final del día (`release_reason = 'Cierre automático'`, evento `released` con `actor_id` null y `payload.auto = true`).
- `private.auto_close_passes(p_at default clock_timestamp())`: lo llama `tick()` cada 30 s. Cierra los pases abiertos de días anteriores y, después de `max(periods.ends)` del día, los de hoy pedidos antes de esa hora. `p_at` solo se usa en las pruebas.
- `report_summary`, `report_detail`, `pass_history` y `student_today_passes` no calculan minutos para los pases con `auto_closed`.
