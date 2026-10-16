import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState, type FormEvent } from 'react';
import { Card, Loading, Notice, SectionLabel } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { errorMessage } from '@/lib/live';
import { supabase } from '@/lib/supabase';

type Dest = {
  id: string;
  label: string;
  kind: 'bathroom' | 'nurse';
  sex: 'H' | 'M' | null;
  capacity: number | null;
  per_group_limit: number | null;
  uses_group_slot: boolean;
  queue_enabled: boolean;
};

type Times = {
  alert_minutes: number;
  escalate_minutes: number;
  confirm_turn_minutes: number;
  auto_lock_after_class_minutes: number;
  undo_seconds: number;
  review_alerts_threshold: number;
  review_exits_threshold: number;
  daily_exits_flag: number;
};

const TIME_FIELDS: {
  key: keyof Times;
  label: string;
  unit: string;
  help: string;
  min: number;
  max: number;
}[] = [
  {
    key: 'alert_minutes',
    label: 'Alerta por tiempo fuera',
    unit: 'min',
    help: 'Baño y trayecto a enfermería',
    min: 1,
    max: 120,
  },
  {
    key: 'escalate_minutes',
    label: 'Repetir si nadie la atiende',
    unit: 'min',
    help: 'Se reenvía con prioridad alta',
    min: 1,
    max: 60,
  },
  {
    key: 'confirm_turn_minutes',
    label: 'Tiempo para confirmar turno',
    unit: 'min',
    help: 'Después pasa al siguiente en la fila',
    min: 1,
    max: 15,
  },
  {
    key: 'auto_lock_after_class_minutes',
    label: 'Bloqueo automático del salón',
    unit: 'min',
    help: 'Después de que termina la clase',
    min: 0,
    max: 60,
  },
  {
    key: 'undo_seconds',
    label: 'Tiempo para deshacer',
    unit: 's',
    help: 'Después de abrir un pase o marcar regreso',
    min: 3,
    max: 60,
  },
  {
    key: 'daily_exits_flag',
    label: 'Marcar al alumno (⚠) en la lista',
    unit: 'salidas al día',
    help: 'Desde cuántas idas al baño en el mismo día',
    min: 1,
    max: 20,
  },
  {
    key: 'review_alerts_threshold',
    label: '"A revisar": alertas',
    unit: 'o más',
    help: 'En el periodo del reporte',
    min: 1,
    max: 50,
  },
  {
    key: 'review_exits_threshold',
    label: '"A revisar": salidas',
    unit: 'más de',
    help: 'En el periodo del reporte',
    min: 1,
    max: 100,
  },
];

