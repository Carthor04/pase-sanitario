import { useQueryClient } from '@tanstack/react-query';
import { useId, useState, type ChangeEvent } from 'react';
import { Card, Notice, SectionLabel } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { parseImportCsv, TEMPLATE_HEADERS, type CsvRow, type ImportKind } from '@/lib/csv';
import type { Json } from '@/lib/database.types';
import { supabase } from '@/lib/supabase';
import alumnosUrl from '../../../data/templates/alumnos.csv?url';
import gruposUrl from '../../../data/templates/grupos.csv?url';
import horarioUrl from '../../../data/templates/horario.csv?url';
import personalUrl from '../../../data/templates/personal.csv?url';
import seccionesUrl from '../../../data/templates/secciones.csv?url';

const CONFIG: Record<
  ImportKind,
  {
    rpc: 'import_groups' | 'import_students' | 'import_staff' | 'import_schedule' | 'import_sections';
    template: string;
    file: string;
    help: string;
    invalidates: string[];
  }
> = {
  groups: {
    rpc: 'import_groups',
    template: gruposUrl,
    file: 'grupos.csv',
    help: 'Agrega grupos nuevos y actualiza salón y orden de los que ya existen.',
    invalidates: ['groups', 'my_groups'],
  },
  students: {
    rpc: 'import_students',
    template: alumnosUrl,
    file: 'alumnos.csv',
    help: 'Reemplaza la lista de cada grupo que venga en el archivo. Los alumnos que ya no aparecen se dan de baja (su historial se conserva).',
    invalidates: ['students'],
  },
  staff: {
    rpc: 'import_staff',
    template: personalUrl,
    file: 'personal.csv',
    help: 'Agrega o actualiza personal por correo. Roles separados por ; (teacher, prefect, nurse, coordinator, director, admin). Nadie se da de baja desde aquí.',
    invalidates: ['staff'],
  },
  schedule: {
    rpc: 'import_schedule',
    template: horarioUrl,
    file: 'horario.csv',
    help: 'Reemplaza el horario completo de cada grupo que venga en el archivo. Días de lunes a viernes, horas HH:MM.',
    invalidates: ['my_groups', 'current_class'],
  },
  sections: {
    rpc: 'import_sections',
    template: seccionesUrl,
    file: 'secciones.csv',
    help: 'Clases por nivel (como Inglés): en salon_grupo va el grupo cuyo salón se usa y en materia la misma materia del horario de ese salón (ej. Inglés básico). Reemplaza la lista de cada clase que venga en el archivo.',
    invalidates: ['roster'],
  },
};

type RowError = { row: number; message: string };
type ImportResult =
  { ok: true; summary: Record<string, number> } | { ok: false; errors: RowError[] };

const SUMMARY_LABELS: Record<string, string> = {
  inserted: 'nuevos',
  updated: 'actualizados',
  deactivated: 'dados de baja',
  replaced: 'clases reemplazadas',
  groups: 'grupos',
  sections: 'clases',
  students: 'alumnos',
};

export function ImportPanel({ kind, title }: { kind: ImportKind; title: string }) {
  const cfg = CONFIG[kind];
  const inputId = useId();
  const queryClient = useQueryClient();
  const [fileName, setFileName] = useState<string | null>(null);
  const [rows, setRows] = useState<CsvRow[] | null>(null);
  const [parseError, setParseError] = useState<string | null>(null);
  const [result, setResult] = useState<ImportResult | null>(null);
  const [busy, setBusy] = useState(false);

  async function onFile(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    setResult(null);
    setRows(null);
    setParseError(null);
    setFileName(file?.name ?? null);
    if (!file) return;
    const parsed = parseImportCsv(await file.text(), kind);
    if (parsed.ok) setRows(parsed.rows);
    else setParseError(parsed.error);
  }

  async function runImport() {
    if (!rows) return;
    setBusy(true);
    const { data, error } = await supabase.rpc(cfg.rpc, { p_rows: rows as unknown as Json });
    setBusy(false);
    if (error) {
      setResult({ ok: false, errors: [{ row: 0, message: error.message }] });
      return;
    }
    const res = data as unknown as ImportResult;
    setResult(res);
    if (res.ok) {
      setRows(null);
      await Promise.all(
        cfg.invalidates.map((key) => queryClient.invalidateQueries({ queryKey: [key] })),
      );
    }
  }

  return (
    <Card>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <SectionLabel>{title}</SectionLabel>
        <a href={cfg.template} download={cfg.file} className="text-[15px] font-bold text-accent">
          Descargar plantilla
        </a>
      </div>
      <p className="m-0 text-[15px] text-muted">{cfg.help}</p>
      <p className="m-0 text-[13px] text-muted">
        Columnas: <code>{TEMPLATE_HEADERS[kind].join(', ')}</code>. Guarda como CSV desde Excel o
        Google Sheets.
      </p>

      <div className="flex flex-wrap items-center gap-3">
        <label htmlFor={inputId} className={`${buttonClass.secondary} cursor-pointer`}>
          Elegir archivo CSV
        </label>
        <input
          id={inputId}
          type="file"
          accept=".csv,text/csv"
          onChange={onFile}
          className="sr-only"
        />
        <span className="text-[15px] text-muted">{fileName ?? 'Ningún archivo'}</span>
      </div>

      {parseError ? <Notice tone="error">{parseError}</Notice> : null}

      {rows ? (
        <div className="flex flex-wrap items-center gap-3">
          <span className="text-[15px]">
            <strong>{rows.length}</strong> filas listas para revisar.
          </span>
          <button type="button" className={buttonClass.primary} onClick={runImport} disabled={busy}>
            {busy ? 'Importando…' : 'Importar'}
          </button>
        </div>
      ) : null}

      {result?.ok ? (
        <Notice tone="ok">
          Importación lista:{' '}
          {Object.entries(result.summary)
            .map(([k, v]) => `${v} ${SUMMARY_LABELS[k] ?? k}`)
            .join(' · ')}
          .
        </Notice>
      ) : null}

      {result && !result.ok ? (
        <div className="flex flex-col gap-2">
          <Notice tone="error">
            No se importó nada: corrige{' '}
            {result.errors.length === 1 ? 'este error' : 'estos errores'} en el archivo y vuelve a
            subirlo.
          </Notice>
          <div className="max-h-[320px] overflow-auto rounded-btn border border-line">
            <table className="w-full border-collapse text-left text-[15px]">
              <thead className="sticky top-0 bg-ground">
                <tr>
                  <th className="px-3 py-2 font-bold">Línea</th>
                  <th className="px-3 py-2 font-bold">Error</th>
                </tr>
              </thead>
              <tbody>
                {result.errors.map((err, i) => (
                  <tr key={i} className="border-t border-line">
                    <td className="px-3 py-2 font-mono tabular-nums">{err.row || '—'}</td>
                    <td className="px-3 py-2">{err.message}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}
    </Card>
  );
}
