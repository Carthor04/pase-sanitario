// Conexión a la BD vinculada para los scripts de prueba: DATABASE_URL, o el pooler de
// `supabase link` + SUPABASE_DB_PASSWORD (se lee de .env.local si no está en el entorno).
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('..', import.meta.url));

function fromEnvFile(name) {
  const file = join(root, '.env.local');
  if (!existsSync(file)) return undefined;
  const line = readFileSync(file, 'utf8')
    .split(/\r?\n/)
    .find((l) => l.startsWith(`${name}=`));
  return line?.slice(name.length + 1).replace(/^"|"$/g, '');
}

export function connectionString() {
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
