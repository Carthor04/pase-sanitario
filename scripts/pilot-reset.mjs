// Limpieza ÚNICA antes de la prueba piloto: borra los datos de prueba de la BD vinculada.
// Excepción autorizada por dirección a la regla "nada se borra". Haz antes el respaldo
// (node scripts/db-backup.mjs).
//   node scripts/pilot-reset.mjs            → simulacro: borra en una transacción, cuenta y revierte
//   node scripts/pilot-reset.mjs --aplicar  → lo mismo, pero confirma (COMMIT)
// Conserva: destinos (destinations), reglas (settings, notification_rules), al personal de
// KEEP_STAFF con su cuenta y PIN, y los grupos de KEEP_GROUPS con sus alumnos y horario (ya son
// los oficiales). Borra todo lo demás: pases y su bitácora (de todos los grupos), alertas,
// avisos enviados, suscripciones push, equipos (y sus usuarios anónimos), intentos de
// seguridad, horario, alumnos y grupos de ejemplo y el resto del personal.
import pg from 'pg';
import { connectionString } from './db-connection.mjs';

const KEEP_STAFF = ['carthorca@gmail.com', 'saelcarrillot@institutooviedo.edu.mx'];
const KEEP_GROUPS = ['2°C'];
const apply = process.argv.includes('--aplicar');

// En orden de llaves foráneas: primero lo que depende de lo demás.
const STEPS = [
  ['nurse_notes', 'delete from public.nurse_notes'],
  ['alerts', 'delete from public.alerts'],
  ['notifications_outbox', 'delete from public.notifications_outbox'],
  ['pass_events', 'delete from public.pass_events'],
  ['passes', 'delete from public.passes'],
  ['push_subscriptions', 'delete from public.push_subscriptions'],
  ['device_unlocks', 'delete from public.device_unlocks'],
  ['device_pairings', 'delete from public.device_pairings'],
  ['devices', 'delete from public.devices'],
  ['auth.users (anónimos de equipos)', 'delete from auth.users where is_anonymous'],
  ['security_attempts', 'delete from public.security_attempts'],
  [
    'schedule_entries (grupos de ejemplo)',
    'delete from public.schedule_entries e using public.groups g where g.id = e.group_id and not g.name = any ($1)',
    [KEEP_GROUPS],
  ],
  [
    'periods (sin clases)',
    'delete from public.periods p where not exists (select 1 from public.schedule_entries e where e.period_id = p.id)',
  ],
  [
    'students (grupos de ejemplo)',
    'delete from public.students s using public.groups g where g.id = s.group_id and not g.name = any ($1)',
    [KEEP_GROUPS],
  ],
  ['groups (de ejemplo)', 'delete from public.groups where not name = any ($1)', [KEEP_GROUPS]],
  [
    'staff_pins (personal de ejemplo)',
    'delete from public.staff_pins p using public.staff s where s.id = p.staff_id and not lower(s.email) = any ($1)',
    [KEEP_STAFF],
  ],
  [
    'staff (personal de ejemplo)',
    'delete from public.staff where not lower(email) = any ($1)',
    [KEEP_STAFF],
  ],
];

const c = new pg.Client({
  connectionString: connectionString(),
  ssl: { rejectUnauthorized: false },
});
await c.connect();
await c.query('begin');
try {
  const { rows: kept } = await c.query(
    'select email from public.staff where lower(email) = any ($1)',
    [KEEP_STAFF],
  );
  if (kept.length !== KEEP_STAFF.length)
    throw new Error('No encuentro a todo el personal que se conserva.');
  const { rows: keptGroups } = await c.query(
    'select name from public.groups where name = any ($1)',
    [KEEP_GROUPS],
  );
  if (keptGroups.length !== KEEP_GROUPS.length)
    throw new Error('No encuentro los grupos que se conservan.');

  const result = [];
  for (const [label, sql, params] of STEPS) {
    const r = await c.query(sql, params);
    result.push({ tabla: label, borrados: r.rowCount });
  }
  console.table(result);

  const { rows: left } = await c.query(`
    select (select count(*) from public.staff)::int personal,
           (select count(*) from public.groups)::int grupos,
           (select count(*) from public.students)::int alumnos,
           (select count(*) from public.schedule_entries)::int clases,
           (select count(*) from public.passes)::int pases,
           (select count(*) from public.destinations)::int destinos,
           (select count(*) from public.settings)::int settings,
           (select count(*) from public.notification_rules)::int reglas_aviso,
           (select count(*) from auth.users)::int usuarios_auth`);
  console.log('Queda:', left[0]);

  await c.query(apply ? 'commit' : 'rollback');
  console.log(
    apply
      ? 'APLICADO (COMMIT).'
      : 'Simulacro: nada cambió (ROLLBACK). Usa --aplicar para confirmar.',
  );
} catch (e) {
  await c.query('rollback');
  throw e;
} finally {
  await c.end();
}
