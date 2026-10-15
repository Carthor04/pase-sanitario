import { Navigate } from 'react-router';
import { navForRoles } from '@/lib/nav';
import { useStaff } from '@/lib/session';

/** Inicio: cada rol cae en su primera pestaña (maestro → Mi grupo, prefectura → En vivo…). */
export function Home() {
  const { roles } = useStaff();
  const first = navForRoles(roles)[0]?.to ?? '/mas';
  return <Navigate to={first} replace />;
}
