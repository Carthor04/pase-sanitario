import { BrandMark } from '@/components/layout/BrandMark';
import { Loading, Notice } from '@/components/ui/Page';
import { hhmm, useCurrentClass, useStudents } from '@/lib/queries';
import { useDevice } from '@/lib/session';
import { useClock } from '@/lib/useClock';

/**
 * Computadora del salón ya vinculada. En la Fase 3 esta pantalla se vuelve SalonBloqueo
 * (PIN + estado en solo lectura) y Main (desbloqueada).
 */
export function SalonHome() {
  const device = useDevice();
  const clock = useClock();
  const current = useCurrentClass(device.group_id);
  const students = useStudents(device.group_id);

  return (
    <div className="flex min-h-screen flex-col bg-ground">
      <header className="bg-dark text-white">
        <div className="mx-auto flex max-w-container items-center gap-4 px-4 py-3 sm:px-6">
          <BrandMark />
          <div className="flex min-w-0 flex-col">
            <span className="font-display text-[26px] font-bold leading-none">
              {device.group_name}
            </span>
            <span className="text-[15px] text-white/80">
              {current.data
                ? `${current.data.subject} · ${hhmm(current.data.starts)} – ${hhmm(current.data.ends)}${
                    current.data.teacher_name ? ` · ${current.data.teacher_name}` : ''
                  }`
                : 'Sin clase en este momento'}
            </span>
          </div>
          <span className="ml-auto font-mono text-[28px] font-semibold tabular-nums">{clock}</span>
        </div>
      </header>

      <main className="mx-auto flex w-full max-w-container flex-1 flex-col gap-4 px-4 py-5 sm:px-6">
        <Notice tone="ok">
          Equipo vinculado a <strong>{device.group_name}</strong>
          {device.label ? ` (${device.label})` : ''}. El desbloqueo con PIN y los pases llegan en la
          siguiente fase.
        </Notice>
        {students.isPending ? <Loading /> : null}
        <ul className="m-0 grid list-none gap-2.5 p-0 [grid-template-columns:repeat(auto-fill,minmax(168px,1fr))]">
          {students.data?.map((s) => (
            <li
              key={s.id}
              className="flex min-h-[56px] items-center gap-2 rounded-card border border-line bg-surface px-3"
            >
              <span className="font-mono text-[15px] font-semibold tabular-nums text-muted">
                {s.list_number}
              </span>
              <span className="min-w-0 flex-1 truncate">{s.full_name}</span>
              <span className="text-[13px] font-bold text-muted">{s.sex}</span>
            </li>
          ))}
        </ul>
      </main>
    </div>
  );
}
