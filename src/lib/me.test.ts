import { canManage, parseMe } from './me';
import { readAuthError } from './session';

describe('parseMe', () => {
  it('reconoce personal y descarta roles desconocidos', () => {
    expect(
      parseMe({
        kind: 'staff',
        id: 'a',
        full_name: 'Laura',
        email: 'l@x.mx',
        roles: ['teacher', 'hacker', 'admin'],
        has_pin: true,
      }),
    ).toEqual({
      kind: 'staff',
      id: 'a',
      full_name: 'Laura',
      email: 'l@x.mx',
      roles: ['teacher', 'admin'],
      has_pin: true,
    });
  });

  it('trae las pestañas de Ajustes → Permisos', () => {
    const me = parseMe({
      kind: 'staff',
      id: 'a',
      full_name: 'Laura',
      email: 'l@x.mx',
      roles: ['teacher'],
      tabs: ['grupo', 7, 'reportes'],
      has_pin: false,
    });
    expect(me.kind === 'staff' && me.tabs).toEqual(['grupo', 'reportes']);
  });

  it('reconoce un equipo de salón', () => {
    expect(
      parseMe({ kind: 'device', id: 'd', label: null, group_id: 'g', group_name: '2°B' }),
    ).toEqual({ kind: 'device', id: 'd', label: null, group_id: 'g', group_name: '2°B' });
  });

  it('cualquier otra cosa es "sin acceso"', () => {
    expect(parseMe(null)).toEqual({ kind: 'none', email: null, anonymous: false });
    expect(parseMe({ kind: 'none', email: 'x@gmail.com', anonymous: false })).toEqual({
      kind: 'none',
      email: 'x@gmail.com',
      anonymous: false,
    });
  });
});

describe('canManage', () => {
  it('solo coordinación, dirección y admin', () => {
    expect(canManage(['teacher', 'prefect', 'nurse'])).toBe(false);
    expect(canManage(['teacher', 'coordinator'])).toBe(true);
    expect(canManage(['director'])).toBe(true);
  });
});

describe('readAuthError', () => {
  it('lee el error que deja Supabase al volver de Google (query o hash)', () => {
    expect(
      readAuthError({
        search: '?error=server_error&error_description=Database+error+saving+new+user',
        hash: '',
      }),
    ).toBe('Database error saving new user');
    expect(readAuthError({ search: '', hash: '#error=access_denied' })).toBe('access_denied');
    expect(readAuthError({ search: '?code=abc', hash: '' })).toBeNull();
  });
});
