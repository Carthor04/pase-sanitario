// Orden de las listas de alumnos: alfabético por nombre completo, que se captura con los
// apellidos primero ("Aguirre Pérez Uriel"). Reglas del español: sin distinguir acentos ni
// mayúsculas, y la ñ después de la n.
const collator = new Intl.Collator('es-MX', { sensitivity: 'base' });

export function byName<T extends { full_name: string; list_number: number }>(a: T, b: T): number {
  return collator.compare(a.full_name, b.full_name) || a.list_number - b.list_number;
}
