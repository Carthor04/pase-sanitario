// Solo en desarrollo (npm run dev): muestra el tablero con datos ficticios para revisar el
// diseño sin sesión. Las acciones fallan porque no hay usuario; es solo para ver.
import { useMemo, useState } from 'react';
import { BathroomsLive } from '@/components/pass/BathroomsLive';
import { GroupLive } from '@/components/pass/GroupLive';
import { InstallApp } from '@/components/InstallApp';
import { DeviceMenu } from '@/components/pass/DeviceMenu';
import type { BathroomsStatus } from '@/lib/live';
import { PinPad } from '@/components/pass/PinPad';
import { LiveBoard } from '@/pages/LiveBoard';
import { ReportBody } from '@/pages/Reports';
import type { Report } from '@/lib/reports';
import type { LiveBoard as LiveData, LivePass } from '@/lib/monitor';
import { StaffContext } from '@/lib/session';
import type { Board, BoardPass, StudentRef } from '@/lib/board';

const NAMES = [
  'Ana Torres',
  'Bruno Cázares',
  'Carla Domínguez',
  'Diego Esparza',
  'Elena Fuentes',
  'Fernando García',
  'Pedro Gómez',
  'Gabriela Hernández',
  'Hugo Ibarra',
  'Isabel Juárez',
  'Javier López',
  'Karla Medina',
  'Lucía Navarro',
  'Luis Martínez',
  'María Ochoa',
  'Mateo Pérez',
  'Natalia Quiroz',
  'Óscar Ramos',
  'Paola Salinas',
  'Ricardo Tapia',
  'Renata Uribe',
  'Jorge Valdez',
  'Sofía Villalobos',
  'Santiago Zamora',
];

