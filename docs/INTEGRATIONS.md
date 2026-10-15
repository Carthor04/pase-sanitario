# Integraciones

## 1. Notificaciones push (Web Push)
Implementado en la Fase 5 (`20261015160000_notifications.sql`, `supabase/functions/send-push`).
- **Llaves VAPID** en los secretos de la función: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` (`https://pase-oviedo.vercel.app`) y `PUSH_WEBHOOK_SECRET`. La llave pública también está en `settings.vapid_public_key` (la app la lee con `push_config()`). Si se cambian las llaves, todos tienen que volver a activar las notificaciones.
- El usuario activa las notificaciones en **Más → Notificaciones** o **Ajustes → Notificaciones** (cada equipo por separado); la suscripción se guarda con `save_push_subscription`.
- Un trigger en `alerts` encola avisos (alerta, escalada, atendida, resuelta) en `notifications_outbox` según `notification_rules`, **solo para quien tiene al menos un equipo registrado**.
- Al insertar en la bandeja, `pg_net` llama a `send-push` con el encabezado `x-push-secret`; un cron cada minuto (`pase-push`) la vuelve a llamar si quedan pendientes. La URL y el secreto están en Vault (`send_push_url`, `send_push_secret`). La función reserva lotes con `claim_push_batch` (sin envíos dobles), envía con `web-push` y cierra con `finish_push`, que borra suscripciones vencidas (404/410).
- iPhone/iPad: solo funciona con la PWA instalada en la pantalla de inicio (iOS 16.4+); la app muestra las instrucciones.
- Íconos PNG para iPhone y notificaciones: `node scripts/make-icons.mjs`.

## 2. WhatsApp (bot con número dedicado)
- Servicio aparte en `services/whatsapp-bot/` con **whatsapp-web.js** (Node 20). Corre 24/7 en Railway/Render/VPS con sesión persistente (`LocalAuth` en volumen).
- Se vincula escaneando QR con el chip dedicado. Exponer el QR en un endpoint protegido o en logs para el primer vínculo.
- Escucha `notifications_outbox` (`channel='whatsapp'`) vía Supabase Realtime (con respaldo de polling cada 30 s), envía al grupo cuyo ID está en una variable de entorno `WA_GROUP_ID`, y marca `sent_at` o `error`.
- Endpoint `/health` y reporte de estado a la tabla `settings` o a una tabla `integration_status` para mostrar "Conectado" en Configuración.
- **Riesgo conocido:** es una vía no oficial; WhatsApp puede bloquear el número. Nunca es el único canal. Migración futura: WhatsApp Cloud API (plantilla de utilidad a destinatarios individuales).
- Mensajes:
  - Alerta: `⚠️ {alumno} ({grupo}) lleva {min} min fuera · {lugar} · Clase: {materia}, {maestro}`
  - Escalada: `🔴 SIN ATENDER · {alumno} ({grupo}) · {min} min · {lugar}`
  - Atendida: `👤 {persona} atiende a {alumno} ({grupo})`
  - Resuelta: `✅ {alumno} ({grupo}) regresó · {min} min`

## 3. Google Sheets
- Cuenta de servicio de Google Cloud con Sheets API habilitada. La hoja de destino se comparte con el correo de la cuenta de servicio como editor. El ID va en `settings.sheets_spreadsheet_id`.
- Edge Function `export-sheets`:
  - **A demanda** (botón "Exportar a Google Sheets"): crea una pestaña nueva `Reporte AAAA-MM-DD` con el rango elegido: hoja de movimientos + resumen por grupo + a revisar.
  - **Diaria a las 15:00** (pg_cron + `pg_net`): agrega los movimientos del día a la pestaña `Registro`.
- Columnas de movimientos: Fecha, Hora salida, Hora regreso, Minutos, Alumno, Grupo, Destino, Materia, Autorizó, Cierre, Alerta (sí/no), Atendió.

## 4. Login con Google
- Supabase Auth, proveedor Google, con `hd=<dominio del colegio>`. Además, el trigger de alta solo acepta correos que existan en `staff` activo.
- Equipos de salón: usuario técnico por equipo creado al vincular (código de 6 dígitos generado por coordinación). La sesión del equipo no expira; lo que expira es el desbloqueo (`device_unlocks`).

## 5. RFID / UHF (fase futura, solo preparar)
- Edge Function `ingest-reader-event` con API key por lector: recibe `{reader_id, tag, at}`.
- Mapear `tag` → `students.rfid_tag` y `reader_id` → lugar (puerta del baño, puerta del salón).
- Reglas iniciales: lectura en puerta del salón con pase `out` → `returned` (source `rfid`). Lectura en baño → evento `arrived_bathroom` solo informativo.
