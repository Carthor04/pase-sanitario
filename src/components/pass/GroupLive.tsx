import { useCallback, useEffect, useMemo, useRef, useState, type KeyboardEvent } from 'react';
import { BellIcon, CheckIcon } from '@/components/ui/icons';
import { buttonClass } from '@/components/ui/styles';
import {
  bathroomFor,
  elapsedMs,
  formatCountdown,
  formatElapsed,
  isOverdue,
  nursePasses,
  occupancy,
  passForStudent,
  passTag,
  requestMessage,
  slotPass,
  turnLeftMs,
  turnPasses,
  type Bathroom,
  type Board,
  type BoardPass,
  type Sex,
  type StudentRef,
  type Tone,
} from '@/lib/board';
import { playTurnSound } from '@/lib/device';
import { errorMessage, usePassAction, useServerNow } from '@/lib/live';
import { PassMenu } from './PassMenu';

const timeFmt = new Intl.DateTimeFormat('es-MX', {
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
  timeZone: 'America/Mexico_City',
});
const hm = (iso: string | null) => (iso ? timeFmt.format(new Date(iso)) : '');

const TAG_CLASS: Record<Tone, string> = {
  out: 'bg-ink text-white',
  wait: 'bg-wait-bg text-wait-fg',
  alert: 'bg-alert-fg text-white',
  nurse: 'bg-nurse-bg text-nurse-fg',
  free: 'bg-free-bg text-free-fg',
};
const TILE_CLASS: Record<Tone, string> = {
  out: 'border-2 border-ink',
  wait: 'border-2 border-wait-bd bg-wait-bg/40',
  alert: 'border-2 border-alert-bd bg-alert-bg',
  nurse: 'border-2 border-nurse-bd',
  free: 'border border-line',
};

type Undo = { passId: string; message: string; until: number };

type Props = {
  board: Board & { offsetMs: number };
  groupName: string;
  students: StudentRef[];
  /** Salón: captura rápida con teclado. */
  capture?: boolean;
  /** Texto bajo el menú, p. ej. a nombre de quién quedan los pases. */
  footnote?: string;
};

/**
 * Pantalla de un grupo con pases en vivo. La misma sirve en la computadora del salón
 * (Main/SalonTurno) y en el celular (MovilGrupo/MovilTurno): debajo de 640 px se acomoda
 * como la versión de celular.
 */
