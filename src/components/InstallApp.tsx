import { useEffect, useState } from 'react';
import { Card, SectionLabel } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { getInstallState, promptInstall, subscribeInstall, type InstallState } from '@/lib/install';

/**
 * Instalar la app en la pantalla de inicio (Más). No se muestra si ya está instalada. Si se
 * cancela el diálogo del navegador, el botón se cambia por los pasos desde el menú ⋮.
 */
export function InstallApp() {
  const [state, setState] = useState<InstallState>(getInstallState);

  useEffect(() => subscribeInstall(() => setState(getInstallState())), []);

  if (state === 'installed') return null;

  return (
    <Card>
      <SectionLabel>Instalar app</SectionLabel>
      <p className="m-0 text-[15px] text-muted">
        Agrega Pase a tu pantalla de inicio: abre en pantalla completa, como cualquier app, y recibe
        las notificaciones.
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
          Abre el menú del navegador (<strong>⋮</strong>) y elige <strong>Instalar app</strong> o{' '}
          <strong>Agregar a la pantalla principal</strong>. En Android usa Chrome.
        </p>
      ) : null}
    </Card>
  );
}