/** Configuración → Baños y reglas (SPEC §3 y §10). Los valores viven en destinations/settings. */
export function RulesPanel() {
  const queryClient = useQueryClient();
  const data = useQuery({
    queryKey: ['rules'],
    queryFn: async () => {
      const [d, s] = await Promise.all([
        supabase
          .from('destinations')
          .select('id, label, kind, sex, capacity, per_group_limit, uses_group_slot, queue_enabled')
          .order('kind')
          .order('sex'),
        supabase
          .from('settings')
          .select(
            'alert_minutes, escalate_minutes, confirm_turn_minutes, auto_lock_after_class_minutes, undo_seconds, review_alerts_threshold, review_exits_threshold, daily_exits_flag',
          )
          .eq('id', 1)
          .single(),
      ]);
      if (d.error) throw d.error;
      if (s.error) throw s.error;
      return { dests: d.data as Dest[], times: s.data as Times };
    },
  });

  const [dests, setDests] = useState<Dest[]>([]);
  const [times, setTimes] = useState<Times | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);

  useEffect(() => {
    if (data.data) {
      setDests(data.data.dests);
      setTimes(data.data.times);
    }
  }, [data.data]);

  if (data.isPending || !times) return <Loading />;
  if (data.isError) return <Notice tone="error">{errorMessage(data.error)}</Notice>;

  const setDest = (id: string, patch: Partial<Dest>) =>
    setDests((ds) => ds.map((d) => (d.id === id ? { ...d, ...patch } : d)));

  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setMsg(null);
    try {
      for (const d of dests) {
        const { error } = await supabase
          .from('destinations')
          .update({
            capacity: d.capacity,
            per_group_limit: d.per_group_limit,
            uses_group_slot: d.uses_group_slot,
            queue_enabled: d.queue_enabled,
          })
          .eq('id', d.id);
        if (error) throw error;
      }
      const { error } = await supabase.from('settings').update(times!).eq('id', 1);
      if (error) throw error;
      setMsg({ tone: 'ok', text: 'Cambios guardados. Aplican de inmediato.' });
      await queryClient.invalidateQueries({ queryKey: ['rules'] });
      await queryClient.invalidateQueries({ queryKey: ['board'] });
    } catch (err) {
      setMsg({
        tone: 'error',
        text: /check/i.test(errorMessage(err))
          ? 'Algún valor está fuera de rango. Revisa los números.'
          : errorMessage(err),
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={save} className="flex flex-col gap-4">
      <Card>
        <SectionLabel>Baños y enfermería</SectionLabel>
        <div className="grid gap-3 md:grid-cols-3">
          {dests.map((d) =>
            d.kind === 'bathroom' ? (
              <div key={d.id} className="flex flex-col gap-3 rounded-card border border-line p-4">
                <span className="font-display text-[20px] font-bold">{d.label}</span>
                <NumberField
                  label="Personas dentro a la vez"
                  value={d.capacity ?? 1}
                  min={1}
                  max={20}
                  onChange={(v) => setDest(d.id, { capacity: v })}
                />
                <NumberField
                  label="Fuera por grupo"
                  value={d.per_group_limit ?? 1}
                  min={1}
                  max={10}
                  onChange={(v) => setDest(d.id, { per_group_limit: v })}
                />
                <span className="text-[13px] text-muted">
                  Con 1 por grupo, nunca coinciden dos del mismo grupo y sexo.
                </span>
              </div>
            ) : (
              <div key={d.id} className="flex flex-col gap-3 rounded-card border border-line p-4">
                <span className="font-display text-[20px] font-bold">{d.label}</span>
                <span className="text-[15px]">
                  No ocupa el lugar del grupo, no hace fila y no tiene límite.
                </span>
                <span className="text-[13px] text-muted">
                  La alerta cuenta solo el trayecto: al marcar &quot;Llegó&quot; se detiene.
                </span>
              </div>
            ),
          )}
        </div>
        <span className="text-[13px] text-muted">
          Si subes la capacidad con gente formada, se llama al siguiente en ese momento.
        </span>
      </Card>

      <Card>
        <SectionLabel>Tiempos y umbrales</SectionLabel>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {TIME_FIELDS.map((f) => (
            <div key={f.key} className="flex flex-col gap-1">
              <NumberField
                label={f.label}
                unit={f.unit}
                value={times[f.key]}
                min={f.min}
                max={f.max}
                onChange={(v) => setTimes((t) => (t ? { ...t, [f.key]: v } : t))}
              />
              <span className="text-[13px] text-muted">{f.help}</span>
            </div>
          ))}
        </div>
      </Card>

      {msg ? <Notice tone={msg.tone}>{msg.text}</Notice> : null}
      <div className="flex justify-end gap-2">
        <button
          type="button"
          className={buttonClass.secondary}
          disabled={busy}
          onClick={() => {
            setDests(data.data!.dests);
            setTimes(data.data!.times);
            setMsg(null);
          }}
        >
          Descartar
        </button>
        <button type="submit" className={buttonClass.primary} disabled={busy}>
          {busy ? 'Guardando…' : 'Guardar cambios'}
        </button>
      </div>
    </form>
  );
}

function NumberField({
  label,
  value,
  min,
  max,
  unit,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  unit?: string;
  onChange: (v: number) => void;
}) {
  const id = label.replace(/\W+/g, '-');
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={id} className="text-[15px] font-bold">
        {label}
      </label>
      <div className="flex items-center gap-2">
        <input
          id={id}
          type="number"
          inputMode="numeric"
          min={min}
          max={max}
          value={value}
          onChange={(e) => onChange(Math.max(min, Math.min(max, Number(e.target.value) || min)))}
          className="min-h-btn w-[96px] rounded-btn border border-line-strong px-3 font-mono text-[18px] tabular-nums"
        />
        {unit ? <span className="text-muted">{unit}</span> : null}
      </div>
    </div>
  );
}