export function GroupLive({ board, groupName, students, capture, footnote }: Props) {
  const now = useServerNow(board.offsetMs);
  const action = usePassAction();
  const [menuFor, setMenuFor] = useState<StudentRef | null>(null);
  const [undo, setUndo] = useState<Undo | null>(null);
  const [error, setError] = useState<string | null>(null);
  const clearUndo = useCallback(() => setUndo(null), []);
  const s = board.settings;

  // Sonido cuando aparece un turno nuevo de este grupo.
  const seenTurns = useRef<Set<string> | null>(null);
  const turns = turnPasses(board.passes);
  useEffect(() => {
    const ids = new Set(turns.map((p) => p.id));
    if (seenTurns.current && [...ids].some((id) => !seenTurns.current!.has(id))) playTurnSound();
    seenTurns.current = ids;
  }, [turns]);

  useEffect(() => {
    if (!error) return;
    const id = window.setTimeout(() => setError(null), 6000);
    return () => window.clearTimeout(id);
  }, [error]);

  const studentById = useMemo(() => new Map(students.map((st) => [st.id, st])), [students]);

  async function run(
    a: Parameters<typeof action.mutateAsync>[0],
    onOk?: (r: Awaited<ReturnType<typeof action.mutateAsync>>) => void,
  ) {
    setError(null);
    try {
      const res = await action.mutateAsync(a);
      onOk?.(res);
      return true;
    } catch (err) {
      setError(errorMessage(err));
      return false;
    }
  }

  function request(student: StudentRef, kind: 'bathroom' | 'nurse') {
    void run({ type: 'request', studentId: student.id, kind }, (res) => {
      setMenuFor(null);
      setUndo({
        passId: res.id,
        message: requestMessage(student, res.status as BoardPass['status'], groupName, {
          label: kind === 'nurse' ? 'Enfermería' : bathroomFor(board, student.sex)?.label,
          queuePosition: res.queue_position,
        }),
        until: Date.now() + s.undo_seconds * 1000,
      });
    });
  }

  function markReturned(pass: BoardPass) {
    const time = pass.started_at ? ` · ${formatElapsed(elapsedMs(pass, now))}` : '';
    void run({ type: 'return', passId: pass.id }, () => {
      setMenuFor(null);
      setUndo({
        passId: pass.id,
        message: `Regreso de ${pass.full_name} registrado${time}`,
        until: Date.now() + s.undo_seconds * 1000,
      });
    });
  }

  function onPassAction(type: 'return' | 'cancel', pass: BoardPass) {
    if (type === 'return') markReturned(pass);
    else void run({ type: 'cancel', passId: pass.id }, () => setMenuFor(null));
  }

  // Captura rápida: número de lista + B (baño), E (enfermería), R (regresó).
  const [num, setNum] = useState('');
  function onCaptureKey(e: KeyboardEvent<HTMLInputElement>) {
    const key = e.key.toLowerCase();
    if (!['b', 'e', 'r'].includes(key)) return;
    e.preventDefault();
    const n = Number(num);
    setNum('');
    const student = students.find((st) => st.list_number === n);
    if (!student) {
      setError(num ? `No hay alumno con el número ${num}` : 'Escribe primero el número de lista');
      return;
    }
    if (key === 'r') {
      const pass = passForStudent(board.passes, student.id);
      if (!pass || (pass.status !== 'out' && pass.status !== 'arrived')) {
        setError(`#${n} ${student.full_name} no está fuera`);
        return;
      }
      markReturned(pass);
    } else {
      request(student, key === 'b' ? 'bathroom' : 'nurse');
    }
  }

  const boy = slotPass(board.passes, 'H');
  const girl = slotPass(board.passes, 'M');
  const nurse = nursePasses(board.passes);

  return (
    <div className="flex flex-col gap-4 sm:gap-5">
      {turns.map((p) => (
        <TurnBanner
          key={p.id}
          pass={p}
          bathroom={bathroomFor(board, p.sex)}
          left={turnLeftMs(p, now, s)}
          busy={action.isPending}
          onConfirm={() => void run({ type: 'confirm', passId: p.id })}
          onCede={() => void run({ type: 'cede', passId: p.id })}
        />
      ))}

      <section
        aria-label="Lugares del grupo"
        className="grid grid-cols-2 gap-3 sm:grid-cols-3 sm:gap-4"
      >
        <SexSlot
          sex="H"
          pass={boy}
          board={board}
          now={now}
          busy={action.isPending}
          onReturn={markReturned}
        />
        <SexSlot
          sex="M"
          pass={girl}
          board={board}
          now={now}
          busy={action.isPending}
          onReturn={markReturned}
        />
        <NurseSlot
          passes={nurse}
          board={board}
          now={now}
          busy={action.isPending}
          onReturn={markReturned}
        />
      </section>

      {capture ? (
        <section
          aria-label="Captura rápida"
          className="hidden flex-wrap items-center gap-3 rounded-card border border-line bg-surface px-5 py-3.5 sm:flex"
        >
          <label htmlFor="captura" className="font-bold">
            Número de lista
          </label>
          <input
            id="captura"
            type="text"
            inputMode="numeric"
            autoComplete="off"
            placeholder="Ej. 22"
            value={num}
            onChange={(e) => setNum(e.target.value.replace(/\D/g, '').slice(0, 2))}
            onKeyDown={onCaptureKey}
            className="min-h-btn w-[120px] rounded-btn border border-line-strong px-4 font-mono text-[22px] tabular-nums"
          />
          <span className="text-muted">
            luego <Kbd>B</Kbd> baño <Kbd>E</Kbd> enfermería <Kbd>R</Kbd> regresó
          </span>
          <span className="ml-auto text-[15px] text-muted">o toca el nombre del alumno</span>
        </section>
      ) : null}

      <section aria-labelledby="lista" className="flex flex-col gap-3">
        <div className="flex flex-wrap items-end justify-between gap-2">
          <h2 id="lista" className="m-0 font-display text-[22px] font-bold">
            Lista · {students.length} alumnos
          </h2>
          <span className="hidden text-[15px] text-muted sm:inline">
            H = baño hombres · M = baño mujeres (automático)
          </span>
        </div>
        <ul className="m-0 grid list-none grid-cols-1 gap-2 p-0 sm:grid-cols-[repeat(auto-fill,minmax(168px,1fr))] sm:gap-2.5">
          {students.map((st) => {
            const pass = passForStudent(board.passes, st.id);
            const tag = pass ? passTag(pass, now, s) : null;
            return (
              <li key={st.id}>
                <button
                  type="button"
                  onClick={() => setMenuFor(st)}
                  className={`flex min-h-[56px] w-full items-center gap-3 rounded-btn-lg bg-surface px-3 text-left sm:min-h-[72px] sm:flex-col sm:items-stretch sm:gap-1 sm:rounded-card sm:p-3 ${
                    tag ? TILE_CLASS[tag.tone] : TILE_CLASS.free
                  }`}
                >
                  <span className="flex items-center justify-between sm:w-full">
                    <span className="w-7 text-right font-mono text-[15px] font-semibold tabular-nums text-muted sm:w-auto sm:text-left sm:text-[20px] sm:text-ink">
                      {st.list_number}
                    </span>
                    <SexChip sex={st.sex} className="hidden sm:inline" />
                  </span>
                  <span className="min-w-0 flex-1 truncate text-[17px] sm:flex-none sm:text-[15px] sm:font-bold">
                    {st.full_name}
                  </span>
                  {tag ? (
                    <span
                      className={`shrink-0 self-center rounded-chip px-2 py-0.5 font-mono text-[12px] font-bold tabular-nums sm:self-start ${TAG_CLASS[tag.tone]}`}
                    >
                      {tag.label}
                    </span>
                  ) : null}
                  <SexChip sex={st.sex} className="sm:hidden" />
                </button>
              </li>
            );
          })}
        </ul>
      </section>

      <BathroomBar bathrooms={board.bathrooms} now={now} />

      {menuFor ? (
        <PassMenu
          student={studentById.get(menuFor.id) ?? menuFor}
          board={board}
          now={now}
          groupName={groupName}
          footnote={footnote}
          busy={action.isPending}
          onRequest={(kind) => request(menuFor, kind)}
          onPassAction={onPassAction}
          onClose={() => setMenuFor(null)}
        />
      ) : null}

      <div className="pointer-events-none fixed inset-x-0 bottom-[86px] z-30 flex flex-col items-center gap-2 px-4 sm:bottom-6">
        {error ? (
          <div
            role="alert"
            className="pointer-events-auto w-full max-w-[560px] rounded-card border-2 border-alert-bd bg-alert-bg px-4 py-3 font-bold text-alert-fg shadow-lg"
          >
            {error}
          </div>
        ) : null}
        {undo ? (
          <UndoToast
            undo={undo}
            busy={action.isPending}
            onExpire={clearUndo}
            onUndo={() => void run({ type: 'undo', passId: undo.passId }, () => setUndo(null))}
          />
        ) : null}
      </div>
    </div>
  );
}

