import { useQuery } from '@tanstack/react-query';
import { useId, useState } from 'react';
import { Card, Loading, SectionLabel } from '@/components/ui/Page';
import { hhmm, useGroups } from '@/lib/queries';
import { supabase } from '@/lib/supabase';
import { ImportPanel } from './ImportPanel';

type Entry = {
  weekday: number;
  starts: string;
  ends: string;
  subject: string;
  teacher_name: string | null;
};
const DAYS = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes'];

/** Configuración → Horarios: ver el horario de un grupo e importar grupos/horario. */
export function SchedulePanel() {
  const selectId = useId();
  const groups = useGroups();
  const [groupId, setGroupId] = useState('');
  const selected = groupId || groups.data?.[0]?.id || '';

  const schedule = useQuery({
    queryKey: ['schedule', selected],
    enabled: Boolean(selected),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('group_schedule', { p_group_id: selected });
      if (error) throw error;
      return data as unknown as Entry[];
    },
  });

  const slots = [...new Set((schedule.data ?? []).map((e) => `${e.starts}|${e.ends}`))].sort();

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <SectionLabel>Horario del grupo</SectionLabel>
          <div className="flex items-center gap-2">
            <label htmlFor={selectId} className="font-bold">
              Grupo
            </label>
            <select
              id={selectId}
              value={selected}
              onChange={(e) => setGroupId(e.target.value)}
              className="min-h-btn rounded-btn border border-line-strong bg-surface px-3 text-[16px]"
            >
              {groups.data?.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </select>
          </div>
        </div>
        {schedule.isPending ? <Loading /> : null}
        {schedule.data && schedule.data.length === 0 ? (
          <span className="text-muted">Este grupo no tiene horario. Impórtalo abajo.</span>
        ) : null}
        {schedule.data && schedule.data.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px] border-collapse text-left text-[14px]">
              <thead>
                <tr className="border-b border-line">
                  <th className="py-2 pr-2 font-bold">Hora</th>
                  {DAYS.map((d) => (
                    <th key={d} className="px-2 py-2 font-bold">
                      {d}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {slots.map((slot) => {
                  const [starts, ends] = slot.split('|');
                  return (
                    <tr key={slot} className="border-b border-line align-top last:border-0">
                      <td className="whitespace-nowrap py-2 pr-2 font-mono tabular-nums text-muted">
                        {hhmm(starts)}–{hhmm(ends)}
                      </td>
                      {[1, 2, 3, 4, 5].map((wd) => {
                        const e = schedule.data.find(
                          (x) => x.weekday === wd && x.starts === starts && x.ends === ends,
                        );
                        return (
                          <td key={wd} className="px-2 py-2">
                            {e ? (
                              <>
                                <span className="font-bold">{e.subject}</span>
                                {e.teacher_name ? (
                                  <span className="block text-[12px] text-muted">
                                    {e.teacher_name}
                                  </span>
                                ) : null}
                              </>
                            ) : null}
                          </td>
                        );
                      })}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : null}
      </Card>
      <ImportPanel kind="groups" title="Importar grupos" />
      <ImportPanel kind="schedule" title="Importar horario" />
    </div>
  );
}
