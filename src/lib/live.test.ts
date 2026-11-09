import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  canPauseBathroom,
  canRemoveFromQueue,
  debounce,
  isWaiting,
  MINUTE_MARGIN_MS,
  msToNextMinute,
  nextTurnDeadline,
} from './live';

describe('isWaiting', () => {
  it('solo los pases que todavía no salen', () => {
    expect(isWaiting('group_wait')).toBe(true);
    expect(isWaiting('queued')).toBe(true);
    expect(isWaiting('called')).toBe(true);
    expect(isWaiting('out')).toBe(false);
    expect(isWaiting('arrived')).toBe(false);
    expect(isWaiting('returning')).toBe(false);
  });
});

describe('canRemoveFromQueue', () => {
  it('maestros, prefectura, coordinación y admin', () => {
    expect(canRemoveFromQueue(['teacher'])).toBe(true);
    expect(canRemoveFromQueue(['prefect'])).toBe(true);
    expect(canRemoveFromQueue(['coordinator'])).toBe(true);
    expect(canRemoveFromQueue(['admin'])).toBe(true);
  });

  it('no dirección, psicopedagogía ni enfermería sin otro rol', () => {
    expect(canRemoveFromQueue(['director'])).toBe(false);
    expect(canRemoveFromQueue(['counselor'])).toBe(false);
    expect(canRemoveFromQueue(['nurse'])).toBe(false);
    expect(canRemoveFromQueue(['counselor', 'teacher'])).toBe(true);
  });
});

describe('canPauseBathroom', () => {
  it('maestros, prefectura, coordinación, dirección y admin', () => {
    expect(canPauseBathroom(['teacher'])).toBe(true);
    expect(canPauseBathroom(['director'])).toBe(true);
    expect(canPauseBathroom(['nurse'])).toBe(false);
    expect(canPauseBathroom(['counselor'])).toBe(false);
  });
});

describe('debounce', () => {
  afterEach(() => vi.useRealTimers());

  it('junta una ráfaga de eventos en una sola llamada', () => {
    vi.useFakeTimers();
    const fn = vi.fn();
    const call = debounce(fn, 500);
    call();
    call();
    vi.advanceTimersByTime(300);
    call();
    expect(fn).not.toHaveBeenCalled();
    vi.advanceTimersByTime(500);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('eventos separados por más de la ventana refrescan cada uno', () => {
    vi.useFakeTimers();
    const fn = vi.fn();
    const call = debounce(fn, 500);
    call();
    vi.advanceTimersByTime(600);
    call();
    vi.advanceTimersByTime(600);
    expect(fn).toHaveBeenCalledTimes(2);
  });

  it('cancel descarta la llamada pendiente', () => {
    vi.useFakeTimers();
    const fn = vi.fn();
    const call = debounce(fn, 500);
    call();
    call.cancel();
    vi.advanceTimersByTime(1000);
    expect(fn).not.toHaveBeenCalled();
  });
});

describe('msToNextMinute', () => {
  it('espera hasta poco después del siguiente minuto exacto', () => {
    const at = new Date('2026-11-09T14:59:45Z').getTime();
    expect(msToNextMinute(at)).toBe(15_000 + MINUTE_MARGIN_MS);
    expect(msToNextMinute(new Date('2026-11-09T15:00:00Z').getTime())).toBe(
      60_000 + MINUTE_MARGIN_MS,
    );
  });
});

describe('nextTurnDeadline', () => {
  const settings = { confirm_turn_minutes: 2 } as Parameters<
    typeof nextTurnDeadline
  >[0]['settings'];
  it('el turno que vence primero', () => {
    const passes = [
      { status: 'called', called_at: '2026-11-09T15:01:00Z' },
      { status: 'called', called_at: '2026-11-09T15:00:00Z' },
      { status: 'queued', called_at: null },
    ] as Parameters<typeof nextTurnDeadline>[0]['passes'];
    expect(nextTurnDeadline({ passes, settings })).toBe(new Date('2026-11-09T15:02:00Z').getTime());
  });
  it('sin turnos no hay nada que revisar', () => {
    expect(nextTurnDeadline({ passes: [], settings })).toBeNull();
  });
});
