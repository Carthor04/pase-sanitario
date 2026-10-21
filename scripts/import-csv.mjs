// Importa un CSV de plantilla (data/templates/) en la BD vinculada con la MISMA lógica que
// Configuración → importar: el lector de src/lib/csv.ts y la RPC import_* como un usuario admin.
//   node scripts/import-csv.mjs <groups|students|staff|schedule|sections> <archivo.csv> --como <correo> [--aplicar]
// Sin --aplicar es simulacro: llama la RPC dentro de una transacción y la revierte.
import { readFileSync } from 'node:fs';
import pg from 'pg';
import { parseImportCsv } from '../src/lib/csv.ts';
import { connectionString } from './db-connection.mjs';

const RPC = {
  groups: 'import_groups',
  students: 'import_students',
  staff: 'import_staff',
  schedule: 'import_schedule',
  sections: 'import_sections',
};
const [kind, file] = process.argv.slice(2);
const asArg = process.argv.indexOf('--como');
const email = asArg > 0 ? process.argv[asArg + 1] : undefined;
const apply = process.argv.includes('--aplicar');
if (!RPC[kind] || !file || !email) {
  console.error(
    'Uso: node scripts/import-csv.mjs <groups|students|staff|schedule|sections> <archivo.csv> --como <correo> [--aplicar]',
  );
  process.exit(1);
}

const parsed = parseImportCsv(readFileSync(file, 'utf8'), kind);
if (!parsed.ok) {
  console.error(parsed.error);
  process.exit(1);
}

const c = new pg.Client({
  connectionString: connectionString(),
  ssl: { rejectUnauthorized: false },
});
await c.connect();
await c.query('begin');
try {
  const { rows: users } = await c.query(
    `select u.id from auth.users u join public.staff s on s.auth_user_id = u.id
      where lower(u.email) = lower($1) and s.active`,
    [email],
  );
  if (!users.length) throw new Error(`No hay personal activo con cuenta para ${email}`);
  // Igual que la app: rol authenticated con los claims del JWT de ese usuario.
  await c.query(
    `select set_config('request.jwt.claims', $1, true), set_config('role', 'authenticated', true)`,
    [JSON.stringify({ sub: users[0].id, role: 'authenticated', email, is_anonymous: false })],
  );
  const { rows } = await c.query(`select public.${RPC[kind]}($1::jsonb) as r`, [
    JSON.stringify(parsed.rows),
  ]);
  const result = rows[0].r;
  await c.query(apply && result.ok ? 'commit' : 'rollback');
  if (result.ok) {
    console.log(`${parsed.rows.length} filas · resultado:`, result.summary);
    console.log(apply ? 'APLICADO.' : 'Simulacro: nada cambió. Usa --aplicar para confirmar.');
  } else {
    console.table(result.errors);
    console.log('Con errores: no se importó nada.');
    process.exitCode = 1;
  }
} catch (e) {
  await c.query('rollback');
  throw e;
} finally {
  await c.end();
}
