import { useId, useState } from 'react';
import { ReportDetailDialog } from '@/components/reports/ReportDetailDialog';
import { Card, Loading, Notice, PageTitle, SectionLabel } from '@/components/ui/Page';
import { errorMessage } from '@/lib/live';
import { hm } from '@/lib/monitor';
import {
  RANGE_LABELS,
  closureText,
  heatmapMatrix,
  rangeFor,
  rangeTitle,
  useHistory,
  useReport,
  type DetailFilter,
  type RangeKey,
  type Report,
} from '@/lib/reports';

const DAYS = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie'];
const DAY_NAMES = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes'];

type OpenDetail = (f: DetailFilter) => void;
const fmtMin = (n: number | null | undefined) => (n == null ? '—' : `${Number(n).toFixed(1)} min`);

const dayTimeFmt = new Intl.DateTimeFormat('es-MX', {
  weekday: 'long',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
  timeZone: 'America/Mexico_City',
});

/** Reportes de Coordinación y Dirección (SPEC §9). */
export function Reports() {
  const selectId = useId();
  const [range, setRange] = useState<RangeKey>('week');
  const { from, to } = rangeFor(range);
  const report = useReport(from, to);

  return (
    <div className="flex flex-col gap-4 sm:gap-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="flex flex-col">
          <PageTitle>Reportes</PageTitle>
          <span className="text-[15px] text-muted sm:text-[17px]">
            {range === 'today' ? 'Hoy, ' : 'Periodo '}
            {rangeTitle(from, to)}
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <label htmlFor={selectId} className="sr-only">
            Periodo
          </label>
          <select
            id={selectId}
            value={range}
            onChange={(e) => setRange(e.target.value as RangeKey)}
            className="min-h-btn rounded-btn border border-line-strong bg-surface px-3 text-[16px]"
          >
            {(Object.keys(RANGE_LABELS) as RangeKey[]).map((k) => (
              <option key={k} value={k}>
                {RANGE_LABELS[k]}
              </option>
            ))}
          </select>
          <button
            type="button"
            disabled
            title="Pendiente: requiere la cuenta de servicio de Google"
            className="min-h-btn rounded-btn bg-free-fg px-4 text-[16px] font-bold text-white opacity-50"
          >
            Exportar a Google Sheets
          </button>
        </div>
      </div>

      {report.isPending ? <Loading /> : null}
      {report.isError ? <Notice tone="error">{errorMessage(report.error)}</Notice> : null}
      {report.data ? <ReportBody report={report.data} from={from} to={to} /> : null}
    </div>
  );
}

/** Exportado para la vista de diseño de desarrollo. */
export function ReportBody({ report, from, to }: { report: Report; from: string; to: string }) {
  const t = report.totals;
  const mq = report.max_queue;
  const [detail, setDetail] = useState<DetailFilter | null>(null);
  return (
    <>
      <section aria-label="Resumen" className="grid grid-cols-2 gap-3 lg:grid-cols-4 lg:gap-4">
        <Stat
          label="Salidas"
          value={String(t.exits)}
          sub={`${t.bathroom} baño · ${t.nurse} enfermería`}
          onClick={() => setDetail({ title: 'Todas las salidas' })}
        />
        <Stat
          label="Tiempo promedio"
          value={fmtMin(t.avg_minutes)}
          sub={`Hombres ${t.avg_minutes_h ?? '—'} · Mujeres ${t.avg_minutes_m ?? '—'}`}
          onClick={() =>
            setDetail({
              title: 'Salidas al baño · más tiempo fuera',
              destination: 'bathroom',
              byMinutes: true,
            })
          }
        />
        <Stat
          label="Alertas"
          value={String(report.alerts.count)}
          tone="alert"
          sub={`${report.alerts.acknowledged_fast} atendidas en menos de 3 min`}
          onClick={() =>
            setDetail({ title: 'Salidas con alerta', alertsOnly: true, byMinutes: true })
          }
        />
        <Stat
          label="Fila máxima"
          value={String(mq?.size ?? 0)}
          tone="wait"
          sub={mq ? `${mq.destination} · ${dayTimeFmt.format(new Date(mq.at))}` : 'Sin fila'}
        />
      </section>

      <Heatmap report={report} onOpen={setDetail} />

      <div className="grid gap-4 lg:grid-cols-[2fr_1fr]">
        <ByGroup report={report} onOpen={setDetail} />
        <Review report={report} />
      </div>

      <Recent from={from} to={to} />

      {detail ? (
        <ReportDetailDialog from={from} to={to} filter={detail} onClose={() => setDetail(null)} />
      ) : null}
    </>
  );
}

