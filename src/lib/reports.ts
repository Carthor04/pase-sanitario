// Reportes e historial (SPEC §9): tipos, consultas y utilidades de fechas en hora de México.
import { useQuery } from '@tanstack/react-query';
import { supabase } from './supabase';

export type Report = {
  from: string;
  to: string;
  thresholds: { alerts: number; exits: number };
  totals: {
    exits: number;
    bathroom: number;
    nurse: number;
    avg_minutes: number | null;
    avg_minutes_h: number | null;
    avg_minutes_m: number | null;
  };
  alerts: { count: number; acknowledged_fast: number; escalated: number };
  max_queue: { size: number; destination: string; at: string } | null;
  heatmap: { destination: string; weekday: number; hour: number; count: number }[];
  queued_slots: { destination: string; weekday: number; hour: number }[];
  by_group: {
    group_id: string;
    group_name: string;
    exits: number;
    avg_minutes: number | null;
    alerts: number;
  }[];
  review: {
    student_id: string;
    full_name: string;
    list_number: number;
    group_name: string;
    exits: number;
    nurse: number;
    avg_minutes: number | null;
    alerts: number;
    top_subject: string | null;
  }[];
};

export type HistoryRow = {
  id: string;
  requested_at: string;
  started_at: string | null;
  ended_at: string | null;
  status: string;
  period_subject: string | null;
  release_reason: string | null;
  minutes: number | null;
  full_name: string;
  list_number: number;
  group_name: string;
  destination: string;
  kind: 'bathroom' | 'nurse';
  opened_by: string | null;
  closed_by: string | null;
  from_device: boolean;
  alert: { level: number; acknowledged_by: string | null } | null;
};

export type TimelineEvent = {
  type: string;
  at: string;
  actor: string | null;
  from_device: boolean;
  payload: Record<string, unknown>;
};

// ---------------------------------------------------------------------------
// Fechas (siempre en hora de México, como 'YYYY-MM-DD')
// ---------------------------------------------------------------------------
const dayFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Mexico_City',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

/** Fecha de hoy en México como YYYY-MM-DD. */
export const todayMx = (now = new Date()) => dayFmt.format(now);

function addDays(iso: string, days: number): string {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

const weekday = (iso: string) => new Date(`${iso}T12:00:00Z`).getUTCDay() || 7; // 1 = lunes

export type RangeKey = 'week' | 'last_week' | 'month' | 'last_30' | 'today';

export const RANGE_LABELS: Record<RangeKey, string> = {
  today: 'Hoy',
  week: 'Esta semana',
  last_week: 'Semana pasada',
  month: 'Este mes',
  last_30: 'Últimos 30 días',
};

/** Rango [desde, hasta] para el selector de periodo. Las semanas van de lunes a viernes. */
export function rangeFor(key: RangeKey, today = todayMx()): { from: string; to: string } {
  const monday = addDays(today, 1 - weekday(today));
  switch (key) {
    case 'today':
      return { from: today, to: today };
    case 'week':
      return { from: monday, to: addDays(monday, 4) };
    case 'last_week':
      return { from: addDays(monday, -7), to: addDays(monday, -3) };
    case 'month':
      return { from: `${today.slice(0, 8)}01`, to: today };
    case 'last_30':
      return { from: addDays(today, -29), to: today };
  }
}

const MONTHS = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/** "del 12 al 16 de octubre", "del 28 de septiembre al 2 de octubre", "15 de octubre". */
export function rangeTitle(from: string, to: string): string {
  const [, fm, fd] = from.split('-').map(Number) as [number, number, number];
  const [, tm, td] = to.split('-').map(Number) as [number, number, number];
  if (from === to) return `${td} de ${MONTHS[tm - 1]}`;
  if (fm === tm) return `del ${fd} al ${td} de ${MONTHS[tm - 1]}`;
  return `del ${fd} de ${MONTHS[fm - 1]} al ${td} de ${MONTHS[tm - 1]}`;
}

// ---------------------------------------------------------------------------
// Mapa de calor
// ---------------------------------------------------------------------------
export type HeatCell = { weekday: number; hour: number; count: number; queued: boolean };

/**
 * Matriz lunes–viernes × horas (7 a 13 por defecto, o más si hubo salidas fuera de ese
 * horario) para un baño.
 */
export function heatmapMatrix(report: Report, destination: string) {
  const cells = report.heatmap.filter((c) => c.destination === destination);
  const hours = new Set([7, 8, 9, 10, 11, 12, 13]);
  for (const c of cells) hours.add(c.hour);
  const hourList = [...hours].sort((a, b) => a - b);
  const queued = new Set(
    report.queued_slots
      .filter((q) => q.destination === destination)
      .map((q) => `${q.weekday}:${q.hour}`),
  );
  const rows = [1, 2, 3, 4, 5].map((wd) =>
    hourList.map<HeatCell>((hour) => ({
      weekday: wd,
      hour,
      count: cells.find((c) => c.weekday === wd && c.hour === hour)?.count ?? 0,
      queued: queued.has(`${wd}:${hour}`),
    })),
  );
  const max = Math.max(1, ...cells.map((c) => c.count));
  return { hours: hourList, rows, max };
}

// ---------------------------------------------------------------------------
// Consultas
// ---------------------------------------------------------------------------
export function useReport(from: string, to: string) {
  return useQuery({
    queryKey: ['report', from, to],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('report_summary', { p_from: from, p_to: to });
      if (error) throw error;
      return data as unknown as Report;
    },
  });
}

export function useHistory(filters: { from: string; to: string; query: string; groupId: string }) {
  return useQuery({
    queryKey: ['history', filters],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('pass_history', {
        p_from: filters.from,
        p_to: filters.to,
        p_query: filters.query || undefined,
        p_group: filters.groupId || undefined,
        p_limit: 200,
      });
      if (error) throw error;
      return data as unknown as HistoryRow[];
    },
  });
}

export function useTimeline(passId: string | null) {
  return useQuery({
    queryKey: ['timeline', passId],
    enabled: Boolean(passId),
    queryFn: async () => {
      const { data, error } = await supabase.rpc('pass_timeline', { p_pass_id: passId! });
      if (error) throw error;
      return data as unknown as TimelineEvent[];
    },
  });
}

/** Cómo terminó un pase, en palabras. */
export function closureText(
  r: Pick<HistoryRow, 'status' | 'closed_by' | 'release_reason' | 'alert'>,
): string {
  switch (r.status) {
    case 'returned':
      return r.alert
        ? `Regresó con alerta${r.alert.acknowledged_by ? ` · atendió ${r.alert.acknowledged_by}` : ''}`
        : 'Regresó';
    case 'released':
      return `Liberado${r.release_reason ? `: ${r.release_reason}` : ''}`;
    case 'cancelled':
      return 'Cancelado';
    case 'arrived':
      return 'En enfermería';
    case 'out':
      return 'Fuera';
    default:
      return 'En espera';
  }
}

export const EVENT_LABELS: Record<string, string> = {
  requested: 'Se pidió el pase',
  promoted: 'Pasó a la fila / salió',
  called: 'Le tocó su turno',
  confirmed: 'Se confirmó su salida',
  ceded: 'Cedió el turno',
  turn_expired: 'No se confirmó a tiempo',
  arrived: 'Llegó a enfermería',
  returned: 'Regresó',
  released: 'Se liberó el lugar',
  cancelled: 'Se canceló',
  undo: 'Se deshizo el último cambio',
  alert: 'Alerta de tiempo',
  escalated: 'Alerta escalada',
  alert_ack: 'Alguien atiende la alerta',
  note: 'Nota de enfermería',
};
