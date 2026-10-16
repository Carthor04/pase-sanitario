import {
  bathroomHint,
  formatCountdown,
  formatElapsed,
  passTag,
  requestMessage,
  slotPass,
  type Board,
  type BoardPass,
  type StudentRef,
} from './board';

const settings = {
  alert_minutes: 10,
  confirm_turn_minutes: 2,
  undo_seconds: 10,
  auto_lock_after_class_minutes: 5,
};
const T0 = new Date('2026-10-16T16:00:00Z').getTime();
const iso = (offsetMs: number) => new Date(T0 + offsetMs).toISOString();

function pass(over: Partial<BoardPass>): BoardPass {
  return {
    id: 'p',
    student_id: 's14',
    list_number: 14,
    full_name: 'Luis Martínez',
    sex: 'H',
    status: 'out',
    destination_id: 'bath_h',
    destination_kind: 'bathroom',
    destination_label: 'Baño hombres',
    requested_at: iso(0),
    queue_ts: null,
    called_at: null,
    started_at: iso(0),
    arrived_at: null,
    period_subject: 'Matemáticas',
    opened_by_name: 'Laura',
    queue_position: null,
    waiting_for: null,
    ...over,
  };
}

const board = (passes: BoardPass[], over: Partial<Board> = {}): Board => ({
  now: iso(0),
  settings,
  passes,
  bathrooms: [
    { id: 'bath_h', label: 'Baño hombres', sex: 'H', capacity: 1, occupants: [], queue: [] },
    { id: 'bath_m', label: 'Baño mujeres', sex: 'M', capacity: 3, occupants: [], queue: [] },
  ],
  ...over,
});

const jorge: StudentRef = { id: 's22', list_number: 22, full_name: 'Jorge Valdez', sex: 'H' };
const ana: StudentRef = { id: 's1', list_number: 1, full_name: 'Ana Torres', sex: 'M' };

describe('cronómetros', () => {
  it('formatea tiempo fuera y cuenta regresiva', () => {
    expect(formatElapsed(372_000)).toBe('06:12');
    expect(formatElapsed(3_909_000)).toBe('1:05:09');
    expect(formatElapsed(-5)).toBe('00:00');
    expect(formatCountdown(102_000)).toBe('1:42');
    expect(formatCountdown(4_100)).toBe('0:05');
    expect(formatCountdown(-1)).toBe('0:00');
  });
});

describe('passTag', () => {
  it('fuera, alerta a los 10 min, turno y espera, siempre con texto', () => {
    expect(passTag(pass({}), T0 + 372_000, settings)).toEqual({
      label: 'Fuera · 06:12',
      tone: 'out',
    });
    expect(passTag(pass({}), T0 + 760_000, settings)).toEqual({
      label: 'Alerta · 12:40',
      tone: 'alert',
    });
    expect(passTag(pass({ status: 'called', called_at: iso(0) }), T0 + 18_000, settings)).toEqual({
      label: 'Su turno · 1:42',
      tone: 'wait',
    });
    expect(
      passTag(
        pass({ status: 'group_wait', waiting_for: { list_number: 14, full_name: 'Luis' } }),
        T0,
        settings,
      ).label,
    ).toBe('Espera · sale al regresar #14');
  });

  it('en enfermería ya no hay alerta (solo cuenta el trayecto)', () => {
    const nurse = pass({ destination_kind: 'nurse', destination_id: 'nurse', status: 'arrived' });
    expect(passTag(nurse, T0 + 3_600_000, settings)).toEqual({
      label: 'En enfermería',
      tone: 'nurse',
    });
    expect(passTag({ ...nurse, status: 'out' }, T0 + 700_000, settings).tone).toBe('alert');
  });
});

describe('bathroomHint', () => {
  it('avisa que queda en espera si el lugar del grupo está ocupado', () => {
    const b = board([pass({})]);
    expect(bathroomHint(jorge, b)).toEqual({
      text: 'Queda en espera: Luis Martínez (#14) sigue fuera. Sale en cuanto regrese.',
      tone: 'wait',
    });
    expect(slotPass(b.passes, 'M')).toBeUndefined();
  });

  it('entra directo si hay lugar y no hay fila', () => {
    const b = board([], {
      bathrooms: [
        {
          id: 'bath_m',
          label: 'Baño mujeres',
          sex: 'M',
          capacity: 3,
          occupants: [
            { group_name: '1°A', own: false, status: 'out', since: iso(0) },
            { group_name: '2°C', own: false, status: 'out', since: iso(0) },
          ],
          queue: [],
        },
      ],
    });
    expect(bathroomHint(ana, b)).toEqual({
      text: 'Baño mujeres · entra directo (2 de 3 ocupados)',
      tone: 'free',
    });
  });

  it('queda en fila si el baño está lleno o hay fila', () => {
    const b = board([], {
      bathrooms: [
        {
          id: 'bath_h',
          label: 'Baño hombres',
          sex: 'H',
          capacity: 1,
          occupants: [{ group_name: '3°A', own: false, status: 'out', since: iso(0) }],
          queue: [{ group_name: '1°C', own: false }],
        },
      ],
    });
    expect(bathroomHint(jorge, b)).toEqual({
      text: 'Baño hombres lleno · queda en fila (1 antes)',
      tone: 'wait',
    });
  });

  it('bloquea si el alumno ya tiene pase', () => {
    expect(bathroomHint(jorge, board([pass({ student_id: 's22' })])).tone).toBe('blocked');
  });
});

describe('requestMessage', () => {
  it('explica el resultado que dio la BD', () => {
    expect(requestMessage(jorge, 'group_wait', '2°B')).toBe(
      'Ya hay un niño de 2°B fuera; Jorge Valdez quedó en espera',
    );
    expect(requestMessage(ana, 'queued', '2°B', { queuePosition: 2 })).toBe(
      'Ana Torres quedó en fila (lugar 2)',
    );
    expect(requestMessage(ana, 'out', '2°B', { label: 'Baño mujeres' })).toBe(
      'Ana Torres salió al baño mujeres',
    );
    expect(requestMessage(ana, 'out', '2°B', { label: 'Enfermería' })).toBe(
      'Ana Torres va a enfermería',
    );
  });
});

describe('todayLabel', () => {
  it('resume las salidas del día', async () => {
    const { todayLabel } = await import('./live');
    expect(todayLabel(undefined)).toBeNull();
    expect(todayLabel({ bathroom: 0, nurse: 0 })).toBeNull();
    expect(todayLabel({ bathroom: 2, nurse: 0 })).toBe('2 baño');
    expect(todayLabel({ bathroom: 3, nurse: 1 })).toBe('3 baño · 1 enfermería');
  });
});
