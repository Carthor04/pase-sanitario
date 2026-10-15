// Solo en desarrollo (npm run dev): muestra el tablero con datos ficticios para revisar el
// diseño sin sesión. Las acciones fallan porque no hay usuario; es solo para ver.
import { useMemo, useState } from 'react';
import { GroupLive } from '@/components/pass/GroupLive';
import { PinPad } from '@/components/pass/PinPad';
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
  const [view, setView] = useState<'turno' | 'libre' | 'pin'>('turno');
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
      <div className="flex flex-wrap gap-2 border-b border-line bg-surface p-3">
        <strong className="mr-2 self-center">Vista de prueba (datos ficticios)</strong>
        {(['turno', 'libre', 'pin'] as const).map((v) => (
          <button
            key={v}
            type="button"
            onClick={() => setView(v)}
            className={`min-h-touch rounded-btn border px-3 font-bold ${view === v ? 'border-accent text-accent' : 'border-line'}`}
          >
            {v}
          </button>
        ))}
      </div>
      <main className="mx-auto max-w-container px-4 py-5 sm:px-6">
        {view === 'pin' ? (
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
            footnote="Queda registrado a nombre de Laura Ramírez."
          />
        )}
      </main>
    </div>
  );
}
