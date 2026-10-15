import { useEffect, useId, useState, type FormEvent } from 'react';
import { buttonClass } from '@/components/ui/styles';
import { formatElapsed } from '@/lib/board';
import { alertStatusText, hm, type PassAlert } from '@/lib/monitor';

type AlertCardProps = {
  name: string;
  groupName: string;
  place: string;
  startedAt: string | null;
  periodSubject?: string | null;
  alert: NonNullable<PassAlert>;
  now: number;
  busy: boolean;
  onAcknowledge?: () => void;
  onRelease?: () => void;
  onReturn?: () => void;
};

/** Tarjeta roja de alerta de 10 min (Prefectura, MovilPrefectura y Alertas del maestro). */
export function AlertCard(p: AlertCardProps) {
  const elapsed = p.startedAt ? p.now - new Date(p.startedAt).getTime() : 0;
  const escalated = p.alert.level === 2 && !p.alert.acknowledged_by_name;
  return (
    <section
      role="alert"
      aria-label={`Alerta: ${p.name}`}
      className={`flex flex-col gap-3 rounded-card border-2 border-alert-bd bg-alert-bg px-4 py-4 sm:flex-row sm:items-center sm:gap-6 sm:px-5 ${
        escalated ? 'ring-4 ring-alert-bd/30' : ''
      }`}
    >
      <div className="flex items-start justify-between gap-3 sm:contents">
        <span className="order-2 font-mono text-[32px] font-semibold tabular-nums leading-none text-alert-fg sm:order-none sm:text-[36px]">
          {formatElapsed(elapsed)}
        </span>
        <div className="order-1 flex min-w-0 flex-1 flex-col sm:order-none">
          <span className="text-[19px] font-bold leading-tight sm:text-[20px]">
            {p.name} · {p.groupName} · {p.place}
          </span>
          <span className="text-[14px] text-alert-fg">
            {escalated ? 'ALERTA ESCALADA · ' : ''}
            {alertStatusText(p.alert)}
            {p.startedAt ? ` · salió ${hm(p.startedAt)}` : ''}
            {p.periodSubject ? ` en ${p.periodSubject}` : ''}
          </span>
        </div>
      </div>
      <div className="grid grid-cols-[1fr_1.6fr] gap-2 sm:flex sm:shrink-0">
        {p.onRelease ? (
          <button
            type="button"
            disabled={p.busy}
            onClick={p.onRelease}
            className="min-h-btn rounded-btn border border-alert-bd bg-surface px-4 text-[15px] font-bold text-alert-fg disabled:opacity-60"
          >
            Liberar lugar
          </button>
        ) : null}
        {p.onAcknowledge && !p.alert.acknowledged_by_name ? (
          <button
            type="button"
            disabled={p.busy}
            onClick={p.onAcknowledge}
            className="min-h-btn rounded-btn bg-alert-fg px-5 text-[17px] font-bold text-white disabled:opacity-60"
          >
            Yo lo atiendo
          </button>
        ) : p.onReturn ? (
          <button
            type="button"
            disabled={p.busy}
            onClick={p.onReturn}
            className={`${buttonClass.primary} ${p.onRelease ? '' : 'col-span-2'}`}
          >
            Marcar regreso
          </button>
        ) : null}
      </div>
    </section>
  );
}

/** Liberar lugar: pide el motivo (obligatorio, queda en la bitácora). */
export function ReleaseDialog({
  name,
  busy,
  onConfirm,
  onClose,
}: {
  name: string;
  busy: boolean;
  onConfirm: (reason: string) => void;
  onClose: () => void;
}) {
  const id = useId();
  const [reason, setReason] = useState('');
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  function submit(e: FormEvent) {
    e.preventDefault();
    if (reason.trim()) onConfirm(reason.trim());
  }

  return (
    <div
      className="fixed inset-0 z-40 flex items-end justify-center bg-ink/50 sm:items-center sm:p-6"
      onClick={onClose}
    >
      <form
        role="dialog"
        aria-modal="true"
        aria-labelledby={`${id}-t`}
        onSubmit={submit}
        onClick={(e) => e.stopPropagation()}
        className="pb-safe flex w-full flex-col gap-4 rounded-t-[22px] bg-surface p-5 sm:max-w-[480px] sm:rounded-card-lg sm:p-7"
      >
        <h2 id={`${id}-t`} className="m-0 font-display text-[24px] font-bold">
          Liberar lugar de {name}
        </h2>
        <p className="m-0 text-[15px] text-muted">
          Cierra el pase sin marcar regreso y deja libre su lugar. Queda como incidencia en la
          bitácora.
        </p>
        <label htmlFor={id} className="font-bold">
          Motivo (obligatorio)
        </label>
        <textarea
          id={id}
          autoFocus
          rows={3}
          maxLength={300}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="Ej. Se le encontró en el patio y regresó con prefectura"
          className="rounded-btn border border-line-strong p-3 text-[17px]"
        />
        <div className="grid grid-cols-2 gap-2">
          <button type="button" onClick={onClose} className={buttonClass.secondary}>
            Cancelar
          </button>
          <button type="submit" disabled={busy || !reason.trim()} className={buttonClass.danger}>
            Liberar lugar
          </button>
        </div>
      </form>
    </div>
  );
}
