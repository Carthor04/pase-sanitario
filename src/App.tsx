import { lazy, Suspense } from 'react';
import { Route, Routes } from 'react-router';
import { RequireDevice, RequireStaff } from '@/components/auth/Gates';
import { AppShell } from '@/components/layout/AppShell';
import { Alerts } from '@/pages/Alerts';
import { Bathrooms } from '@/pages/Bathrooms';
import { History } from '@/pages/History';
import { Home } from '@/pages/Home';
import { LinkDevice } from '@/pages/LinkDevice';
import { LiveBoard } from '@/pages/LiveBoard';
import { Login } from '@/pages/Login';
import { More } from '@/pages/More';
import { MyGroup } from '@/pages/MyGroup';
import { MyPin } from '@/pages/MyPin';
import { Nurse } from '@/pages/Nurse';
import { Placeholder } from '@/pages/Placeholder';
import { Reports } from '@/pages/Reports';
import { SalonHome } from '@/pages/SalonHome';
import { Settings } from '@/pages/settings/Settings';

// Vista de diseño con datos ficticios: solo existe en `npm run dev`.
const UiPreview = import.meta.env.DEV
  ? lazy(() => import('@/pages/dev/UiPreview').then((m) => ({ default: m.UiPreview })))
  : null;

export function App() {
  return (
    <Routes>
      <Route path="entrar" element={<Login />} />
      <Route path="vincular" element={<LinkDevice />} />
      {UiPreview ? (
        <Route
          path="dev/ui"
          element={
            <Suspense>
              <UiPreview />
            </Suspense>
          }
        />
      ) : null}

      {/* Computadora del salón (sesión anónima vinculada a un grupo). */}
      <Route element={<RequireDevice />}>
        <Route path="salon" element={<SalonHome />} />
      </Route>

      {/* Personal con Google. */}
      <Route element={<RequireStaff />}>
        <Route element={<AppShell />}>
          <Route index element={<Home />} />
          <Route path="grupo" element={<MyGroup />} />
          <Route path="mi-pin" element={<MyPin />} />
          <Route path="mas" element={<More />} />
          <Route path="ajustes/*" element={<Settings />} />
          <Route path="banos" element={<Bathrooms />} />
          <Route path="alertas" element={<Alerts />} />
          <Route path="en-vivo" element={<LiveBoard />} />
          <Route path="enfermeria" element={<Nurse />} />
          <Route path="reportes" element={<Reports />} />
          <Route path="historial" element={<History />} />
          <Route
            path="*"
            element={
              <Placeholder title="No encontrada" phase={0} description="Esta página no existe." />
            }
          />
        </Route>
      </Route>
    </Routes>
  );
}
