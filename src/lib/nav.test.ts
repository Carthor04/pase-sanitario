import { navForRoles } from './nav';

const labels = (roles: Parameters<typeof navForRoles>[0]) => navForRoles(roles).map((i) => i.label);

describe('navForRoles', () => {
  it('maestro', () => {
    expect(labels(['teacher'])).toEqual(['Mi grupo', 'Baños', 'Alertas', 'Perfil']);
  });
  it('prefectura', () => {
    expect(labels(['prefect'])).toEqual(['En vivo', 'Mi grupo', 'Historial', 'Perfil']);
  });
  it('enfermería', () => {
    expect(labels(['nurse'])).toEqual(['Enfermería', 'Historial']);
  });
  it('coordinación y dirección', () => {
    expect(labels(['coordinator'])).toEqual([
      'En vivo',
      'Mi grupo',
      'Reportes',
      'Historial',
      'Ajustes',
    ]);
    expect(labels(['director'])).toEqual(['En vivo', 'Reportes', 'Historial', 'Ajustes']);
  });
  it('coordinadora que también da clase: une sin duplicar y sin pasar de 5', () => {
    expect(labels(['coordinator', 'teacher'])).toEqual([
      'En vivo',
      'Mi grupo',
      'Reportes',
      'Historial',
      'Ajustes',
    ]);
  });
  it('psicopedagogía que da clase: En vivo además de su grupo', () => {
    expect(labels(['teacher', 'counselor'])).toEqual(['En vivo', 'Mi grupo', 'Perfil']);
  });
  it('sin roles: sin pestañas', () => {
    expect(navForRoles([])).toEqual([]);
  });
});
