// Datos en vivo: tablero del grupo con Realtime, reloj sincronizado con el servidor y
// acciones sobre pases. El cliente nunca decide; solo llama RPC y muestra el resultado.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { parseBoard, type ActiveStatus } from './board';
import { supabase } from './supabase';

/** Escucha cambios en `passes` y refresca los tableros. Devuelve si hay conexión. */
export function useLivePasses(): boolean {
  const queryClient = useQueryClient();
  const [online, setOnline] = useState(true);

  useEffect(() => {
    const channel = supabase
      .channel(`passes-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'passes' }, () => {
        void queryClient.invalidateQueries({ queryKey: ['board'] });
      })
      .subscribe((status) => {
        setOnline(status === 'SUBSCRIBED');
        // Al reconectar puede haber cambios perdidos.
        if (status === 'SUBSCRIBED') void queryClient.invalidateQueries({ queryKey: ['board'] });
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
  | { type: 'confirm' | 'cede' | 'return' | 'cancel' | 'undo'; passId: string };

const RPC = {
  confirm: 'confirm_turn',
  cede: 'cede_turn',
  return: 'mark_returned',
  cancel: 'cancel_pass',
  undo: 'undo_last',
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
          : await supabase.rpc(RPC[action.type], { p_pass_id: action.passId });
      if (error) throw error;
      return data as unknown as PassResult;
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: ['board'] }),
  });
}
