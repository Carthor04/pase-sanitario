import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';
import { BrandMark } from '@/components/layout/BrandMark';
import { BathroomsLive } from '@/components/pass/BathroomsLive';
import { GroupLive } from '@/components/pass/GroupLive';
import { PinPad } from '@/components/pass/PinPad';
import { Loading, Notice } from '@/components/ui/Page';
import { LockIcon } from '@/components/ui/icons';
import {
  elapsedMs,
  formatElapsed,
  nursePasses,
  slotPass,
  withListNumbers,
  type Board,
  type BoardPass,
} from '@/lib/board';
import { useAudioUnlock, useWakeLock } from '@/lib/device';
import { errorMessage, useBoard, useLivePasses, useServerNow } from '@/lib/live';
import { hhmm, useCurrentClass, useGroups, useRoster } from '@/lib/queries';
import { useDevice } from '@/lib/session';
import { supabase } from '@/lib/supabase';
import { useClock } from '@/lib/useClock';

type Session = {
  now: string;
  unlocked: boolean;
  staff_name: string | null;
  unlocked_at: string | null;
  expires_at: string | null;
  last_lock: { staff_name: string; locked_at: string; reason: string } | null;
};

const timeFmt = new Intl.DateTimeFormat('es-MX', {
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
  timeZone: 'America/Mexico_City',
});
const hm = (iso: string | null | undefined) => (iso ? timeFmt.format(new Date(iso)) : '');

function useDeviceSession() {
  return useQuery({
    queryKey: ['device_session'],
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('device_session');
      if (error) throw error;
      return data as unknown as Session;
    },
  });
}

const UNLOCK_ERRORS: Record<string, string> = {
  wrong_pin: 'PIN incorrecto',
  locked: 'Demasiados intentos. Espera un minuto.',
};

