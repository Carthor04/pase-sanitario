import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Card, Loading, Notice, SectionLabel } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { errorMessage, invalidateLive } from '@/lib/live';
import { supabase } from '@/lib/supabase';

type Range = { starts: string; ends: string };

/**
 * Horarios sin baño (solo admin): de lunes a viernes, en esas horas nadie entra a los baños
 * ni se agrega a las listas de espera. Las reglas viven en la BD (set_bathroom_closures).
 */
export function ClosuresPanel() {
  const query = useQuery({
    queryKey: ['closures'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('bathroom_closures_list');
      if (error) throw error;
      return data as unknown as Range[];
    },
  });
  if (query.isError) return <Notice tone="error">{errorMessage(query.error)}</Notice>;
  if (!query.data) return <Loading />;
  // La key reinicia el borrador cuando cambia lo guardado.
  return <ClosuresForm key={JSON.stringify(query.data)} saved={query.data} />;
}

function ClosuresForm({ saved }: { saved: Range[] }) {
  const queryClient = useQueryClient();
  const [ranges, setRanges] = useState<Range[]>(saved);
  const [msg, setMsg] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);
  const save = useMutation({
    mutationFn: async (r: Range[]) => {
      const { error } = await supabase.rpc('set_bathroom_closures', { p_ranges: r });
      if (error) throw error;
    },
    onSuccess: () => setMsg({ tone: 'ok', text: 'Horarios guardados. Aplican de inmediato.' }),
    onError: (err) => setMsg({ tone: 'error', text: errorMessage(err) }),
    onSettled: () =>
      Promise.all([
        queryClient.invalidateQueries({ queryKey: ['closures'] }),
        invalidateLive(queryClient),
      ]),
  });
  const dirty = JSON.stringify(ranges) !== JSON.stringify(saved);
  const set = (i: number, patch: Partial<Range>) =>
    setRanges((rs) => rs.map((r, k) => (k === i ? { ...r, ...patch } : r)));

  return (
    <Card>
      <SectionLabel>Horarios sin baño</SectionLabel>
      <p className="m-0 text-[15px] text-muted">
        De lunes a viernes, en estos horarios no se entra a los baños ni se agrega a nadie a las
        listas de espera. Quien ya está fuera sigue con su tiempo; la fila sigue en el mismo orden
        al terminar.
      </p>
      {ranges.length === 0 ? <Notice>Sin horarios: los baños abren todo el día.</Notice> : null}
      <ul className="m-0 flex list-none flex-col gap-2 p-0">
        {ranges.map((r, i) => (
          <li key={i} className="flex flex-wrap items-end gap-2">
            <label className="flex flex-col gap-1">
              <span className="text-[14px] font-bold">De</span>
              <input
                type="time"
                value={r.starts}
                onChange={(e) => set(i, { starts: e.target.value })}
                className="min-h-btn rounded-btn border border-line-strong px-3 font-mono text-[17px] tabular-nums"
              />
            </label>
            <label className="flex flex-col gap-1">
              <span className="text-[14px] font-bold">A</span>
              <input
                type="time"
                value={r.ends}
                onChange={(e) => set(i, { ends: e.target.value })}
                className="min-h-btn rounded-btn border border-line-strong px-3 font-mono text-[17px] tabular-nums"
              />
            </label>
            <button
              type="button"
              onClick={() => setRanges((rs) => rs.filter((_, k) => k !== i))}
              className={buttonClass.danger}
            >
              Quitar
            </button>
          </li>
        ))}
      </ul>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => setRanges((rs) => [...rs, { starts: '', ends: '' }])}
          className={buttonClass.secondary}
        >
          Agregar horario
        </button>
        <button
          type="button"
          disabled={!dirty || save.isPending}
          onClick={() => save.mutate(ranges)}
          className={buttonClass.primary}
        >
          Guardar horarios
        </button>
      </div>
      {msg ? <Notice tone={msg.tone}>{msg.text}</Notice> : null}
    </Card>
  );
}
