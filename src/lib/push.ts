// Suscripción a notificaciones push de este equipo (INTEGRATIONS §1).
import { supabase } from './supabase';

export type PushState =
  | 'unsupported' // el navegador no tiene Web Push
  | 'ios-install' // iPhone/iPad: primero hay que instalar la app en la pantalla de inicio
  | 'denied' // el usuario bloqueó las notificaciones
  | 'off'
  | 'on';

export function isIos(ua = navigator.userAgent): boolean {
  return /iPad|iPhone|iPod/.test(ua) || (ua.includes('Macintosh') && navigator.maxTouchPoints > 1);
}

export function isStandalone(): boolean {
  return (
    window.matchMedia?.('(display-mode: standalone)').matches ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true
  );
}

const supported = () =>
  'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;

export async function currentSubscription(): Promise<PushSubscription | null> {
  if (!supported()) return null;
  const reg = await navigator.serviceWorker.getRegistration();
  return (await reg?.pushManager.getSubscription()) ?? null;
}

export async function getPushState(): Promise<PushState> {
  if (isIos() && !isStandalone()) return 'ios-install';
  if (!supported()) return 'unsupported';
  if (Notification.permission === 'denied') return 'denied';
  return (await currentSubscription()) ? 'on' : 'off';
}

/** Llave VAPID pública (base64url) → bytes. */
export function urlBase64ToUint8Array(base64: string): Uint8Array {
  const padded = (base64 + '='.repeat((4 - (base64.length % 4)) % 4))
    .replace(/-/g, '+')
    .replace(/_/g, '/');
  const raw = atob(padded);
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

/** Pide permiso y registra este equipo. Debe llamarse desde un toque del usuario. */
export async function enablePush(): Promise<void> {
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') throw new Error('No se dio permiso para notificaciones.');

  const { data, error } = await supabase.rpc('push_config');
  if (error) throw error;
  const key = (data as { vapid_public_key?: string } | null)?.vapid_public_key;
  if (!key) throw new Error('Las notificaciones aún no están configuradas en el servidor.');

  const reg = await navigator.serviceWorker.ready;
  const sub =
    (await reg.pushManager.getSubscription()) ??
    (await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(key),
    }));
  const json = sub.toJSON();
  const { error: saveError } = await supabase.rpc('save_push_subscription', {
    p_endpoint: sub.endpoint,
    p_p256dh: json.keys?.p256dh ?? '',
    p_auth: json.keys?.auth ?? '',
    p_user_agent: navigator.userAgent,
  });
  if (saveError) throw saveError;
}

export async function disablePush(): Promise<void> {
  const sub = await currentSubscription();
  if (!sub) return;
  await supabase.rpc('delete_push_subscription', { p_endpoint: sub.endpoint });
  await sub.unsubscribe();
}
