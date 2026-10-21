import { useQuery } from '@tanstack/react-query';
import { useId, useState } from 'react';
import { Card, Loading, Notice, SectionLabel } from '@/components/ui/Page';
import { errorMessage } from '@/lib/live';
import { hhmm, useGroups } from '@/lib/queries';
import { useCurrentClasses } from '@/lib/schedule';
import { supabase } from '@/lib/supabase';
import { ImportPanel } from './ImportPanel';
import { WeekGrid } from './WeekGrid';

type Entry = {
  weekday: number;
  starts: string;
  ends: string;
  subject: string;
  teacher_name: string | null;
};

/** Configuración → Horarios: la clase de cada grupo ahora, el horario de un grupo e importar. */
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

  return (
    <div className="flex flex-col gap-4">
      <NowCard onPick={setGroupId} />
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
          <WeekGrid
            entries={schedule.data}
            cell={(e) => (
              <>
                <span className="font-bold">{e.subject}</span>
                {e.teacher_name ? (
                  <span className="block text-[12px] text-muted">{e.teacher_name}</span>
                ) : null}
              </>
            )}
          />
        ) : null}
      </Card>
      <ImportPanel kind="groups" title="Importar grupos" />
      <ImportPanel kind="schedule" title="Importar horario" />
      <ImportPanel kind="sections" title="Importar clases por nivel (Inglés)" />
    </div>
  );
}

/** En qué clase está cada grupo en este momento. */
function NowCard({ onPick }: { onPick: (groupId: string) => void }) {
  const current = useCurrentClasses();
  const inClass = current.data?.filter((g) => g.subject).length ?? 0;
  return (
    <Card>
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <SectionLabel>Ahora</SectionLabel>
        {current.data ? (
          <span className="text-[14px] text-muted">
            {inClass} de {current.data.length} grupos en clase · se actualiza cada minuto
          </span>
        ) : null}
      </div>
      {current.isPending ? <Loading /> : null}
      {current.isError ? <Notice tone="error">{errorMessage(current.error)}</Notice> : null}
      {current.data ? (
        <ul className="m-0 grid list-none gap-2 p-0 sm:grid-cols-2 lg:grid-cols-3">
          {current.data.map((g) => (
            <li key={g.group_id}>
              <button
                type="button"
                onClick={() => onPick(g.group_id)}
                title={`Ver el horario de ${g.group_name}`}
                className={`flex min-h-btn w-full items-start gap-3 rounded-btn-lg border px-3 py-2 text-left hover:border-accent ${
                  g.subject ? 'border-transparent bg-free-bg' : 'border-line bg-surface'
                }`}
              >
                <span className="w-12 shrink-0 font-display text-[20px] font-bold">
                  {g.group_name}
                </span>
                <span className="flex min-w-0 flex-col">
                  {g.subject ? (
                    <>
                      <span className="font-bold">
                        <span aria-hidden="true" className="text-free-fg">
                          ●{' '}
                        </span>
                        {g.subject}
                      </span>
                      <span className="text-[13px] text-muted">
                        {g.teacher_name ?? 'Sin maestro'} · hasta{' '}
                        <span className="font-mono tabular-nums">{hhmm(g.ends!)}</span>
                      </span>
                    </>
                  ) : (
                    <span className="text-muted">○ Sin clase en este momento</span>
                  )}
                </span>
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </Card>
  );
}
