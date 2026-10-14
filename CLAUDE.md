# Pase Sanitario — contexto del proyecto

PWA para controlar salidas de alumnos al baño y a enfermería en una secundaria (Instituto, León, Gto., México). El maestro es el único que opera el sistema; el alumno nunca toca nada. Primera entrega: 9 grupos de secundaria. Después: lectores RFID/UHF como otra fuente de eventos.

Lee estos documentos antes de programar cualquier cosa:

- `docs/SPEC.md` — reglas de negocio, estados del pase, roles, flujos. **Es la fuente de verdad.**
- `docs/DATA_MODEL.md` — esquema de Postgres, funciones RPC, RLS, cron.
- `docs/DESIGN.md` — tokens de diseño, componentes y cómo leer los mockups.
- `docs/design/*.dc.html` y `docs/design/png/` — mockups aprobados de cada pantalla.
- `docs/INTEGRATIONS.md` — WhatsApp, notificaciones push, Google Sheets.
- `docs/PLAN.md` — fases, tareas y criterios de aceptación. Trabaja una fase a la vez.

## Stack

- Frontend: Vite + React 18 + TypeScript (strict) + Tailwind CSS + React Router + TanStack Query. PWA con `vite-plugin-pwa`.
- Backend: Supabase (Postgres, Auth con Google, Realtime, Edge Functions en Deno, pg_cron).
- Bot de WhatsApp: servicio Node aparte en `services/whatsapp-bot/` (whatsapp-web.js), corre en un VPS/Railway, no en Supabase.
- Hosting del frontend: Vercel.
- Zona horaria: `America/Mexico_City`. Guarda todo como `timestamptz`; muestra en hora local.

## Reglas que no se negocian

1. **Toda regla de cupo y fila vive en Postgres** (funciones `plpgsql` con bloqueo `FOR UPDATE`). El frontend nunca decide si un alumno puede salir; solo llama RPC y muestra el resultado. Dos maestros que pidan el último lugar al mismo tiempo: uno sale, el otro queda en fila.
2. **Nada se borra.** Cada cambio de estado de un pase escribe una fila en `pass_events` (quién, desde qué equipo, cuándo). Deshacer = un evento nuevo que revierte, no un DELETE.
3. **Los valores de reglas salen de la tabla `settings`/`bathrooms`**, nunca de constantes en código (capacidades, minutos de alerta, minutos para confirmar turno, etc.).
4. **Privacidad:** datos de menores. Solo personal autenticado ve nombres. Nada de pantallas públicas con nombres. RLS activado en todas las tablas.
5. **Interfaz en español de México**, textos cortos y directos, botones de mínimo 48 px, cronómetros con números tabulares. Responsive desde 360 px; la misma app sirve en la computadora del salón, tablet y celular.
6. El color nunca es la única señal de estado: siempre hay texto o ícono.

## Convenciones

- Nombres de tablas y código en inglés; textos de UI en español.
- Migraciones SQL en `supabase/migrations/` con timestamp. Seeds de ejemplo en `supabase/seed.sql` (marcados como ejemplo).
- Tipos de BD generados con `supabase gen types typescript` en `src/lib/database.types.ts`.
- Pruebas: Vitest para lógica de frontend; pgTAP (o scripts SQL de prueba) para las funciones de reglas. Las reglas de cupo y fila **deben** tener pruebas.
- Commits pequeños por tarea del plan. Antes de cerrar una fase, corre lint, typecheck y pruebas.

## Comandos

```bash
npm run dev          # frontend
npm run build && npm run preview
npm run test
supabase start       # BD local
supabase db reset    # aplica migraciones + seed
supabase functions serve
```
