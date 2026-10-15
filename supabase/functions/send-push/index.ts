// send-push: envía los avisos pendientes de notifications_outbox por Web Push.
// La llama Postgres (pg_net) al insertar en la bandeja y un cron cada minuto de respaldo.
// Se protege con el encabezado x-push-secret (PUSH_WEBHOOK_SECRET); no usa JWT.
// Secretos: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT, PUSH_WEBHOOK_SECRET.
import { createClient } from 'npm:@supabase/supabase-js@2.47.10';
import webpush from 'npm:web-push@3.6.7';

type Sub = { endpoint: string; p256dh: string; auth: string };
type Row = {
  id: number;
  recipient_staff_id: string;
  body: string;
  payload: { title?: string; url?: string; tag?: string; level?: number };
  subscriptions: Sub[];
};

const env = (name: string) => {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Falta el secreto ${name}`);
  return v;
};

webpush.setVapidDetails(env('VAPID_SUBJECT'), env('VAPID_PUBLIC_KEY'), env('VAPID_PRIVATE_KEY'));
const supabase = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false },
});

async function sendRow(row: Row) {
  const message = JSON.stringify({
    title: row.payload.title ?? 'Pase Sanitario',
    body: row.body,
    url: row.payload.url ?? '/',
    tag: row.payload.tag,
    urgent: (row.payload.level ?? 1) >= 2,
  });
  const ok: string[] = [];
  const dead: string[] = [];
  const errors: string[] = [];

  await Promise.all(
    row.subscriptions.map(async (s) => {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          message,
          { TTL: 600, urgency: 'high' },
        );
        ok.push(s.endpoint);
      } catch (err) {
        const status = (err as { statusCode?: number }).statusCode;
        // 404/410: el navegador ya no existe o quitó el permiso.
        if (status === 404 || status === 410) dead.push(s.endpoint);
        else errors.push(`${status ?? ''} ${(err as Error).message}`.trim());
      }
    }),
  );

  const error =
    row.subscriptions.length === 0
      ? 'Sin equipos registrados'
      : ok.length === 0
        ? errors.join('; ') || 'Suscripciones vencidas'
        : null;
  await supabase.rpc('finish_push', {
    p_id: row.id,
    p_error: error,
    p_dead_endpoints: dead,
    p_ok_endpoints: ok,
  });
  return error === null;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Método no permitido', { status: 405 });
  if (req.headers.get('x-push-secret') !== env('PUSH_WEBHOOK_SECRET')) {
    return new Response('No autorizado', { status: 401 });
  }

  const { data, error } = await supabase.rpc('claim_push_batch', { p_limit: 100 });
  if (error) {
    console.error('claim_push_batch', error.message);
    return Response.json({ error: error.message }, { status: 500 });
  }
  const rows = (data ?? []) as Row[];
  const results = await Promise.all(rows.map(sendRow));
  return Response.json({ processed: rows.length, sent: results.filter(Boolean).length });
});
