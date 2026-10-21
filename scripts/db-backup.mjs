// Respaldo de DATOS de la BD vinculada a un .sql restaurable, sin pg_dump ni Docker.
//   node scripts/db-backup.mjs [--out <carpeta>]
// Por omisión escribe en ~/Documents/Respaldos Pase sanitario/ (fuera del repo: trae datos de menores).
// Incluye todas las tablas de public y private, más auth.users y auth.identities. El esquema no
// va en el archivo: es el de supabase/migrations en el commit y las versiones que se anotan arriba.
// Restaurar (sobre una BD con las mismas migraciones y tablas vacías): ejecutar el .sql completo.
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { execSync } from 'node:child_process';
import pg from 'pg';
import { connectionString, root } from './db-connection.mjs';

const outArg = process.argv.indexOf('--out');
const outDir =
  outArg > 0 ? process.argv[outArg + 1] : join(homedir(), 'Documents', 'Respaldos Pase sanitario');
if (outDir.startsWith(root)) throw new Error('El respaldo no puede quedar dentro del repo.');
mkdirSync(outDir, { recursive: true });

const c = new pg.Client({
  connectionString: connectionString(),
  ssl: { rejectUnauthorized: false },
});
await c.connect();

// Orden por llaves foráneas: primero las tablas de las que dependen las demás.
const { rows: tables } = await c.query(`
  with recursive t as (
    select c.oid, n.nspname s, c.relname n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'r'
      and (n.nspname in ('public', 'private') or (n.nspname = 'auth' and c.relname in ('users', 'identities')))
  ), dep as (
    select t.oid, 0 lvl from t
    union all
    select f.conrelid, dep.lvl + 1 from dep
    join pg_constraint f on f.contype = 'f' and f.confrelid = dep.oid and f.conrelid <> dep.oid
    where dep.lvl < 20
  )
  select t.s, t.n, max(dep.lvl) lvl from t join dep using (oid) group by 1, 2 order by 3, 1, 2`);

const commit = execSync('git rev-parse HEAD', { cwd: root }).toString().trim();
const { rows: migs } = await c.query(
  'select version from supabase_migrations.schema_migrations order by 1',
);
const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const file = join(outDir, `pase-sanitario-${stamp}.sql`);

const out = [
  `-- Respaldo de datos Pase Sanitario · ${new Date().toISOString()}`,
  `-- Commit del esquema: ${commit}`,
  `-- Migraciones aplicadas: ${migs.map((m) => m.version).join(', ')}`,
  '-- CONTIENE DATOS DE MENORES. No compartir ni subir a repositorios.',
  'begin;',
  "set local session_replication_role = 'replica';",
];
const counts = {};
for (const { s, n } of tables) {
  const { rows } = await c.query(`select coalesce(json_agg(t), '[]') j from ${s}."${n}" t`);
  const json = JSON.stringify(rows[0].j);
  counts[`${s}.${n}`] = rows[0].j.length;
  if (!rows[0].j.length) continue;
  let tag = 'd';
  while (json.includes(`$${tag}$`)) tag += 'x';
  // Sin columnas generadas (p. ej. auth.users.confirmed_at): no aceptan valores.
  const { rows: cols } = await c.query(
    `select string_agg(quote_ident(attname), ', ' order by attnum) l from pg_attribute
     where attrelid = $1::regclass and attnum > 0 and not attisdropped and attgenerated = ''`,
    [`${s}."${n}"`],
  );
  out.push(
    `insert into ${s}."${n}" (${cols[0].l}) overriding system value select ${cols[0].l} from json_populate_recordset(null::${s}."${n}", $${tag}$${json}$${tag}$);`,
  );
}
const { rows: seqs } = await c.query(`
  select format('%I.%I', n.nspname, c.relname) seq from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'S' and n.nspname in ('public', 'private')`);
for (const { seq } of seqs) {
  const { rows } = await c.query(`select last_value, is_called from ${seq}`);
  out.push(`select setval('${seq}', ${rows[0].last_value}, ${rows[0].is_called});`);
}
out.push('commit;', '');
writeFileSync(file, out.join('\n'));
writeFileSync(file.replace(/\.sql$/, '.json'), JSON.stringify({ commit, counts }, null, 2));
await c.end();

console.log(`Respaldo: ${file}`);
console.table(counts);
