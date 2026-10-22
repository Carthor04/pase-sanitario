export const ROLES = [
  'teacher',
  'prefect',
  'nurse',
  'coordinator',
  'director',
  'admin',
  'counselor',
] as const;
export type Role = (typeof ROLES)[number];

export const ROLE_LABELS: Record<Role, string> = {
  teacher: 'Maestro',
  prefect: 'Prefectura',
  nurse: 'Enfermería',
  coordinator: 'Coordinación',
  director: 'Dirección',
  admin: 'Admin',
  counselor: 'Psicopedagogía',
};

export type NavItem = { to: string; label: string };

const ITEMS = {
  enVivo: { to: '/en-vivo', label: 'En vivo' },
  grupo: { to: '/grupo', label: 'Mi grupo' },
  hoy: { to: '/enfermeria', label: 'Enfermería' },
  banos: { to: '/banos', label: 'Baños' },
  alertas: { to: '/alertas', label: 'Alertas' },
  reportes: { to: '/reportes', label: 'Reportes' },
  historial: { to: '/historial', label: 'Historial' },
  ajustes: { to: '/ajustes', label: 'Ajustes' },
  perfil: { to: '/perfil', label: 'Perfil' },
} satisfies Record<string, NavItem>;

type ItemKey = keyof typeof ITEMS;

/** Pestañas que el admin reparte por rol (Ajustes → Permisos). Perfil y Ajustes van fijos. */
export const GRANTABLE_TABS = [
  { id: 'en-vivo', label: 'En vivo' },
  { id: 'grupo', label: 'Mi grupo' },
  { id: 'banos', label: 'Baños' },
  { id: 'alertas', label: 'Alertas' },
  { id: 'enfermeria', label: 'Enfermería' },
  { id: 'reportes', label: 'Reportes' },
  { id: 'historial', label: 'Historial' },
] as const;
export type TabId = (typeof GRANTABLE_TABS)[number]['id'];

const FIXED: ItemKey[] = ['ajustes', 'perfil'];
const keyForTab = (tab: string) =>
  GRANTABLE_TABS.some((t) => t.id === tab)
    ? (Object.keys(ITEMS) as ItemKey[]).find((k) => ITEMS[k].to === `/${tab}`)
    : undefined;

// Navegación inferior por rol (SPEC §6). Es la de omisión: la que vale la trae me().tabs.
export const navByRole: Record<Role, ItemKey[]> = {
  teacher: ['grupo', 'banos', 'alertas', 'perfil'],
  // Prefectura y coordinación también autorizan salidas desde "Mi grupo".
  prefect: ['enVivo', 'grupo', 'historial', 'perfil'],
  nurse: ['hoy', 'historial'],
  coordinator: ['enVivo', 'grupo', 'reportes', 'historial', 'ajustes'],
  director: ['enVivo', 'reportes', 'historial', 'ajustes'],
  admin: ['enVivo', 'reportes', 'historial', 'ajustes'],
  // Psicopedagogía ve los baños en vivo (solo lectura).
  counselor: ['enVivo', 'perfil'],
};

// Orden canónico cuando una persona tiene varios roles.
const ORDER: ItemKey[] = Object.keys(ITEMS) as ItemKey[];

// "En vivo" ya muestra baños y alertas; "Ajustes" ya cubre lo que va en "Perfil".
const SUPERSEDED_BY: Partial<Record<ItemKey, ItemKey>> = {
  banos: 'enVivo',
  alertas: 'enVivo',
  perfil: 'ajustes',
};

export const MAX_NAV_ITEMS = 5;

/**
 * Menú de una persona. `tabs` son sus pestañas según Ajustes → Permisos (me().tabs); sin
 * ellas se usa el menú por omisión de cada rol. Perfil y Ajustes siempre salen del rol.
 */
export function navForRoles(roles: readonly Role[], tabs?: readonly string[]): NavItem[] {
  const keys = new Set(
    tabs
      ? [
          ...tabs.map(keyForTab).filter((k): k is ItemKey => k !== undefined),
          ...roles.flatMap((r) => navByRole[r].filter((k) => FIXED.includes(k))),
        ]
      : roles.flatMap((r) => navByRole[r]),
  );
  for (const [key, by] of Object.entries(SUPERSEDED_BY) as [ItemKey, ItemKey][]) {
    if (keys.has(by)) keys.delete(key);
  }
  let ordered = ORDER.filter((k) => keys.has(k));
  if (ordered.length > MAX_NAV_ITEMS) {
    ordered = [...ordered.slice(0, MAX_NAV_ITEMS - 1), 'perfil'];
  }
  return ordered.map((k) => ITEMS[k]);
}
