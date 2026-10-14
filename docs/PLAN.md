# Plan de trabajo

Trabaja **una fase a la vez**. Al terminar cada fase: lint, typecheck, pruebas en verde, y un resumen de lo hecho y lo pendiente. No avances de fase sin confirmación.

---

## Fase 0 · Arranque (½ día)
- [ ] Proyecto Vite + React + TS + Tailwind + Router + TanStack Query + vite-plugin-pwa.
- [ ] Supabase local (`supabase init`), cliente tipado, variables `.env.example`.
- [ ] Tokens de `DESIGN.md` en `tailwind.config` + fuentes.
- [ ] Layout base responsive con `BottomNav` (celular) y encabezado (escritorio).
- [ ] ESLint, Prettier, Vitest, script `typecheck`.

**Listo cuando:** `npm run dev` muestra un layout vacío con tokens y fuentes correctas en 360 px y 1440 px.

## Fase 1 · Datos base y acceso (1–2 días)
- [ ] Migraciones de catálogos: `staff`, `groups`, `students`, `periods`, `schedule_entries`, `destinations`, `settings`, `devices`, `device_unlocks`.
- [ ] RLS por rol.
- [ ] Login con Google restringido a `staff` activo; pantalla de "no tienes acceso".
- [ ] Importar CSV (plantillas en `data/templates/`) desde Configuración → Alumnos / Personal / Horarios. Validación con errores por fila.
- [ ] Definir y cambiar PIN de 4 dígitos (Personal y PIN). Hash con `pgcrypto`.
- [ ] Vinculación de equipo de salón con código de 6 dígitos.
- [ ] `v_current_class`: materia y maestro actual por grupo.
- [ ] Seed de ejemplo: 9 grupos, 30 alumnos por grupo, horario de lunes a viernes.

**Listo cuando:** un coordinador importa los CSV, un maestro entra con Google en su celular y ve su grupo de la hora actual, y una compu queda vinculada a 2°B.

## Fase 2 · Motor de pases (2–3 días) — la más importante
- [ ] `passes`, `pass_events`, índices y enum de estados.
- [ ] RPC: `request_pass`, `confirm_turn`, `cede_turn`, `mark_returned`, `mark_arrived`, `release_pass`, `cancel_pass`, `undo_last`, `advance`.
- [ ] `unlock_device`, `lock_device`, `current_actor` con límite de intentos.
- [ ] `tick()` con pg_cron cada minuto: vencer turnos, autobloqueo de equipos.
- [ ] **Pruebas SQL** que cubran como mínimo:
  - Hombres capacidad 1: segundo niño de otro grupo queda `queued`.
  - Mismo grupo: segundo niño queda `group_wait`; al regresar el primero, pasa a `queued`/`out`.
  - Niño y niña del mismo grupo pueden estar fuera a la vez.
  - Mujeres capacidad 3: la cuarta queda en fila.
  - Enfermería no ocupa lugar del grupo ni hace fila.
  - Turno no confirmado en 2 min → segundo lugar; se llama al siguiente.
  - Concurrencia: dos `request_pass` simultáneos por el último lugar → solo uno `out`.
  - Un alumno no puede tener dos pases activos.
  - Acciones con equipo bloqueado o unlock vencido → error.
  - Deshacer dentro de 10 s revierte; después de 10 s falla.

**Listo cuando:** todas las pruebas pasan y las reglas se pueden cambiar desde `destinations`/`settings` sin tocar código.

## Fase 3 · Pantallas de salón y celular del maestro (2–3 días)
- [ ] Equipo de salón: `SalonBloqueo` → `Main` → `SalonMenu` → `SalonTurno` (ver `docs/design/`).
- [ ] Botón Bloquear y autobloqueo (el cliente reacciona al vencimiento del unlock).
- [ ] Captura rápida por teclado (número + B/E/R).
- [ ] Celular: `MovilGrupo`, `MovilMenu` (hoja inferior), `MovilTurno`; cambio de grupo.
- [ ] Realtime: los cambios se ven al instante en todos los dispositivos.
- [ ] Toast Deshacer, sonido de turno, Wake Lock en modo salón.
- [ ] Estados vacíos y errores claros ("Ya hay un niño de 2°B fuera; quedó en espera").

