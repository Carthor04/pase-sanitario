import { parseCsvCells, parseImportCsv } from './csv';

describe('parseCsvCells', () => {
  it('respeta comillas, comillas dobles y CRLF', () => {
    const text = 'a,b\r\n"Pérez, Juan","dijo ""hola"""\r\n';
    expect(parseCsvCells(text)).toEqual([
      ['a', 'b'],
      ['Pérez, Juan', 'dijo "hola"'],
    ]);
  });

  it('detecta punto y coma (Excel en español)', () => {
    expect(parseCsvCells('grupo;salon\n2°B;Salón 12')).toEqual([
      ['grupo', 'salon'],
      ['2°B', 'Salón 12'],
    ]);
  });
});

describe('parseImportCsv', () => {
  it('lee la plantilla de alumnos con número de línea', () => {
    const text =
      '\uFEFFgrupo,numero_lista,nombre_completo,sexo\n2°B,1,Ana Torres Ruiz,M\n\n2°B,2,Bruno Cázares,H\n';
    const res = parseImportCsv(text, 'students');
    expect(res).toEqual({
      ok: true,
      rows: [
        { _row: 2, grupo: '2°B', numero_lista: '1', nombre_completo: 'Ana Torres Ruiz', sexo: 'M' },
        { _row: 4, grupo: '2°B', numero_lista: '2', nombre_completo: 'Bruno Cázares', sexo: 'H' },
      ],
    });
  });

  it('acepta encabezados con mayúsculas, acentos y columnas opcionales faltantes', () => {
    const res = parseImportCsv('Nombre completo,Correo,Roles\nLaura,l@x.mx,teacher', 'staff');
    expect(res).toEqual({
      ok: true,
      rows: [
        { _row: 2, nombre_completo: 'Laura', correo: 'l@x.mx', roles: 'teacher', whatsapp: '' },
      ],
    });
  });

  it('explica qué columnas faltan', () => {
    const res = parseImportCsv('grupo,dia,inicio\n2°B,lunes,07:30', 'schedule');
    expect(res).toEqual({
      ok: false,
      error: expect.stringContaining('Faltan columnas: fin, materia'),
    });
  });

  it('rechaza archivos sin filas', () => {
    expect(parseImportCsv('grupo,salon,orden\n', 'groups')).toEqual({
      ok: false,
      error: 'El archivo no tiene filas.',
    });
  });
});
