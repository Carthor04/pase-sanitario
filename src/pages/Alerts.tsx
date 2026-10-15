import { useState } from 'react';
import { Link } from 'react-router';
import { AlertCard } from '@/components/pass/AlertCard';
import { Loading, Notice, PageTitle } from '@/components/ui/Page';
import { useAudioUnlock } from '@/lib/device';
import { errorMessage, useLivePasses, usePassAction, useServerNow } from '@/lib/live';
import { useAlertSound, useMyAlerts } from '@/lib/monitor';

/**
 * Alertas del maestro: las de los grupos que tiene a cargo ahora (según horario) y las de
 * los alumnos que él dejó salir (SPEC §7).
 */
export function Alerts() {
  const alerts = useMyAlerts();
  useLivePasses();
  useAudioUnlock();
  const action = usePassAction();
  const now = useServerNow();
  const [error, setError] = useState<string | null>(null);
  useAlertSound(alerts.data?.map((a) => ({ id: a.alert.id, level: a.alert.level })));

  if (alerts.isPending) return <Loading />;
  if (alerts.isError) return <Notice tone="error">{errorMessage(alerts.error)}</Notice>;

  return (
    <div className="flex flex-col gap-4">
      <PageTitle>Alertas</PageTitle>
      {error ? <Notice tone="error">{error}</Notice> : null}
      {alerts.data.length === 0 ? (
        <Notice tone="ok">
          Sin alertas. Aquí aparece cualquier alumno de tu clase actual, o que tú dejaste salir, que
          lleve más tiempo del permitido fuera.
        </Notice>
      ) : null}
      {alerts.data.map((a) => (
        <div key={a.pass_id} className="flex flex-col gap-1">
          <AlertCard
            name={a.full_name}
            groupName={a.group_name}
            place={a.destination_label}
            startedAt={a.started_at}
            periodSubject={a.period_subject}
            alert={a.alert}
            now={now}
            busy={action.isPending}
            onReturn={
              a.status === 'out' || a.status === 'arrived'
                ? () =>
                    void action
                      .mutateAsync({ type: 'return', passId: a.pass_id })
                      .catch((err) => setError(errorMessage(err)))
                : undefined
            }
          />
          <Link
            to={`/grupo?g=${a.group_id}`}
            className="self-end text-[14px] font-bold text-accent"
          >
            Ver {a.group_name}
          </Link>
        </div>
      ))}
    </div>
  );
}
