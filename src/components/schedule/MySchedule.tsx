import { Card, Loading, Notice, SectionLabel } from '@/components/ui/Page';
import { errorMessage } from '@/lib/live';
import { hhmm } from '@/lib/queries';
import { WEEK_DAYS, isNow, useNowMx, useTeacherSchedule } from '@/lib/schedule';
import { TeacherStatus } from './TeacherStatus';
import { WeekGrid } from './WeekGrid';

/** Perfil del maestro: su clase ahora (o la siguiente), sus clases de hoy y la semana. */
export function MySchedule({ staffId, name }: { staffId: string; name: string }) {
  const schedule = useTeacherSchedule(staffId);
  const now = useNowMx();

  if (schedule.isPending) return <Loading />;
  if (schedule.isError) return <Notice tone="error">{errorMessage(schedule.error)}</Notice>;

  const entries = schedule.data.entries;
  const today = entries.filter((e) => e.weekday === now.weekday);

  return (
    <Card>
      <SectionLabel>Mi horario</SectionLabel>
      {entries.length === 0 ? (
        <span className="text-[15px] text-muted">
          Todavía no tienes clases en el horario. Pide a coordinación que revise tu correo en el
          horario importado.
        </span>
      ) : (
        <>
          <TeacherStatus name={name} data={schedule.data} />
          {today.length ? (
            <div className="flex flex-col gap-1">
              <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-muted">
                Hoy · {WEEK_DAYS[now.weekday - 1]}
              </span>
              <ul className="m-0 flex list-none flex-col gap-1 p-0">
                {today.map((e) => {
                  const current = isNow(e, now);
                  const past = e.ends <= now.time;
                  return (
                    <li
                      key={`${e.starts}-${e.group_name}`}
                      className={`flex items-center gap-3 rounded-btn px-3 py-2 ${
                        current ? 'border-2 border-free-fg bg-free-bg' : 'border border-line'
                      } ${past ? 'text-muted' : ''}`}
                    >
                      <span className="w-[92px] shrink-0 font-mono text-[15px] tabular-nums">
                        {hhmm(e.starts)}–{hhmm(e.ends)}
                      </span>
                      <span className="flex min-w-0 flex-col">
                        <span className="font-bold">
                          {e.group_name} · {e.subject}
                        </span>
                        {e.room ? <span className="text-[13px] text-muted">{e.room}</span> : null}
                      </span>
                      {current ? (
                        <span className="ml-auto shrink-0 text-[13px] font-bold text-free-fg">
                          Ahora
                        </span>
                      ) : null}
                    </li>
                  );
                })}
              </ul>
            </div>
          ) : null}
          <details className="rounded-btn border border-line px-3 py-2">
            <summary className="min-h-[40px] cursor-pointer content-center font-bold">
              Semana completa
            </summary>
            <div className="pt-2">
              <WeekGrid
                entries={entries}
                cell={(e) => (
                  <>
                    <span className="font-bold">{e.group_name}</span>
                    <span className="block text-[12px] text-muted">
                      {e.subject}
                      {e.room ? ` · ${e.room}` : ''}
                    </span>
                  </>
                )}
              />
            </div>
          </details>
        </>
      )}
    </Card>
  );
}
