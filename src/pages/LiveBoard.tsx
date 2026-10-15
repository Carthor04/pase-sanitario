import { useEffect, useState } from 'react';
import { AlertCard, ReleaseDialog } from '@/components/pass/AlertCard';
import { Loading, Notice } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { formatElapsed } from '@/lib/board';
import { useAudioUnlock } from '@/lib/device';
import { errorMessage, useLivePasses, usePassAction, useServerNow } from '@/lib/live';
import {
  alertStatusText,
  hm,
  useAlertSound,
  useLiveBoard,
  type LiveBoard as Board,
  type LiveDestination,
  type LivePass,
} from '@/lib/monitor';
import type { Role } from '@/lib/nav';
import { useStaff } from '@/lib/session';
import { useClock } from '@/lib/useClock';

type Caps = {
  ack: boolean;
  release: boolean;
  returnBath: boolean;
  returnNurse: boolean;
  arrive: boolean;
};

function capsFor(roles: Role[]): Caps {
  const has = (...r: Role[]) => roles.some((x) => r.includes(x));
  return {
    ack: has('prefect', 'coordinator', 'admin'),
    release: has('prefect', 'coordinator', 'admin'),
    returnBath: has('teacher', 'prefect', 'coordinator', 'admin'),
    returnNurse: has('teacher', 'prefect', 'nurse', 'coordinator', 'admin'),
    arrive: has('nurse', 'coordinator', 'admin'),
  };
}

const elapsedSince = (iso: string | null, now: number) => (iso ? now - new Date(iso).getTime() : 0);

/**
 * Monitor en vivo (Prefectura en escritorio/tablet, MovilPrefectura en celular): alertas
 * arriba y una columna por lugar. Dirección lo ve en solo lectura. `preview` solo lo usa
 * la vista de diseño de desarrollo.
 */
