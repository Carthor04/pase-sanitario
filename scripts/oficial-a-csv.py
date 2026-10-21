"""Convierte los Excel oficiales del Instituto Oviedo (data/oficial/) a las plantillas CSV de
data/templates/ y los valida antes de importar. Escribe en data/oficial/csv/ (ignorada en git:
datos de menores). Luego se importan con scripts/import-csv.mjs.

    python scripts/oficial-a-csv.py

Entradas en data/oficial/:
  - "Listas 2026-27.xlsx": una pestaña por grupo (#, matrícula, nombre con apellidos primero).
  - "alumnos_sexo_para_verificar.xlsx": sexo H/M por alumno, verificado por la escuela.
  - "personal_para_llenar.xlsx": nombre, correo institucional y roles.
  - "Jornada maestr@s  26 -27.xlsx": horario POR DOCENTE (cada celda es el grupo).

Reglas del horario (decisiones del 2026-10-20):
  - En Tecnología y robótica, "2ºAT" es Tecnología y "2ºA" es Robótica.
  - Inglés y Artes vienen por grado ("INGLES 1EROS.", "1eros."): por ahora se cargan en cada
    grupo del grado, SIN docente, hasta tener las listas por nivel.
"""
import collections
import csv
import re
import sys
from pathlib import Path

import openpyxl

sys.stdout.reconfigure(encoding='utf-8')
ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'data' / 'oficial'
OUT = SRC / 'csv'
OUT.mkdir(exist_ok=True)

GROUPS = [f'{g}°{s}' for g in '123' for s in 'ABC']
ROOMS = {'2°C': 'Salón 6'}  # el resto aún no se conoce
PART = {'de', 'del', 'la', 'los', 'las', 'y'}
DAYS = {'lunes': 'lunes', 'martes': 'martes', 'miércoles': 'miércoles', 'miercoles': 'miércoles',
        'jueves': 'jueves', 'viernes': 'viernes'}
errors = []


def title(name):
    words = ' '.join(str(name).split()).rstrip('.').split(' ')
    return ' '.join(w.lower() if k and w.lower() in PART else w[:1].upper() + w[1:].lower()
                    for k, w in enumerate(words))