function Kbd({ children }: { children: string }) {
  return (
    <kbd className="mx-0.5 rounded-[6px] border border-line-strong bg-ground px-2 py-0.5 font-mono text-[15px] text-ink">
      {children}
    </kbd>
  );
}

function SexChip({ sex, className = '' }: { sex: Sex; className?: string }) {
  return (
    <span
      className={`shrink-0 rounded-[6px] border border-line px-1.5 text-[12px] font-bold text-muted ${className}`}
      aria-label={sex === 'H' ? 'Baño hombres' : 'Baño mujeres'}
    >
      {sex}
    </span>
  );
}

function Chip({ tone, children }: { tone: Tone; children: React.ReactNode }) {
  return (
    <span className={`rounded-chip px-2.5 py-0.5 text-[13px] font-bold ${TAG_CLASS[tone]}`}>
      {children}
    </span>
  );
}

function SlotFrame({
  tone,
  title,
  chip,
  children,
}: {
  tone: Tone | 'idle';
  title: string;
  chip: React.ReactNode;
  children: React.ReactNode;
}) {
  const idle = tone === 'idle' || tone === 'free';
  // En celular las tarjetas libres van en dos columnas; las ocupadas, a lo ancho.
  return (
    <div
      className={`flex flex-col gap-2 rounded-card bg-surface px-4 py-3 sm:col-span-1 sm:gap-3 sm:px-5 sm:py-[18px] ${
        idle ? 'border border-line' : `col-span-2 ${TILE_CLASS[tone]}`
      }`}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="text-[12px] font-bold uppercase tracking-[0.08em] text-muted sm:text-[13px]">
          {title}
        </span>
        {chip}
      </div>
      {children}
    </div>
  );
}

