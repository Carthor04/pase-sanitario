import { closureText, heatmapMatrix, rangeFor, rangeTitle, todayMx, type Report } from './reports';

describe('fechas de reportes', () => {
  it('usa la fecha de México, no la UTC', () => {
    // 15 oct 2026 a las 23:30 en México = 16 oct 05:30 UTC.
    expect(todayMx(new Date('2026-10-16T05:30:00Z'))).toBe('2026-10-15');
  });

  it('calcula semanas de lunes a viernes', () => {
    expect(rangeFor('week', '2026-10-15')).toEqual({ from: '2026-10-12', to: '2026-10-16' });
    expect(rangeFor('last_week', '2026-10-15')).toEqual({ from: '2026-10-05', to: '2026-10-09' });
    expect(rangeFor('week', '2026-10-18')).toEqual({ from: '2026-10-12', to: '2026-10-16' }); // domingo
    expect(rangeFor('month', '2026-10-15')).toEqual({ from: '2026-10-01', to: '2026-10-15' });
    expect(rangeFor('last_30', '2026-10-15')).toEqual({ from: '2026-09-16', to: '2026-10-15' });
  });

  it('titula el periodo en español', () => {
    expect(rangeTitle('2026-10-12', '2026-10-16')).toBe('del 12 al 16 de octubre');
    expect(rangeTitle('2026-09-28', '2026-10-02')).toBe('del 28 de septiembre al 2 de octubre');
    expect(rangeTitle('2026-10-15', '2026-10-15')).toBe('15 de octubre');
  });
});

describe('heatmapMatrix', () => {
  const report = {
    heatmap: [
      { destination: 'bath_h', weekday: 1, hour: 10, count: 11 },
      { destination: 'bath_h', weekday: 2, hour: 15, count: 1 },
      { destination: 'bath_m', weekday: 1, hour: 10, count: 4 },
    ],
    queued_slots: [{ destination: 'bath_h', weekday: 1, hour: 10 }],
  } as unknown as Report;

  it('arma lunes–viernes × horas, agrega horas fuera de 7–13 y marca las que tuvieron fila', () => {
    const m = heatmapMatrix(report, 'bath_h');
    expect(m.hours).toEqual([7, 8, 9, 10, 11, 12, 13, 15]);
    expect(m.rows).toHaveLength(5);
    expect(m.rows[0]![3]).toEqual({ weekday: 1, hour: 10, count: 11, queued: true });
    expect(m.rows[1]![7]!.count).toBe(1);
    expect(m.max).toBe(11);
  });
});

describe('closureText', () => {
  it('explica cómo terminó el pase', () => {
    expect(
      closureText({ status: 'returned', closed_by: null, release_reason: null, alert: null }),
    ).toBe('Regresó');
    expect(
      closureText({
        status: 'released',
        closed_by: 'Juan',
        release_reason: 'Se fue a casa',
        alert: null,
      }),
    ).toBe('Liberado: Se fue a casa');
    expect(
      closureText({
        status: 'released',
        closed_by: null,
        release_reason: 'Cierre automático',
        alert: null,
      }),
    ).toBe('Cierre automático: no se marcó el regreso');
    expect(
      closureText({
        status: 'returned',
        closed_by: null,
        release_reason: null,
        alert: { level: 1, acknowledged_by: 'Juan Pérez' },
      }),
    ).toBe('Regresó con alerta · atendió Juan Pérez');
  });
});
