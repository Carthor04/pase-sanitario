import { useQueryClient } from '@tanstack/react-query';
import { Navigate, Outlet } from 'react-router';
import { FullScreen, Loading, Notice } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { DeviceContext, StaffContext, signOut, useMe, useSession } from '@/lib/session';
import { isSupabaseConfigured } from '@/lib/supabase';

function MeError({ retry }: { retry: () => void }) {
  return (
    <FullScreen title="No se pudo conectar">
      <Notice tone="error">Revisa tu conexión a internet e inténtalo de nuevo.</Notice>
      <button type="button" className={buttonClass.primary} onClick={retry}>
        Reintentar
      </button>
    </FullScreen>
  );
}

export function NoAccess({ email }: { email: string | null }) {
  const queryClient = useQueryClient();
  return (
    <FullScreen title="No tienes acceso">
      <p className="m-0">
        {email ? (
          <>
            La cuenta <strong className="break-all">{email}</strong> no está registrada como
            personal activo.
          </>
        ) : (
          'Tu cuenta no está registrada como personal activo.'
        )}{' '}
        Pide a coordinación que te dé de alta en Personal y PIN.
      </p>
      <button type="button" className={buttonClass.secondary} onClick={() => signOut(queryClient)}>
        Entrar con otra cuenta
      </button>
    </FullScreen>
  );
}

function NotConfigured() {
  return (
    <FullScreen title="Falta configurar Supabase">
      <Notice tone="warn">
        Define VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY en .env.local (o en Vercel).
      </Notice>
    </FullScreen>
  );
}

/** Solo personal activo con Google. Los equipos de salón van a /salon. */
export function RequireStaff() {
  const session = useSession();
  const me = useMe();

  if (!isSupabaseConfigured) return <NotConfigured />;
  if (session === null) return <Navigate to="/entrar" replace />;
  if (session === undefined || me.isPending) {
    return (
      <FullScreen>
        <Loading />
      </FullScreen>
    );
  }
  if (me.isError) return <MeError retry={() => me.refetch()} />;

  const data = me.data;
  if (data.kind === 'device') return <Navigate to="/salon" replace />;
  if (data.kind === 'none') {
    return data.anonymous ? <Navigate to="/vincular" replace /> : <NoAccess email={data.email} />;
  }
  return (
    <StaffContext.Provider value={data}>
      <Outlet />
    </StaffContext.Provider>
  );
}

/** Solo una computadora de salón vinculada. */
export function RequireDevice() {
  const session = useSession();
  const me = useMe();

  if (!isSupabaseConfigured) return <NotConfigured />;
  if (session === null) return <Navigate to="/vincular" replace />;
  if (session === undefined || me.isPending) {
    return (
      <FullScreen>
        <Loading />
      </FullScreen>
    );
  }
  if (me.isError) return <MeError retry={() => me.refetch()} />;

  const data = me.data;
  if (data.kind === 'staff') return <Navigate to="/" replace />;
  if (data.kind === 'none') {
    return data.anonymous ? <Navigate to="/vincular" replace /> : <NoAccess email={data.email} />;
  }
  return (
    <DeviceContext.Provider value={data}>
      <Outlet />
    </DeviceContext.Provider>
  );
}
