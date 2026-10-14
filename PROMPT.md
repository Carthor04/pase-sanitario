# Prompts para Claude Code

## Prompt inicial (pégalo en la primera sesión)

```
Vamos a construir "Pase Sanitario", una PWA para controlar salidas de alumnos al baño y a enfermería en una secundaria.

Antes de escribir código:
1. Lee CLAUDE.md y todos los archivos de docs/ (SPEC, DATA_MODEL, DESIGN, INTEGRATIONS, PLAN).
2. Revisa los mockups en docs/design/ (los .dc.html como fuente exacta de estilos y textos, y los PNG como referencia visual).
3. Dime en un resumen corto cómo entendiste las reglas de cupo y fila (SPEC §3 y §4) y lista cualquier contradicción o duda que encuentres entre los documentos.

Después, trabaja solo la Fase 0 del PLAN. Al terminar, corre lint, typecheck y pruebas, y dame un resumen de lo hecho y lo que sigue. No avances a la Fase 1 hasta que te lo confirme.
```

## Prompts por fase (para las siguientes sesiones)

**Fase 1**

```
Continúa con la Fase 1 del PLAN (datos base y acceso). Usa las plantillas de data/templates/ para el importador y crea un seed de ejemplo. Respeta RLS de DATA_MODEL. Al terminar, muéstrame cómo probar el login de un maestro y la vinculación de un equipo de salón.
```

**Fase 2**

```
Continúa con la Fase 2 del PLAN: el motor de pases en Postgres. Toda la lógica de cupo, fila, turnos y deshacer va en funciones plpgsql con bloqueo FOR UPDATE, como dice DATA_MODEL. Escribe primero las pruebas SQL de la lista de la Fase 2, luego las funciones, y no termines hasta que todas pasen. Incluye la prueba de concurrencia.
```

**Fase 3**

```
Continúa con la Fase 3: pantallas del salón y del celular del maestro. Reproduce fielmente SalonBloqueo, Main, SalonMenu, SalonTurno, MovilGrupo, MovilMenu y MovilTurno de docs/design/ con React + Tailwind y los tokens de DESIGN.md. Conecta todo a las RPC de la Fase 2 y a Realtime. Al terminar, compara tus pantallas con los PNG de docs/design/png/ y corrige diferencias de espaciado, color o texto.
```

**Fase 4**

```
Continúa con la Fase 4: Prefectura, Enfermería y alertas dentro de la app, según SPEC §7 y los mockups Prefectura, MovilPrefectura y Enfermeria.
```

**Hito · Demo para Dirección**

```
Implementa el hito "Demo para Dirección" del PLAN y deja que docs/DEMO.md se pueda seguir completo. Usa un proyecto Supabase separado para la demo; ninguna función de demo (acceso sin Google, acelerador de tiempo, simulador, reinicio) debe existir en el proyecto de producción: contrólalo con una variable de entorno VITE_DEMO_MODE y un flag en settings. Al terminar, recorre tú mismo el guion en el navegador y dime qué paso falla.
```

**Fase 5**

```
Continúa con la Fase 5: notificaciones push y el bot de WhatsApp en services/whatsapp-bot/, según INTEGRATIONS.md. Incluye Dockerfile, health check, instrucciones de despliegue en Railway y el botón "Enviar prueba" en Configuración.
```

**Fase 6**

```
Continúa con la Fase 6: reportes (Coordinacion y MovilReportes), exportación a Google Sheets (a demanda y diaria) y la pantalla de Configuración completa.
```

**Fase 7**

```
Continúa con la Fase 7: endurecimiento. Revisa RLS y funciones security definer buscando huecos, haz la PWA instalable, maneja la pérdida de conexión, prepara el despliegue en Vercel y escribe los manuales de una página para maestros y prefectura en docs/manuales/.
```

## Consejos de uso

- Una fase por sesión. Si la sesión se alarga, pide un resumen y empieza otra con "Continúa con la Fase N; lee CLAUDE.md y PLAN.md".
- Si cambias una regla con el colegio, actualiza primero `docs/SPEC.md` y luego pide: "Actualicé SPEC §X; ajusta el código y las pruebas".
- Para revisar diseño: "Abre la app en 390 px y 1440 px, toma capturas y compáralas con docs/design/png/".
