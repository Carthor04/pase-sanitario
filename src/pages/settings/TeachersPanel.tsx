import { useId, useState } from 'react';
import { Card, Loading, Notice, SectionLabel } from '@/components/ui/Page';
import { errorMessage } from '@/lib/live';
import { useTeacherSchedule, useTeachers } from '@/lib/schedule';
import { TeacherStatus } from '@/components/schedule/TeacherStatus';
import { WeekGrid } from '@/components/schedule/WeekGrid';

/** Configuración → Docentes: horario de un maestro y si está en clase en este momento. */
export function TeachersPanel() {
  const selectId = useId();
  const teachers = useTeachers();
  const [staffId, setStaffId] = useState('');
  const selected = staffId || teachers.data?.[0]?.id || '';
  const schedule = useTeacherSchedule(selected);
  const name = teachers.data?.find((t) => t.id === selected)?.full_name ?? '';

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <SectionLabel>Horario del docente</SectionLabel>
          <div className="flex min-w-0 items-center gap-2">
            <label htmlFor={selectId} className="font-bold">
              Docente
            </label>
            <select
              id={selectId}
              value={selected}
              onChange={(e) => setStaffId(e.target.value)}
              className="min-h-btn min-w-0 max-w-[260px] rounded-btn border border-line-strong bg-surface px-3 text-[16px] sm:max-w-none"
            >
              {teachers.data?.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.full_name}
                </option>
              ))}
            </select>
          </div>
        </div>

        {teachers.isPending || (selected && schedule.isPending) ? <Loading /> : null}
        {teachers.isError ? <Notice tone="error">{errorMessage(teachers.error)}</Notice> : null}
        {schedule.isError ? <Notice tone="error">{errorMessage(schedule.error)}</Notice> : null}
        {teachers.data && teachers.data.length === 0 ? (
          <span className="text-muted">No hay maestros registrados en Personal.</span>
        ) : null}

        {schedule.data ? (
          <>
            <TeacherStatus name={name} data={schedule.data} />
            {schedule.data.entries.length === 0 ? (
              <span className="text-muted">
                Sin clases en el horario. Revisa que el horario importado tenga su correo.
              </span>
            ) : (
              <WeekGrid
                entries={schedule.data.entries}
                cell={(e) => (
                  <>
                    <span className="font-bold">{e.group_name}</span>
                    <span className="block text-[12px] text-muted">
                      {e.subject}
                      {e.room ? ` · ${e.room}` : ''}
                    </span>
                  </>
                )}
              />
            )}
          </>
        ) : null}
      </Card>
    </div>
  );
}
