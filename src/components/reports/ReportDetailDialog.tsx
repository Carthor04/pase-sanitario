import { useEffect, useState } from 'react';
import { Loading, Notice } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { errorMessage } from '@/lib/live';
import { hm } from '@/lib/monitor';
import { sortDetail, useReportDetail, type DetailFilter, type DetailRow } from '@/lib/reports';

const dayFmt = new Intl.DateTimeFormat('es-MX', {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  timeZone: 'America/Mexico_City',
});

function stateText(r: DetailRow): string {
  if (r.minutes != null) return `${Number(r.minutes).toFixed(1)} min`;
  if (r.status === 'released') return 'Liberado';
  if (r.status === 'cancelled') return 'Cancelado';
  return 'En curso';
}

/** Ventana con los alumnos que salieron en el cuadro del reporte que se tocó. */
export function ReportDetailDialog({
  from,
  to,
  filter,
  onClose,
}: {
  from: string;
  to: string;
  filter: DetailFilter;
  onClose: () => void;
}) {
  const detail = useReportDetail(from, to, filter);
  const [byMinutes, setByMinutes] = useState(Boolean(filter.byMinutes));
  const multiDay = from !== to;

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const rows = detail.data ? sortDetail(detail.data, byMinutes) : [];
  const timed = rows.filter((r) => r.minutes != null);
  const avg = timed.length ? timed.reduce((s, r) => s + Number(r.minutes), 0) / timed.length : null;

  return (
    <div
      className="fixed inset-0 z-40 flex items-end justify-center bg-ink/50 sm:items-center sm:p-6"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={filter.title}
        onClick={(e) => e.stopPropagation()}
        className="pb-safe flex max-h-[88vh] w-full flex-col gap-3 overflow-y-auto rounded-t-[22px] bg-surface p-5 sm:max-w-[640px] sm:rounded-card-lg sm:p-7"
      >
        <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-muted">
          Quién salió
        </span>
        <h2 className="m-0 font-display text-[22px] font-bold sm:text-[26px]">{filter.title}</h2>

        {detail.isPending ? <Loading /> : null}
        {detail.isError ? <Notice tone="error">{errorMessage(detail.error)}</Notice> : null}

        {detail.data ? (
          <>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="text-[15px] text-muted">
                {rows.length} {rows.length === 1 ? 'salida' : 'salidas'}
                {avg != null ? ` · promedio ${avg.toFixed(1)} min` : ''}
                {rows.length >= 1000 ? ' · se muestran las primeras 1000' : ''}
              </span>
              <div role="group" aria-label="Ordenar" className="flex gap-1">
                {[
                  { v: false, label: 'Por hora' },
                  { v: true, label: 'Más tiempo' },
                ].map((o) => (
                  <button
                    key={o.label}
                    type="button"
                    aria-pressed={byMinutes === o.v}
                    onClick={() => setByMinutes(o.v)}
                    className={`min-h-touch rounded-btn border px-3 text-[14px] font-bold ${
                      byMinutes === o.v
                        ? 'border-ink bg-ink text-white'
                        : 'border-line-strong bg-surface'
                    }`}
                  >
                    {o.label}
                  </button>
                ))}
              </div>
            </div>

            {rows.length === 0 ? (
              <p className="m-0 text-[15px] text-muted">Nadie salió en este cuadro.</p>
            ) : (
              <ol className="m-0 flex list-none flex-col gap-1.5 p-0">
                {rows.map((r) => (
                  <li
                    key={r.id}
                    className={`flex flex-col gap-0.5 rounded-btn border px-3 py-2 ${
                      r.alert ? 'border-alert-bd bg-alert-bg' : 'border-line'
                    }`}
                  >
                    <span className="flex flex-wrap items-baseline justify-between gap-x-3">
                      <span className="min-w-0 font-bold">
                        {r.full_name}
                        <span className="font-normal text-muted"> · {r.group_name}</span>
                      </span>
                      <span
                        className={`shrink-0 font-mono font-semibold tabular-nums ${
                          r.alert ? 'text-alert-fg' : ''
                        }`}
                      >
                        {stateText(r)}
                        {r.alert ? ' · ⚠ alerta' : ''}
                      </span>
                    </span>
                    <span className="text-[14px] text-muted">
                      <span className="font-mono tabular-nums">
                        {multiDay ? `${dayFmt.format(new Date(r.started_at))} · ` : ''}
                        {hm(r.started_at)}
                        {r.ended_at ? `–${hm(r.ended_at)}` : ''}
                      </span>
                      {' · '}
                      {r.destination}
                      {r.subject ? ` · en ${r.subject}` : ' · sin clase registrada'}
                      {r.opened_by ? ` · autorizó ${r.opened_by}` : ''}
                      {r.queued ? ' · hizo fila' : ''}
                    </span>
                  </li>
                ))}
              </ol>
            )}
          </>
        ) : null}

        <button type="button" onClick={onClose} className={buttonClass.secondary}>
          Cerrar
        </button>
      </div>
    </div>
  );
}
