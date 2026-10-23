import { useEffect, useId, useState } from 'react';
import { buttonClass } from '@/components/ui/styles';
import type { BathroomPause as Pause } from '@/lib/board';
import { errorMessage, usePauseBathroom } from '@/lib/live';
import { hm } from '@/lib/monitor';

const REASONS = ['Limpieza', 'Mantenimiento', 'Otro'] as const;

/** Aviso de baño en pausa. En la compu del salón (dark) solo dice desde cuándo y por qué. */
export function PauseBanner({ pause, dark = false }: { pause: Pause; dark?: boolean }) {
  return (
    <div
      role="status"
      className={`flex flex-col rounded-btn border-2 px-3 py-2 ${
        dark ? 'border-[#FFD08A] text-[#FFD08A]' : 'border-wait-bd bg-wait-bg text-wait-fg'
      }`}
    >
      <strong>
        <span aria-hidden="true">⏸ </span>
        {pause.scheduled ? 'Cerrado' : 'En pausa'}
        {pause.reason ? ` · ${pause.reason}` : ''}
      </strong>
      <span className="text-[13px]">
        {pause.scheduled
          ? `De ${hm(pause.since)} a ${hm(pause.until)}`
          : `Desde ${hm(pause.since)}`}
        {pause.by && !dark ? ` · ${pause.by}` : ''} · no se piden pases y la fila no avanza
      </span>
    </div>
  );
}

/**
 * Pausar o reanudar un baño (Baños y En vivo). Muestra el aviso si está en pausa y, para
 * quien puede, el botón. Pausar pide confirmación y el motivo.
 */
export function PauseControl({
  destination,
  label,
  pause,
  canControl,
}: {
  destination: string;
  label: string;
  pause: Pause | null | undefined;
  canControl: boolean;
}) {
  const mutation = usePauseBathroom();
  const [asking, setAsking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run(a: { pause: boolean; reason?: string }) {
    setError(null);
    try {
      await mutation.mutateAsync({ destination, ...a });
      setAsking(false);
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  return (
    <div className="flex flex-col gap-2">
      {pause ? <PauseBanner pause={pause} /> : null}
      {/* El horario sin baño termina solo: no se reanuda ni se pausa a mano. */}
      {canControl && !pause?.scheduled ? (
        pause ? (
          <button
            type="button"
            disabled={mutation.isPending}
            onClick={() => void run({ pause: false })}
            className={buttonClass.primary}
          >
            <span aria-hidden="true">▶</span> Reanudar baño
          </button>
        ) : (
          <button type="button" onClick={() => setAsking(true)} className={buttonClass.secondary}>
            <span aria-hidden="true">⏸</span> Pausar baño
          </button>
        )
      ) : null}
      {error ? (
        <p role="alert" className="m-0 text-[14px] font-bold text-alert-fg">
          {error}
        </p>
      ) : null}
      {asking ? (
        <PauseDialog
          label={label}
          busy={mutation.isPending}
          onConfirm={(reason) => void run({ pause: true, reason })}
          onClose={() => setAsking(false)}
        />
      ) : null}
    </div>
  );
}

function PauseDialog({
  label,
  busy,
  onConfirm,
  onClose,
}: {
  label: string;
  busy: boolean;
  onConfirm: (reason: string) => void;
  onClose: () => void;
}) {
  const id = useId();
  const [reason, setReason] = useState<(typeof REASONS)[number]>('Limpieza');
  const [other, setOther] = useState('');
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const text = reason === 'Otro' ? other.trim() : reason;

  return (
    <div
      className="fixed inset-0 z-40 flex items-end justify-center bg-ink/50 sm:items-center sm:p-6"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby={`${id}-t`}
        onClick={(e) => e.stopPropagation()}
        className="pb-safe flex w-full flex-col gap-3 rounded-t-[22px] bg-surface p-5 text-ink sm:max-w-[460px] sm:rounded-card-lg sm:p-7"
      >
        <h2 id={`${id}-t`} className="m-0 font-display text-[24px] font-bold">
          ¿Pausar {label}?
        </h2>
        <p className="m-0 text-[15px] text-muted">
          Nadie podrá pedir pase a este baño y la fila se detiene hasta que lo reanudes. Quien ya
          está dentro sigue con su tiempo.
        </p>
        <span className="font-bold">Motivo</span>
        <div className="flex flex-wrap gap-2">
          {REASONS.map((r) => (
            <button
              key={r}
              type="button"
              aria-pressed={reason === r}
              onClick={() => setReason(r)}
              className={`inline-flex min-h-btn items-center gap-1.5 rounded-btn border px-3.5 text-[15px] font-bold ${
                reason === r ? 'border-ink bg-ink text-white' : 'border-line-strong text-muted'
              }`}
            >
              {reason === r ? <span aria-hidden="true">✓</span> : null}
              {r}
            </button>
          ))}
        </div>
        {reason === 'Otro' ? (
          <input
            autoFocus
            maxLength={120}
            value={other}
            onChange={(e) => setOther(e.target.value)}
            placeholder="Ej. Falta de agua"
            aria-label="Otro motivo"
            className="min-h-btn rounded-btn border border-line-strong px-3 text-[17px]"
          />
        ) : null}
        <div className="grid grid-cols-2 gap-2">
          <button type="button" onClick={onClose} className={buttonClass.secondary}>
            Cancelar
          </button>
          <button
            type="button"
            disabled={busy || !text}
            onClick={() => onConfirm(text)}
            className={buttonClass.primary}
          >
            Pausar
          </button>
        </div>
      </div>
    </div>
  );
}