export function UiPreview() {
  type View = 'turno' | 'libre' | 'pin' | 'prefectura' | 'reportes' | 'baños' | 'instalar';
  // ?vista=libre abre esa vista directo (para tomar capturas de las guías).
  const [view, setView] = useState<View>(
    () => (new URLSearchParams(window.location.search).get('vista') as View | null) ?? 'turno',
  );
  const students: StudentRef[] = NAMES.map((full_name, i) => ({
    id: `s${i + 1}`,
    list_number: i + 1,
    full_name,
    sex: i % 2 === 0 ? 'M' : 'H',
  }));

  const board = useMemo(() => {
    const now = Date.now();
    const iso = (minAgo: number) => new Date(now - minAgo * 60_000).toISOString();
    const base = (n: number): BoardPass => ({
      id: `p${n}`,
      student_id: `s${n}`,
      list_number: n,
      full_name: NAMES[n - 1]!,
      sex: n % 2 === 0 ? 'H' : 'M',
      status: 'out',
      destination_id: n % 2 === 0 ? 'bath_h' : 'bath_m',
      destination_kind: 'bathroom',
      destination_label: n % 2 === 0 ? 'Baño hombres' : 'Baño mujeres',
      requested_at: iso(13),
      queue_ts: null,
      called_at: null,
      started_at: iso(12.7),
      arrived_at: null,
      period_subject: 'Matemáticas',
      opened_by_name: 'Laura Ramírez',
      queue_position: null,
      waiting_for: null,
    });
    const passes: BoardPass[] =
      view === 'turno'
        ? [
            {
              ...base(7),
              sex: 'H',
              destination_id: 'bath_h',
              destination_label: 'Baño hombres',
              status: 'called',
              started_at: null,
              called_at: iso(0.3),
            },
            { ...base(17), sex: 'M', destination_id: 'bath_m', destination_label: 'Baño mujeres' },
            {
              ...base(16),
              destination_id: 'nurse',
              destination_kind: 'nurse',
              destination_label: 'Enfermería',
              status: 'arrived',
              started_at: iso(8),
              arrived_at: iso(5),
            },
            {
              ...base(22),
              sex: 'H',
              status: 'group_wait',
              started_at: null,
              waiting_for: { list_number: 7, full_name: NAMES[6]! },
            },
          ]
        : view === 'libre'
          ? [
              {
                ...base(14),
                sex: 'H',
                destination_id: 'bath_h',
                destination_label: 'Baño hombres',
                started_at: iso(6.2),
              },
            ]
          : [];
    const b: Board & { offsetMs: number } = {
      now: new Date(now).toISOString(),
      offsetMs: 0,
      settings: {
        alert_minutes: 10,
        confirm_turn_minutes: 2,
        undo_seconds: 10,
        auto_lock_after_class_minutes: 5,
      },
      passes,
      bathrooms: [
        {
          id: 'bath_h',
          label: 'Baño hombres',
          sex: 'H',
          capacity: 1,
          occupants: [
            {
              group_name: view === 'turno' ? '2°B' : '2°B',
              own: true,
              status: view === 'turno' ? 'called' : 'out',
              since: iso(6.2),
            },
          ],
          queue: [
            { group_name: '3°A', own: false },
            { group_name: '1°C', own: false },
          ],
        },
        {
          id: 'bath_m',
          label: 'Baño mujeres',
          sex: 'M',
          capacity: 3,
          occupants: [
            { group_name: '1°A', own: false, status: 'out', since: iso(4) },
            { group_name: '2°C', own: false, status: 'out', since: iso(2) },
          ],
          queue: [],
        },
      ],
    };
    return b;
  }, [view]);

  return (
    <div className="min-h-screen bg-ground">
      <div
        className={`flex flex-wrap gap-2 border-b border-line bg-surface p-3 ${
          new URLSearchParams(window.location.search).has('limpio') ? 'hidden' : ''
        }`}
      >
        <strong className="mr-2 self-center">Vista de prueba (datos ficticios)</strong>
        {(['turno', 'libre', 'pin', 'prefectura', 'reportes', 'baños', 'instalar'] as const).map(
          (v) => (
            <button
              key={v}
              type="button"
              onClick={() => setView(v)}
              className={`min-h-touch rounded-btn border px-3 font-bold ${view === v ? 'border-accent text-accent' : 'border-line'}`}
            >
              {v}
            </button>
          ),
        )}
      </div>
      <main className="mx-auto max-w-container px-4 py-5 sm:px-6">
        {view === 'instalar' ? (
          <div className="flex max-w-[480px] flex-col gap-3">
            <InstallApp />
            <div className="flex items-center gap-2">
              Menú del equipo: <DeviceMenu />
            </div>
          </div>
        ) : view === 'baños' ? (
          <div className="grid gap-6 lg:grid-cols-2">
            <div className="flex flex-col gap-3 lg:col-span-2">
              <h2 className="m-0 font-display text-[22px] font-bold">Personal (pantalla Baños)</h2>
              <BathroomsLive preview={bathroomsPreview(true)} canPause />
            </div>
            <div className="flex flex-col gap-3">
              <h2 className="m-0 font-display text-[22px] font-bold">Panel (salón desbloqueado)</h2>
              <BathroomsLive variant="panel" ownGroup="2°B" preview={bathroomsPreview()} />
            </div>
            <div className="flex flex-col gap-3 rounded-card bg-dark p-5">
              <h2 className="m-0 font-display text-[22px] font-bold text-white">Bloqueada</h2>
              <BathroomsLive variant="dark" ownGroup="2°B" preview={bathroomsPreview()} />
            </div>
          </div>
        ) : view === 'reportes' ? (
          <ReportBody report={reportPreview()} from="2026-10-12" to="2026-10-16" />
        ) : view === 'prefectura' ? (
          <StaffContext.Provider
            value={{
              kind: 'staff',
              id: 'x',
              full_name: 'Juan Pérez',
              email: 'x@x',
              roles: ['prefect'],
              has_pin: true,
            }}
          >
            <LiveBoard preview={livePreview()} />
          </StaffContext.Provider>
        ) : view === 'pin' ? (
          <div className="mx-auto max-w-[460px] rounded-[22px] bg-surface p-8">
            <PinPad
              onSubmit={async (pin) =>
                pin === '1234' ? null : 'PIN incorrecto · quedan 4 intentos'
              }
            />
          </div>
        ) : (
          <GroupLive
            board={board}
            groupName="2°B"
            students={students}
            capture
            todayPreview={{
              flag: 3,
              counts: {
                s14: { bathroom: 4, nurse: 0 },
                s3: { bathroom: 1, nurse: 1 },
                s7: { bathroom: 3, nurse: 0 },
              },
            }}
            footnote="Queda registrado a nombre de Laura Ramírez."
          />
        )}
      </main>
    </div>
  );
}

