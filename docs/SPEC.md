# Especificación funcional

## 1. Contexto

- Secundaria con **9 grupos** (1°A–C, 2°A–C, 3°A–C; confirmar nombres reales con el CSV de grupos).
- Cada salón tiene una computadora. El sistema también debe funcionar completo desde celular y tablet.
- Todo el personal tiene correo institucional de Google Workspace.
- Hay **baño de hombres**, **baño de mujeres** y **enfermería**.

## 2. Roles

| Rol | Qué hace | Dónde |
|---|---|---|
| `teacher` | Abre y cierra pases de su grupo en esa hora | Compu del salón (con PIN) o su celular |
| `prefect` | Ve todo en vivo, atiende alertas, libera lugares | Tablet o celular |
| `nurse` | Confirma llegada y regreso de enfermería | Celular |
| `coordinator` | Todo lo anterior + reportes + configuración | Cualquiera |
| `director` | Reportes, en vivo (lectura), recibe alertas, configuración | Cualquiera |
| `admin` | Soporte técnico (Andrés) | Cualquiera |

Una persona puede tener más de un rol.

## 3. Reglas de negocio (valores por defecto, todos configurables)

| Regla | Hombres | Mujeres | Enfermería |
|---|---|---|---|
| Fuera por grupo a la vez | 1 niño | 1 niña | Sin límite, **no ocupa lugar del grupo** |
| Personas dentro del baño | 1 | 3 | — |
| Fila global | Sí | Sí | No |
| Alerta por tiempo fuera | 10 min | 10 min | 10 min |

- El baño se asigna **solo** según el sexo registrado del alumno. El maestro nunca elige baño.
- Como cada grupo solo tiene una niña fuera, las alumnas en el baño de mujeres siempre son de grupos distintos (no requiere validación extra).
- El baño cuenta como ocupado **desde que el alumno sale del salón** hasta que el maestro marca el regreso (no hay sensor en el baño todavía).
- Un alumno no puede tener dos pases activos.

## 4. Estados de un pase

### Baño
```
group_wait ──► queued ──► called ──► out ──► returned
     │            │          │        │
     └────────────┴──────────┴────────┴──► cancelled / released
```
- `group_wait`: ya hay alguien del mismo grupo y mismo sexo en `queued`, `called` u `out`. Espera a que se libere el lugar del grupo.
- `queued`: en la fila global del baño, ordenado por `queue_ts` (FIFO).
- `called`: es su turno. Tiene `confirm_minutes` (default 2) para que el maestro confirme. Se ve la franja ámbar "Turno de X" con cuenta regresiva y sonido.
  - Si el maestro **confirma** → `out`.
  - Si **cede** o **no confirma a tiempo** → vuelve a `queued` en **segundo lugar** (detrás del siguiente) y se llama al siguiente.
- `out`: fuera del salón, corre el cronómetro desde `started_at`.
- `returned`: el maestro marcó regreso. Cierra el pase.
- `released`: prefectura liberó el lugar (requiere motivo). Cierra el pase y genera incidencia.
- `cancelled`: el maestro canceló antes de salir.

**Lugar del grupo:** por grupo y por sexo, a lo más un pase en `queued | called | out`. Los demás quedan en `group_wait`.

**Ocupación del baño:** `count(called) + count(out)` ≤ `capacity`. `called` reserva lugar.

**Al pedir un pase de baño:**
1. Si el alumno ya tiene pase activo → error claro.
2. Si el lugar del grupo (mismo sexo) está ocupado → `group_wait`.
3. Si hay lugar en el baño **y** la fila está vacía → `out` directo.
4. Si no → `queued`.

**Cada vez que un pase se cierra o cambia** se ejecuta `advance(bathroom)`:
1. Promueve el `group_wait` más antiguo de ese grupo/sexo a `queued` (o `out` si hay lugar y la fila está vacía).
2. Mientras haya lugar, pasa el primero de la fila a `called`.

### Enfermería
`out` (en camino) → `arrived` (la enfermera confirma) → `returned` (la enfermera lo regresa, o el maestro marca regreso). No hace fila ni ocupa lugar.

### Deshacer
Durante 10 s después de "Marcar regreso" o de abrir un pase, aparece "Deshacer". Revierte con un evento nuevo (`undo`) y re-ejecuta `advance`.

