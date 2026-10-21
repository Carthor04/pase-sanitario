import { hhmm } from '@/lib/queries';
import { nextToday, useNowMx, type TeacherSchedule } from '@/lib/schedule';

/** "En clase ahora" o "Sin clase · siguiente…". El estado lo decide el servidor. */
export function TeacherStatus({ name, data }: { name: string; data: TeacherSchedule }) {
  const now = useNowMx();
  const c = data.current;
  const next = nextToday(data.entries, now);
  if (c) {
    return (
      <div
        role="status"
        className="flex flex-col gap-0.5 rounded-btn-lg border-2 border-free-fg bg-free-bg px-4 py-3"
      >
        <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-free-fg">
          ● En clase ahora
        </span>
        <span className="font-display text-[22px] font-bold">
          {c.group_name} · {c.subject}
        </span>
        <span className="text-[15px] text-muted">
          {name}
          {c.room ? ` · ${c.room}` : ''} ·{' '}
          <span className="font-mono tabular-nums">
            {hhmm(c.starts)}–{hhmm(c.ends)}
          </span>
        </span>
        {next ? (
          <span className="text-[15px]">
            Después: <strong>{next.group_name}</strong> · {next.subject}
            {next.room ? ` · ${next.room}` : ''} a las{' '}
            <span className="font-mono tabular-nums">{hhmm(next.starts)}</span>
          </span>
        ) : null}
      </div>
    );
  }
  return (
    <div
      role="status"
      className="flex flex-col gap-0.5 rounded-btn-lg border border-line px-4 py-3"
    >
      <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-muted">
        ○ Sin clase en este momento
      </span>
      <span className="text-[16px]">
        {next ? (
          <>
            Siguiente: <strong>{next.group_name}</strong> · {next.subject}
            {next.room ? ` · ${next.room}` : ''} a las{' '}
            <span className="font-mono tabular-nums">{hhmm(next.starts)}</span>
          </>
        ) : data.entries.some((e) => e.weekday === now.weekday) ? (
          'Ya terminó sus clases de hoy.'
        ) : (
          'Hoy no tiene clases.'
        )}
      </span>
    </div>
  );
}
