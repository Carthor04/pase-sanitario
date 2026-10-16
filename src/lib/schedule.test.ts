import { isNow, nextToday, nowMx, slotsOf } from './schedule';
import { sortDetail, type DetailRow } from './reports';

describe('horarios en hora de México', () => {
  it('nowMx convierte a la zona de México (viernes 16 de oct 2026, 10:05 en León)', () => {
    expect(nowMx(new Date('2026-10-16T16:05:30Z'))).toEqual({ weekday: 5, time: '10:05:30' });
    // Domingo a medianoche.
    expect(nowMx(new Date('2026-10-18T06:00:00Z'))).toEqual({ weekday: 7, time: '00:00:00' });
  });

  const entries = [
    { weekday: 5, starts: '08:00:00', ends: '08:50:00', subject: 'Química' },
    { weekday: 5, starts: '10:00:00', ends: '10:50:00', subject: 'Física' },
    { weekday: 5, starts: '11:00:00', ends: '11:50:00', subject: 'Historia' },
    { weekday: 4, starts: '10:00:00', ends: '10:50:00', subject: 'Arte' },
  ];
  const now = { weekday: 5, time: '10:05:30' };

  it('isNow: solo la clase de hoy a esta hora (el fin no cuenta)', () => {
    expect(entries.filter((e) => isNow(e, now)).map((e) => e.subject)).toEqual(['Física']);
    expect(isNow(entries[1]!, { weekday: 5, time: '10:50:00' })).toBe(false);
  });

  it('nextToday: la siguiente de hoy, o null', () => {
    expect(nextToday(entries, now)?.subject).toBe('Historia');
    expect(nextToday(entries, { weekday: 5, time: '12:00:00' })).toBeNull();
  });

  it('slotsOf: franjas únicas y ordenadas', () => {
    expect(slotsOf(entries)).toEqual([
      '08:00:00|08:50:00',
      '10:00:00|10:50:00',
      '11:00:00|11:50:00',
    ]);
  });
});

describe('detalle de reportes', () => {
  const row = (id: string, minutes: number | null) => ({ id, minutes }) as DetailRow;
  it('ordena de más a menos tiempo fuera; los que siguen fuera al final', () => {
    const rows = [row('a', 3), row('b', null), row('c', 12.5), row('d', 6)];
    expect(sortDetail(rows, true).map((r) => r.id)).toEqual(['c', 'd', 'a', 'b']);
    expect(sortDetail(rows, false)).toBe(rows);
  });
});
