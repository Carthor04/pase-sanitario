import type { Json } from './database.types';

export const PIN_ERRORS: Record<string, string> = {
  invalid: 'El PIN debe tener exactamente 4 dígitos.',
  taken: 'Ese PIN no está disponible, elige otro.',
  rate_limited: 'Demasiados intentos. Espera 15 minutos y vuelve a intentarlo.',
  not_found: 'Esa persona no está activa.',
};

/** Resultado de set_my_pin / set_staff_pin → mensaje de error o null si salió bien. */
export function pinResultError(data: Json): string | null {
  const res = (data ?? {}) as { ok?: boolean; error?: string };
  if (res.ok) return null;
  return PIN_ERRORS[res.error ?? ''] ?? 'No se pudo guardar el PIN.';
}
