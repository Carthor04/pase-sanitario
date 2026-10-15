import { NavLink, Navigate, Route, Routes } from 'react-router';
import { Card, Notice, PageTitle } from '@/components/ui/Page';
import { canManage } from '@/lib/me';
import { useStaff } from '@/lib/session';
import { DevicesPanel } from './DevicesPanel';
import { ImportPanel } from './ImportPanel';
import { StaffPanel } from './StaffPanel';

const TABS = [
  { to: 'banos', label: 'Baños y reglas' },
  { to: 'horarios', label: 'Horarios' },
  { to: 'alumnos', label: 'Alumnos' },
  { to: 'personal', label: 'Personal y PIN' },
  { to: 'equipos', label: 'Salones y equipos' },
  { to: 'notificaciones', label: 'Notificaciones' },
];

function Later({ title, phase }: { title: string; phase: number }) {
  return (
    <Card>
      <span className="font-bold">{title}</span>
      <span className="text-muted">Esta sección se construye en la Fase {phase}.</span>
    </Card>
  );
}

/** Configuración (SPEC §10). Solo coordinación, dirección y admin. */
export function Settings() {
  const staff = useStaff();
  if (!canManage(staff.roles)) {
    return (
      <div className="flex flex-col gap-4">
        <PageTitle>Ajustes</PageTitle>
        <Notice>Solo coordinación y dirección pueden cambiar la configuración.</Notice>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <PageTitle>Configuración</PageTitle>
      <nav aria-label="Ajustes" className="-mx-1 flex gap-1 overflow-x-auto px-1 pb-1">
        {TABS.map((t) => (
          <NavLink
            key={t.to}
            to={t.to}
            className={({ isActive }) =>
              [
                'inline-flex min-h-touch shrink-0 items-center rounded-btn px-3.5 text-[15px] font-bold',
                isActive ? 'bg-surface text-ink shadow-sm' : 'text-muted hover:text-ink',
              ].join(' ')
            }
          >
            {t.label}
          </NavLink>
        ))}
      </nav>
      <Routes>
        <Route index element={<Navigate to="alumnos" replace />} />
        <Route path="banos" element={<Later title="Baños y reglas" phase={6} />} />
        <Route
          path="horarios"
          element={
            <div className="flex flex-col gap-4">
              <ImportPanel kind="groups" title="Grupos" />
              <ImportPanel kind="schedule" title="Horario" />
            </div>
          }
        />
        <Route path="alumnos" element={<ImportPanel kind="students" title="Alumnos" />} />
        <Route
          path="personal"
          element={
            <div className="flex flex-col gap-4">
              <ImportPanel kind="staff" title="Importar personal" />
              <StaffPanel />
            </div>
          }
        />
        <Route path="equipos" element={<DevicesPanel />} />
        <Route path="notificaciones" element={<Later title="Notificaciones" phase={5} />} />
        <Route path="*" element={<Navigate to="alumnos" replace />} />
      </Routes>
    </div>
  );
}
