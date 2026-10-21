// Lecturas de la Fase 4: monitor en vivo (prefectura), alertas del maestro y enfermería.
import { useQuery } from '@tanstack/react-query';
import { useEffect, useRef } from 'react';
import type { ActiveStatus, Sex } from './board';
import { playAlertSound } from './device';
import { supabase } from './supabase';

export type PassAlert = {
  id: string;
  level: 1 | 2;
  created_at: string;
  acknowledged_by_name: string | null;
  acknowledged_at: string | null;
} | null;

export type LivePass = {
  id: string;
  student_id: string;
  list_number: number;
  full_name: string;
  sex: Sex;
  group_id: string;
  group_name: string;
  status: ActiveStatus;
  destination_id: string;
  requested_at: string;
  queue_ts: string | null;
  called_at: string | null;
  started_at: string | null;
  arrived_at: string | null;
  left_nurse_at: string | null;
  period_subject: string | null;
  opened_by_name: string | null;
  current_teacher_name: string | null;
  alert: PassAlert;
};

export type LiveDestination = {
  id: string;
  label: string;
  kind: 'bathroom' | 'nurse';
  sex: Sex | null;
  capacity: number | null;
};

export type LiveBoard = {
  now: string;
  settings: { alert_minutes: number; escalate_minutes: number; confirm_turn_minutes: number };
  destinations: LiveDestination[];
  passes: LivePass[];
  stats: { exits_today: number; alerts_today: number };
  offsetMs: number;
};

export type MyAlert = {
  pass_id: string;
  full_name: string;
  list_number: number;
  group_id: string;
  group_name: string;
  status: ActiveStatus;
  destination_label: string;
  started_at: string | null;
  period_subject: string | null;
  alert: NonNullable<PassAlert>;
};

export type NursePass = {
  id: string;
  full_name: string;
  list_number: number;
  group_name: string;
  status: ActiveStatus | 'returned' | 'released' | 'cancelled';
  period_subject?: string | null;
  started_at: string | null;
  arrived_at: string | null;
  left_nurse_at: string | null;
  ended_at: string | null;
  opened_by_name: string | null;
  note: string | null;
  alert: PassAlert;
};

const withOffset = <T extends { now: string }>(data: T) => ({
  ...data,
  offsetMs: new Date(data.now).getTime() - Date.now(),
});

export function useLiveBoard() {
  return useQuery({
    queryKey: ['live'],
    refetchInterval: 15_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('live_board');
      if (error) throw error;
      return withOffset(data as unknown as Omit<LiveBoard, 'offsetMs'>) as LiveBoard;
    },
  });
}

export function useMyAlerts(enabled = true) {
  return useQuery({
    queryKey: ['my_alerts'],
    enabled,
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('my_alerts');
      if (error) throw error;
      return data as unknown as MyAlert[];
    },
  });
}

export function useNurseToday() {
  return useQuery({
    queryKey: ['nurse'],
    refetchInterval: 30_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('nurse_today');
      if (error) throw error;
      return withOffset(data as unknown as { now: string; passes: NursePass[] });
    },
  });
}

/** Suena cuando aparece una alerta nueva o una se escala. */
export function useAlertSound(alerts: { id: string; level: number }[] | undefined) {
  const seen = useRef<Set<string> | null>(null);
  useEffect(() => {
    if (!alerts) return;
    const keys = new Set(alerts.map((a) => `${a.id}:${a.level}`));
    if (seen.current && [...keys].some((k) => !seen.current!.has(k))) playAlertSound();
    seen.current = keys;
  }, [alerts]);
}

const timeFmt = new Intl.DateTimeFormat('es-MX', {
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
  timeZone: 'America/Mexico_City',
});
/** 10:47 en hora de México. */
export const hm = (iso: string | null | undefined) => (iso ? timeFmt.format(new Date(iso)) : '');

/** "Sin atender", "Atiende Juan Pérez" o "Escalada · sin atender". */
/**
 * Pases en alerta para el monitor: los que ya tienen alerta en la BD y los que ya pasaron el
 * tiempo aunque tick() (cada 30 s) todavía no la cree. Así la tarjeta, el sonido y "Yo lo
 * atiendo" aparecen en cuanto se cumple el tiempo; atender crea la alerta si falta.
 */
export function overdueAlerts(
  board: LiveBoard,
  now: number,
): (LivePass & { alert: NonNullable<PassAlert> })[] {
  const limit = board.settings.alert_minutes * 60_000;
  return board.passes.flatMap((p) => {
    if (p.alert) return [{ ...p, alert: p.alert }];
    const since =
      p.status === 'out' ? p.started_at : p.status === 'returning' ? p.left_nurse_at : null;
    if (!since || now - new Date(since).getTime() < limit) return [];
    const created = new Date(new Date(since).getTime() + limit).toISOString();
    return [
      {
        ...p,
        alert: {
          id: `pass:${p.id}`,
          level: 1 as const,
          created_at: created,
          acknowledged_by_name: null,
          acknowledged_at: null,
        },
      },
    ];
  });
}

/** Momento (ms) en que el siguiente pase cumple el tiempo de alerta, o null si no hay. */
export function nextAlertAt(board: LiveBoard): number | null {
  const limit = board.settings.alert_minutes * 60_000;
  const times = board.passes
    .filter((p) => !p.alert)
    .map((p) =>
      p.status === 'out' ? p.started_at : p.status === 'returning' ? p.left_nurse_at : null,
    )
    .filter((s): s is string => Boolean(s))
    .map((s) => new Date(s).getTime() + limit);
  return times.length ? Math.min(...times) : null;
}

export function alertStatusText(alert: NonNullable<PassAlert>): string {
  if (alert.acknowledged_by_name) return `${alert.acknowledged_by_name} va en camino`;
  return alert.level === 2 ? 'Escalada · sin atender' : 'Sin atender';
}
