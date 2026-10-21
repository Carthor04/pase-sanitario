import { navForRoles } from './nav';

const labels = (roles: Parameters<typeof navForRoles>[0]) => navForRoles(roles).map((i) => i.label);

describe('navForRoles', () => {
  it('maestro', () => {
    expect(labels(['teacher'])).toEqual(['Mi grupo', 'Baños', 'Alertas', 'Perfil']);
  });
  it('prefectura', () => {
    expect(labels(['prefect'])).toEqual(['En vivo', 'Historial', 'Perfil']);
  });
  it('enfermería', () => {
    expect(labels(['nurse'])).toEqual(['Enfermería', 'Historial']);
  });
  it('coordinación y dirección', () => {
    const expected = ['En vivo', 'Reportes', 'Historial', 'Ajustes'];
    expect(labels(['coordinator'])).toEqual(expected);
    expect(labels(['director'])).toEqual(expected);
  });
  it('coordinadora que también da clase: une sin duplicar y sin pasar de 5', () => {
    expect(labels(['coordinator', 'teacher'])).toEqual([
      'Mi grupo',
      'En vivo',
      'Reportes',
      'Historial',
      'Ajustes',
    ]);
  });
  it('sin roles: sin pestañas', () => {
    expect(navForRoles([])).toEqual([]);
  });
});
