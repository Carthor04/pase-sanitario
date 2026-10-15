import { useState } from 'react';
import { Link, Navigate, useLocation } from 'react-router';
import { FullScreen, Loading, Notice } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { readAuthError, signInWithGoogle, useMe, useSession } from '@/lib/session';

export function Login() {
  const session = useSession();
  const me = useMe();
  const location = useLocation();
  const [error, setError] = useState<string | null>(null);
  const urlError = readAuthError(location);

  if (session && me.data?.kind === 'staff') return <Navigate to="/" replace />;
  if (session && me.data?.kind === 'device') return <Navigate to="/salon" replace />;

  async function start() {
    setError(null);
    const { error: err } = await signInWithGoogle();
    if (err) setError('No se pudo abrir el inicio de sesión de Google. Inténtalo de nuevo.');
  }

  return (
    <FullScreen title="Entrar">
      {urlError ? (
        <Notice tone="error">
          Esa cuenta de Google no está registrada como personal activo. Pide a coordinación que te
          dé de alta y vuelve a intentarlo.
        </Notice>
      ) : null}
      {error ? <Notice tone="error">{error}</Notice> : null}
      {session === undefined ? <Loading /> : null}
      <p className="m-0 text-muted">Usa tu cuenta de Google registrada en el colegio.</p>
      <button type="button" className={buttonClass.primary} onClick={start}>
        Entrar con Google
      </button>
      <div className="border-t border-line pt-4 text-[15px]">
        ¿Es la computadora del salón?{' '}
        <Link to="/vincular" className="font-bold text-accent">
          Vincular este equipo
        </Link>
      </div>
    </FullScreen>
  );
}
