import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { PushSettings } from '@/components/PushSettings';
import { Card, Loading, Notice, SectionLabel } from '@/components/ui/Page';
import { supabase } from '@/lib/supabase';

type Rule = { role: string; channel: 'app' | 'push' | 'whatsapp'; enabled: boolean };

const RECIPIENTS = [
  {
    role: 'current_teacher',
    name: 'Maestro a cargo en esa hora',
    help: 'Según el horario del grupo en ese momento',
  },
  {
    role: 'authorizing_teacher',
    name: 'Maestro que autorizó la salida',
    help: 'Si es distinto del que tiene la clase ahora',
  },
  { role: 'prefect', name: 'Prefectura', help: 'Todo el personal con rol de prefectura' },
  { role: 'coordinator', name: 'Coordinación', help: 'Todo el personal con rol de coordinación' },
  { role: 'director', name: 'Dirección', help: 'Todo el personal con rol de dirección' },
];
const CHANNELS = [
  { channel: 'app', label: 'En la app' },
  { channel: 'push', label: 'Notificación' },
  { channel: 'whatsapp', label: 'WhatsApp' },
] as const;

const KIND_LABEL: Record<string, string> = {
  alert: 'Alerta',
  escalated: 'Escalada',
  acknowledged: 'Atendida',
  resolved: 'Resuelta',
  test: 'Prueba',
};

const dateFmt = new Intl.DateTimeFormat('es-MX', {
  dateStyle: 'short',
  timeStyle: 'short',
  timeZone: 'America/Mexico_City',
});

/** Ajustes → Notificaciones: quién recibe la alerta y por qué canal (SPEC §7). */
export function NotificationsPanel() {
  const queryClient = useQueryClient();

  const rules = useQuery({
    queryKey: ['notification_rules'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('notification_rules')
        .select('role, channel, enabled');
      if (error) throw error;
      return data as Rule[];
    },
  });

  const outbox = useQuery({
    queryKey: ['outbox'],
    refetchInterval: 15_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('notifications_outbox')
        .select(
          'id, kind, channel, body, created_at, sent_at, error, staff:recipient_staff_id(full_name)',
        )
        .order('id', { ascending: false })
        .limit(20);
      if (error) throw error;
      return data;
    },
  });

  const toggle = useMutation({
    mutationFn: async (r: Rule) => {
      const { error } = await supabase
        .from('notification_rules')
        .update({ enabled: !r.enabled })
        .eq('role', r.role)
        .eq('channel', r.channel);
      if (error) throw error;
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: ['notification_rules'] }),
  });

  const find = (role: string, channel: string) =>
    rules.data?.find((r) => r.role === role && r.channel === channel);

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <SectionLabel>Quién recibe la alerta de 10 min</SectionLabel>
        {rules.isPending ? <Loading /> : null}
        {toggle.isError ? <Notice tone="error">No se pudo guardar el cambio.</Notice> : null}
        <div className="overflow-x-auto">
          <table className="w-full min-w-[520px] border-collapse text-left">
            <thead>
              <tr className="border-b border-line text-[14px] text-muted">
                <th className="py-2 pr-3 font-bold">Destinatario</th>
                {CHANNELS.map((c) => (
                  <th key={c.channel} className="px-2 py-2 text-center font-bold">
                    {c.label}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {RECIPIENTS.map((r) => (
                <tr key={r.role} className="border-b border-line last:border-0">
                  <td className="py-3 pr-3">
                    <span className="font-bold">{r.name}</span>
                    <br />
                    <span className="text-[14px] text-muted">{r.help}</span>
                  </td>
                  {CHANNELS.map((c) => {
                    const rule = find(r.role, c.channel);
                    const soon = c.channel === 'whatsapp';
                    return (
                      <td key={c.channel} className="px-2 py-3 text-center">
                        <input
                          type="checkbox"
                          className="h-6 w-6"
                          aria-label={`${r.name}: ${c.label}`}
                          checked={rule?.enabled ?? false}
                          disabled={!rule || soon || toggle.isPending}
                          onChange={() => rule && toggle.mutate(rule)}
                        />
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="m-0 text-[14px] text-muted">
          Se avisa al crear la alerta, si se escala (nadie la atiende), cuando alguien la atiende y
          cuando se resuelve. WhatsApp llega en una fase posterior. La notificación solo llega a
          quien la activó en su celular o computadora.
        </p>
      </Card>

      <PushSettings />

      <Card>
        <SectionLabel>Últimos envíos</SectionLabel>
        {outbox.isPending ? <Loading /> : null}
        {outbox.data && !outbox.data.length ? (
          <span className="text-[15px] text-muted">Todavía no se ha enviado nada.</span>
        ) : null}
        <ul className="m-0 flex list-none flex-col gap-1.5 p-0">
          {outbox.data?.map((o) => (
            <li
              key={o.id}
              className="flex flex-col gap-0.5 rounded-btn border border-line px-3 py-2 text-[14px]"
            >
              <span className="flex flex-wrap justify-between gap-2">
                <span>
                  <strong>{KIND_LABEL[o.kind] ?? o.kind}</strong> ·{' '}
                  {o.channel === 'whatsapp' ? 'Grupo de WhatsApp' : (o.staff?.full_name ?? '—')}
                </span>
                <span
                  className={`font-bold ${o.sent_at ? 'text-free-fg' : o.error ? 'text-alert-fg' : 'text-wait-fg'}`}
                >
                  {o.sent_at ? 'Enviado' : o.error ? 'Error' : 'Pendiente'} ·{' '}
                  {dateFmt.format(new Date(o.created_at))}
                </span>
              </span>
              <span className="text-muted">{o.body}</span>
              {o.error && !o.sent_at ? <span className="text-alert-fg">{o.error}</span> : null}
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}
