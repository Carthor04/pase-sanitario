import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { Board, BoardPass, StudentRef } from '@/lib/board';
import { GroupLive } from './GroupLive';

const rpc = vi.fn();
vi.mock('@/lib/supabase', () => ({
  isSupabaseConfigured: true,
  supabase: { rpc: (...args: unknown[]) => rpc(...args) },
}));

const students: StudentRef[] = [
  { id: 's3', list_number: 3, full_name: 'Carla Domínguez', sex: 'M' },
  { id: 's14', list_number: 14, full_name: 'Luis Martínez', sex: 'H' },
];

const out: BoardPass = {
  id: 'p14',
  student_id: 's14',
  list_number: 14,
  full_name: 'Luis Martínez',
  sex: 'H',
  status: 'out',
  destination_id: 'bath_h',
  destination_kind: 'bathroom',
  destination_label: 'Baño hombres',
  requested_at: new Date().toISOString(),
  queue_ts: null,
  called_at: null,
  started_at: new Date().toISOString(),
  arrived_at: null,
  period_subject: null,
  opened_by_name: null,
  queue_position: null,
  waiting_for: null,
};

const board: Board & { offsetMs: number } = {
  now: new Date().toISOString(),
  offsetMs: 0,
  settings: {
    alert_minutes: 10,
    confirm_turn_minutes: 2,
    undo_seconds: 10,
    auto_lock_after_class_minutes: 5,
  },
  passes: [out],
  bathrooms: [
    { id: 'bath_h', label: 'Baño hombres', sex: 'H', capacity: 1, occupants: [], queue: [] },
    { id: 'bath_m', label: 'Baño mujeres', sex: 'M', capacity: 3, occupants: [], queue: [] },
  ],
};

function renderLive() {
  render(
    <QueryClientProvider client={new QueryClient()}>
      <GroupLive board={board} groupName="2°B" students={students} capture />
    </QueryClientProvider>,
  );
  return screen.getByLabelText('Número de lista');
}

describe('captura rápida', () => {
  beforeEach(() => rpc.mockReset());

  it('número + B abre pase de baño y ofrece deshacer', async () => {
    rpc.mockResolvedValue({
      data: { id: 'new', status: 'out', queue_position: null },
      error: null,
    });
    const input = renderLive();
    fireEvent.change(input, { target: { value: '3' } });
    fireEvent.keyDown(input, { key: 'b' });
    await waitFor(() =>
      expect(rpc).toHaveBeenCalledWith('request_pass', { p_student_id: 's3', p_kind: 'bathroom' }),
    );
    expect(await screen.findByText('Carla Domínguez salió al baño mujeres')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Deshacer/ })).toBeInTheDocument();
  });

  it('número + R marca el regreso del que está fuera', async () => {
    rpc.mockResolvedValue({ data: { id: 'p14', status: 'returned' }, error: null });
    const input = renderLive();
    fireEvent.change(input, { target: { value: '14' } });
    fireEvent.keyDown(input, { key: 'R' });
    await waitFor(() => expect(rpc).toHaveBeenCalledWith('mark_returned', { p_pass_id: 'p14' }));
  });

  it('muestra el error de la BD tal cual (ya viene en español)', async () => {
    rpc.mockResolvedValue({ data: null, error: { message: 'El alumno ya tiene un pase activo' } });
    const input = renderLive();
    fireEvent.change(input, { target: { value: '3' } });
    fireEvent.keyDown(input, { key: 'e' });
    expect(await screen.findByRole('alert')).toHaveTextContent('El alumno ya tiene un pase activo');
  });

  it('avisa si el número no existe o el alumno no está fuera', () => {
    const input = renderLive();
    fireEvent.change(input, { target: { value: '40' } });
    fireEvent.keyDown(input, { key: 'b' });
    expect(screen.getByRole('alert')).toHaveTextContent('No hay alumno con el número 40');
    fireEvent.change(input, { target: { value: '3' } });
    fireEvent.keyDown(input, { key: 'r' });
    expect(screen.getByRole('alert')).toHaveTextContent('#3 Carla Domínguez no está fuera');
    expect(rpc).not.toHaveBeenCalled();
  });
});

describe('salidas del día', () => {
  beforeEach(() => rpc.mockReset());

  it('marca con ⚠ a quien llegó al límite y al tocarlo muestra horarios y clases', async () => {
    rpc.mockImplementation(async (fn: string) => {
      if (fn === 'group_today_counts') {
        return {
          data: {
            flag: 3,
            counts: { s14: { bathroom: 3, nurse: 0 }, s3: { bathroom: 1, nurse: 0 } },
          },
          error: null,
        };
      }
      if (fn === 'student_today_passes') {
        return {
          data: [
            {
              started_at: '2026-10-16T14:05:00Z',
              ended_at: '2026-10-16T14:11:00Z',
              status: 'returned',
              destination: 'Baño hombres',
              kind: 'bathroom',
              subject: 'Matemáticas',
              opened_by: 'Laura Ramírez',
              minutes: 6,
              alert: false,
            },
          ],
          error: null,
        };
      }
      return { data: null, error: null };
    });
    render(
      <QueryClientProvider client={new QueryClient()}>
        <GroupLive board={board} groupName="2°B" groupId="g" students={students} />
      </QueryClientProvider>,
    );
    const flag = await screen.findByRole('button', {
      name: /Luis Martínez salió 3 veces al baño hoy/,
    });
    expect(screen.getAllByText('Hoy: 1 baño').length).toBeGreaterThan(0); // Carla: sin marca
    expect(screen.queryByRole('button', { name: /Carla Domínguez salió/ })).toBeNull();
    fireEvent.click(flag);
    expect(
      await screen.findByRole('dialog', { name: 'Salidas de hoy de Luis Martínez' }),
    ).toBeInTheDocument();
    expect(await screen.findByText('08:05 – 08:11')).toBeInTheDocument();
    expect(
      screen.getByText('Baño hombres · en Matemáticas · autorizó Laura Ramírez'),
    ).toBeInTheDocument();
  });
});
