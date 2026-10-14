import { Route, Routes } from 'react-router-dom';
import { AppShell } from '@/components/layout/AppShell';
import { Home } from '@/pages/Home';
import { Placeholder } from '@/pages/Placeholder';

export function App() {
  return (
    <Routes>
      <Route element={<AppShell />}>
        <Route index element={<Home />} />
        <Route path="grupo" element={<Placeholder title="Mi grupo" phase={3} />} />
        <Route path="salon" element={<Placeholder title="Salón" phase={3} />} />
        <Route path="banos" element={<Placeholder title="Baños" phase={3} />} />
        <Route path="alertas" element={<Placeholder title="Alertas" phase={4} />} />
        <Route path="en-vivo" element={<Placeholder title="En vivo" phase={4} />} />
        <Route path="enfermeria" element={<Placeholder title="Enfermería" phase={4} />} />
        <Route path="reportes" element={<Placeholder title="Reportes" phase={6} />} />
        <Route path="historial" element={<Placeholder title="Historial" phase={6} />} />
        <Route path="ajustes/*" element={<Placeholder title="Ajustes" phase={6} />} />
        <Route path="mas" element={<Placeholder title="Más" phase={5} />} />
        <Route
          path="*"
          element={
            <Placeholder title="No encontrada" phase={0} description="Esta página no existe." />
          }
        />
      </Route>
    </Routes>
  );
}
