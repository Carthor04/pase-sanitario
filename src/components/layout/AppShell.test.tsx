import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router';
import type { StaffMe } from '@/lib/me';
import type { Role } from '@/lib/nav';
import { StaffContext } from '@/lib/session';
import { AppShell } from './AppShell';

const rpc = vi.fn(async () => ({ data: [] as unknown[], error: null }));
vi.mock('@/lib/supabase', () => ({
  isSupabaseConfigured: true,
  supabase: { rpc: () => rpc() },
}));

function renderAt(url: string, roles: Role[] = ['teacher']) {
  const staff: StaffMe = {
    kind: 'staff',
    id: 's1',
    full_name: 'Laura Ramírez',
    email: 'laura@colegio.edu.mx',
    roles,
    has_pin: false,
  };
  return render(
    <QueryClientProvider client={new QueryClient()}>
      <StaffContext.Provider value={staff}>
        <MemoryRouter initialEntries={[url]}>
          <Routes>
            <Route element={<AppShell />}>
              <Route path="*" element={<p>contenido</p>} />
            </Route>
          </Routes>
        </MemoryRouter>
      </StaffContext.Provider>
    </QueryClientProvider>,
  );
}

const linkLabels = (nav: HTMLElement) =>
  within(nav)
    .getAllByRole('link')
    .map((l) => l.textContent);

describe('AppShell', () => {
  it('muestra la navegación del maestro', () => {
    renderAt('/grupo');
    expect(screen.getByText('contenido')).toBeInTheDocument();
    const navs = screen.getAllByRole('navigation', { name: 'Secciones' });
    expect(navs).toHaveLength(2); // encabezado (escritorio) y barra inferior (celular)
    for (const nav of navs) {
      expect(linkLabels(nav)).toEqual(['Mi grupo', 'Baños', 'Alertas', 'Perfil']);
    }
  });

  it('marca la pestaña activa', () => {
    renderAt('/grupo');
    const bottom = screen.getAllByRole('navigation', { name: 'Secciones' })[1]!;
    expect(within(bottom).getByRole('link', { name: 'Mi grupo' })).toHaveAttribute(
      'aria-current',
      'page',
    );
  });

  it('muestra cuántas alertas tiene el maestro', async () => {
    rpc.mockResolvedValueOnce({ data: [{ pass_id: 'p' }], error: null });
    renderAt('/grupo');
    const bottom = screen.getAllByRole('navigation', { name: 'Secciones' })[1]!;
    const alertas = within(bottom).getByRole('link', { name: /Alertas/ });
    expect(await within(alertas).findByText('1')).toBeInTheDocument();
  });

  it('cambia de pestañas según los roles de la sesión', () => {
    renderAt('/enfermeria', ['nurse']);
    const bottom = screen.getAllByRole('navigation', { name: 'Secciones' })[1]!;
    expect(linkLabels(bottom)).toEqual(['Enfermería', 'Historial']);
  });
});
