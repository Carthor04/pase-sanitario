export const ROLES = ['teacher', 'prefect', 'nurse', 'coordinator', 'director', 'admin'] as const;
export type Role = (typeof ROLES)[number];

export const ROLE_LABELS: Record<Role, string> = {
  teacher: 'Maestro',
  prefect: 'Prefectura',
  nurse: 'Enfermería',
  coordinator: 'Coordinación',
  director: 'Dirección',
  admin: 'Admin',
};

export type NavItem = { to: string; label: string };

const ITEMS = {
  grupo: { to: '/grupo', label: 'Mi grupo' },
  hoy: { to: '/enfermeria', label: 'Enfermería' },
  enVivo: { to: '/en-vivo', label: 'En vivo' },
  banos: { to: '/banos', label: 'Baños' },
  alertas: { to: '/alertas', label: 'Alertas' },
  reportes: { to: '/reportes', label: 'Reportes' },
  historial: { to: '/historial', label: 'Historial' },
  ajustes: { to: '/ajustes', label: 'Ajustes' },
  mas: { to: '/mas', label: 'Más' },
} satisfies Record<string, NavItem>;

type ItemKey = keyof typeof ITEMS;

// Navegación inferior por rol (SPEC §6).
export const navByRole: Record<Role, ItemKey[]> = {
  teacher: ['grupo', 'banos', 'alertas', 'mas'],
  prefect: ['enVivo', 'historial', 'mas'],
  nurse: ['hoy', 'historial'],
  coordinator: ['enVivo', 'reportes', 'historial', 'ajustes'],
  director: ['enVivo', 'reportes', 'historial', 'ajustes'],
  admin: ['enVivo', 'reportes', 'historial', 'ajustes'],
};

// Orden canónico cuando una persona tiene varios roles.
const ORDER: ItemKey[] = Object.keys(ITEMS) as ItemKey[];

// "En vivo" ya muestra baños y alertas; "Ajustes" ya cubre lo que va en "Más".
const SUPERSEDED_BY: Partial<Record<ItemKey, ItemKey>> = {
  banos: 'enVivo',
  alertas: 'enVivo',
  mas: 'ajustes',
};

export const MAX_NAV_ITEMS = 5;

export function navForRoles(roles: readonly Role[]): NavItem[] {
  const keys = new Set(roles.flatMap((r) => navByRole[r]));
  for (const [key, by] of Object.entries(SUPERSEDED_BY) as [ItemKey, ItemKey][]) {
    if (keys.has(by)) keys.delete(key);
  }
  let ordered = ORDER.filter((k) => keys.has(k));
  if (ordered.length > MAX_NAV_ITEMS) {
    ordered = [...ordered.slice(0, MAX_NAV_ITEMS - 1), 'mas'];
  }
  return ordered.map((k) => ITEMS[k]);
}