/** Computadora del salón: SalonBloqueo (PIN) ↔ Main (desbloqueada). */
export function SalonHome() {
  const device = useDevice();
  const queryClient = useQueryClient();
  const session = useDeviceSession();
  const board = useBoard(device.group_id);
  const roster = useRoster(device.group_id);
  const current = useCurrentClass(device.group_id);
  const groups = useGroups();
  const online = useLivePasses();
  const clock = useClock();
  useAudioUnlock();
  useWakeLock();

  const room = groups.data?.find((g) => g.id === device.group_id)?.room;
  const unlocked = session.data?.unlocked ?? false;

  // Autobloqueo: al vencer el desbloqueo se vuelve a preguntar a la BD.
  const expiresAt = session.data?.expires_at;
  useEffect(() => {
    if (!expiresAt) return;
    const ms = new Date(expiresAt).getTime() - Date.now() + 1000;
    const id = window.setTimeout(
      () => void queryClient.invalidateQueries({ queryKey: ['device_session'] }),
      Math.max(1000, Math.min(ms, 2_147_000_000)),
    );
    return () => window.clearTimeout(id);
  }, [expiresAt, queryClient]);

  async function unlock(pin: string): Promise<string | null> {
    const { data, error } = await supabase.rpc('unlock_device', { p_pin: pin });
    if (error) return errorMessage(error);
    const res = data as { ok: boolean; error?: string; attempts_left?: number };
    if (!res.ok) {
      const base = UNLOCK_ERRORS[res.error ?? ''] ?? 'No se pudo desbloquear';
      return res.error === 'wrong_pin' && res.attempts_left
        ? `${base} · quedan ${res.attempts_left} intentos`
        : base;
    }
    await queryClient.invalidateQueries({ queryKey: ['device_session'] });
    return null;
  }

  async function lock() {
    await supabase.rpc('lock_device');
    await queryClient.invalidateQueries({ queryKey: ['device_session'] });
  }

  const classText = current.data
    ? `${current.data.subject}${current.data.teacher_name ? ` · ${current.data.teacher_name}` : ''}`
    : 'Sin clase en este momento';
  const classTime = current.data ? `${hhmm(current.data.starts)} – ${hhmm(current.data.ends)}` : '';

  if (session.isPending || board.isPending) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-dark text-white">
        <Loading />
      </div>
    );
  }

  if (!unlocked) {
    return (
      <div className="flex min-h-screen flex-col bg-dark text-white">
        <header className="mx-auto flex w-full max-w-container items-center gap-4 px-6 py-5 sm:px-16">
          <BrandMark />
          <span className="font-display text-[26px] font-bold">
            {device.group_name}
            {room ? ` · ${room}` : ''}
          </span>
          <span className="ml-auto font-mono text-[24px] font-semibold tabular-nums">{clock}</span>
        </header>
        <main className="mx-auto flex w-full max-w-[980px] flex-1 flex-col items-center justify-center gap-8 px-4 py-6 lg:flex-row lg:items-start lg:gap-8">
          <section
            aria-labelledby="lockTitle"
            className="flex w-full max-w-[460px] flex-col items-center gap-3 rounded-[22px] bg-surface px-8 py-8 text-ink"
          >
            <span className="flex h-14 w-14 items-center justify-center rounded-full bg-nurse-bg text-accent">
              <LockIcon size={26} />
            </span>
            <h1 id="lockTitle" className="m-0 font-display text-[28px] font-bold">
              Pantalla bloqueada
            </h1>
            <span className="text-[15px] text-muted">Clase actual</span>
            <span className="text-center text-[19px] font-bold">{classText}</span>
            {classTime ? (
              <span className="font-mono text-[15px] tabular-nums text-muted">{classTime}</span>
            ) : null}
            <PinPad onSubmit={unlock} />
            <span className="text-center text-[13px] text-muted">
              Escribe tu PIN para desbloquear. Si eres suplente, usa tu propio PIN y los pases
              quedarán a tu nombre.
            </span>
          </section>
          {board.data ? (
            <LockedStatus board={board.data} session={session.data} groupName={device.group_name} />
          ) : null}
        </main>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col bg-ground">
      <header className="border-b border-line bg-surface">
        <div className="mx-auto flex max-w-container flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3 sm:px-6">
          <div className="flex items-center gap-3">
            <BrandMark />
            <div className="flex flex-col">
              <span className="font-display text-[24px] font-bold leading-none">
                {device.group_name}
              </span>
              <span className="text-[13px] text-muted">{room ?? 'Secundaria'}</span>
            </div>
          </div>
          <div className="flex min-w-0 flex-1 flex-col">
            <span className="truncate">
              <strong className="text-[17px]">{current.data?.subject ?? 'Sin clase'}</strong>{' '}
              <span className="text-muted">{current.data?.teacher_name ?? ''}</span>{' '}
              <span className="font-mono text-[14px] tabular-nums text-muted">{classTime}</span>
            </span>
            <span className="text-[13px] text-muted">
              Desbloqueó {session.data?.staff_name} a las {hm(session.data?.unlocked_at)}
            </span>
          </div>
          <span
            className={`flex items-center gap-1.5 text-[14px] font-bold ${online ? 'text-free-fg' : 'text-alert-fg'}`}
          >
            <span
              aria-hidden="true"
              className={`h-2.5 w-2.5 rounded-full ${online ? 'bg-free-fg' : 'bg-alert-fg'}`}
            />
            {online ? 'En línea' : 'Sin conexión'}
          </span>
          <span className="font-mono text-[24px] font-semibold tabular-nums">{clock}</span>
          <button
            type="button"
            onClick={lock}
            aria-label="Bloquear pantalla"
            className="inline-flex min-h-btn items-center gap-2 rounded-btn border border-line-strong bg-surface px-4 font-bold"
          >
            <LockIcon />
            Bloquear
          </button>
        </div>
      </header>
      <main className="mx-auto grid w-full max-w-[1600px] flex-1 gap-5 px-4 py-5 sm:px-6 xl:grid-cols-[minmax(0,1fr)_320px]">
        <div className="min-w-0">
          {board.isError ? <Notice tone="error">No se pudo cargar el grupo.</Notice> : null}
          {roster.data?.section ? (
            <div className="mb-4">
              <Notice tone="info">
                Clase por nivel: la lista es la de {roster.data.section.subject}, con alumnos de
                varios grupos.
              </Notice>
            </div>
          ) : null}
          {board.data && roster.data ? (
            <GroupLive
              board={withListNumbers(board.data, roster.data.students)}
              groupName={device.group_name}
              groupId={device.group_id}
              students={roster.data.students}
              capture
              bathroomBar={false}
              footnote={`Un toque abre el pase. Queda registrado a nombre de ${session.data?.staff_name}, quien desbloqueó a las ${hm(session.data?.unlocked_at)}.`}
            />
          ) : (
            <Loading />
          )}
        </div>
        {/* Baños de toda la escuela en vivo (solo grupos, sin nombres). */}
        <aside
          aria-label="Baños en vivo"
          className="flex flex-col gap-3 xl:sticky xl:top-5 xl:self-start"
        >
          <h2 className="m-0 font-display text-[22px] font-bold">Baños ahora</h2>
          <BathroomsLive
            variant="panel"
            ownGroup={device.group_name}
            alertMinutes={board.data?.settings.alert_minutes}
          />
        </aside>
      </main>
    </div>
  );
}

