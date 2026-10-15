// Corre las pruebas SQL de supabase/tests/ contra la BD vinculada (no hace falta Docker).
// Cada archivo va en su propia transacción que SIEMPRE se revierte: no deja datos.
// Conexión: DATABASE_URL, o el pooler de `supabase link` + SUPABASE_DB_PASSWORD
// (se lee de .env.local si no está en el entorno).
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const root = fileURLToPath(new URL('..', import.meta.url));
const testsDir = join(root, 'supabase', 'tests');

function fromEnvFile(name) {
  const file = join(root, '.env.local');
  if (!existsSync(file)) return undefined;
  const line = readFileSync(file, 'utf8')
    .split(/\r?\n/)
    .find((l) => l.startsWith(`${name}=`));
  return line?.slice(name.length + 1).replace(/^"|"$/g, '');
}

function connectionString() {
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;
  const poolerFile = join(root, 'supabase', '.temp', 'pooler-url');
  const password = process.env.SUPABASE_DB_PASSWORD ?? fromEnvFile('SUPABASE_DB_PASSWORD');
  if (!existsSync(poolerFile) || !password) {
    throw new Error('Falta DATABASE_URL o (supabase link + SUPABASE_DB_PASSWORD).');
  }
  const url = new URL(readFileSync(poolerFile, 'utf8').trim());
  url.password = password;
  return url.toString();
}

const only = process.argv[2];
const helpers = readFileSync(join(testsDir, '_helpers.sql'), 'utf8');
const files = readdirSync(testsDir)
  .filter((f) => f.endsWith('.sql') && !f.startsWith('_'))
  .filter((f) => !only || f.includes(only))
  .sort();

const client = new pg.Client({
  connectionString: connectionString(),
  ssl: { rejectUnauthorized: false },
});
await client.connect();

let failed = 0;
for (const file of files) {
  const sql = readFileSync(join(testsDir, file), 'utf8');
  const notices = [];
  const onNotice = (n) => notices.push(n.message);
  client.on('notice', onNotice);
  try {
    await client.query('begin');
    await client.query(helpers);
    await client.query(sql);
    console.log(`✔ ${file}`);
    for (const n of notices) console.log(`    ${n}`);
  } catch (err) {
    failed++;
    console.log(`✘ ${file}\n    ${err.message}`);
    if (err.where) console.log(`    ${err.where.split('\n')[0]}`);
  } finally {
    await client.query('rollback').catch(() => {});
    client.off('notice', onNotice);
  }
}

await client.end();
console.log(`\n${files.length - failed}/${files.length} archivos de prueba pasaron`);
process.exit(failed ? 1 : 0);
