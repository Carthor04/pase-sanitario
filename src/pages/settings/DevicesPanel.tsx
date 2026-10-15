import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useId, useState, type FormEvent } from 'react';
import { Card, Loading, Notice, SectionLabel } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { useGroups } from '@/lib/queries';
import { supabase } from '@/lib/supabase';

const dateFmt = new Intl.DateTimeFormat('es-MX', {
  dateStyle: 'medium',
  timeStyle: 'short',
  timeZone: 'America/Mexico_City',
});

function Countdown({ until }: { until: string }) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);
  const left = Math.max(0, Math.round((new Date(until).getTime() - now) / 1000));
  if (!left) return <span className="font-bold text-alert-fg">Vencido: genera otro</span>;
  return (
    <span className="font-mono tabular-nums">
      vence en {Math.floor(left / 60)}:{String(left % 60).padStart(2, '0')}
    </span>
  );
}

export function DevicesPanel() {
  const groupId = useId();
  const labelId = useId();
  const queryClient = useQueryClient();
  const groups = useGroups();
  const [group, setGroup] = useState('');
  const [label, setLabel] = useState('');
  const [code, setCode] = useState<{ code: string; expires_at: string; group: string } | null>(
    null,
  );

  const devices = useQuery({
    queryKey: ['devices'],
    refetchInterval: code ? 5_000 : false, // para ver aparecer el equipo al vincularse
    queryFn: async () => {
      const { data, error } = await supabase
        .from('devices')
        .select('id, label, created_at, last_seen_at, revoked_at, groups(name)')
        .order('created_at', { ascending: false });
      if (error) throw error;
      return data;
    },
  });

  const create = useMutation({
    mutationFn: async (e: FormEvent) => {
      e.preventDefault();
      const { data, error } = await supabase.rpc('create_device_pairing', {
        p_group_id: group,
        p_label: label,
      });
      if (error) throw error;
      const res = data as { code: string; expires_at: string };
      setCode({ ...res, group: groups.data?.find((g) => g.id === group)?.name ?? '' });
    },
  });

  const revoke = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('revoke_device', { p_device_id: id });
      if (error) throw error;
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: ['devices'] }),
  });

  return (
    <Card>
      <SectionLabel>Salones y equipos</SectionLabel>
      <p className="m-0 text-[15px] text-muted">
        Genera un código y escríbelo en la computadora del salón en{' '}
        <strong>{window.location.host}/vincular</strong>. El código sirve una sola vez.
      </p>

      <form onSubmit={(e) => create.mutate(e)} className="flex flex-wrap items-end gap-3">
        <div className="flex flex-col gap-1.5">
          <label htmlFor={groupId} className="text-[15px] font-bold">
            Grupo
          </label>
          <select
            id={groupId}
            required
            value={group}
            onChange={(e) => setGroup(e.target.value)}
            className="min-h-btn min-w-[140px] rounded-btn border border-line-strong bg-surface px-3 text-[17px]"
          >
            <option value="">Elige…</option>
            {groups.data?.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name}
              </option>
            ))}
          </select>
        </div>
        <div className="flex min-w-[200px] flex-1 flex-col gap-1.5">
          <label htmlFor={labelId} className="text-[15px] font-bold">
            Nombre del equipo (opcional)
          </label>
          <input
            id={labelId}
            value={label}
            onChange={(e) => setLabel(e.target.value)}
            placeholder="Computadora del salón"
            className="min-h-btn rounded-btn border border-line-strong bg-surface px-3 text-[17px]"
          />
        </div>
        <button type="submit" className={buttonClass.primary} disabled={!group || create.isPending}>
          Generar código
        </button>
      </form>
      {create.isError ? <Notice tone="error">No se pudo generar el código.</Notice> : null}

      {code ? (
        <div className="flex flex-col items-start gap-1 rounded-card border-2 border-accent bg-surface p-4">
          <span className="text-[15px] text-muted">Código para {code.group}</span>
          <span className="font-mono text-[44px] font-semibold tabular-nums tracking-[0.2em]">
            {code.code}
          </span>
          <Countdown until={code.expires_at} />
        </div>
      ) : null}

      {devices.isPending ? <Loading /> : null}
      {revoke.isError ? <Notice tone="error">No se pudo revocar el equipo.</Notice> : null}
      <ul className="m-0 flex list-none flex-col gap-2 p-0">
        {devices.data?.map((d) => (
          <li
            key={d.id}
            className="flex flex-wrap items-center justify-between gap-2 rounded-btn-lg border border-line p-3"
          >
            <div className="flex flex-col">
              <span className="font-bold">
                {d.groups?.name} {d.label ? `· ${d.label}` : ''}
              </span>
              <span className="text-[15px] text-muted">
                {d.revoked_at
                  ? `Revocado ${dateFmt.format(new Date(d.revoked_at))}`
                  : d.last_seen_at
                    ? `Visto ${dateFmt.format(new Date(d.last_seen_at))}`
                    : `Vinculado ${dateFmt.format(new Date(d.created_at))}`}
              </span>
            </div>
            {d.revoked_at ? (
              <span className="rounded-chip border border-line px-2.5 py-0.5 text-[13px] font-bold text-muted">
                Revocado
              </span>
            ) : (
              <button
                type="button"
                className={buttonClass.danger}
                disabled={revoke.isPending}
                onClick={() => {
                  if (window.confirm('¿Revocar este equipo? Tendrá que vincularse de nuevo.')) {
                    revoke.mutate(d.id);
                  }
                }}
              >
                Revocar
              </button>
            )}
          </li>
        ))}
      </ul>
      {devices.data && !devices.data.length ? (
        <span className="text-[15px] text-muted">Todavía no hay equipos vinculados.</span>
      ) : null}
    </Card>
  );
}
