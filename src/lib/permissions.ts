// Ajustes → Permisos (solo admin): pestañas por rol y roles por persona. Las reglas viven en
// Postgres (permissions_overview, set_role_tabs, set_staff_roles); aquí solo se muestran.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type { Role } from './nav';
import { supabase } from './supabase';

export type PermissionStaff = {
  id: string;
  full_name: string;
  email: string;
  roles: Role[];
  active: boolean;
};

export type Permissions = {
  role_tabs: Partial<Record<Role, string[]>>;
  staff: PermissionStaff[];
};

export function usePermissions() {
  return useQuery({
    queryKey: ['permissions'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('permissions_overview');
      if (error) throw error;
      return data as unknown as Permissions;
    },
  });
}

type Change =
  { kind: 'role'; role: Role; tabs: string[] } | { kind: 'staff'; staffId: string; roles: Role[] };

/** Guarda un cambio y refresca la lista, el personal y el menú propio. */
export function useSavePermission() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (c: Change) => {
      const { error } =
        c.kind === 'role'
          ? await supabase.rpc('set_role_tabs', { p_role: c.role, p_tabs: c.tabs })
          : await supabase.rpc('set_staff_roles', { p_staff_id: c.staffId, p_roles: c.roles });
      if (error) throw error;
    },
    onSettled: () =>
      Promise.all(
        ['permissions', 'staff', 'me'].map((k) => queryClient.invalidateQueries({ queryKey: [k] })),
      ),
  });
}

/** Agrega o quita un elemento, sin repetir. */
export function toggle<T>(list: readonly T[], item: T): T[] {
  return list.includes(item) ? list.filter((x) => x !== item) : [...list, item];
}

/** Mismos elementos sin importar el orden. */
export function sameSet<T>(a: readonly T[], b: readonly T[]): boolean {
  return a.length === b.length && a.every((x) => b.includes(x));
}

/** Busca por nombre o correo, sin acentos ni mayúsculas. */
export function matchesStaff(p: PermissionStaff, query: string): boolean {
  const norm = (s: string) =>
    s
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '');
  const q = norm(query.trim());
  return !q || norm(p.full_name).includes(q) || norm(p.email).includes(q);
}
