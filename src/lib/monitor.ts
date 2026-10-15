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
  started_at: string | null;
  arrived_at: string | null;
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
    refetchInterval: 30_000,
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
export function alertStatusText(alert: NonNullable<PassAlert>): string {
  if (alert.acknowledged_by_name) return `${alert.acknowledged_by_name} va en camino`;
  return alert.level === 2 ? 'Escalada · sin atender' : 'Sin atender';
}
