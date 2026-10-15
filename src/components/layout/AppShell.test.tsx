import { render, screen, within } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router';
import type { StaffMe } from '@/lib/me';
import type { Role } from '@/lib/nav';
import { StaffContext } from '@/lib/session';
import { AppShell } from './AppShell';

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
    <StaffContext.Provider value={staff}>
      <MemoryRouter initialEntries={[url]}>
        <Routes>
          <Route element={<AppShell />}>
            <Route path="*" element={<p>contenido</p>} />
          </Route>
        </Routes>
      </MemoryRouter>
    </StaffContext.Provider>,
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
      expect(linkLabels(nav)).toEqual(['Mi grupo', 'Baños', 'Alertas', 'Más']);
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

  it('cambia de pestañas según los roles de la sesión', () => {
    renderAt('/enfermeria', ['nurse']);
    const bottom = screen.getAllByRole('navigation', { name: 'Secciones' })[1]!;
    expect(linkLabels(bottom)).toEqual(['Hoy', 'Historial']);
  });
});
