import { useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router';
import { PushSettings } from '@/components/PushSettings';
import { Card, PageTitle } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { canManage } from '@/lib/me';
import { ROLE_LABELS } from '@/lib/nav';
import { signOut, useStaff } from '@/lib/session';

export function More() {
  const staff = useStaff();
  const queryClient = useQueryClient();
  return (
    <div className="flex max-w-[480px] flex-col gap-4">
      <PageTitle>Más</PageTitle>
      <Card>
        <div className="flex flex-col">
          <span className="text-[17px] font-bold">{staff.full_name}</span>
          <span className="break-all text-[15px] text-muted">{staff.email}</span>
          <span className="text-[15px] text-muted">
            {staff.roles.map((r) => ROLE_LABELS[r]).join(' · ')}
          </span>
        </div>
        <Link to="/mi-pin" className={buttonClass.secondary}>
          {staff.has_pin ? 'Cambiar mi PIN' : 'Definir mi PIN'}
        </Link>
        {canManage(staff.roles) ? (
          <Link to="/ajustes" className={buttonClass.secondary}>
            Ajustes
          </Link>
        ) : null}
        <button
          type="button"
          className={buttonClass.secondary}
          onClick={() => signOut(queryClient)}
        >
          Cerrar sesión
        </button>
      </Card>
      <PushSettings />
    </div>
  );
}
