import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Card, Loading, Notice, SectionLabel } from '@/components/ui/Page';
import { errorMessage } from '@/lib/live';
import { supabase } from '@/lib/supabase';
import { ImportPanel } from './ImportPanel';

type Guard = {
  weekday: number;
  starts: string;
  ends: string;
  staff_id: string | null;
  staff_name: string | null;
};

const DAYS = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes'];

/**
 * Guardias del baño: quién cuida el baño a cada hora. Quien está de guardia ve En vivo
 * durante su turno. Se cargan desde el horario oficial y aquí se corrigen una por una.
 */
export function GuardsPanel() {
  const queryClient = useQueryClient();
  const [error, setError] = useState<string | null>(null);
  const guards = useQuery({
    queryKey: ['guards'],
    queryFn: async () => {
      const { data, error: err } = await supabase.rpc('bathroom_guards_list');
      if (err) throw err;
      return data as unknown as Guard[];
    },
  });
  const staff = useQuery({
    queryKey: ['staff', 'guards'],
    queryFn: async () => {
      const { data, error: err } = await supabase
        .from('staff')
        .select('id, full_name')
        .eq('active', true)
        .order('full_name');
      if (err) throw err;
      return data;
    },
  });
  const save = useMutation({
    mutationFn: async (g: { weekday: number; starts: string; staffId: string | null }) => {
      const { error: err } = await supabase.rpc('set_bathroom_guard', {
        p_weekday: g.weekday,
        p_starts: g.starts,
        p_staff_id: g.staffId,
      });
      if (err) throw err;
    },
    onError: (err) => setError(errorMessage(err)),
    onSuccess: () => setError(null),
    onSettled: () =>
      Promise.all(['guards', 'me'].map((k) => queryClient.invalidateQueries({ queryKey: [k] }))),
  });

  if (guards.isError) return <Notice tone="error">{errorMessage(guards.error)}</Notice>;
  if (!guards.data || !staff.data) return <Loading />;
  const empty = guards.data.filter((g) => !g.staff_id).length;

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <SectionLabel>Guardias del baño</SectionLabel>
        <p className="m-0 text-[15px] text-muted">
          Quien está de guardia ve En vivo mientras dura su turno. Lo que puede hacer ahí depende de
          su rol.
          {empty ? ` ${empty} sin asignar.` : ''}
        </p>
        {error ? <Notice tone="error">{error}</Notice> : null}
        {guards.data.length === 0 ? (
          <Notice>Todavía no hay guardias. Impórtalas desde el archivo de abajo.</Notice>
        ) : null}
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-5">
          {DAYS.map((day, i) => (
            <section key={day} aria-label={day} className="flex flex-col gap-2">
              <h3 className="m-0 font-display text-[18px] font-bold">{day}</h3>
              {guards.data
                .filter((g) => g.weekday === i + 1)
                .map((g) => (
                  <label key={g.starts} className="flex flex-col gap-1">
                    <span className="font-mono text-[13px] tabular-nums text-muted">
                      {g.starts}–{g.ends}
                    </span>
                    <select
                      value={g.staff_id ?? ''}
                      disabled={save.isPending}
                      onChange={(e) =>
                        save.mutate({
                          weekday: g.weekday,
                          starts: g.starts,
                          staffId: e.target.value || null,
                        })
                      }
                      className={`min-h-btn rounded-btn border px-2 text-[15px] ${
                        g.staff_id ? 'border-line-strong bg-surface' : 'border-wait-bd bg-wait-bg'
                      }`}
                    >
                      <option value="">Sin asignar</option>
                      {staff.data.map((s) => (
                        <option key={s.id} value={s.id}>
                          {s.full_name}
                        </option>
                      ))}
                    </select>
                  </label>
                ))}
            </section>
          ))}
        </div>
      </Card>
      <ImportPanel kind="guards" title="Importar guardias desde CSV" />
    </div>
  );
}