function ReturnButton({
  busy,
  onClick,
  name,
}: {
  busy: boolean;
  onClick: () => void;
  name: string;
}) {
  return (
    <button type="button" disabled={busy} onClick={onClick} className={buttonClass.primary}>
      <CheckIcon />
      Marcar regreso
      <span className="sr-only"> de {name}</span>
    </button>
  );
}

function SexSlot({
  sex,
  pass,
  board,
  now,
  busy,
  onReturn,
}: {
  sex: Sex;
  pass: BoardPass | undefined;
  board: Board;
  now: number;
  busy: boolean;
  onReturn: (p: BoardPass) => void;
}) {
  const bath = bathroomFor(board, sex);
  const title = `${sex === 'H' ? 'Niño' : 'Niña'} · ${bath?.label ?? 'Baño'}`;
  const s = board.settings;

  if (!pass) {
    const occ = bath ? occupancy(bath) : 0;
    return (
      <SlotFrame tone="idle" title={title} chip={<Chip tone="free">Libre</Chip>}>
        <span className="text-[15px] text-muted sm:text-[17px]">
          {sex === 'H' ? 'Ningún alumno fuera' : 'Ninguna alumna fuera'}
        </span>
        {bath ? (
          <span className="text-[13px] text-muted sm:text-[15px]">
            {bath.label}: {occ}
            {bath.capacity !== null ? ` de ${bath.capacity}` : ''} ocupados
            {bath.queue.length ? ` · ${bath.queue.length} en fila` : ' · sin fila'}
          </span>
        ) : null}
      </SlotFrame>
    );
  }

  if (pass.status === 'out') {
    const overdue = isOverdue(pass, now, s);
    const elapsed = elapsedMs(pass, now);
    const pct = Math.min(100, (elapsed / (s.alert_minutes * 60_000)) * 100);
    return (
      <SlotFrame
        tone={overdue ? 'alert' : 'out'}
        title={title}
        chip={
          <Chip tone={overdue ? 'alert' : 'out'}>
            {overdue ? `Alerta ${s.alert_minutes} min` : 'Fuera'}
          </Chip>
        }
      >
        <div className="flex items-end justify-between gap-3">
          <div className="flex min-w-0 flex-col">
            <span className="truncate text-[20px] font-bold sm:text-[22px]">{pass.full_name}</span>
            <span className={`text-[15px] ${overdue ? 'text-alert-fg' : 'text-muted'}`}>
              #{pass.list_number} · salió {hm(pass.started_at)}
              {pass.period_subject ? ` en ${pass.period_subject}` : ''}
            </span>
          </div>
          <span
            className={`font-mono text-[32px] font-semibold tabular-nums leading-none sm:text-[40px] ${overdue ? 'text-alert-fg' : ''}`}
          >
            {formatElapsed(elapsed)}
          </span>
        </div>
        <div className="h-1.5 overflow-hidden rounded-[3px] bg-[#E6EBF0]" aria-hidden="true">
          <div
            className={`h-full ${overdue ? 'bg-alert-fg' : 'bg-ink'}`}
            style={{ width: `${pct}%` }}
          />
        </div>
        <ReturnButton busy={busy} onClick={() => onReturn(pass)} name={pass.full_name} />
      </SlotFrame>
    );
  }

  // called o queued: el alumno todavía no sale.
  return (
    <SlotFrame
      tone="wait"
      title={title}
      chip={<Chip tone="wait">{pass.status === 'called' ? 'Su turno' : 'En fila'}</Chip>}
    >
      <span className="truncate text-[20px] font-bold sm:text-[22px]">{pass.full_name}</span>
      <span className="text-[15px] text-muted">
        #{pass.list_number} ·{' '}
        {pass.status === 'called'
          ? 'confirma su salida arriba'
          : `lugar ${pass.queue_position ?? '—'} en la fila`}
      </span>
      {bath && bath.queue.length > 0 ? (
        <span className="text-[13px] text-muted">
          Fila: {bath.queue.map((q) => q.group_name).join(', ')}
        </span>
      ) : null}
    </SlotFrame>
  );
}

