// Datos en vivo: tablero del grupo con Realtime, reloj sincronizado con el servidor y
// acciones sobre pases. El cliente nunca decide; solo llama RPC y muestra el resultado.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { parseBoard, type ActiveStatus } from './board';
import { supabase } from './supabase';

/** Consultas que dependen de pases y alertas: se refrescan con cada cambio. */
export const LIVE_KEYS = ['board', 'live', 'my_alerts', 'nurse'] as const;

export function invalidateLive(queryClient: ReturnType<typeof useQueryClient>) {
  return Promise.all(LIVE_KEYS.map((k) => queryClient.invalidateQueries({ queryKey: [k] })));
}

/** Escucha cambios en `passes` y `alerts` y refresca las pantallas. Devuelve si hay conexión. */
export function useLivePasses(): boolean {
  const queryClient = useQueryClient();
  const [online, setOnline] = useState(true);

  useEffect(() => {
    const channel = supabase
      .channel(`passes-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'passes' }, () => {
        void invalidateLive(queryClient);
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'alerts' }, () => {
        void invalidateLive(queryClient);
      })
      .subscribe((status) => {
        setOnline(status === 'SUBSCRIBED');
        // Al reconectar puede haber cambios perdidos.
        if (status === 'SUBSCRIBED') void invalidateLive(queryClient);
      });
    const goOffline = () => setOnline(false);
    window.addEventListener('offline', goOffline);
    return () => {
      window.removeEventListener('offline', goOffline);
      void supabase.removeChannel(channel);
    };
  }, [queryClient]);

  return online;
}

export function useBoard(groupId: string | undefined) {
  return useQuery({
    queryKey: ['board', groupId],
    enabled: Boolean(groupId),
    refetchInterval: 30_000, // respaldo por si se pierde un evento de Realtime
    queryFn: async () => {
      const { data, error } = await supabase.rpc('group_board', { p_group_id: groupId! });
      if (error) throw error;
      const board = parseBoard(data);
      return { ...board, offsetMs: new Date(board.now).getTime() - Date.now() };
    },
  });
}

/**
 * Hora actual del servidor (con la diferencia de reloj de este equipo corregida), en ms.
 * Se actualiza cada segundo para los cronómetros.
 */
export function useServerNow(offsetMs = 0): number {
  const [now, setNow] = useState(() => Date.now() + offsetMs);
  useEffect(() => {
    const tick = () => setNow(Date.now() + offsetMs);
    tick();
    const id = window.setInterval(tick, 1000);
    return () => window.clearInterval(id);
  }, [offsetMs]);
  return now;
}

type PassResult = {
  id: string;
  status: ActiveStatus | 'returned' | 'cancelled' | 'released';
  queue_position: number | null;
  destination_id: string;
};

type Action =
  | { type: 'request'; studentId: string; kind: 'bathroom' | 'nurse' }
  | {
      type: 'confirm' | 'cede' | 'return' | 'cancel' | 'undo' | 'arrived' | 'sendBack';
      passId: string;
    }
  | { type: 'release'; passId: string; reason: string }
  | { type: 'acknowledge'; alertId: string }
  | { type: 'note'; passId: string; body: string };

const RPC = {
  confirm: 'confirm_turn',
  cede: 'cede_turn',
  return: 'mark_returned',
  cancel: 'cancel_pass',
  undo: 'undo_last',
  arrived: 'mark_arrived',
  sendBack: 'nurse_send_back',
} as const;

/** Mensaje legible de un error de Supabase (las RPC ya devuelven textos en español). */
export function errorMessage(err: unknown): string {
  if (err && typeof err === 'object' && 'message' in err && typeof err.message === 'string') {
    if (/Failed to fetch|NetworkError|network/i.test(err.message)) {
      return 'Sin conexión. Revisa el internet e inténtalo de nuevo.';
    }
    return err.message;
  }
  return 'No se pudo completar la acción.';
}

/** Acciones sobre pases y alertas. Todas son RPC: el cliente no decide nada. */
export function usePassAction() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (action: Action): Promise<PassResult> => {
      const { data, error } =
        action.type === 'request'
          ? await supabase.rpc('request_pass', {
              p_student_id: action.studentId,
              p_kind: action.kind,
            })
          : action.type === 'release'
            ? await supabase.rpc('release_pass', {
                p_pass_id: action.passId,
                p_reason: action.reason,
              })
            : action.type === 'acknowledge'
              ? await supabase.rpc('acknowledge_alert', { p_alert_id: action.alertId })
              : action.type === 'note'
                ? await supabase.rpc('add_nurse_note', {
                    p_pass_id: action.passId,
                    p_body: action.body,
                  })
                : await supabase.rpc(RPC[action.type], { p_pass_id: action.passId });
      if (error) throw error;
      return data as unknown as PassResult;
    },
    onSettled: () => invalidateLive(queryClient),
  });
}

export type BathroomsStatus = {
  now: string;
  nurse: number;
  offsetMs: number;
  bathrooms: {
    id: string;
    label: string;
    sex: 'H' | 'M';
    capacity: number | null;
    occupants: { group_name: string; status: 'called' | 'out'; since: string }[];
    queue: { group_name: string; since: string }[];
    group_wait: number;
  }[];
};

/** Estado de todos los baños (solo grupos, sin nombres). Se refresca con Realtime. */
export function useBathrooms() {
  return useQuery({
    queryKey: ['board', 'bathrooms'],
    refetchInterval: 30_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('bathrooms_status');
      if (error) throw error;
      const s = data as unknown as Omit<BathroomsStatus, 'offsetMs'>;
      return { ...s, offsetMs: new Date(s.now).getTime() - Date.now() } as BathroomsStatus;
    },
  });
}

export type TodayCounts = {
  /** A partir de cuántas salidas al baño en el día se marca al alumno (settings). */
  flag: number;
  counts: Record<string, { bathroom: number; nurse: number }>;
};

/** Salidas de hoy por alumno del grupo (baño y enfermería). Se refresca con Realtime. */
export function useTodayCounts(groupId: string | undefined) {
  return useQuery({
    queryKey: ['board', 'counts', groupId],
    enabled: Boolean(groupId),
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('group_today_counts', { p_group_id: groupId! });
      if (error) throw error;
      return data as unknown as TodayCounts;
    },
  });
}

export type TodayExit = {
  started_at: string;
  ended_at: string | null;
  status: string;
  destination: string;
  kind: 'bathroom' | 'nurse';
  subject: string | null;
  opened_by: string | null;
  minutes: number | null;
  alert: boolean;
};

/** Salidas de hoy de un alumno: horario, destino, clase y quién autorizó. */
export function useStudentToday(studentId: string | null) {
  return useQuery({
    queryKey: ['board', 'student-today', studentId],
    enabled: Boolean(studentId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('student_today_passes', {
        p_student_id: studentId!,
      });
      if (error) throw error;
      return data as unknown as TodayExit[];
    },
  });
}

/** "2 baño · 1 enfermería" o null si no ha salido hoy. */
export function todayLabel(c: { bathroom: number; nurse: number } | undefined): string | null {
  if (!c || (!c.bathroom && !c.nurse)) return null;
  const parts = [];
  if (c.bathroom) parts.push(`${c.bathroom} baño`);
  if (c.nurse) parts.push(`${c.nurse} enfermería`);
  return parts.join(' · ');
}
