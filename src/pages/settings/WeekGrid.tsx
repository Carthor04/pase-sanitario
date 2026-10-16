import type { ReactNode } from 'react';
import { hhmm } from '@/lib/queries';
import { WEEK_DAYS, isNow, slotsOf, useNowMx } from '@/lib/schedule';

type Slot = { weekday: number; starts: string; ends: string };

/** Horario semanal (franjas × lunes–viernes) con la clase de este momento resaltada. */
export function WeekGrid<T extends Slot>({
  entries,
  cell,
}: {
  entries: T[];
  cell: (e: T) => ReactNode;
}) {
  const now = useNowMx();
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[640px] border-collapse text-left text-[14px]">
        <thead>
          <tr className="border-b border-line">
            <th className="py-2 pr-2 font-bold">Hora</th>
            {WEEK_DAYS.map((d, i) => (
              <th
                key={d}
                className={`px-2 py-2 font-bold ${now.weekday === i + 1 ? 'text-accent' : ''}`}
              >
                {d}
                {now.weekday === i + 1 ? <span className="font-normal"> · hoy</span> : null}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {slotsOf(entries).map((slot) => {
            const [starts, ends] = slot.split('|') as [string, string];
            return (
              <tr key={slot} className="border-b border-line align-top last:border-0">
                <td className="whitespace-nowrap py-2 pr-2 font-mono tabular-nums text-muted">
                  {hhmm(starts)}–{hhmm(ends)}
                </td>
                {[1, 2, 3, 4, 5].map((wd) => {
                  const e = entries.find(
                    (x) => x.weekday === wd && x.starts === starts && x.ends === ends,
                  );
                  const current = e ? isNow(e, now) : false;
                  return (
                    <td
                      key={wd}
                      aria-current={current ? 'time' : undefined}
                      className={`px-2 py-2 ${
                        current ? 'rounded-[8px] bg-free-bg outline outline-2 outline-free-fg' : ''
                      }`}
                    >
                      {current ? (
                        <span className="block text-[11px] font-bold uppercase tracking-[0.08em] text-free-fg">
                          ● Ahora
                        </span>
                      ) : null}
                      {e ? cell(e) : null}
                    </td>
                  );
                })}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
