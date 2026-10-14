import { render, screen, within } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { AppShell } from './AppShell';

function renderAt(url: string) {
  return render(
    <MemoryRouter
      initialEntries={[url]}
      future={{ v7_startTransition: true, v7_relativeSplatPath: true }}
    >
      <Routes>
        <Route element={<AppShell />}>
          <Route path="*" element={<p>contenido</p>} />
        </Route>
      </Routes>
    </MemoryRouter>,
  );
}

const linkLabels = (nav: HTMLElement) =>
  within(nav)
    .getAllByRole('link')
    .map((l) => l.textContent);

describe('AppShell', () => {
  it('muestra la navegación del maestro por defecto', () => {
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

  it('cambia de pestañas según el rol (solo en desarrollo)', () => {
    renderAt('/en-vivo?roles=nurse');
    const bottom = screen.getAllByRole('navigation', { name: 'Secciones' })[1]!;
    expect(linkLabels(bottom)).toEqual(['Hoy', 'Historial']);
  });
});
