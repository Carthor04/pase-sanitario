// Corre las pruebas SQL de supabase/tests/ contra la BD vinculada (no hace falta Docker).
// Cada archivo va en su propia transacción que SIEMPRE se revierte: no deja datos.
// Conexión: DATABASE_URL, o el pooler de `supabase link` + SUPABASE_DB_PASSWORD
// (se lee de .env.local si no está en el entorno).
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import pg from 'pg';
import { connectionString, root } from './db-connection.mjs';

const testsDir = join(root, 'supabase', 'tests');

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