function livePreview(): LiveData {
  const now = Date.now();
  const iso = (minAgo: number) => new Date(now - minAgo * 60_000).toISOString();
  const p = (
    o: Partial<LivePass> &
      Pick<LivePass, 'id' | 'full_name' | 'group_name' | 'destination_id' | 'status'>,
  ): LivePass => ({
    student_id: o.id,
    list_number: 7,
    sex: 'H',
    group_id: 'g',
    requested_at: iso(15),
    queue_ts: null,
    called_at: null,
    started_at: null,
    arrived_at: null,
    left_nurse_at: null,
    period_subject: 'Matemáticas',
    opened_by_name: 'Laura Ramírez',
    current_teacher_name: 'Prof. Núñez',
    alert: null,
    ...o,
  });
  return {
    now: new Date(now).toISOString(),
    offsetMs: 0,
    settings: { alert_minutes: 10, escalate_minutes: 5, confirm_turn_minutes: 2 },
    destinations: [
      { id: 'bath_h', label: 'Baño hombres', kind: 'bathroom', sex: 'H', capacity: 1 },
      { id: 'bath_m', label: 'Baño mujeres', kind: 'bathroom', sex: 'M', capacity: 3 },
      { id: 'nurse', label: 'Enfermería', kind: 'nurse', sex: null, capacity: null },
    ],
    passes: [
      p({
        id: 'a',
        full_name: 'Pedro Gómez',
        group_name: '2°B',
        destination_id: 'bath_h',
        status: 'out',
        started_at: iso(0.7),
      }),
      p({
        id: 'b',
        full_name: 'Raúl Herrera',
        group_name: '3°A',
        destination_id: 'bath_h',
        status: 'queued',
        queue_ts: iso(6.2),
      }),
      p({
        id: 'c',
        full_name: 'Emiliano Cruz',
        group_name: '1°C',
        destination_id: 'bath_h',
        status: 'queued',
        queue_ts: iso(2.1),
        current_teacher_name: 'Prof. Lara',
      }),
      p({
        id: 'd',
        full_name: 'Natalia Quiroz',
        group_name: '2°B',
        destination_id: 'bath_m',
        status: 'out',
        started_at: iso(12.7),
        alert: {
          id: 'al',
          level: 1,
          created_at: iso(2.7),
          acknowledged_by_name: null,
          acknowledged_at: null,
        },
      }),
      p({
        id: 'e',
        full_name: 'Sofía Ramírez',
        group_name: '1°A',
        destination_id: 'bath_m',
        status: 'out',
        started_at: iso(3.2),
      }),
      p({
        id: 'f',
        full_name: 'Paola Núñez',
        group_name: '2°C',
        destination_id: 'bath_m',
        status: 'out',
        started_at: iso(1.4),
      }),
      p({
        id: 'g',
        full_name: 'Daniela Ortiz',
        group_name: '3°B',
        destination_id: 'bath_m',
        status: 'queued',
        queue_ts: iso(0.7),
      }),
      p({
        id: 'h',
        full_name: 'Mateo Pérez',
        group_name: '2°B',
        destination_id: 'nurse',
        status: 'arrived',
        started_at: iso(8),
        arrived_at: iso(6),
      }),
      p({
        id: 'i',
        full_name: 'Iván Ruiz',
        group_name: '3°C',
        destination_id: 'nurse',
        status: 'out',
        started_at: iso(1.5),
      }),
    ],
    stats: { exits_today: 52, alerts_today: 2 },
  };
}

