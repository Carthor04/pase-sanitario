// Instalar la PWA en la pantalla de inicio (Más → Instalar app).
// Chrome/Edge en Android y computadora mandan `beforeinstallprompt` una sola vez y muy
// pronto, así que se escucha desde que carga la app (main.tsx importa este módulo) y se
// guarda para cuando el usuario toque el botón. Safari en iPhone no lo manda: ahí se
// muestran los pasos de Compartir → Agregar a inicio.
import { isIos, isStandalone } from './push';

type InstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
};

export type InstallState =
  | 'installed' // ya se abrió desde el ícono (o se acaba de instalar)
  | 'prompt' // el navegador permite instalar con un toque
  | 'ios' // iPhone/iPad: pasos manuales en Safari
  | 'manual'; // otro navegador: desde su menú

let deferred: InstallPromptEvent | null = null;
let justInstalled = false;
const listeners = new Set<() => void>();
const notify = () => listeners.forEach((fn) => fn());

if (typeof window !== 'undefined') {
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault(); // sin mini barra del navegador: se instala desde el botón
    deferred = e as InstallPromptEvent;
    notify();
  });
  window.addEventListener('appinstalled', () => {
    deferred = null;
    justInstalled = true;
    notify();
  });
}

export function getInstallState(): InstallState {
  if (justInstalled || isStandalone()) return 'installed';
  if (deferred) return 'prompt';
  if (isIos()) return 'ios';
  return 'manual';
}

export function subscribeInstall(fn: () => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/** Abre el diálogo de instalación del navegador. Debe llamarse desde un toque. */
export async function promptInstall(): Promise<boolean> {
  const e = deferred;
  if (!e) return false;
  await e.prompt();
  const { outcome } = await e.userChoice;
  deferred = null; // el evento solo sirve una vez
  notify();
  return outcome === 'accepted';
}
