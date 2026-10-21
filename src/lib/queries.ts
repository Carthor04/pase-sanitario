import { useQuery } from '@tanstack/react-query';
import { byName } from './students';
import { supabase } from './supabase';

export type Student = {
  id: string;
  list_number: number;
  full_name: string;
  sex: 'H' | 'M';
  /** Solo en clases por nivel: el grupo del alumno (la lista mezcla grupos). */
  group_name?: string;
};

export type RosterSection = { id: string; subject: string; teacher_name: string | null };
export type Roster = { section: RosterSection | null; students: Student[] };

type RawRoster = {
  section: RosterSection | null;
  students: (Student & { group_name: string })[];
};

/**
 * Lista del salón según la hora: la del grupo o, en una clase por nivel (Inglés), la de los
 * alumnos de ese nivel. En la clase por nivel los números van del 1 en orden alfabético (los
 * números de lista se repiten entre grupos) y cada alumno lleva su grupo.
 */
export function useRoster(groupId: string | undefined) {
  return useQuery({
    queryKey: ['roster', groupId],
    enabled: Boolean(groupId),
    refetchInterval: 60_000, // la lista cambia al empezar y terminar la clase por nivel
    queryFn: async (): Promise<Roster> => {
      const { data, error } = await supabase.rpc('room_roster', { p_group_id: groupId! });
      if (error) throw error;
      const raw = data as unknown as RawRoster;
      const sorted = [...raw.students].sort(byName);
      return {
        section: raw.section,
        students: raw.section
          ? sorted.map((s, i) => ({ ...s, list_number: i + 1 }))
          : sorted.map(({ id, list_number, full_name, sex }) => ({
              id,
              list_number,
              full_name,
              sex,
            })),
      };
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
