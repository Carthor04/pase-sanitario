import { useEffect, useRef } from 'react';
import { ChevronIcon, CloseIcon, PlusIcon, ToiletIcon } from '@/components/ui/icons';
import { buttonClass } from '@/components/ui/styles';
import { TodayList } from './TodayExits';
import {
  bathroomHint,
  passForStudent,
  passTag,
  sexLabel,
  type Board,
  type BoardPass,
  type StudentRef,
} from '@/lib/board';

type Props = {
  student: StudentRef;
  board: Board;
  now: number;
  groupName: string;
  footnote?: string;
  /** Salidas de hoy, p. ej. "2 baño · 1 enfermería". */
  today?: string | null;
  /** Muestra la lista de salidas de hoy (horario, destino y clase). */
  showToday?: boolean;
  busy: boolean;
  onRequest: (kind: 'bathroom' | 'nurse') => void;
  onPassAction: (type: 'return' | 'cancel', pass: BoardPass) => void;
  onClose: () => void;
};

const HINT_TONE = {
  free: 'text-free-fg',
  wait: 'text-wait-fg',
  blocked: 'text-muted',
};

/**
 * Menú del alumno: Baño / Enfermería (SalonMenu en escritorio, MovilMenu como hoja
 * inferior en celular). Si ya tiene pase, muestra su estado y las acciones posibles.
 */
export function PassMenu(props: Props) {
  const {
    student,
    board,
    now,
    groupName,
    footnote,
    today,
    showToday,
    busy,
    onRequest,
    onPassAction,
    onClose,
  } = props;
  const firstButton = useRef<HTMLButtonElement>(null);
  const pass = passForStudent(board.passes, student.id);
  const hint = bathroomHint(student, board);

  useEffect(() => {
    firstButton.current?.focus();
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
        aria-labelledby="pass-menu-title"
        onClick={(e) => e.stopPropagation()}
        className="pb-safe flex w-full flex-col gap-4 rounded-t-[22px] bg-surface p-5 sm:max-w-[520px] sm:rounded-card-lg sm:p-7"
      >
        <div
          aria-hidden="true"
          className="mx-auto h-1.5 w-10 rounded-full bg-line-strong sm:hidden"
        />
        <div className="flex items-start justify-between gap-3">
          <div className="flex flex-col">
            <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-muted">
              {groupName} · {sexLabel(student.sex)}
            </span>
            <h2
              id="pass-menu-title"
              className="m-0 font-display text-[28px] font-bold leading-tight"
            >
              {student.full_name}{' '}
              <span className="font-mono text-[20px] text-muted">#{student.list_number}</span>
            </h2>
            <span className="text-[15px] text-muted">
              {today ? `Hoy ha salido: ${today}` : 'Hoy no ha salido'}
            </span>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Cerrar"
            className="hidden h-11 w-11 shrink-0 items-center justify-center rounded-full border border-line sm:inline-flex"
          >
            <CloseIcon />
          </button>
        </div>

        {pass ? (
          <ActivePass
            pass={pass}
            board={board}
            now={now}
            busy={busy}
            firstButton={firstButton}
            onPassAction={onPassAction}
          />
        ) : (
          <div className="flex flex-col gap-3">
            <button
              ref={firstButton}
              type="button"
              disabled={busy || hint.tone === 'blocked'}
              onClick={() => onRequest('bathroom')}
              className={`flex min-h-[84px] items-center gap-4 rounded-card border-2 p-4 text-left disabled:opacity-50 ${
                hint.tone === 'wait' ? 'border-wait-bd bg-wait-bg/40' : 'border-accent'
              }`}
            >
              <span
                className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-btn ${
                  hint.tone === 'wait' ? 'bg-wait-bg text-wait-fg' : 'bg-nurse-bg text-accent'
                }`}
              >
                <ToiletIcon size={24} />
              </span>
              <span className="flex min-w-0 flex-1 flex-col">
                <span className="text-[20px] font-bold">Baño</span>
                <span className={`text-[15px] font-bold ${HINT_TONE[hint.tone]}`}>{hint.text}</span>
              </span>
              <ChevronIcon className="text-muted" />
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={() => onRequest('nurse')}
              className="flex min-h-[84px] items-center gap-4 rounded-card border border-line-strong p-4 text-left disabled:opacity-50"
            >
              <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-btn bg-nurse-bg text-nurse-fg">
                <PlusIcon size={24} />
              </span>
              <span className="flex min-w-0 flex-1 flex-col">
                <span className="text-[20px] font-bold">Enfermería</span>
                <span className="text-[15px] text-muted">Sale ya · no hace fila</span>
              </span>
              <ChevronIcon className="text-muted" />
            </button>
          </div>
        )}

        {showToday && today ? (
          <details className="rounded-card border border-line px-3 py-2">
            <summary className="min-h-touch cursor-pointer content-center font-bold">
              Salidas de hoy ({today})
            </summary>
            <div className="pt-2">
              <TodayList studentId={student.id} />
            </div>
          </details>
        ) : null}

        <button type="button" onClick={onClose} className={`${buttonClass.secondary} sm:hidden`}>
          Cancelar
        </button>
        {footnote ? <p className="m-0 text-center text-[13px] text-muted">{footnote}</p> : null}
      </div>
    </div>
  );
}

function ActivePass({
  pass,
  board,
  now,
  busy,
  firstButton,
  onPassAction,
}: {
  pass: BoardPass;
  board: Board;
  now: number;
  busy: boolean;
  firstButton: React.RefObject<HTMLButtonElement>;
  onPassAction: Props['onPassAction'];
}) {
  const tag = passTag(pass, now, board.settings);
  const canReturn = pass.status === 'out' || pass.status === 'arrived';
  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-card border border-line bg-ground p-4">
        <span className="text-[15px] text-muted">{pass.destination_label}</span>
        <p className="m-0 text-[20px] font-bold">{tag.label}</p>
      </div>
      {canReturn ? (
        <button
          ref={firstButton}
          type="button"
          disabled={busy}
          onClick={() => onPassAction('return', pass)}
          className={buttonClass.primary}
        >
          Marcar regreso
        </button>
      ) : (
        <button
          ref={firstButton}
          type="button"
          disabled={busy}
          onClick={() => onPassAction('cancel', pass)}
          className={buttonClass.danger}
        >
          Cancelar pase
        </button>
      )}
    </div>
  );
}