function Stat({
  label,
  value,
  sub,
  tone,
  onClick,
}: {
  label: string;
  value: string;
  sub: string;
  tone?: 'alert' | 'wait';
  onClick?: () => void;
}) {
  const body = (
    <>
      <SectionLabel>{label}</SectionLabel>
      <span
        className={`font-mono text-[28px] font-semibold tabular-nums leading-tight sm:text-[40px] ${
          tone === 'alert' ? 'text-alert-fg' : tone === 'wait' ? 'text-wait-fg' : ''
        }`}
      >
        {value}
      </span>
      <span className="hidden text-[14px] text-muted sm:inline">{sub}</span>
      {onClick ? <span className="text-[13px] font-bold text-accent">Ver alumnos ›</span> : null}
    </>
  );
  if (!onClick) return <Card className="gap-1 p-4 sm:p-5">{body}</Card>;
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={`${label}: ${value}. Ver alumnos`}
      className="flex flex-col gap-1 rounded-card border border-line bg-surface p-4 text-left transition hover:border-accent focus-visible:outline focus-visible:outline-2 focus-visible:outline-accent sm:p-5"
    >
      {body}
    </button>
  );
}

function Heatmap({ report, onOpen }: { report: Report; onOpen: OpenDetail }) {
  const [dest, setDest] = useState<'bath_h' | 'bath_m'>('bath_h');
  const m = heatmapMatrix(report, dest);
  const label = dest === 'bath_h' ? 'Baño hombres' : 'Baño mujeres';
  return (
    <Card>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="m-0 font-display text-[20px] font-bold sm:text-[24px]">
          {label} · salidas por hora
        </h2>
        <div role="group" aria-label="Baño" className="flex gap-1">
          {(['bath_h', 'bath_m'] as const).map((d) => (
            <button
              key={d}
              type="button"
              aria-pressed={dest === d}
              onClick={() => setDest(d)}
              className={`min-h-touch rounded-btn border px-3 text-[15px] font-bold ${
                dest === d ? 'border-ink bg-ink text-white' : 'border-line-strong bg-surface'
              }`}
            >
              {d === 'bath_h' ? 'Hombres' : 'Mujeres'}
            </button>
          ))}
        </div>
      </div>
      <p className="m-0 text-[14px] text-muted">
        Cada cuadro es el número de salidas en esa hora. Los cuadros con borde tuvieron fila. Toca
        un cuadro para ver quién salió.
      </p>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[280px] border-separate border-spacing-1 text-center">
          <thead>
            <tr>
              <th />
              {m.hours.map((h) => (
                <th key={h} className="font-mono text-[12px] font-normal text-muted sm:text-[14px]">
                  {h}
                  <span className="hidden sm:inline">:00</span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {m.rows.map((row, i) => (
              <tr key={i}>
                <th className="pr-1 text-left font-mono text-[13px] font-normal text-muted">
                  {DAYS[i]}
                </th>
                {row.map((c) => {
                  const a = c.count / m.max;
                  return (
                    <td key={c.hour} className="p-0">
                      <button
                        type="button"
                        disabled={!c.count}
                        onClick={() =>
                          onOpen({
                            title: `${label} · ${DAY_NAMES[i]} ${c.hour}:00–${c.hour}:59`,
                            destination: dest,
                            weekday: c.weekday,
                            hour: c.hour,
                          })
                        }
                        title={`${DAYS[i]} ${c.hour}:00 · ${c.count} salidas${c.queued ? ' · hubo fila' : ''}`}
                        aria-label={`${DAYS[i]} ${c.hour}:00, ${c.count} salidas${c.queued ? ', hubo fila' : ''}`}
                        className={`h-10 w-full min-w-[30px] rounded-[8px] font-mono text-[14px] font-semibold tabular-nums enabled:cursor-pointer enabled:hover:ring-2 enabled:hover:ring-ink sm:h-12 sm:text-[16px] ${
                          c.queued ? 'outline outline-2 -outline-offset-2 outline-wait-bd' : ''
                        }`}
                        style={{
                          backgroundColor: c.count
                            ? `rgba(29, 78, 137, ${0.15 + a * 0.8})`
                            : '#EEF1F4',
                          color: a > 0.55 ? '#fff' : '#15212C',
                        }}
                      >
                        {c.count || ''}
                      </button>
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

function ByGroup({ report, onOpen }: { report: Report; onOpen: OpenDetail }) {
  const max = Math.max(1, ...report.by_group.map((g) => g.exits));
  const openGroup = (g: Report['by_group'][number]) =>
    onOpen({ title: `Salidas de ${g.group_name}`, groupId: g.group_id });
  return (
    <Card>
      <div className="flex flex-col">
        <h2 className="m-0 font-display text-[20px] font-bold sm:text-[24px]">Por grupo</h2>
        <span className="text-[14px] text-muted">
          Toca un grupo para ver quién salió, o el número de alertas para ver solo esas.
        </span>
      </div>
      <table className="w-full border-collapse text-left">
        <thead>
          <tr className="border-b border-line text-[12px] uppercase tracking-[0.08em] text-muted">
            <th className="py-2 font-bold">Grupo</th>
            <th className="py-2 font-bold">Salidas</th>
            <th className="hidden py-2 sm:table-cell" />
            <th className="hidden py-2 font-bold sm:table-cell">Prom. fuera</th>
            <th className="py-2 text-right font-bold">Alertas</th>
          </tr>
        </thead>
        <tbody>
          {report.by_group.map((g) => (
            <tr
              key={g.group_id}
              className={`border-b border-line last:border-0 ${
                g.exits ? 'cursor-pointer hover:bg-[#F3F6F9]' : ''
              }`}
              onClick={() => (g.exits ? openGroup(g) : undefined)}
            >
              <td className="py-1">
                <button
                  type="button"
                  disabled={!g.exits}
                  onClick={(e) => {
                    e.stopPropagation();
                    openGroup(g);
                  }}
                  className="min-h-touch pr-3 text-left font-bold text-accent underline-offset-2 hover:underline disabled:text-ink disabled:no-underline"
                >
                  {g.group_name}
                </button>
              </td>
              <td className="py-2.5 font-mono tabular-nums">{g.exits}</td>
              <td className="hidden w-[40%] py-2.5 pr-4 sm:table-cell">
                <span className="block h-2 rounded-full bg-[#E6EBF0]" aria-hidden="true">
                  <span
                    className="block h-2 rounded-full bg-accent"
                    style={{ width: `${(g.exits / max) * 100}%` }}
                  />
                </span>
              </td>
              <td className="hidden py-2.5 font-mono tabular-nums sm:table-cell">
                {fmtMin(g.avg_minutes)}
              </td>
              <td className="py-1 text-right">
                <button
                  type="button"
                  disabled={!g.alerts}
                  aria-label={`${g.alerts} alertas en ${g.group_name}`}
                  onClick={(e) => {
                    e.stopPropagation();
                    onOpen({
                      title: `Alertas de ${g.group_name}`,
                      groupId: g.group_id,
                      alertsOnly: true,
                      byMinutes: true,
                    });
                  }}
                  className={`inline-flex min-h-touch min-w-[44px] items-center justify-center rounded-chip px-2 font-bold enabled:hover:ring-2 enabled:hover:ring-alert-bd ${
                    g.alerts >= 2
                      ? 'bg-alert-bg text-alert-fg'
                      : g.alerts === 1
                        ? 'bg-wait-bg text-wait-fg'
                        : 'bg-free-bg text-free-fg'
                  }`}
                >
                  {g.alerts}
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  );
}

function Review({ report }: { report: Report }) {
  return (
    <Card>
      <div className="flex flex-col">
        <h2 className="m-0 font-display text-[20px] font-bold sm:text-[24px]">A revisar</h2>
        <span className="text-[14px] text-muted">
          {report.thresholds.alerts} o más alertas, más de {report.thresholds.exits} salidas o 3+
          visitas a enfermería en el periodo
        </span>
      </div>
      {report.review.length === 0 ? (
        <span className="text-[15px] text-muted">Nadie en este periodo.</span>
      ) : null}
      <ul className="m-0 flex list-none flex-col gap-2 p-0">
        {report.review.map((r) => (
          <li
            key={r.student_id}
            className="flex items-start justify-between gap-2 rounded-btn-lg border border-line p-3"
          >
            <div className="flex min-w-0 flex-col">
              <span className="font-bold">{r.full_name}</span>
              <span className="text-[13px] text-muted">
                {r.group_name} · {r.exits} salidas · prom. {fmtMin(r.avg_minutes)}
                {r.top_subject ? ` · casi siempre en ${r.top_subject}` : ''}
              </span>
            </div>
            <span
              className={`shrink-0 rounded-chip px-2.5 py-0.5 text-[13px] font-bold ${
                r.alerts >= report.thresholds.alerts
                  ? 'bg-alert-bg text-alert-fg'
                  : r.exits > report.thresholds.exits
                    ? 'bg-wait-bg text-wait-fg'
                    : 'bg-nurse-bg text-nurse-fg'
              }`}
            >
              {r.alerts >= report.thresholds.alerts
                ? `${r.alerts} alertas`
                : r.exits > report.thresholds.exits
                  ? `${r.exits} salidas`
                  : `${r.nurse} enfermería`}
            </span>
          </li>
        ))}
      </ul>
    </Card>
  );
}

function Recent({ from, to }: { from: string; to: string }) {
  const searchId = useId();
  const [query, setQuery] = useState('');
  const history = useHistory({ from, to, query, groupId: '' });
  return (
    <Card className="hidden sm:flex">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="m-0 font-display text-[24px] font-bold">Movimientos</h2>
        <label htmlFor={searchId} className="sr-only">
          Buscar
        </label>
        <input
          id={searchId}
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Buscar alumno, grupo o maestro"
          className="min-h-btn w-[320px] rounded-btn border border-line-strong px-3 text-[16px]"
        />
      </div>
      {history.isPending ? <Loading /> : null}
      <div className="overflow-x-auto">
        <table className="w-full border-collapse text-left text-[15px]">
          <thead>
            <tr className="border-b border-line text-[12px] uppercase tracking-[0.08em] text-muted">
              <th className="py-2">Hora</th>
              <th className="py-2">Alumno</th>
              <th className="py-2">Destino</th>
              <th className="py-2">Fuera</th>
              <th className="py-2">Autorizó</th>
              <th className="py-2">Cierre</th>
            </tr>
          </thead>
          <tbody>
            {history.data?.slice(0, 50).map((r) => (
              <tr key={r.id} className="border-b border-line last:border-0">
                <td className="py-2 font-mono tabular-nums">
                  {hm(r.started_at ?? r.requested_at)}
                </td>
                <td className="py-2 font-bold">
                  {r.full_name} · {r.group_name}
                </td>
                <td className="py-2">{r.destination}</td>
                <td
                  className={`py-2 font-mono tabular-nums ${r.alert ? 'font-bold text-alert-fg' : ''}`}
                >
                  {r.minutes != null ? fmtMin(r.minutes) : r.ended_at ? '—' : 'en curso'}
                </td>
                <td className="py-2">
                  {r.opened_by ?? '—'}
                  {r.from_device ? ' (PIN)' : ''}
                </td>
                <td className="py-2">{closureText(r)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {history.data && history.data.length === 0 ? (
        <span className="text-[15px] text-muted">Sin movimientos en este periodo.</span>
      ) : null}
    </Card>
  );
}