function NurseSlot({
  passes,
  board,
  now,
  busy,
  onReturn,
}: {
  passes: BoardPass[];
  board: Board;
  now: number;
  busy: boolean;
  onReturn: (p: BoardPass) => void;
}) {
  if (!passes.length) {
    return (
      <SlotFrame tone="idle" title="Enfermería" chip={<Chip tone="free">Nadie</Chip>}>
        <span className="text-[15px] text-muted sm:text-[17px]">Ningún alumno en enfermería</span>
        <span className="hidden text-[15px] text-muted sm:inline">
          No ocupa el lugar del grupo ni hace fila.
        </span>
      </SlotFrame>
    );
  }
  const anyOverdue = passes.some((p) => isOverdue(p, now, board.settings));
  return (
    <SlotFrame
      tone={anyOverdue ? 'alert' : 'nurse'}
      title="Enfermería"
      chip={
        <Chip tone={anyOverdue ? 'alert' : 'nurse'}>
          {passes.length === 1
            ? passes[0]!.status === 'arrived'
              ? 'Llegó'
              : 'En camino'
            : `${passes.length} alumnos`}
        </Chip>
      }
    >
      {passes.map((p) => (
        <div key={p.id} className="flex flex-col gap-2">
          <div className="flex items-end justify-between gap-3">
            <div className="flex min-w-0 flex-col">
              <span className="truncate text-[18px] font-bold">{p.full_name}</span>
              <span className="text-[15px] text-muted">
                #{p.list_number} ·{' '}
                {p.status === 'arrived'
                  ? `en enfermería desde ${hm(p.arrived_at)}`
                  : `en camino desde ${hm(p.started_at)}`}
              </span>
            </div>
            <span className="font-mono text-[24px] font-semibold tabular-nums">
              {formatElapsed(elapsedMs(p, now))}
            </span>
          </div>
          <ReturnButton busy={busy} onClick={() => onReturn(p)} name={p.full_name} />
        </div>
      ))}
    </SlotFrame>
  );
}

