import { useQuery } from '@tanstack/react-query';
import { Card, Loading, Notice, PageTitle } from '@/components/ui/Page';
import { formatElapsed } from '@/lib/board';
import { errorMessage, useLivePasses, useServerNow } from '@/lib/live';
import { supabase } from '@/lib/supabase';

type Status = {
  now: string;
  nurse: number;
  bathrooms: {
    id: string;
    label: string;
    sex: 'H' | 'M';
    capacity: number | null;
    occupants: { group_name: string; status: 'called' | 'out'; since: string }[];
    queue: { group_name: string; since: string }[];
    group_wait: number;
  }[];
};

/** Baños (maestro): cuántos hay dentro y quién está en fila, sin nombres de alumnos. */
export function Bathrooms() {
  useLivePasses();
  const status = useQuery({
    queryKey: ['board', 'bathrooms'],
    refetchInterval: 30_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('bathrooms_status');
      if (error) throw error;
      const s = data as unknown as Status;
      return { ...s, offsetMs: new Date(s.now).getTime() - Date.now() };
    },
  });
  const now = useServerNow(status.data?.offsetMs ?? 0);

  if (status.isPending) return <Loading />;
  if (status.isError) return <Notice tone="error">{errorMessage(status.error)}</Notice>;

  return (
    <div className="flex flex-col gap-4">
      <PageTitle>Baños</PageTitle>
      <div className="grid gap-4 sm:grid-cols-2">
        {status.data.bathrooms.map((b) => {
          const occ = b.occupants.length;
          const full = b.capacity !== null && occ >= b.capacity;
          return (
            <Card key={b.id}>
              <div className="flex items-center justify-between gap-2">
                <h2 className="m-0 font-display text-[22px] font-bold">{b.label}</h2>
                <span
                  className={`rounded-chip px-2.5 py-0.5 text-[13px] font-bold ${full ? 'bg-ink text-white' : 'bg-free-bg text-free-fg'}`}
                >
                  {occ}
                  {b.capacity !== null ? ` / ${b.capacity}` : ''} · {full ? 'Lleno' : 'Con lugar'}
                </span>
              </div>
              <div className="flex flex-col gap-1.5">
                <span className="text-[12px] font-bold uppercase tracking-[0.08em] text-muted">
                  Dentro
                </span>
                {occ === 0 ? <span className="text-muted">Nadie</span> : null}
                {b.occupants.map((o, i) => (
                  <span
                    key={i}
                    className="flex justify-between rounded-btn border border-line px-3 py-2"
                  >
                    <strong>{o.group_name}</strong>
                    <span className="font-mono tabular-nums">
                      {o.status === 'called'
                        ? 'su turno'
                        : formatElapsed(now - new Date(o.since).getTime())}
                    </span>
                  </span>
                ))}
              </div>
              <div className="flex flex-col gap-1.5">
                <span className="text-[12px] font-bold uppercase tracking-[0.08em] text-wait-fg">
                  Fila · {b.queue.length}
                </span>
                {b.queue.length === 0 ? (
                  <span className="text-free-fg">
                    Sin fila: si sale alguien ahora, entra directo
                  </span>
                ) : null}
                {b.queue.map((q, i) => (
                  <span
                    key={i}
                    className="flex justify-between rounded-btn border border-wait-bd/50 bg-wait-bg/40 px-3 py-2"
                  >
                    <span>
                      {i + 1}. <strong>{q.group_name}</strong>
                    </span>
                    <span className="font-mono tabular-nums text-wait-fg">
                      espera {formatElapsed(now - new Date(q.since).getTime())}
                    </span>
                  </span>
                ))}
                {b.group_wait ? (
                  <span className="text-[14px] text-muted">
                    {b.group_wait} en espera de su grupo
                  </span>
                ) : null}
              </div>
            </Card>
          );
        })}
      </div>
      <Notice>
        Enfermería: {status.data.nurse} {status.data.nurse === 1 ? 'alumno' : 'alumnos'} ahora. No
        hace fila ni ocupa lugar del grupo.
      </Notice>
    </div>
  );
}
