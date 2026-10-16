import { useEffect } from 'react';
import { Loading, Notice } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { errorMessage, useStudentToday } from '@/lib/live';
import { hm } from '@/lib/monitor';

/** Lista de las salidas de hoy de un alumno: hora, destino, clase y quién autorizó. */
export function TodayList({ studentId }: { studentId: string }) {
  const today = useStudentToday(studentId);
  if (today.isPending) return <Loading />;
  if (today.isError) return <Notice tone="error">{errorMessage(today.error)}</Notice>;
  if (!today.data.length) return <p className="m-0 text-[15px] text-muted">Hoy no ha salido.</p>;
  return (
    <ol className="m-0 flex list-none flex-col gap-1.5 p-0">
      {today.data.map((e, i) => (
        <li
          key={i}
          className={`flex flex-col rounded-btn border px-3 py-2 ${
            e.alert ? 'border-alert-bd bg-alert-bg' : 'border-line'
          }`}
        >
          <span className="flex flex-wrap justify-between gap-x-3">
            <span className="font-mono font-semibold tabular-nums">
              {hm(e.started_at)}
              {e.ended_at ? ` – ${hm(e.ended_at)}` : ' – en curso'}
            </span>
            <span className={`font-bold ${e.alert ? 'text-alert-fg' : ''}`}>
              {e.minutes != null ? `${e.minutes} min` : ''}
              {e.alert ? ' · alerta' : ''}
            </span>
          </span>
          <span className="text-[14px] text-muted">
            {e.destination}
            {e.subject ? ` · en ${e.subject}` : ''}
            {e.opened_by ? ` · autorizó ${e.opened_by}` : ''}
          </span>
        </li>
      ))}
    </ol>
  );
}

/** Ventana con las salidas de hoy (al tocar el símbolo ⚠ de la lista). */
export function TodayDialog({
  studentId,
  name,
  onClose,
}: {
  studentId: string;
  name: string;
  onClose: () => void;
}) {
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
        aria-label={`Salidas de hoy de ${name}`}
        onClick={(e) => e.stopPropagation()}
        className="pb-safe flex max-h-[85vh] w-full flex-col gap-3 overflow-y-auto rounded-t-[22px] bg-surface p-5 sm:max-w-[480px] sm:rounded-card-lg sm:p-7"
      >
        <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-wait-fg">
          Salidas de hoy
        </span>
        <h2 className="m-0 font-display text-[24px] font-bold">{name}</h2>
        <TodayList studentId={studentId} />
        <button type="button" onClick={onClose} className={buttonClass.secondary}>
          Cerrar
        </button>
      </div>
    </div>
  );
}
