import { useEffect, useState, type ReactNode } from 'react';
import { Card, SectionLabel } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { getInstallState, promptInstall, subscribeInstall, type InstallState } from '@/lib/install';

/**
 * Instalar la app en la pantalla de inicio o en la computadora (Perfil, entrada y vincular
 * equipo). No se muestra si ya está instalada. Si se cancela el diálogo del navegador, el
 * botón se cambia por los pasos desde el menú del navegador. `plain` la muestra sin tarjeta,
 * dentro de otra.
 */
export function InstallApp({ plain = false }: { plain?: boolean }) {
  const [state, setState] = useState<InstallState>(getInstallState);

  useEffect(() => subscribeInstall(() => setState(getInstallState())), []);

  if (state === 'installed') return null;

  const content: ReactNode = (
    <>
      <SectionLabel>Instalar app</SectionLabel>
      <p className="m-0 text-[15px] text-muted">
        Instala Pase en este equipo: abre en su propia ventana, como cualquier app, y recibe las
        notificaciones.
      </p>

      {state === 'prompt' ? (
        <button type="button" className={buttonClass.primary} onClick={() => void promptInstall()}>
          Instalar app
        </button>
      ) : null}

      {state === 'ios' ? (
        <ol className="m-0 flex list-decimal flex-col gap-1 pl-5 text-[15px]">
          <li>
            Abre esta página en <strong>Safari</strong>.
          </li>
          <li>
            Toca <strong>Compartir</strong> (el cuadro con la flecha hacia arriba).
          </li>
          <li>
            Elige <strong>Agregar a inicio</strong> y luego <strong>Agregar</strong>.
          </li>
          <li>
            Abre <strong>Pase</strong> desde el ícono y entra con tu cuenta.
          </li>
        </ol>
      ) : null}

      {state === 'manual' ? (
        <p className="m-0 text-[15px]">
          En Chrome o Edge: abre el menú (<strong>⋮</strong>) y elige <strong>Instalar app</strong>{' '}
          (en celular también puede decir <strong>Agregar a la pantalla principal</strong>). En la
          computadora aparece además un ícono de instalar en la barra de direcciones.
        </p>
      ) : null}
    </>
  );

  return plain ? (
    <div className="flex flex-col gap-3 border-t border-line pt-4">{content}</div>
  ) : (
    <Card>{content}</Card>
  );
}
