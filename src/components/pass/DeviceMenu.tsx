import { useEffect, useState } from 'react';
import { PushSettings } from '@/components/PushSettings';
import { buttonClass } from '@/components/ui/styles';

/**
 * Menú discreto "⋯" de la computadora del salón: activar o desactivar las notificaciones de
 * este equipo y enviar una prueba.
 */
export function DeviceMenu({ dark = false }: { dark?: boolean }) {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label="Más opciones del equipo"
        title="Más opciones"
        className={`inline-flex h-11 w-11 items-center justify-center rounded-btn text-[22px] font-bold leading-none ${
          dark ? 'text-white/70 hover:bg-white/10' : 'text-muted hover:bg-ground'
        }`}
      >
        ⋯
      </button>
      {open ? (
        <div
          className="fixed inset-0 z-40 flex items-end justify-center bg-ink/50 sm:items-center sm:p-6"
          onClick={() => setOpen(false)}
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Opciones del equipo"
            onClick={(e) => e.stopPropagation()}
            className="pb-safe flex w-full flex-col gap-3 rounded-t-[22px] bg-ground p-4 text-ink sm:max-w-[480px] sm:rounded-card-lg"
          >
            <PushSettings device />
            <button type="button" onClick={() => setOpen(false)} className={buttonClass.secondary}>
              Cerrar
            </button>
          </div>
        </div>
      ) : null}
    </>
  );
}
