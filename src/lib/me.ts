import type { Json } from './database.types';
import { ROLES, type Role } from './nav';

export type StaffMe = {
  kind: 'staff';
  id: string;
  full_name: string;
  email: string;
  roles: Role[];
  /** Pestañas que ve según Ajustes → Permisos; sin ellas, el menú por omisión del rol. */
  tabs?: string[];
  has_pin: boolean;
};
export type DeviceMe = {
  kind: 'device';
  id: string;
  label: string | null;
  group_id: string;
  group_name: string;
};
export type NoneMe = { kind: 'none'; email: string | null; anonymous: boolean };
export type Me = StaffMe | DeviceMe | NoneMe;

type Obj = Record<string, Json | undefined>;
const str = (v: Json | undefined) => (typeof v === 'string' ? v : null);

/** Convierte la respuesta de la RPC `me()` en un tipo seguro. */
export function parseMe(raw: Json): Me {
  const o = (raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {}) as Obj;
  if (o.kind === 'staff') {
    const roles = Array.isArray(o.roles)
      ? o.roles.filter(
          (r): r is Role => typeof r === 'string' && (ROLES as readonly string[]).includes(r),
        )
      : [];
    return {
      kind: 'staff',
      id: str(o.id) ?? '',
      full_name: str(o.full_name) ?? '',
      email: str(o.email) ?? '',
      roles,
      ...(Array.isArray(o.tabs)
        ? { tabs: o.tabs.filter((t): t is string => typeof t === 'string') }
        : {}),
      has_pin: o.has_pin === true,
    };
  }
  if (o.kind === 'device') {
    return {
      kind: 'device',
      id: str(o.id) ?? '',
      label: str(o.label),
      group_id: str(o.group_id) ?? '',
      group_name: str(o.group_name) ?? '',
    };
  }
  return { kind: 'none', email: str(o.email), anonymous: o.anonymous === true };
}

const MANAGER_ROLES: Role[] = ['coordinator', 'director', 'admin'];
export const canManage = (roles: readonly Role[]) => roles.some((r) => MANAGER_ROLES.includes(r));
