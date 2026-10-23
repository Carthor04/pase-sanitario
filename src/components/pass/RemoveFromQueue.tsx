import { useEffect, useId, useState } from 'react';
import { buttonClass } from '@/components/ui/styles';

/**
 * Quitar de la fila a alguien que todavía no sale (cancel_pass). Con `detail` muestra
 * primero al alumno y el botón; sin él, va directo a la confirmación.
 */
export function RemoveFromQueueDialog({
  name,
  groupName,
  detail,
  question,
  note = 'Su maestro tendrá que pedir el pase otra vez.',
  confirmLabel = 'Sí, quitar',
  busy,
  onConfirm,
  onClose,
}: {
  name: string;
  groupName: string;
  detail?: string;
  /** Pregunta de la confirmación; por omisión "¿Quitar a X de la fila?". */
  question?: string;
  note?: string;
  confirmLabel?: string;
  busy: boolean;
  onConfirm: () => void;
  onClose: () => void;
}) {
  const id = useId();
  const [confirming, setConfirming] = useState(detail === undefined);
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
        aria-labelledby={`${id}-t`}
        onClick={(e) => e.stopPropagation()}
        className="pb-safe flex w-full flex-col gap-3 rounded-t-[22px] bg-surface p-5 sm:max-w-[460px] sm:rounded-card-lg sm:p-7"
      >
        <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-muted">
          {groupName}
        </span>
        {confirming ? (
          <>
            <h2 id={`${id}-t`} className="m-0 font-display text-[24px] font-bold">
              {question ?? `¿Quitar a ${name} de la fila?`}
            </h2>
            <p className="m-0 text-[15px] text-muted">{note}</p>
            <div className="grid grid-cols-2 gap-2">
              <button type="button" onClick={onClose} className={buttonClass.secondary}>
                No
              </button>
              <button
                type="button"
                autoFocus
                disabled={busy}
                onClick={onConfirm}
                className={buttonClass.danger}
              >
                {confirmLabel}
              </button>
            </div>
          </>
        ) : (
          <>
            <h2 id={`${id}-t`} className="m-0 font-display text-[26px] font-bold">
              {name}
            </h2>
            {detail ? <p className="m-0 text-[15px] text-muted">{detail}</p> : null}
            <button
              type="button"
              onClick={() => setConfirming(true)}
              className={buttonClass.danger}
            >
              Quitar de la fila
            </button>
            <button type="button" onClick={onClose} className={buttonClass.secondary}>
              Cerrar
            </button>
          </>
        )}
      </div>
    </div>
  );
}