function reportPreview(): Report {
  const counts = [
    [3, 6, 7, 11, 9, 7, 5],
    [4, 7, 8, 13, 10, 8, 4],
    [2, 5, 7, 12, 9, 6, 5],
    [3, 6, 9, 12, 11, 7, 6],
    [2, 5, 6, 10, 8, 6, 3],
  ];
  const groups = ['1°A', '1°B', '1°C', '2°A', '2°B', '2°C', '3°A', '3°B', '3°C'];
  const exits = [24, 29, 31, 22, 38, 27, 35, 19, 23];
  return {
    from: '2026-10-12',
    to: '2026-10-16',
    thresholds: { alerts: 2, exits: 8 },
    totals: {
      exits: 248,
      bathroom: 196,
      nurse: 52,
      avg_minutes: 5.9,
      avg_minutes_h: 6.4,
      avg_minutes_m: 5.1,
    },
    alerts: { count: 11, acknowledged_fast: 9, escalated: 2 },
    max_queue: { size: 5, destination: 'Baño hombres', at: '2026-10-13T16:00:00Z' },
    heatmap: counts.flatMap((row, d) =>
      row.map((count, h) => ({ destination: 'bath_h', weekday: d + 1, hour: 7 + h, count })),
    ),
    queued_slots: [1, 2, 3, 4, 5].map((wd) => ({ destination: 'bath_h', weekday: wd, hour: 10 })),
    by_group: groups.map((g, i) => ({
      group_id: g,
      group_name: g,
      exits: exits[i]!,
      avg_minutes: 4.7 + (i % 4) * 0.7,
      alerts: [0, 1, 1, 0, 3, 1, 3, 0, 2][i]!,
    })),
    review: [
      {
        student_id: 'a',
        full_name: 'Natalia Quiroz',
        list_number: 17,
        group_name: '2°B',
        exits: 6,
        nurse: 0,
        avg_minutes: 9.8,
        alerts: 3,
        top_subject: 'Matemáticas',
      },
      {
        student_id: 'b',
        full_name: 'Raúl Herrera',
        list_number: 9,
        group_name: '3°A',
        exits: 11,
        nurse: 0,
        avg_minutes: 6.1,
        alerts: 0,
        top_subject: 'Química',
      },
      {
        student_id: 'c',
        full_name: 'Iván Ruiz',
        list_number: 21,
        group_name: '3°C',
        exits: 1,
        nurse: 4,
        avg_minutes: 4,
        alerts: 0,
        top_subject: null,
      },
    ],
  };
}

function bathroomsPreview(names = false): BathroomsStatus {
  const iso = (minAgo: number) => new Date(Date.now() - minAgo * 60_000).toISOString();
  const who = (full_name: string, subject: string, opened_by: string) =>
    names ? { full_name, subject, opened_by } : {};
  return {
    now: new Date().toISOString(),
    offsetMs: 0,
    names,
    nurse: 2,
    nurse_queue: [
      {
        group_name: '3°C',
        status: 'out',
        since: iso(1.5),
        ...who('Iván Ruiz', 'Historia', 'Prof. Lara'),
      },
    ],
    nurse_care: [
      {
        group_name: '2°B',
        status: 'arrived',
        since: iso(6),
        ...who('Mateo Pérez', 'Español', 'Prof. Soto'),
      },
    ],
    nurse_returning: [],
    bathrooms: [
      {
        id: 'bath_h',
        label: 'Baño hombres',
        sex: 'H',
        capacity: 1,
        paused: { since: iso(4), by: 'Prefectura', reason: 'Limpieza' },
        group_wait: 1,
        occupants: [
          {
            group_name: '2°B',
            status: 'out',
            since: iso(4.2),
            ...who('Pedro Gómez', 'Matemáticas', 'Prof. Ramírez'),
          },
        ],
        queue: [
          {
            group_name: '3°A',
            status: 'queued',
            since: iso(3.1),
            ...who('Raúl Herrera', 'Ciencias', 'Prof. Núñez'),
          },
          {
            group_name: '1°C',
            status: 'queued',
            since: iso(1.2),
            ...who('Emiliano Cruz', 'Inglés', 'Prof. Lara'),
          },
        ],
        group_wait_list: names
          ? [
              {
                group_name: '2°B',
                status: 'group_wait',
                since: iso(0.8),
                ...who('Jorge Valdez', 'Matemáticas', 'Prof. Ramírez'),
              },
            ]
          : undefined,
      },
      {
        id: 'bath_m',
        label: 'Baño mujeres',
        sex: 'M',
        capacity: 3,
        group_wait: 0,
        occupants: [
          {
            group_name: '1°A',
            status: 'out',
            since: iso(11.4),
            ...who('Sofía Ramírez', 'Artes', 'Prof. Vega'),
          },
          {
            group_name: '2°C',
            status: 'out',
            since: iso(2),
            ...who('Paola Núñez', 'Física', 'Prof. Luna'),
          },
        ],
        queue: [],
      },
    ],
  };
}
