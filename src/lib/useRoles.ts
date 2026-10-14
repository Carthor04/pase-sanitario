import { useSearchParams } from 'react-router';
import type { Role } from './nav';

const ALL: Role[] = ['teacher', 'prefect', 'nurse', 'coordinator', 'director', 'admin'];

/**
 * Roles del usuario actual. Temporal hasta la Fase 1 (login con Google):
 * en desarrollo se pueden probar con `?roles=prefect` o `?roles=coordinator,teacher`.
 */
export function useRoles(): Role[] {
  const [params] = useSearchParams();
  if (import.meta.env.DEV) {
    const fromUrl = (params.get('roles') ?? '')
      .split(',')
      .filter((r): r is Role => (ALL as string[]).includes(r));
    if (fromUrl.length) return fromUrl;
  }
  return ['teacher'];
}
