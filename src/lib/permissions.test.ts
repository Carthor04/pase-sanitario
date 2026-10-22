import { describe, expect, it } from 'vitest';
import { matchesStaff, sameSet, toggle } from './permissions';

describe('toggle', () => {
  it('agrega y quita sin repetir', () => {
    expect(toggle(['grupo'], 'banos')).toEqual(['grupo', 'banos']);
    expect(toggle(['grupo', 'banos'], 'grupo')).toEqual(['banos']);
  });
});

describe('sameSet', () => {
  it('no importa el orden', () => {
    expect(sameSet(['a', 'b'], ['b', 'a'])).toBe(true);
    expect(sameSet(['a'], ['a', 'b'])).toBe(false);
    expect(sameSet([], [])).toBe(true);
  });
});

describe('matchesStaff', () => {
  const p = {
    id: '1',
    full_name: 'Alan Magaña',
    email: 'alan@colegio.mx',
    roles: ['teacher' as const],
    active: true,
  };
  it('por nombre sin acentos o por correo', () => {
    expect(matchesStaff(p, 'magana')).toBe(true);
    expect(matchesStaff(p, 'ALAN@')).toBe(true);
    expect(matchesStaff(p, 'gaby')).toBe(false);
    expect(matchesStaff(p, '  ')).toBe(true);
  });
});