export function LiveBoard({ preview }: { preview?: Board } = {}) {
  const staff = useStaff();
  const caps = capsFor(staff.roles);
  const live = useLiveBoard();
  const online = useLivePasses();
  const clock = useClock();
  const action = usePassAction();
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<LivePass | null>(null);
  const [releasing, setReleasing] = useState<LivePass | null>(null);
  const [tab, setTab] = useState(0);
  useAudioUnlock();

  const board = preview ?? live.data;
  const now = useServerNow(board?.offsetMs ?? 0);
  const alerts = (board?.passes ?? []).filter((p) => p.alert);
  useAlertSound(alerts.map((p) => ({ id: p.alert!.id, level: p.alert!.level })));

  useEffect(() => {
    if (!error) return;
    const id = window.setTimeout(() => setError(null), 6000);
    return () => window.clearTimeout(id);
  }, [error]);

  async function run(a: Parameters<typeof action.mutateAsync>[0]) {
    setError(null);
    try {
      await action.mutateAsync(a);
      setSelected(null);
      setReleasing(null);
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  if (!preview && live.isPending) return <Loading />;
  if (!board) {
    return <Notice tone="error">{errorMessage(live.error)}</Notice>;
  }

  const title = staff.roles.includes('prefect') ? 'Prefectura' : 'En vivo';
  const outCount = board.passes.filter((p) => p.status === 'out' || p.status === 'arrived').length;
  const queueCount = board.passes.filter((p) => p.status === 'queued').length;
  const columns = board.destinations;
  const destLabel = (id: string) => columns.find((d) => d.id === id)?.label ?? '';
  const canReturn = (p: LivePass) =>
    (p.status === 'out' || p.status === 'arrived') &&
    (columns.find((d) => d.id === p.destination_id)?.kind === 'nurse'
      ? caps.returnNurse
      : caps.returnBath);

  return (
    <div className="flex flex-col gap-4">
      <header className="-mx-4 -mt-4 flex flex-wrap items-center gap-x-4 gap-y-2 bg-dark px-4 py-4 text-white sm:mx-0 sm:mt-0 sm:rounded-card sm:px-6">
        <h1 className="m-0 font-display text-[26px] font-bold">{title}</h1>
        <span
          className={`inline-flex items-center gap-1.5 rounded-chip bg-white/10 px-2.5 py-0.5 text-[13px] font-bold ${online ? 'text-[#8FE0B0]' : 'text-[#FFB4AC]'}`}
        >
          <span
            aria-hidden="true"
            className={`h-2 w-2 rounded-full ${online ? 'bg-[#3FCF8E]' : 'bg-[#FF6B5E]'}`}
          />
          {online ? 'En vivo' : 'Sin conexión'}
        </span>
        <span className="ml-auto text-[15px] text-white/80">
          Fuera ahora <strong className="text-white">{outCount}</strong> · En fila{' '}
          <strong className="text-white">{queueCount}</strong>
        </span>
        <span className="hidden font-mono text-[22px] font-semibold tabular-nums sm:inline">
          {clock}
        </span>
      </header>

      {alerts.length ? (
        <div className="flex flex-col gap-3">
          {alerts
            .sort(
              (a, b) =>
                b.alert!.level - a.alert!.level ||
                a.alert!.created_at.localeCompare(b.alert!.created_at),
            )
            .map((p) => (
              <AlertCard
                key={p.id}
                name={p.full_name}
                groupName={p.group_name}
                place={destLabel(p.destination_id)}
                startedAt={p.started_at}
                periodSubject={p.period_subject}
                alert={p.alert!}
                now={now}
                busy={action.isPending}
                onAcknowledge={
                  caps.ack
                    ? () => void run({ type: 'acknowledge', alertId: p.alert!.id })
                    : undefined
                }
                onRelease={caps.release ? () => setReleasing(p) : undefined}
                onReturn={
                  canReturn(p) ? () => void run({ type: 'return', passId: p.id }) : undefined
                }
              />
            ))}
        </div>
      ) : null}

      {/* Celular: pestañas por lugar */}
      <div
        role="tablist"
        aria-label="Lugares"
        className="grid grid-cols-3 gap-1 rounded-card bg-[#E4E9EE] p-1 sm:hidden"
      >
        {columns.map((d, i) => (
          <button
            key={d.id}
            role="tab"
            type="button"
            aria-selected={tab === i}
            onClick={() => setTab(i)}
            className={`min-h-btn rounded-btn px-2 text-[15px] font-bold ${tab === i ? 'bg-surface text-ink' : 'text-muted'}`}
          >
            {shortLabel(d)} {countLabel(d, board)}
          </button>
        ))}
      </div>

      <div className="grid gap-4 sm:grid-cols-[repeat(auto-fit,minmax(300px,1fr))]">
        {columns.map((d, i) => (
          <div key={d.id} className={tab === i ? '' : 'hidden sm:block'}>
            <Column dest={d} board={board} now={now} onSelect={setSelected} />
          </div>
        ))}
      </div>

      <footer className="flex flex-wrap justify-between gap-2 text-[14px] text-muted">
        <span>
          Hoy: <strong className="text-ink">{board.stats.exits_today}</strong> salidas ·{' '}
          <strong className="text-ink">{board.stats.alerts_today}</strong> alertas
        </span>
        <span>Toca a un alumno para marcar regreso o liberar su lugar</span>
      </footer>

      {selected ? (
        <PersonDialog
          pass={board.passes.find((p) => p.id === selected.id) ?? selected}
          place={destLabel(selected.destination_id)}
          now={now}
          busy={action.isPending}
          canReturn={canReturn(selected)}
          caps={caps}
          isNurse={columns.find((d) => d.id === selected.destination_id)?.kind === 'nurse'}
          onAction={(type) => {
            if (type === 'release') setReleasing(selected);
            else if (type === 'ack' && selected.alert)
              void run({ type: 'acknowledge', alertId: selected.alert.id });
            else if (type === 'arrived') void run({ type: 'arrived', passId: selected.id });
            else void run({ type: 'return', passId: selected.id });
          }}
          onClose={() => setSelected(null)}
        />
      ) : null}

      {releasing ? (
        <ReleaseDialog
          name={releasing.full_name}
          busy={action.isPending}
          onConfirm={(reason) => void run({ type: 'release', passId: releasing.id, reason })}
          onClose={() => setReleasing(null)}
        />
      ) : null}

      {error ? (
        <div
          role="alert"
          className="fixed inset-x-4 bottom-[86px] z-50 mx-auto max-w-[560px] rounded-card border-2 border-alert-bd bg-alert-bg px-4 py-3 font-bold text-alert-fg shadow-lg sm:bottom-6"
        >
          {error}
        </div>
      ) : null}
    </div>
  );
}

const shortLabel = (d: LiveDestination) =>
  d.kind === 'nurse' ? 'Enfermería' : d.sex === 'H' ? 'Hombres' : 'Mujeres';

function countLabel(d: LiveDestination, board: Board) {
  const inside = board.passes.filter(
    (p) => p.destination_id === d.id && ['called', 'out', 'arrived'].includes(p.status),
  ).length;
  return d.capacity === null ? String(inside) : `${inside}/${d.capacity}`;
}

function Column({
  dest,
  board,
  now,
  onSelect,
}: {
  dest: LiveDestination;
  board: Board;
  now: number;
  onSelect: (p: LivePass) => void;
}) {
  const mine = board.passes.filter((p) => p.destination_id === dest.id);
  const inside = mine
    .filter((p) => p.status === 'out' || p.status === 'arrived' || p.status === 'called')
    .sort((a, b) =>
      (a.started_at ?? a.called_at ?? '').localeCompare(b.started_at ?? b.called_at ?? ''),
    );
  const queue = mine
    .filter((p) => p.status === 'queued')
    .sort((a, b) => (a.queue_ts ?? '').localeCompare(b.queue_ts ?? ''));
  const groupWait = mine.filter((p) => p.status === 'group_wait');
  const full = dest.capacity !== null && inside.length >= dest.capacity;
  const alertMs = board.settings.alert_minutes * 60_000;

  return (
    <section
      aria-labelledby={`col-${dest.id}`}
      className="flex flex-col rounded-card-lg border border-line bg-surface"
    >
      <div className="flex items-center justify-between border-b border-line px-5 py-4">
        <h2 id={`col-${dest.id}`} className="m-0 font-display text-[22px] font-bold">
          {dest.label}
        </h2>
        <span
          className={`rounded-chip px-2.5 py-0.5 text-[13px] font-bold ${
            dest.capacity === null
              ? 'bg-nurse-bg text-nurse-fg'
              : full
                ? 'bg-ink text-white'
                : 'bg-free-bg text-free-fg'
          }`}
        >
          {dest.capacity === null
            ? 'Sin límite'
            : `${inside.length} / ${dest.capacity}${full ? ' lleno' : ''}`}
        </span>
      </div>
      <div className="flex flex-col gap-2 p-3">
        <span className="px-2 pt-1 text-[12px] font-bold uppercase tracking-[0.08em] text-muted">
          {dest.kind === 'nurse' ? 'En enfermería y en camino' : 'Dentro · más tiempo primero'}
        </span>
        {inside.length === 0 ? (
          <span className="px-2 pb-2 text-[15px] text-muted">Nadie</span>
        ) : null}
        {inside.map((p) => {
          const elapsed = elapsedSince(p.started_at, now);
          const overdue = p.status === 'out' && elapsed >= alertMs;
          const nurse = dest.kind === 'nurse';
          return (
            <button
              key={p.id}
              type="button"
              onClick={() => onSelect(p)}
              className={`flex flex-col gap-1.5 rounded-btn-lg border px-3 py-2.5 text-left ${
                overdue
                  ? 'border-2 border-alert-bd bg-alert-bg'
                  : p.status === 'called'
                    ? 'border-wait-bd bg-wait-bg/40'
                    : nurse
                      ? 'border-nurse-bd/50'
                      : 'border-line'
              }`}
            >
              <span className="flex items-center justify-between gap-2">
                <span className="flex min-w-0 flex-col">
                  <span className="truncate font-bold">{p.full_name}</span>
                  <span className="text-[13px] text-muted">
                    {p.group_name} ·{' '}
                    {p.status === 'called'
                      ? 'su turno, sin confirmar'
                      : p.status === 'arrived'
                        ? `llegó ${hm(p.arrived_at)} ✓`
                        : nurse
                          ? 'en camino'
                          : `salió ${hm(p.started_at)}`}
                    {p.alert ? ` · ${alertStatusText(p.alert)}` : ''}
                  </span>
                </span>
                <span
                  className={`font-mono text-[26px] font-semibold tabular-nums ${overdue ? 'text-alert-fg' : ''}`}
                >
                  {p.status === 'called' ? 'Turno' : formatElapsed(elapsed)}
                </span>
              </span>
              {p.status !== 'called' ? (
                <span
                  className="h-1.5 overflow-hidden rounded-[3px] bg-[#E6EBF0]"
                  aria-hidden="true"
                >
                  <span
                    className={`block h-full ${overdue ? 'bg-alert-fg' : nurse ? 'bg-nurse-bd' : 'bg-ink'}`}
                    style={{ width: `${Math.min(100, (elapsed / alertMs) * 100)}%` }}
                  />
                </span>
              ) : null}
            </button>
          );
        })}

        {dest.kind === 'bathroom' ? (
          <>
            {queue.length ? (
              <span className="px-2 pt-2 text-[12px] font-bold uppercase tracking-[0.08em] text-wait-fg">
                Fila
              </span>
            ) : null}
            {queue.map((p, i) => (
              <button
                key={p.id}
                type="button"
                onClick={() => onSelect(p)}
                className="flex items-center gap-3 rounded-btn-lg border border-wait-bd/50 bg-wait-bg/40 px-3 py-2.5 text-left"
              >
                <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-wait-bg font-bold text-wait-fg">
                  {i + 1}
                </span>
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate font-bold">{p.full_name}</span>
                  <span className="text-[13px] text-muted">
                    {p.group_name}
                    {p.current_teacher_name ? ` · ${p.current_teacher_name}` : ''}
                  </span>
                </span>
                <span className="font-mono text-[15px] tabular-nums text-wait-fg">
                  espera {formatElapsed(elapsedSince(p.queue_ts, now))}
                </span>
              </button>
            ))}
            {groupWait.length ? (
              <span className="px-2 pt-2 text-[13px] text-muted">
                Espera del grupo:{' '}
                {groupWait.map((p) => `${p.full_name} (${p.group_name})`).join(', ')}
              </span>
            ) : null}
          </>
        ) : (
          <span className="px-2 pt-1 text-[14px] font-bold text-free-fg">
            No hace fila ni ocupa lugar del grupo
          </span>
        )}
      </div>
    </section>
  );
}

function PersonDialog({
  pass,
  place,
  now,
  busy,
  canReturn,
  caps,
  isNurse,
  onAction,
  onClose,
}: {
  pass: LivePass;
  place: string;
  now: number;
  busy: boolean;
  canReturn: boolean;
  caps: Caps;
  isNurse: boolean;
  onAction: (type: 'return' | 'release' | 'ack' | 'arrived') => void;
  onClose: () => void;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const nothing =
    !canReturn &&
    !caps.release &&
    !(caps.ack && pass.alert && !pass.alert.acknowledged_by_name) &&
    !(isNurse && caps.arrive && pass.status === 'out');

  return (
    <div
      className="fixed inset-0 z-40 flex items-end justify-center bg-ink/50 sm:items-center sm:p-6"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={pass.full_name}
        onClick={(e) => e.stopPropagation()}
        className="pb-safe flex w-full flex-col gap-3 rounded-t-[22px] bg-surface p-5 sm:max-w-[460px] sm:rounded-card-lg sm:p-7"
      >
        <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-muted">
          {pass.group_name} · {place}
        </span>
        <h2 className="m-0 font-display text-[26px] font-bold">
          {pass.full_name}{' '}
          <span className="font-mono text-[18px] text-muted">#{pass.list_number}</span>
        </h2>
        <p className="m-0 text-[15px] text-muted">
          {pass.started_at
            ? `Fuera ${formatElapsed(now - new Date(pass.started_at).getTime())} · salió ${hm(pass.started_at)}`
            : 'Todavía no sale'}
          {pass.period_subject ? ` en ${pass.period_subject}` : ''}
          {pass.opened_by_name ? ` · autorizó ${pass.opened_by_name}` : ''}
          {pass.current_teacher_name ? ` · ahora con ${pass.current_teacher_name}` : ''}
        </p>
        {isNurse && caps.arrive && pass.status === 'out' ? (
          <button
            type="button"
            disabled={busy}
            onClick={() => onAction('arrived')}
            className={buttonClass.primary}
          >
            Llegó a enfermería
          </button>
        ) : null}
        {caps.ack && pass.alert && !pass.alert.acknowledged_by_name ? (
          <button
            type="button"
            disabled={busy}
            onClick={() => onAction('ack')}
            className="min-h-btn rounded-btn bg-alert-fg px-5 text-[17px] font-bold text-white disabled:opacity-60"
          >
            Yo lo atiendo
          </button>
        ) : null}
        {canReturn ? (
          <button
            type="button"
            disabled={busy}
            onClick={() => onAction('return')}
            className={buttonClass.primary}
          >
            Marcar regreso
          </button>
        ) : null}
        {caps.release ? (
          <button
            type="button"
            disabled={busy}
            onClick={() => onAction('release')}
            className={buttonClass.danger}
          >
            Liberar lugar
          </button>
        ) : null}
        {nothing ? <p className="m-0 text-[15px] text-muted">Solo lectura.</p> : null}
        <button type="button" onClick={onClose} className={buttonClass.secondary}>
          Cerrar
        </button>
      </div>
    </div>
  );
}
