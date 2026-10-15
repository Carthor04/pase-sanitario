import { useQuery } from '@tanstack/react-query';
import { supabase } from './supabase';

export type Student = {
  id: string;
  list_number: number;
  full_name: string;
  sex: 'H' | 'M';
};

export function useStudents(groupId: string | undefined) {
  return useQuery({
    queryKey: ['students', groupId],
    enabled: Boolean(groupId),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('students')
        .select('id, list_number, full_name, sex')
        .eq('group_id', groupId!)
        .eq('active', true)
        .order('list_number');
      if (error) throw error;
      return data as Student[];
    },
  });
}

/** Grupos en el orden del selector del celular (SPEC §6). */
export function useMyGroups() {
  return useQuery({
    queryKey: ['my_groups'],
    refetchInterval: 60_000, // la clase actual cambia con la hora
    queryFn: async () => {
      const { data, error } = await supabase.rpc('my_groups', {});
      if (error) throw error;
      return data;
    },
  });
}

export function useCurrentClass(groupId: string | undefined) {
  return useQuery({
    queryKey: ['current_class', groupId],
    enabled: Boolean(groupId),
    refetchInterval: 60_000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('v_current_class')
        .select('subject, teacher_name, starts, ends')
        .eq('group_id', groupId!)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
  });
}

export function useGroups() {
  return useQuery({
    queryKey: ['groups'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('groups')
        .select('id, name, room, sort')
        .order('sort', { nullsFirst: false })
        .order('name');
      if (error) throw error;
      return data;
    },
  });
}

/** '07:30:00' → '07:30' */
export const hhmm = (t: string | null | undefined) => (t ? t.slice(0, 5) : '');
