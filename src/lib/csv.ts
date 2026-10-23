// Lector de CSV para los importadores (plantillas en data/templates/).
// Acepta coma o punto y coma (Excel en español guarda con ;), comillas, BOM y CRLF.

export type CsvRow = Record<string, string> & { _row: number };

export type ImportKind = 'groups' | 'students' | 'staff' | 'schedule' | 'sections' | 'guards';

export const TEMPLATE_HEADERS: Record<ImportKind, string[]> = {
  groups: ['grupo', 'salon', 'orden'],
  students: ['grupo', 'numero_lista', 'nombre_completo', 'sexo'],
  staff: ['nombre_completo', 'correo', 'roles', 'whatsapp'],
  schedule: ['grupo', 'dia', 'inicio', 'fin', 'materia', 'correo_maestro'],
  sections: ['salon_grupo', 'materia', 'grupo', 'numero_lista'],
  guards: ['dia', 'inicio', 'fin', 'correo_maestro'],
};

// Columnas que pueden faltar en el archivo (se toman como vacías).
const OPTIONAL_HEADERS: Record<ImportKind, string[]> = {
  groups: ['salon', 'orden'],
  students: [],
  staff: ['whatsapp'],
  schedule: ['correo_maestro'],
  sections: [],
  guards: ['correo_maestro'],
};

function detectDelimiter(firstLine: string): ',' | ';' {
  const commas = (firstLine.match(/,/g) ?? []).length;
  const semis = (firstLine.match(/;/g) ?? []).length;
  return semis > commas ? ';' : ',';
}

/** Divide el texto en filas de celdas respetando comillas ("a, b" y "" escapadas). */
export function parseCsvCells(text: string): string[][] {
  const clean = text.replace(/^\uFEFF/, '');
  const delimiter = detectDelimiter(clean.split(/\r?\n/, 1)[0] ?? '');
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let quoted = false;

  for (let i = 0; i < clean.length; i++) {
    const ch = clean[i];
    if (quoted) {
      if (ch === '"' && clean[i + 1] === '"') {
        cell += '"';
        i++;
      } else if (ch === '"') {
        quoted = false;
      } else {
        cell += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === delimiter) {
      row.push(cell);
      cell = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && clean[i + 1] === '\n') i++;
      row.push(cell);
      rows.push(row);
      row = [];
      cell = '';
    } else {
      cell += ch;
    }
  }
  if (cell !== '' || row.length) {
    row.push(cell);
    rows.push(row);
  }
  return rows;
}

const normalizeHeader = (h: string) =>
  h
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\s+/g, '_');

export type ParsedCsv = { ok: true; rows: CsvRow[] } | { ok: false; error: string };

/**
 * Lee el archivo y valida que traiga las columnas de la plantilla. Las filas vacías se
 * ignoran. `_row` es el número de línea en el archivo (la 1 es el encabezado), para que
 * los errores que devuelve la BD apunten a la línea que el usuario ve en Excel.
 */
export function parseImportCsv(text: string, kind: ImportKind): ParsedCsv {
  const cells = parseCsvCells(text);
  const header = cells[0]?.map(normalizeHeader) ?? [];
  const expected = TEMPLATE_HEADERS[kind];
  const missing = expected.filter(
    (h) => !header.includes(h) && !OPTIONAL_HEADERS[kind].includes(h),
  );
  if (missing.length) {
    return {
      ok: false,
      error: `Faltan columnas: ${missing.join(', ')}. Usa la plantilla (${expected.join(', ')}).`,
    };
  }

  const rows: CsvRow[] = [];
  cells.slice(1).forEach((line, i) => {
    if (line.every((c) => c.trim() === '')) return;
    const row = { _row: i + 2 } as CsvRow;
    for (const h of expected) {
      const idx = header.indexOf(h);
      row[h] = idx >= 0 ? (line[idx] ?? '').trim() : '';
    }
    rows.push(row);
  });

  if (!rows.length) return { ok: false, error: 'El archivo no tiene filas.' };
  return { ok: true, rows };
}