def write(name, header, rows):
    with open(OUT / name, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


# ---------------------------------------------------------------- grupos
write('grupos.csv', ['grupo', 'salon', 'orden'], [[g, ROOMS.get(g, ''), i + 1] for i, g in enumerate(GROUPS)])

# ---------------------------------------------------------------- alumnos
sexo = {}
for ws in openpyxl.load_workbook(SRC / 'alumnos_sexo_para_verificar.xlsx', data_only=True).worksheets:
    for r in ws.iter_rows(min_row=2, values_only=True):
        if r[0] is not None:
            sexo[(ws.title, int(r[0]))] = str(r[2] or '').strip().upper()
students = []
for ws in openpyxl.load_workbook(SRC / 'Listas 2026-27.xlsx', data_only=True).worksheets:
    g = ws.title.replace('º', '°').strip()
    seen = set()
    for r in ws.iter_rows(values_only=True):
        if isinstance(r[0], (int, float)) and r[2]:
            n = int(r[0])
            if n in seen:
                errors.append(('alumnos', g, f'número {n} repetido'))
            seen.add(n)
            s = sexo.get((g, n), '')
            if s not in ('H', 'M'):
                errors.append(('alumnos', g, f'#{n} sin sexo H/M'))
            students.append([g, n, title(r[2]), s])
write('alumnos.csv', ['grupo', 'numero_lista', 'nombre_completo', 'sexo'], students)

# ---------------------------------------------------------------- personal
staff = []
emails = set()
for r in openpyxl.load_workbook(SRC / 'personal_para_llenar.xlsx', data_only=True)['personal'].iter_rows(
        min_row=2, values_only=True):
    name, email, roles = (r + (None,) * 3)[:3]
    email = (email or '').strip().lower()
    if not email:
        if name:
            errors.append(('personal', name, 'sin correo: no podrá entrar ni se le asigna horario'))
        continue
    if not name:
        errors.append(('personal', email, 'sin nombre ni roles: no se importa'))
        continue
    if not re.fullmatch(r'[^@\s]+@institutooviedo\.edu\.mx', email):
        errors.append(('personal', email, 'el correo no es @institutooviedo.edu.mx'))
    if email in emails:
        errors.append(('personal', email, 'correo repetido'))
    emails.add(email)
    staff.append([title(name), email, (roles or 'teacher').strip(), ''])
write('personal.csv', ['nombre_completo', 'correo', 'roles', 'whatsapp'], staff)

# ---------------------------------------------------------------- horario
# Pestaña del horario → (correo del docente, materia según la celda)
TEACHER = {
    'Matemáticas I y II': 'hectorfernandezh@institutooviedo.edu.mx',
    'Ignacio Franco': 'ignacio.franco@institutooviedo.edu.mx',
    'Cívica y ética': 'mariselasancheze@institutooviedo.edu.mx',
    'Español II,III': 'amalinallitecuapetlae@institutooviedo.edu.mx',
    'Español I, II': 'eduardorizos@institutooviedo.edu.mx',
    'Biología': 'edgarchavezb@institutooviedo.edu.mx',
    'Geografía y Quimica': 'andreacordobac@institutooviedo.edu.mx',
    'Ed. física': 'carlos.diaz@institutooviedo.edu.mx',
    'historia': '',  # falta el correo
    'OYT': 'andreanoez@institutooviedo.edu.mx',
    'Tecnología y robótica': 'saelcarrillot@institutooviedo.edu.mx',
    'Emprendimiento 2º': 'mariagutierrezr@institutooviedo.edu.mx',
    'Emprendimiento 1º y 3º': 'jorge.esqueda@institutooviedo.edu.mx',
    'Artes': '',
    'Inglés.': '', 'Inglés ': '', 'Inglés': '',
}


def subject(sheet, group, tech):
    sheet = sheet.strip()
    if sheet.startswith('Matemáticas') or sheet == 'Ignacio Franco':
        return 'Matemáticas'
    if sheet.startswith('Español'):
        return 'Español'
    if sheet.startswith('Geografía'):
        return 'Geografía' if group.startswith('1') else 'Química'
    if sheet.startswith('Tecnología'):
        return 'Tecnología' if tech else 'Robótica'
    if sheet.startswith('Emprendimiento'):
        return 'Emprendimiento'
    if sheet.startswith('Inglés'):
        return 'Inglés'
    return {'Cívica y ética': 'Cívica y Ética', 'Biología': 'Biología', 'Ed. física': 'Educación Física',
            'historia': 'Historia', 'OYT': 'Orientación y Tutoría', 'Artes': 'Artes'}[sheet]


def hhmm(s):
    return [f'{int(h):02d}:{m}' for h, m in re.findall(r'(\d{1,2})\s*:\s*(\d{2})', s or '')]


schedule = []
for ws in openpyxl.load_workbook(SRC / 'Jornada maestr@s  26 -27.xlsx').worksheets:
    if ws.title.strip() not in {k.strip() for k in TEACHER} and ws.title not in TEACHER:
        continue  # Baños (rol de guardias) y pestañas vacías
    key = ws.title if ws.title in TEACHER else ws.title.strip()
    email = TEACHER[key]
    if email and email not in emails:
        errors.append(('horario', ws.title, f'{email} no está en personal'))
    # Celdas combinadas (Inglés va de lunes a viernes en una sola celda).
    value = {}
    for m in ws.merged_cells.ranges:
        v = ws.cell(row=m.min_row, column=m.min_col).value
        for r in range(m.min_row, m.max_row + 1):
            for c in range(m.min_col, m.max_col + 1):
                value[(r, c)] = v
    cell = lambda r, c: value.get((r, c), ws.cell(row=r, column=c).value)
    hdr = next(c for row in ws.iter_rows() for c in row if str(c.value or '').strip().lower() == 'hora')
    daycol = {c.column: DAYS[str(c.value).strip().lower()] for c in ws[hdr.row]
              if str(c.value or '').strip().lower() in DAYS}
    for r in range(hdr.row + 1, ws.max_row + 1):
        t = hhmm(str(ws.cell(row=r, column=1).value or ''))
        if len(t) != 2:
            continue
        for col, day in daycol.items():
            raw = re.sub(r'\s+', '', str(cell(r, col) or ''))
            if not raw or re.fullmatch(r'R(E(CREO)?|ECREO)?|RE', raw) or raw.startswith('RE'):
                continue
            m = re.fullmatch(r'([123])[º°o]([ABC])(T?)', raw)
            grade = re.search(r'([123])', raw)
            if m:
                targets, tech = [f'{m.group(1)}°{m.group(2)}'], bool(m.group(3))
            elif grade and re.search(r'(INGLES)?\d(EROS|ROS|DOS)\.?$', raw.upper()):
                targets, tech = [f'{grade.group(1)}°{s}' for s in 'ABC'], False
            else:
                errors.append(('horario', ws.title, f'celda no reconocida: {raw!r}'))
                continue
            for g in targets:
                schedule.append((g, day, t[0], t[1], subject(key, g, tech), email))

# Inglés: los 3 docentes dan la misma hora al mismo grado → una sola fila por grupo.
schedule = sorted(set(schedule))
slot = collections.defaultdict(list)
for e in schedule:
    slot[(e[0], e[1], e[2])].append(e)
for k, v in slot.items():
    if len(v) > 1:
        errors.append(('horario', f'{k[0]} {k[1]} {k[2]}', 'empalme: ' + ' / '.join(f'{x[4]} {x[5]}' for x in v)))
order = {d: i for i, d in enumerate(['lunes', 'martes', 'miércoles', 'jueves', 'viernes'])}
schedule.sort(key=lambda e: (GROUPS.index(e[0]), order[e[1]], e[2]))
write('horario.csv', ['grupo', 'dia', 'inicio', 'fin', 'materia', 'correo_maestro'], schedule)

# ---------------------------------------------------------------- resumen
per = collections.Counter(s[0] for s in students)
hrs = collections.Counter(e[0] for e in schedule)
sin = collections.Counter(e[0] for e in schedule if not e[5])
print('Grupo  alumnos  H   M   clases  sin docente')
for g in GROUPS:
    h = sum(1 for s in students if s[0] == g and s[3] == 'H')
    print(f'{g:5}  {per[g]:7}  {h:2}  {per[g] - h:2}  {hrs[g]:6}  {sin[g]:4}')
print(f'Total: {len(students)} alumnos, {len(staff)} personal, {len(schedule)} clases')
print('\nAvisos:' if errors else '\nSin avisos.')
for e in errors:
    print('  ', ' · '.join(map(str, e)))
