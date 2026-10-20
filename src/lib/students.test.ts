import { byName } from './students';

const s = (list_number: number, full_name: string) => ({ list_number, full_name });

describe('byName', () => {
  it('ordena por apellidos sin importar el número de lista, acentos ni mayúsculas', () => {
    const list = [
      s(1, 'Ñuñez Ruiz Ana'),
      s(2, 'Álvarez Soto Luis'),
      s(3, 'nava Gómez Eva'),
      s(4, 'Aguirre Pérez Uriel'),
      s(5, 'Olvera Morales José'),
    ].sort(byName);
    expect(list.map((x) => x.list_number)).toEqual([4, 2, 3, 1, 5]);
  });

  it('con el mismo nombre desempata por número de lista', () => {
    expect([s(9, 'Ruiz Ana'), s(2, 'Ruiz Ana')].sort(byName).map((x) => x.list_number)).toEqual([
      2, 9,
    ]);
  });
});
