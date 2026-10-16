import { NavLink, Navigate, Route, Routes } from 'react-router';
import { Notice, PageTitle } from '@/components/ui/Page';
import { canManage } from '@/lib/me';
import { useStaff } from '@/lib/session';
import { DevicesPanel } from './DevicesPanel';
import { ImportPanel } from './ImportPanel';
import { NotificationsPanel } from './NotificationsPanel';
import { RulesPanel } from './RulesPanel';
import { SchedulePanel } from './SchedulePanel';
import { StaffPanel } from './StaffPanel';
import { StudentsPanel } from './StudentsPanel';
import { TeachersPanel } from './TeachersPanel';

const TABS = [
  { to: 'banos', label: 'Baños y reglas' },
  { to: 'horarios', label: 'Horarios' },
  { to: 'docentes', label: 'Docentes' },
  { to: 'alumnos', label: 'Alumnos' },
  { to: 'personal', label: 'Personal y PIN' },
  { to: 'equipos', label: 'Salones y equipos' },
  { to: 'notificaciones', label: 'Notificaciones' },
];

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
            to={`/ajustes/${t.to}`}
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
        <Route index element={<Navigate to="/ajustes/banos" replace />} />
        <Route path="banos" element={<RulesPanel />} />
        <Route path="horarios" element={<SchedulePanel />} />
        <Route path="docentes" element={<TeachersPanel />} />
        <Route
          path="alumnos"
          element={
            <div className="flex flex-col gap-4">
              <StudentsPanel />
              <ImportPanel kind="students" title="Importar alumnos desde CSV" />
            </div>
          }
        />
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
        <Route path="notificaciones" element={<NotificationsPanel />} />
        <Route path="*" element={<Navigate to="/ajustes/banos" replace />} />
      </Routes>
    </div>
  );
}