## 5. Computadora del salón (modo salón)

- Coordinación registra cada computadora una vez como "Equipo de salón 2°B" (código de vinculación de 6 dígitos desde Configuración).
- **Pantalla bloqueada** por defecto: muestra grupo, clase actual (según horario), teclado de PIN y, en solo lectura, el estado del grupo (quién está fuera, cronómetros).
- El maestro desbloquea con su **PIN de 4 dígitos**. Cualquier maestro puede desbloquear (suplentes); los pases quedan a nombre de quien desbloqueó.
- **El PIN es único por persona** (decisión 2026-10-15): al definirlo o cambiarlo se rechaza si otra persona activa ya lo usa ("Ese PIN no está disponible, elige otro"), sin revelar de quién es. Así `unlock_device(pin)` identifica al maestro solo con el PIN.
- 5 intentos fallidos → bloqueo de 60 s.
- Botón **Bloquear** (candado) en el encabezado.
- **Bloqueo automático 5 minutos después de que termina la clase** si nadie bloqueó (configurable).
- Una vez desbloqueada, **no se pide PIN por acción**: tocar al alumno abre el menú Baño / Enfermería y un toque abre el pase.
- Atajos de teclado: número de lista + `B` baño, `E` enfermería, `R` regresó.

## 6. Celular

- Login con Google (cuenta institucional). Sesión persistente. **Sin PIN ni bloqueo** en el celular.
- El maestro ve su grupo de la hora actual (según horario) y puede cambiar a **cualquier grupo** (suplencias; decisión 2026-10-15). En el selector aparecen primero el grupo de la hora actual y luego los grupos que imparte; después, todos los demás.
- Navegación inferior por rol:
  - Maestro: Mi grupo · Baños · Alertas · Más
  - Prefectura: En vivo · Historial · Más
  - Enfermería: Hoy · Historial
  - Coordinación/Dirección: En vivo · Reportes · Historial · Ajustes

## 7. Alertas

- Se disparan cuando un pase lleva `alert_minutes` (10) en `out` (o en enfermería sin regresar).
- Destinatarios (configurables por canal):
  - **Maestro a cargo del grupo en ese momento** (según horario) y, si es distinto, el maestro que autorizó la salida → en la app.
  - **Prefectura, Coordinación, Dirección** → app + push + WhatsApp.
- Canales: en la app (banner/tarjeta roja + sonido), web push, mensaje al grupo de WhatsApp "Alertas Sanitarios".
- **"Yo lo atiendo"**: quien la toma queda registrado y todos lo ven.
- **Escalamiento:** si nadie la atiende en `escalate_minutes` (5), se reenvía con prioridad alta.
- **Cierre:** al marcar regreso o liberar, se notifica "Resuelto · 13 min" por los mismos canales.
- Formato WhatsApp: `⚠️ Natalia Quiroz (2°B) lleva 10 min fuera · Baño mujeres · Clase: Español, Prof. Soto`

## 8. Cambio de clase

Un pase no se cierra al sonar el timbre. Si el alumno sigue fuera, el maestro de la siguiente clase lo ve en la pantalla (bloqueada y desbloqueada) con la etiqueta "salió en Matemáticas". Las alertas van al maestro a cargo **ahora**.

## 9. Reportes (Coordinación y Dirección)

- Resumen del periodo: salidas, tiempo promedio fuera, alertas, fila máxima.
- Mapa de calor por baño: salidas por hora × día.
- Tabla por grupo: salidas, promedio, alertas.
- "A revisar": alumnos con 2+ alertas o más de 8 salidas en la semana (umbrales configurables).
- Historial con búsqueda por alumno, grupo, maestro y fecha.
- **Exportar a Google Sheets**: a demanda (rango elegido) y copia diaria automática a las 15:00.

## 10. Configuración

Pestañas: Baños y reglas · Horarios · Alumnos · Personal y PIN · Salones y equipos · Notificaciones.
Importación de alumnos, grupos, horario y personal desde CSV o Google Sheets (plantillas en `data/templates/`).

## 11. Fuera de alcance de la v1

- Lectores RFID/UHF (dejar `ingest-reader-event` preparado, ver INTEGRATIONS.md).
- Aviso automático a padres.
- Apps nativas.
