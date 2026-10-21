import { useEffect, useState } from 'react';
import { Card, Notice, SectionLabel } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { errorMessage } from '@/lib/live';
import { disablePush, enablePush, getPushState, type PushState } from '@/lib/push';
import { supabase } from '@/lib/supabase';

const STATE_TEXT: Record<PushState, string> = {
  on: 'Activadas en este equipo',
  off: 'Desactivadas en este equipo',
  denied: 'Bloqueadas por el navegador',
  unsupported: 'Este navegador no las permite',
  'ios-install': 'Primero instala la app',
};

/**
 * Activar notificaciones push en este celular o computadora (Perfil / Ajustes). En la
 * computadora del salón (`device`) los avisos son los de los alumnos de ese salón.
 */
export function PushSettings({ device = false }: { device?: boolean }) {
  const [state, setState] = useState<PushState | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);

  useEffect(() => {
    void getPushState().then(setState);
  }, []);

  async function act(fn: () => Promise<void>, ok?: string) {
    setBusy(true);
    setMessage(null);
    try {
      await fn();
      setState(await getPushState());
      if (ok) setMessage({ tone: 'ok', text: ok });
    } catch (err) {
      setMessage({ tone: 'error', text: errorMessage(err) });
      setState(await getPushState());
    } finally {
      setBusy(false);
    }
  }

  async function test() {
    const { data, error } = await supabase.rpc('send_test_push');
    if (error) throw error;
    const res = data as { ok: boolean; error?: string; devices?: number };
    if (!res.ok) throw new Error('Activa primero las notificaciones en este equipo.');
  }

  return (
    <Card>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <SectionLabel>Notificaciones</SectionLabel>
        {state ? (
          <span
            className={`rounded-chip px-2.5 py-0.5 text-[13px] font-bold ${
              state === 'on' ? 'bg-free-bg text-free-fg' : 'bg-wait-bg text-wait-fg'
            }`}
          >
            {STATE_TEXT[state]}
          </span>
        ) : null}
      </div>
      <p className="m-0 text-[15px] text-muted">
        {device
          ? 'Esta computadora recibe los avisos de turno, las alertas y los regresos de enfermería de los alumnos de este salón, aunque la app esté minimizada.'
          : 'Recibe las alertas de 10 minutos aunque la app esté cerrada. Se activa en cada celular o computadora por separado.'}
      </p>

      {state === 'ios-install' ? (
        <ol className="m-0 flex list-decimal flex-col gap-1 pl-5 text-[15px]">
          <li>
            En Safari toca <strong>Compartir</strong> (el cuadro con la flecha hacia arriba).
          </li>
          <li>
            Elige <strong>Agregar a inicio</strong> y luego <strong>Agregar</strong>.
          </li>
          <li>
            Abre <strong>Pase</strong> desde el ícono de tu pantalla de inicio, entra y vuelve aquí
            para activar las notificaciones.
          </li>
          <li className="text-muted">Necesitas iOS 16.4 o más reciente.</li>
        </ol>
      ) : null}
      {state === 'denied' ? (
        <Notice tone="warn">
          Bloqueaste las notificaciones para este sitio. Actívalas en la configuración del navegador
          (candado junto a la dirección → Notificaciones → Permitir) y recarga la página.
        </Notice>
      ) : null}
      {state === 'unsupported' ? (
        <Notice tone="warn">
          Este navegador no permite notificaciones. Usa Chrome, Edge o Firefox actualizados.
        </Notice>
      ) : null}

      <div className="flex flex-wrap gap-2">
        {state === 'off' ? (
          <button
            type="button"
            disabled={busy}
            className={buttonClass.primary}
            onClick={() => void act(enablePush, 'Listo: este equipo recibirá las alertas.')}
          >
            Activar notificaciones en este equipo
          </button>
        ) : null}
        {state === 'on' ? (
          <>
            <button
              type="button"
              disabled={busy}
              className={buttonClass.primary}
              onClick={() => void act(test, 'Prueba enviada: debe llegar en unos segundos.')}
            >
              Enviar prueba
            </button>
            <button
              type="button"
              disabled={busy}
              className={buttonClass.secondary}
              onClick={() => void act(disablePush, 'Notificaciones desactivadas en este equipo.')}
            >
              Desactivar
            </button>
          </>
        ) : null}
      </div>
      {message ? <Notice tone={message.tone}>{message.text}</Notice> : null}
    </Card>
  );
}
