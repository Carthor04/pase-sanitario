import { useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router';
import { InstallApp } from '@/components/InstallApp';
import { PushSettings } from '@/components/PushSettings';
import { MySchedule } from '@/components/schedule/MySchedule';
import { Card, PageTitle } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { canManage } from '@/lib/me';
import { ROLE_LABELS } from '@/lib/nav';
import { signOut, useStaff } from '@/lib/session';

/**
 * Perfil: datos de la persona, su horario (si da clases), PIN, instalar la app y avisos.
 * `embedded` lo muestra dentro de Ajustes → Mi cuenta (coordinación y dirección no tienen
 * la pestaña Perfil en la navegación).
 */
export function Profile({ embedded = false }: { embedded?: boolean }) {
  const staff = useStaff();
  const queryClient = useQueryClient();
  return (
    <div className="flex max-w-[560px] flex-col gap-4">
      {embedded ? null : <PageTitle>Perfil</PageTitle>}
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
        {canManage(staff.roles) && !embedded ? (
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
      {staff.roles.includes('teacher') ? (
        <MySchedule staffId={staff.id} name={staff.full_name} />
      ) : null}
      <InstallApp />
      <PushSettings />
    </div>
  );
}
