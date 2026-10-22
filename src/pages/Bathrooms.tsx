import { useEffect, useState } from 'react';
import { BathroomsLive } from '@/components/pass/BathroomsLive';
import { RemoveFromQueueDialog } from '@/components/pass/RemoveFromQueue';
import { PageTitle } from '@/components/ui/Page';
import {
  canRemoveFromQueue,
  errorMessage,
  useLivePasses,
  usePassAction,
  type WaitItem,
} from '@/lib/live';
import { useStaff } from '@/lib/session';

const STATUS_TEXT: Record<string, string> = {
  queued: 'En fila',
  group_wait: 'Espera a que regrese el de su grupo',
  called: 'Su turno, sin confirmar',
};

/** Baños (celular y escritorio): quién está dentro y en fila, por grupo, en tiempo real. */
export function Bathrooms() {
  const online = useLivePasses();
  const staff = useStaff();
  const action = usePassAction();
  const [picked, setPicked] = useState<(WaitItem & { id: string }) | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!error) return;
    const id = window.setTimeout(() => setError(null), 6000);
    return () => window.clearTimeout(id);
  }, [error]);

  async function remove(passId: string) {
    setError(null);
    try {
      await action.mutateAsync({ type: 'cancel', passId });
    } catch (err) {
      setError(errorMessage(err));
    }
    setPicked(null);
  }

  return (
    <div className="flex flex-col gap-4">
      <PageTitle
        aside={
          <span className={`text-[14px] font-bold ${online ? 'text-free-fg' : 'text-alert-fg'}`}>
            {online ? '● En vivo' : 'Sin conexión'}
          </span>
        }
      >
        Baños
      </PageTitle>
      <BathroomsLive onPick={canRemoveFromQueue(staff.roles) ? setPicked : undefined} />

      {picked ? (
        <RemoveFromQueueDialog
          name={picked.full_name ?? picked.group_name}
          groupName={picked.group_name}
          detail={[
            STATUS_TEXT[picked.status],
            picked.subject ? `salió en ${picked.subject}` : null,
            picked.opened_by ? `autorizó ${picked.opened_by}` : null,
            picked.current_teacher ? `ahora con ${picked.current_teacher}` : null,
          ]
            .filter(Boolean)
            .join(' · ')}
          busy={action.isPending}
          onConfirm={() => void remove(picked.id)}
          onClose={() => setPicked(null)}
        />
      ) : null}

      {error ? (
        <div
          role="alert"
          className="fixed inset-x-4 bottom-[86px] z-50 mx-auto max-w-[560px] rounded-card border-2 border-alert-bd bg-alert-bg px-4 py-3 font-bold text-alert-fg shadow-lg sm:bottom-6"
        >
          {error}
        </div>
      ) : null}
    </div>
  );
}
