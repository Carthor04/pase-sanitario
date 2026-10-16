import { useEffect, useId, useState } from 'react';
import { Card, Loading, Notice, PageTitle } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { errorMessage } from '@/lib/live';
import { hm } from '@/lib/monitor';
import { useGroups } from '@/lib/queries';
import {
  EVENT_LABELS,
  closureText,
  todayMx,
  useHistory,
  useTimeline,
  type HistoryRow,
} from '@/lib/reports';

const dateFmt = new Intl.DateTimeFormat('es-MX', {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  timeZone: 'America/Mexico_City',
});

/** Historial con búsqueda por alumno, grupo, maestro y fecha (SPEC §9). */
export function History() {
  const ids = { from: useId(), to: useId(), q: useId(), g: useId() };
  const groups = useGroups();
  const today = todayMx();
  const [from, setFrom] = useState(today);
  const [to, setTo] = useState(today);
  const [query, setQuery] = useState('');
  const [debounced, setDebounced] = useState('');
  const [groupId, setGroupId] = useState('');
  const [open, setOpen] = useState<HistoryRow | null>(null);

  useEffect(() => {
    const id = window.setTimeout(() => setDebounced(query.trim()), 300);
    return () => window.clearTimeout(id);
  }, [query]);

  const history = useHistory({ from, to, query: debounced, groupId });

  return (
    <div className="flex flex-col gap-4">
      <PageTitle>Historial</PageTitle>
      <Card className="grid gap-3 sm:grid-cols-[1fr_1fr_2fr_1fr]">
        <Field id={ids.from} label="Desde">
          <input
            id={ids.from}
            type="date"
            value={from}
            max={to}
            onChange={(e) => setFrom(e.target.value)}
            className={inputClass}
          />
        </Field>
        <Field id={ids.to} label="Hasta">
          <input
            id={ids.to}
            type="date"
            value={to}
            min={from}
            onChange={(e) => setTo(e.target.value)}
            className={inputClass}
          />
        </Field>
        <Field id={ids.q} label="Buscar">
          <input
            id={ids.q}
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Alumno, grupo o maestro"
            className={inputClass}
          />
        </Field>
        <Field id={ids.g} label="Grupo">
          <select
            id={ids.g}
            value={groupId}
            onChange={(e) => setGroupId(e.target.value)}
            className={inputClass}
          >
            <option value="">Todos</option>
            {groups.data?.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name}
              </option>
            ))}
          </select>
        </Field>
      </Card>

      {history.isPending ? <Loading /> : null}
      {history.isError ? <Notice tone="error">{errorMessage(history.error)}</Notice> : null}
      {history.data ? (
        <span className="text-[15px] text-muted">
          {history.data.length === 200
            ? 'Mostrando los 200 más recientes'
            : `${history.data.length} movimientos`}
        </span>
      ) : null}

      <ul className="m-0 flex list-none flex-col gap-2 p-0">
        {history.data?.map((r) => (
          <li key={r.id}>
            <button
              type="button"
              onClick={() => setOpen(r)}
              className={`flex w-full flex-wrap items-center gap-x-4 gap-y-1 rounded-btn-lg border bg-surface px-4 py-3 text-left ${
                r.alert ? 'border-alert-bd' : 'border-line'
              }`}
            >
              <span className="w-[92px] shrink-0 font-mono text-[14px] tabular-nums text-muted">
                {dateFmt.format(new Date(r.requested_at))}
                <br />
                {hm(r.started_at ?? r.requested_at)}
                {r.ended_at ? `–${hm(r.ended_at)}` : ''}
              </span>
              <span className="flex min-w-0 flex-1 flex-col">
                <span className="font-bold">
                  {r.full_name} · {r.group_name}
                </span>
                <span className="text-[14px] text-muted">
                  {r.destination}
                  {r.period_subject ? ` · en ${r.period_subject}` : ''} · autorizó{' '}
                  {r.opened_by ?? '—'}
                  {r.from_device ? ' (PIN)' : ''}
                </span>
              </span>
              <span className="flex flex-col items-end">
                <span
                  className={`font-mono tabular-nums ${r.alert ? 'font-bold text-alert-fg' : ''}`}
                >
                  {r.minutes != null ? `${r.minutes} min` : '—'}
                </span>
                <span className="text-[13px] text-muted">{closureText(r)}</span>
              </span>
            </button>
          </li>
        ))}
      </ul>
      {history.data && history.data.length === 0 ? (
        <Notice>Sin movimientos con esos filtros.</Notice>
      ) : null}

      {open ? <TimelineDialog row={open} onClose={() => setOpen(null)} /> : null}
    </div>
  );
}

const inputClass =
  'min-h-btn w-full rounded-btn border border-line-strong bg-surface px-3 text-[16px]';

function Field({ id, label, children }: { id: string; label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={id} className="text-[14px] font-bold">
        {label}
      </label>
      {children}
    </div>
  );
}

const timeFmt = new Intl.DateTimeFormat('es-MX', {
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hour12: false,
  timeZone: 'America/Mexico_City',
});

/** Bitácora de un pase: cada cambio con quién, desde dónde y cuándo. */
function TimelineDialog({ row, onClose }: { row: HistoryRow; onClose: () => void }) {
  const timeline = useTimeline(row.id);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-40 flex items-end justify-center bg-ink/50 sm:items-center sm:p-6"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={`Bitácora de ${row.full_name}`}
        onClick={(e) => e.stopPropagation()}
        className="pb-safe flex max-h-[85vh] w-full flex-col gap-3 overflow-y-auto rounded-t-[22px] bg-surface p-5 sm:max-w-[520px] sm:rounded-card-lg sm:p-7"
      >
        <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-muted">
          {row.group_name} · {row.destination}
        </span>
        <h2 className="m-0 font-display text-[24px] font-bold">
          {row.full_name}{' '}
          <span className="font-mono text-[18px] text-muted">#{row.list_number}</span>
        </h2>
        <p className="m-0 text-[15px]">{closureText(row)}</p>
        {timeline.isPending ? <Loading /> : null}
        <ol className="m-0 flex list-none flex-col gap-2 border-l-2 border-line p-0 pl-4">
          {timeline.data?.map((e, i) => (
            <li key={i} className="flex flex-col">
              <span className="font-bold">{EVENT_LABELS[e.type] ?? e.type}</span>
              <span className="text-[14px] text-muted">
                <span className="font-mono tabular-nums">{timeFmt.format(new Date(e.at))}</span> ·{' '}
                {e.actor ?? 'Sistema'}
                {e.from_device ? ' · computadora del salón' : ''}
                {typeof e.payload.reason === 'string' ? ` · “${e.payload.reason}”` : ''}
              </span>
            </li>
          ))}
        </ol>
        <button type="button" onClick={onClose} className={buttonClass.secondary}>
          Cerrar
        </button>
      </div>
    </div>
  );
}
