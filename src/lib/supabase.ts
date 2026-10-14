import { createClient } from '@supabase/supabase-js';
import type { Database } from './database.types';
import { env } from './env';

export const isSupabaseConfigured = Boolean(env.supabaseUrl && env.supabaseAnonKey);

// Si faltan las variables, se crea un cliente apuntando a la BD local para que la app
// arranque; cualquier llamada fallará con un error de red claro.
export const supabase = createClient<Database>(
  env.supabaseUrl || 'http://127.0.0.1:54321',
  env.supabaseAnonKey || 'missing-anon-key',
  {
    auth: { persistSession: true, autoRefreshToken: true },
  },
);
