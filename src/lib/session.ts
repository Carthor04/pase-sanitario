import type { Session } from '@supabase/supabase-js';
import { useQuery, type QueryClient } from '@tanstack/react-query';
import { createContext, useContext } from 'react';
import { parseMe, type DeviceMe, type StaffMe } from './me';
import { supabase } from './supabase';

/** undefined = cargando; null = sin sesión. */
export const SessionContext = createContext<Session | null | undefined>(undefined);
export const useSession = () => useContext(SessionContext);

export function useMe() {
  const session = useSession();
  return useQuery({
    queryKey: ['me', session?.user.id],
    enabled: Boolean(session),
    staleTime: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('me');
      if (error) throw error;
      return parseMe(data);
    },
  });
}

export const StaffContext = createContext<StaffMe | null>(null);
export const DeviceContext = createContext<DeviceMe | null>(null);

export function useStaff(): StaffMe {
  const staff = useContext(StaffContext);
  if (!staff) throw new Error('useStaff fuera de RequireStaff');
  return staff;
}

export function useDevice(): DeviceMe {
  const device = useContext(DeviceContext);
  if (!device) throw new Error('useDevice fuera de RequireDevice');
  return device;
}

export async function signOut(queryClient: QueryClient) {
  await supabase.auth.signOut();
  queryClient.clear();
}

/** Inicia sesión con Google y vuelve a la app (la URL debe estar en Redirect URLs de Supabase). */
export function signInWithGoogle() {
  return supabase.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo: `${window.location.origin}/`,
      queryParams: { prompt: 'select_account' },
    },
  });
}

/**
 * Error que Supabase deja en la URL al volver de Google (por ejemplo cuando el trigger
 * rechaza un correo que no es de personal activo). Lee query y hash.
 */
export function readAuthError(location: { search: string; hash: string }): string | null {
  const params = new URLSearchParams(location.search);
  const hash = new URLSearchParams(location.hash.replace(/^#/, ''));
  return (
    params.get('error_description') ??
    hash.get('error_description') ??
    params.get('error') ??
    hash.get('error')
  );
}
