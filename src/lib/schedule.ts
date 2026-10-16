// Horarios: clase actual y siguiente, en hora de México.
import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { supabase } from './supabase';

export const WEEK_DAYS = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes'];

const partsFmt = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'America/Mexico_City',
  weekday: 'short',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hour12: false,
});
const WD: Record<string, number> = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };

/** Día de la semana (1 = lunes) y hora 'HH:MM:SS' en México. */
export function nowMx(now = new Date()): { weekday: number; time: string } {
  const p = Object.fromEntries(partsFmt.formatToParts(now).map((x) => [x.type, x.value]));
  const hour = p.hour === '24' ? '00' : p.hour;
  return { weekday: WD[p.weekday!] ?? 7, time: `${hour}:${p.minute}:${p.second}` };
}

type Slot = { weekday: number; starts: string; ends: string };

/** ¿Esta clase está ocurriendo ahora? Las horas vienen como 'HH:MM:SS'. */
export const isNow = (e: Slot, now: { weekday: number; time: string }) =>
  e.weekday === now.weekday && e.starts <= now.time && now.time < e.ends;

/** Siguiente clase de hoy, o null si ya no hay. */
export function nextToday<T extends Slot>(
  entries: T[],
  now: { weekday: number; time: string },
): T | null {
  return (
    entries
      .filter((e) => e.weekday === now.weekday && e.starts > now.time)
      .sort((a, b) => a.starts.localeCompare(b.starts))[0] ?? null
  );
}

/** Franjas distintas 'inicio|fin' ordenadas, para dibujar la tabla semanal. */
export const slotsOf = (entries: Slot[]) =>
  [...new Set(entries.map((e) => `${e.starts}|${e.ends}`))].sort();

/** Hora actual de México que se actualiza cada 30 s (para resaltar la clase actual). */
export function useNowMx() {
  const [now, setNow] = useState(() => nowMx());
  useEffect(() => {
    const id = window.setInterval(() => setNow(nowMx()), 30_000);
    return () => window.clearInterval(id);
  }, []);
  return now;
}

// ---------------------------------------------------------------------------
// Docentes
// ---------------------------------------------------------------------------
export type TeacherEntry = Slot & { subject: string; group_name: string; room: string | null };
export type TeacherSchedule = {
  now: string;
  entries: TeacherEntry[];
  current: {
    subject: string;
    group_name: string;
    room: string | null;
    starts: string;
    ends: string;
  } | null;
};

export function useTeachers() {
  return useQuery({
    queryKey: ['teachers'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('staff')
        .select('id, full_name')
        .eq('active', true)
        .contains('roles', ['teacher'])
        .order('full_name');
      if (error) throw error;
      return data as { id: string; full_name: string }[];
    },
  });
}

export function useTeacherSchedule(staffId: string) {
  return useQuery({
    queryKey: ['teacher-schedule', staffId],
    enabled: Boolean(staffId),
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('teacher_schedule', { p_staff_id: staffId });
      if (error) throw error;
      return data as unknown as TeacherSchedule;
    },
  });
}

export type CurrentClass = {
  group_id: string;
  group_name: string;
  room: string | null;
  subject: string | null;
  teacher_name: string | null;
  starts: string | null;
  ends: string | null;
};

/** Clase actual de cada grupo. */
export function useCurrentClasses() {
  return useQuery({
    queryKey: ['current-classes'],
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('current_classes');
      if (error) throw error;
      return (data as unknown as { groups: CurrentClass[] }).groups;
    },
  });
}
