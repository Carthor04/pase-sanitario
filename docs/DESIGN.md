# Diseño de interfaz

Los mockups aprobados están en `docs/design/`:
- `*.dc.html`: fuente exacta de cada pantalla (colores, tamaños, textos, estructura).
- `png/`: capturas exportadas del lienzo para verlas como imagen.

## Cómo leer los `.dc.html`

Son HTML con estilos en línea y una sintaxis de plantillas propia de la herramienta de diseño. **No los copies tal cual ni cargues `support.js`.** Úsalos como referencia visual y de contenido:
- `{{algo}}` = dato dinámico. Los valores de ejemplo están en el `<script data-dc-script>` al final de cada archivo (`renderVals()`).
- `<sc-for list=… as=…>` = un `.map()`; `<sc-if value=…>` = render condicional.
- `<x-dc>` y `<helmet>` = contenedor; ignóralos.
- `{{accent}}` = color de acento, por defecto `#1D4E89` (se cambiará por el color del colegio).

Reimplementa cada pantalla como componentes React + Tailwind respetando medidas, jerarquía y textos. Los datos de ejemplo (nombres, cifras) son ficticios.

| Archivo | Pantalla | Ruta sugerida |
|---|---|---|
| `SalonBloqueo.dc.html` | Equipo de salón bloqueado (PIN + estado en solo lectura) | `/salon` (estado bloqueado) |
| `Main.dc.html` | Salón desbloqueado: lugares niño/niña/enfermería, captura rápida, lista, estado de baños | `/salon` |
| `SalonMenu.dc.html` | Menú al tocar un alumno: Baño / Enfermería | modal |
| `SalonTurno.dc.html` | Franja "Turno de…", alerta 10 min, enfermería, toast Deshacer | estados de `/salon` |
| `Prefectura.dc.html` | Monitor en vivo: alertas arriba, 3 columnas | `/en-vivo` |
| `Enfermeria.dc.html` | Enfermería en celular | `/enfermeria` |
| `Coordinacion.dc.html` | Reportes | `/reportes` |
| `Configuracion.dc.html` | Configuración | `/ajustes/*` |
| `MovilGrupo.dc.html` | Mi grupo en celular | `/grupo` |
| `MovilMenu.dc.html` | Menú del alumno como hoja inferior | bottom sheet |
| `MovilTurno.dc.html` | Turno y alerta en celular | estados de `/grupo` |
| `MovilPrefectura.dc.html` | En vivo en celular, con pestañas por lugar | `/en-vivo` < 640 px |
| `MovilReportes.dc.html` | Reportes en celular | `/reportes` < 640 px |

Una sola app responsive: por debajo de 640 px usa las versiones "Movil*"; arriba, las de escritorio.

## Tokens

```css
:root {
  /* Base */
  --ground: #F3F5F7;      /* fondo de página */
  --surface: #FFFFFF;     /* tarjetas */
  --line: #DCE2E8;        /* bordes */
  --line-strong: #C5CED8; /* bordes de inputs y botones secundarios */
  --ink: #15212C;         /* texto principal, estado "fuera" */
  --muted: #52606D;       /* texto secundario */
  --accent: #1D4E89;      /* color del colegio (placeholder) */

  /* Estados (siempre acompañados de texto) */
  --free-fg: #146C43;   --free-bg: #E3F4EA;              /* libre */
  --wait-fg: #8A4B00;   --wait-bg: #FFF0D6; --wait-bd: #E79B2E; /* fila / turno / espera */
  --alert-fg: #A3221A;  --alert-bg: #FDE9E7; --alert-bd: #C8372D; /* alerta 10 min */
  --nurse-fg: #1F4F9C;  --nurse-bg: #E6EEFB; --nurse-bd: #5B86C9; /* enfermería */
  --dark: #15212C;      /* encabezado de prefectura y pantalla bloqueada */
}
```

Tipografía (Google Fonts):
- Títulos: **Bricolage Grotesque** 700.
- Texto e interfaz: **Atkinson Hyperlegible** 400/700 (muy legible).
- Números, cronómetros y PIN: **Atkinson Hyperlegible Mono** 600 con `font-variant-numeric: tabular-nums`.

Medidas:
- Radios: tarjetas 14–16 px, botones 10–12 px, chips 999 px.
- Botones primarios ≥ 48 px de alto (52 px en acciones críticas). Táctil mínimo 44 px.
- Contenedor máx. 1360 px, padding 24 px (16 px en celular).
- Rejilla de alumnos: `repeat(auto-fill, minmax(168px, 1fr))`, gap 10 px.

## Componentes
- `StatusSlot` (tarjeta Niño / Niña / Enfermería): estados libre, fuera, su turno, alerta, enfermería.
- `StudentTile` (escritorio) y `StudentRow` (celular) con número, nombre, H/M y etiqueta de estado.
- `TurnBanner`: franja ámbar con cuenta regresiva, "Ceder turno" y "Confirmar salida". Sonido al aparecer.
- `AlertCard` con "Yo lo atiendo", "Liberar lugar", "Marcar regreso".
- `PinPad` (4 dígitos, se envía solo al completar).
- `BathroomStatus` (ocupación con pips + fila).
- `Timer` (mm:ss desde `started_at`; barra de progreso hasta el minuto 10).
- `UndoToast` (10 s).
- `BottomNav` por rol (celular).
- `LockButton` (candado) solo en el equipo de salón.

## Comportamiento
- Sonido corto al aparecer "Su turno" y al dispararse una alerta (pedir permiso de audio con el primer toque).
- `prefers-reduced-motion`: sin parpadeos; la alerta usa borde y color fijos.
- Mantener la pantalla encendida en modo salón (Wake Lock API, si está disponible).
