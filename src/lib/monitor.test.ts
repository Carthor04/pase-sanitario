import { withListNumbers, type Board } from './board';
import { nextAlertAt, overdueAlerts, type LiveBoard, type LivePass } from './monitor';

vi.mock('./supabase', () => ({ supabase: {} }));

const T0 = new Date('2026-10-26T13:00:00Z').getTime();
const min = (m: number) => new Date(T0 + m * 60_000).toISOString();

function pass(over: Partial<LivePass>): LivePass {
  return {
    id: 'p',
    student_id: 's',
    list_number: 1,
    full_name: 'Alumno',
    sex: 'H',
    group_id: 'g',
    group_name: '1°A',
    status: 'out',
    destination_id: 'bath_h',
    requested_at: min(0),
    queue_ts: null,
    called_at: null,
    started_at: min(0),
    arrived_at: null,
    left_nurse_at: null,
    period_subject: null,
    opened_by_name: null,
    current_teacher_name: null,
    alert: null,
    ...over,
  };
}

const board = (passes: LivePass[]): LiveBoard => ({
  now: min(0),
  settings: { alert_minutes: 10, escalate_minutes: 5, confirm_turn_minutes: 2 },
  destinations: [
    { id: 'bath_h', label: 'Baño H', kind: 'bathroom', sex: 'H', capacity: 2 },
    { id: 'bath_m', label: 'Baño M', kind: 'bathroom', sex: 'M', capacity: 2 },
    { id: 'nurse', label: 'Enfermería', kind: 'nurse', sex: null, capacity: null },
  ],
  passes,
  stats: { exits_today: 0, alerts_today: 0 },
  offsetMs: 0,
});

describe('alertas del monitor', () => {
  const dbAlert = {
    id: 'a1',
    level: 1 as const,
    created_at: min(10),
    acknowledged_by_name: 'Prefecta',
    acknowledged_at: min(11),
  };

  it('muestra la alerta en cuanto se cumple el tiempo, aunque la BD aún no la cree', () => {
    const b = board([
      pass({ id: 'h', started_at: min(0), alert: dbAlert }),
      pass({ id: 'm', started_at: min(1), destination_id: 'bath_m' }),
      pass({ id: 'x', started_at: min(5) }),
    ]);
    const at11 = T0 + 11 * 60_000;
    const alerts = overdueAlerts(b, at11);
    expect(alerts.map((a) => a.id)).toEqual(['h', 'm']);
    // La primera ya está atendida; la segunda sigue sin atender y se puede atender.
    expect(alerts[0]!.alert.acknowledged_by_name).toBe('Prefecta');
    expect(alerts[1]!.alert.acknowledged_by_name).toBeNull();
  });

  it('enfermería no tiene límite de tiempo: ni de ida ni de regreso', () => {
    const b = board([
      pass({ id: 'ida', destination_id: 'nurse', started_at: min(0) }),
      pass({ id: 'vuelta', destination_id: 'nurse', status: 'returning', left_nurse_at: min(8) }),
    ]);
    expect(overdueAlerts(b, T0 + 60 * 60_000)).toHaveLength(0);
    expect(nextAlertAt(b)).toBeNull();
  });

  it('sabe cuándo el siguiente pase cumple el tiempo', () => {
    const b = board([pass({ id: 'a', started_at: min(3) }), pass({ id: 'b', started_at: min(1) })]);
    expect(nextAlertAt(b)).toBe(T0 + 11 * 60_000);
    expect(nextAlertAt(board([pass({ status: 'queued', started_at: null })]))).toBeNull();
  });
});

describe('lista por nivel', () => {
  it('los pases usan el número de la lista del nivel', () => {
    const b = {
      passes: [
        { student_id: 's9', list_number: 17 },
        { student_id: 'otro', list_number: 4 },
      ],
    };
    const out = withListNumbers(b as unknown as Board, [
      { id: 's9', list_number: 2, full_name: 'B', sex: 'M', group_name: '1°B' },
    ]);
    expect(out.passes.map((p) => p.list_number)).toEqual([2, 4]);
  });
});
