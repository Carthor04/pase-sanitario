import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { StudentsPanel } from './StudentsPanel';

const calls: { table: string; op: string; values?: unknown; eq?: unknown[] }[] = [];

vi.mock('@/lib/supabase', () => {
  const data: Record<string, unknown[]> = {
    groups: [{ id: 'g1', name: '2°B', room: 'Salón 5', sort: 1 }],
    students: [
      { id: 's1', list_number: 1, full_name: 'Aguirre Pérez Uriel', sex: 'H', active: true },
      {
        id: 's2',
        list_number: 2,
        full_name: 'Galván Candelas Jesús Emiliano',
        sex: 'H',
        active: true,
      },
      { id: 's3', list_number: 3, full_name: 'Olvera Morales María José', sex: 'M', active: false },
    ],
  };
  const from = (table: string) => {
    let op = 'select';
    let values: unknown;
    const q = {
      select: () => q,
      order: () => q,
      single: () => q,
      eq: (...args: unknown[]) => {
        calls.push({ table, op, values, eq: args });
        return q;
      },
      insert: (v: unknown) => {
        op = 'insert';
        values = v;
        calls.push({ table, op, values });
        return q;
      },
      update: (v: unknown) => {
        op = 'update';
        values = v;
        return q;
      },
      then: (resolve: (v: unknown) => void) =>
        resolve({ data: op === 'select' ? data[table] : null, error: null }),
    };
    return q;
  };
  return { isSupabaseConfigured: true, supabase: { from } };
});

function renderPanel() {
  render(
    <QueryClientProvider client={new QueryClient()}>
      <StudentsPanel />
    </QueryClientProvider>,
  );
}

describe('Ajustes → listas de los grupos', () => {
  beforeEach(() => {
    calls.length = 0;
  });

  it('muestra la lista completa del grupo y oculta las bajas', async () => {
    renderPanel();
    expect(await screen.findByText('Galván Candelas Jesús Emiliano')).toBeInTheDocument();
    expect(screen.queryByText('Olvera Morales María José')).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Ver dados de baja (1)' }));
    expect(screen.getByText('Olvera Morales María José')).toBeInTheDocument();
  });

  it('quitar = dar de baja (update active=false), nunca borrar', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    renderPanel();
    const row = (await screen.findByText('Aguirre Pérez Uriel')).closest('li')!;
    fireEvent.click(within(row).getByRole('button', { name: 'Quitar' }));
    await waitFor(() =>
      expect(calls).toContainEqual({
        table: 'students',
        op: 'update',
        values: { active: false },
        eq: ['id', 's1'],
      }),
    );
  });

  it('agrega con el siguiente número de lista y limpia espacios del nombre', async () => {
    renderPanel();
    await screen.findByText('Aguirre Pérez Uriel');
    const number = screen.getAllByLabelText('Núm.').at(-1)! as HTMLInputElement;
    expect(number.value).toBe('3');
    fireEvent.change(screen.getAllByLabelText('Nombre completo').at(-1)!, {
      target: { value: '  Ruiz   Pérez Ana ' },
    });
    fireEvent.change(screen.getAllByLabelText('Sexo (baño)').at(-1)!, { target: { value: 'M' } });
    fireEvent.click(screen.getByRole('button', { name: 'Agregar' }));
    await waitFor(() =>
      expect(calls).toContainEqual({
        table: 'students',
        op: 'insert',
        values: { list_number: 3, full_name: 'Ruiz Pérez Ana', sex: 'M', group_id: 'g1' },
      }),
    );
    // El navegador no deja enviar números fuera de 1–99.
    expect(number).toHaveAttribute('min', '1');
    expect(number).toHaveAttribute('max', '99');
  });
});
