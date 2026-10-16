import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router';
import type { StaffMe } from '@/lib/me';
import { StaffContext } from '@/lib/session';
import { Settings } from './Settings';

vi.mock('@/lib/supabase', () => {
  const rows = [
    {
      id: 'a',
      full_name: 'Ana Torres',
      email: 'ana@colegio.edu.mx',
      roles: ['teacher'],
      active: true,
      pin_set_at: null,
      auth_user_id: null,
    },
  ];
  const query = {
    select: () => query,
    order: () => query,
    eq: () => query,
    single: () => query,
    then: (resolve: (v: unknown) => void) => resolve({ data: rows, error: null }),
  };
  return {
    isSupabaseConfigured: true,
    supabase: { from: () => query, rpc: async () => ({ data: { ok: true }, error: null }) },
  };
});

const admin: StaffMe = {
  kind: 'staff',
  id: 's',
  full_name: 'Admin',
  email: 'admin@colegio.edu.mx',
  roles: ['teacher', 'admin'],
  has_pin: false,
};

function Where() {
  return <output data-testid="where">{useLocation().pathname}</output>;
}

describe('Ajustes', () => {
  it('cambia de pestaña sin anidar rutas y abre Asignar PIN', async () => {
    render(
      <QueryClientProvider client={new QueryClient()}>
        <StaffContext.Provider value={admin}>
          <MemoryRouter initialEntries={['/ajustes']}>
            <Routes>
              <Route path="ajustes/*" element={<Settings />} />
            </Routes>
            <Where />
          </MemoryRouter>
        </StaffContext.Provider>
      </QueryClientProvider>,
    );
    expect(screen.getByTestId('where')).toHaveTextContent('/ajustes/banos');

    fireEvent.click(screen.getByRole('link', { name: 'Personal y PIN' }));
    expect(screen.getByTestId('where')).toHaveTextContent(/^\/ajustes\/personal$/);

    fireEvent.click(await screen.findByRole('button', { name: 'Asignar PIN' }));
    expect(screen.getByLabelText('PIN nuevo para Ana Torres')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('link', { name: 'Salones y equipos' }));
    expect(screen.getByTestId('where')).toHaveTextContent(/^\/ajustes\/equipos$/);
  });
});