function TurnBanner({
  pass,
  bathroom,
  left,
  busy,
  onConfirm,
  onCede,
}: {
  pass: BoardPass;
  bathroom: Bathroom | undefined;
  left: number;
  busy: boolean;
  onConfirm: () => void;
  onCede: () => void;
}) {
  const canCede = (bathroom?.queue.length ?? 0) > 0;
  return (
    <section
      role="alert"
      aria-label={`Turno de ${pass.full_name}`}
      className="-mx-4 flex flex-col gap-3 border-b-[3px] border-wait-bd bg-wait-bg px-4 py-4 text-wait-fg sm:mx-0 sm:flex-row sm:items-center sm:gap-5 sm:rounded-card sm:border-2 sm:px-6"
    >
      <BellIcon size={30} className="hidden shrink-0 sm:block" />
      <div className="flex min-w-0 flex-1 items-start justify-between gap-3">
        <div className="flex min-w-0 flex-col">
          <span className="font-display text-[22px] font-bold leading-tight sm:text-[26px]">
            Turno de {pass.full_name}{' '}
            <span className="font-mono text-[18px]">#{pass.list_number}</span>
          </span>
          <span className="text-[15px]">
            {left > 0
              ? `${bathroom?.label ?? 'El baño'} se liberó. Confirma su salida antes de que el turno pase al siguiente.`
              : 'Se acabó el tiempo: el turno pasará al siguiente en fila.'}
          </span>
        </div>
        <div className="flex shrink-0 flex-col items-end">
          <span className="font-mono text-[32px] font-semibold tabular-nums leading-none sm:text-[36px]">
            {formatCountdown(left)}
          </span>
          <span className="text-[12px]">para confirmar</span>
        </div>
      </div>
      <div className="grid grid-cols-[1fr_2fr] gap-2 sm:flex sm:shrink-0">
        <button
          type="button"
          disabled={busy || !canCede}
          onClick={onCede}
          className="min-h-btn rounded-btn border border-wait-bd bg-surface px-4 text-[15px] font-bold text-wait-fg disabled:opacity-60"
        >
          {canCede ? 'Ceder turno' : 'Nadie más en fila'}
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={onConfirm}
          className="min-h-btn-critical rounded-btn bg-ink px-5 text-[17px] font-bold text-white disabled:opacity-60"
        >
          Confirmar salida
        </button>
      </div>
    </section>
  );
}

function BathroomBar({ bathrooms, now }: { bathrooms: Bathroom[]; now: number }) {
  return (
    <section aria-label="Estado de los baños" className="grid gap-3 sm:grid-cols-2">
      {bathrooms.map((b) => {
        const occ = occupancy(b);
        const full = b.capacity !== null && occ >= b.capacity;
        return (
          <div
            key={b.id}
            className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-card border border-line bg-surface px-4 py-3"
          >
            <span className="font-bold">{b.label}</span>
            <span
              className={`rounded-chip px-2.5 py-0.5 text-[13px] font-bold ${full ? 'bg-ink text-white' : 'bg-free-bg text-free-fg'}`}
            >
              {occ}
              {b.capacity !== null ? `/${b.capacity}` : ''} · {full ? 'Ocupado' : 'Con lugar'}
            </span>
            <span className="font-mono text-[14px] tabular-nums text-muted">
              {b.occupants
                .map(
                  (o) =>
                    `${o.group_name}${o.status === 'called' ? ' (turno)' : ` · ${formatElapsed(now - new Date(o.since).getTime())}`}`,
                )
                .join(', ')}
            </span>
            <span
              className={`ml-auto text-[14px] font-bold ${b.queue.length ? 'text-wait-fg' : 'text-free-fg'}`}
            >
              {b.queue.length
                ? `En fila: ${b.queue.map((q) => q.group_name).join(', ')}`
                : 'Sin fila'}
            </span>
          </div>
        );
      })}
    </section>
  );
}

function UndoToast({
  undo,
  busy,
  onUndo,
  onExpire,
}: {
  undo: Undo;
  busy: boolean;
  onUndo: () => void;
  onExpire: () => void;
}) {
  const [left, setLeft] = useState(() => Math.ceil((undo.until - Date.now()) / 1000));
  useEffect(() => {
    const id = window.setInterval(() => {
      const s = Math.ceil((undo.until - Date.now()) / 1000);
      setLeft(s);
      if (s <= 0) onExpire();
    }, 250);
    return () => window.clearInterval(id);
  }, [undo, onExpire]);

  return (
    <div
      role="status"
      className="pointer-events-auto flex w-full max-w-[560px] items-center gap-3 rounded-card bg-ink px-4 py-3 text-white shadow-lg"
    >
      <span className="min-w-0 flex-1 text-[15px]">{undo.message}</span>
      <button
        type="button"
        disabled={busy || left <= 0}
        onClick={onUndo}
        className="min-h-touch shrink-0 rounded-btn border border-white/40 px-3 text-[15px] font-bold"
      >
        Deshacer · <span className="font-mono tabular-nums">{Math.max(0, left)}</span>
      </button>
    </div>
  );
}
