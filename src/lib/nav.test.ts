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

  describe('con las pestañas de Ajustes → Permisos', () => {
    const withTabs = (roles: Parameters<typeof navForRoles>[0], tabs: string[]) =>
      navForRoles(roles, tabs).map((i) => i.label);

    it('maestro al que se le dio Reportes', () => {
      expect(withTabs(['teacher'], ['grupo', 'banos', 'alertas', 'reportes'])).toEqual([
        'Mi grupo',
        'Baños',
        'Alertas',
        'Reportes',
        'Perfil',
      ]);
    });
    it('Ajustes y Perfil siguen saliendo del rol', () => {
      expect(withTabs(['director'], ['reportes'])).toEqual(['Reportes', 'Ajustes']);
      expect(withTabs(['teacher'], [])).toEqual(['Perfil']);
    });
    it('quien ve En vivo no repite Baños ni Alertas', () => {
      expect(withTabs(['teacher'], ['en-vivo', 'grupo', 'banos', 'alertas'])).toEqual([
        'En vivo',
        'Mi grupo',
        'Perfil',
      ]);
    });
    it('ignora pestañas desconocidas', () => {
      expect(withTabs(['teacher'], ['grupo', 'ajustes', 'otra'])).toEqual(['Mi grupo', 'Perfil']);
    });
  });
});