/** Estado del grupo en solo lectura mientras la pantalla está bloqueada. */
function LockedStatus({
  board,
  session,
  groupName,
}: {
  board: Board & { offsetMs: number };
  session?: Session;
  groupName: string;
}) {
  const now = useServerNow(board.offsetMs);
  const rows: { title: string; pass?: BoardPass; empty: string }[] = [
    { title: 'Niño · Baño hombres', pass: slotPass(board.passes, 'H'), empty: 'Libre' },
    { title: 'Niña · Baño mujeres', pass: slotPass(board.passes, 'M'), empty: 'Libre' },
    { title: 'Enfermería', pass: nursePasses(board.passes)[0], empty: 'Nadie' },
  ];
  const last = session?.last_lock;
  return (
    <section aria-label="Estado del grupo" className="flex w-full max-w-[460px] flex-col gap-3">
      <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-white/70">
        Mientras está bloqueada
      </span>
      {rows.map((r) => (
        <div
          key={r.title}
          className="flex items-center justify-between gap-3 rounded-card border border-white/15 bg-white/5 px-4 py-3"
        >
          <div className="flex min-w-0 flex-col">
            <span className="text-[13px] text-white/70">{r.title}</span>
            {r.pass ? (
              <>
                <span className="truncate text-[18px] font-bold">
                  {r.pass.full_name} #{r.pass.list_number}
                </span>
                <span className="text-[13px] text-white/80">
                  {r.pass.status === 'returning'
                    ? `De regreso al salón desde ${hm(r.pass.left_nurse_at)}`
                    : r.pass.status === 'out' || r.pass.status === 'arrived'
                      ? `Salió${r.pass.period_subject ? ` en ${r.pass.period_subject}` : ''} · ${hm(r.pass.started_at)}`
                      : r.pass.status === 'called'
                        ? 'Su turno: desbloquea para confirmar'
                        : `En fila · lugar ${r.pass.queue_position ?? '—'}`}
                </span>
              </>
            ) : null}
          </div>
          {r.pass?.started_at && (r.pass.status === 'out' || r.pass.status === 'arrived') ? (
            <span className="font-mono text-[28px] font-semibold tabular-nums">
              {formatElapsed(elapsedMs(r.pass, now))}
            </span>
          ) : !r.pass ? (
            <span className="font-bold text-[#8FE0B0]">{r.empty}</span>
          ) : null}
        </div>
      ))}
      <span className="mt-2 text-[13px] font-bold uppercase tracking-[0.08em] text-white/70">
        Baños ahora
      </span>
      <BathroomsLive
        variant="dark"
        ownGroup={groupName}
        alertMinutes={board.settings.alert_minutes}
      />
      <p className="m-0 text-[13px] text-white/80">
        Los cronómetros siguen corriendo.
        {last
          ? ` ${last.staff_name} ${last.reason === 'auto' ? 'tenía la sesión; se bloqueó sola' : 'bloqueó'} a las ${hm(last.locked_at)}.`
          : ''}{' '}
        Si nadie bloquea, la pantalla se bloquea sola {board.settings.auto_lock_after_class_minutes}{' '}
        minutos después del timbre.
      </p>
    </section>
  );
}