**Listo cuando:** con dos navegadores (salón 2°B y celular de otro maestro) se puede recorrer todo el ciclo de pases sin recargar.

## Fase 4 · Prefectura, enfermería y alertas en la app (2 días)
- [ ] `Prefectura` (escritorio/tablet) y `MovilPrefectura`.
- [ ] `Enfermeria` (Llegó / Regresa al salón / nota interna).
- [ ] `tick()`: alertas de 10 min, escalamiento a los 5 min sin atender, cierre "Resuelto".
- [ ] "Yo lo atiendo", "Liberar lugar" con motivo obligatorio.
- [ ] Alerta visible para el maestro a cargo ahora y el que autorizó.

**Listo cuando:** un pase de 10 min genera alerta en salón y prefectura, se puede atender y liberar, y queda en la bitácora.

## ★ Hito · Demo para Dirección (1 día, después de la Fase 4)
Objetivo: mostrar el sistema funcionando en vivo **sin datos reales**.
- [ ] Proyecto Supabase separado `pase-demo` y despliegue en Vercel en `demo.<dominio>` (o URL de Vercel).
- [ ] Banner fijo "MODO DEMO · datos ficticios" en todas las pantallas.
- [ ] Seed ficticio: 9 grupos × 30 alumnos con nombres inventados, horario completo, usuarios demo (maestro, prefectura, enfermería, coordinación, dirección).
- [ ] Acceso demo sin Google: pantalla para elegir rol ("Entrar como Maestro 2°B", "Prefectura", "Dirección"…), solo en el proyecto demo.
- [ ] **Acelerador de tiempo:** en demo, `alert_minutes` y `confirm_turn_minutes` se interpretan en segundos ×6 (10 min → 1:40, 2 min → 20 s), configurable. `tick()` cada 10 s (pg_cron admite segundos).
- [ ] **Simulador:** botón "Simular actividad" que abre pases al azar en otros grupos para que haya filas y alertas sin que nadie tenga que operar 9 salones.
- [ ] Botón "Reiniciar demo" (solo coordinación demo) que deja todo en cero.
- [ ] Reportes con una semana de historial ficticio pre-cargado para que el dashboard no salga vacío.

**Listo cuando:** se puede seguir `docs/DEMO.md` de principio a fin en 10 minutos con una computadora y dos celulares.

## Fase 5 · Notificaciones externas (2 días)
- [ ] `notifications_outbox` + `notification_rules` + pantalla Configuración → Notificaciones.
- [ ] Web push (`send-push`) + instrucciones de instalación en iPhone.
- [ ] Bot de WhatsApp en `services/whatsapp-bot/` con Dockerfile, health check y botón "Enviar prueba".

**Listo cuando:** una alerta llega por push y al grupo de WhatsApp en menos de 1 minuto, y su resolución también.

## Fase 6 · Reportes, exportación y configuración (2 días)
- [ ] `Coordinacion` y `MovilReportes`: resumen, mapa de calor, por grupo, a revisar, historial con búsqueda.
- [ ] `export-sheets` a demanda + diario a las 15:00.
- [ ] `Configuracion`: baños y reglas, tiempos, horarios, alumnos, personal y PIN, salones y equipos, notificaciones.

**Listo cuando:** coordinación ve los datos de la semana y exporta a una hoja de Google con un clic.

## Fase 7 · Endurecimiento y piloto (1–2 días + 2–4 semanas de uso)
- [ ] PWA instalable, ícono, offline básico (mensaje "sin conexión", reintentos).
- [ ] Revisión de RLS y de funciones `security definer`.
- [ ] Respaldo diario de BD; plan Pro de Supabase o ping para evitar pausa.
- [ ] Manual de una página para maestros y para prefectura.
- [ ] Despliegue en Vercel + dominio.
- [ ] Piloto con los 9 grupos; recolectar métricas para la propuesta UHF.

## Fase 8 · RFID/UHF (futuro)
- [ ] `ingest-reader-event` y asignación de tags a alumnos.
