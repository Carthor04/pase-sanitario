import { useQueryClient } from '@tanstack/react-query';
import { useState, type FormEvent } from 'react';
import { Link, Navigate, useNavigate } from 'react-router';
import { DigitInput } from '@/components/ui/DigitInput';
import { FullScreen, Loading, Notice } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { useMe, useSession } from '@/lib/session';
import { supabase } from '@/lib/supabase';

const ERRORS: Record<string, string> = {
  invalid_code: 'Ese código no es válido o ya venció. Pide uno nuevo a coordinación.',
  rate_limited: 'Demasiados intentos. Espera unos minutos y vuelve a intentarlo.',
  already_linked: 'Este equipo ya está vinculado.',
  not_anonymous: 'Cierra la sesión de Google en este equipo antes de vincularlo.',
};

/**
 * La computadora del salón entra como usuario anónimo de Supabase y reclama un código
 * de 6 dígitos que generó coordinación (Ajustes → Salones y equipos).
 */
export function LinkDevice() {
  const session = useSession();
  const me = useMe();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (session === undefined || (session && me.isPending)) {
    return (
      <FullScreen>
        <Loading />
      </FullScreen>
    );
  }
  if (me.data?.kind === 'device') return <Navigate to="/salon" replace />;

  const staffSession = session && !session.user.is_anonymous;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (code.length !== 6) return;
    setBusy(true);
    setError(null);
    try {
      if (staffSession) await supabase.auth.signOut();
      const current = (await supabase.auth.getSession()).data.session;
      if (!current) {
        const { error: err } = await supabase.auth.signInAnonymously();
        if (err) {
          setError(
            'No se pudo iniciar la sesión del equipo. Revisa que los inicios anónimos estén activados en Supabase.',
          );
          return;
        }
      }
      const { data, error: err } = await supabase.rpc('claim_device_pairing', { p_code: code });
      if (err) throw err;
      const res = data as { ok: boolean; error?: string };
      if (!res.ok) {
        setError(ERRORS[res.error ?? ''] ?? 'No se pudo vincular el equipo.');
        return;
      }
      await queryClient.invalidateQueries({ queryKey: ['me'] });
      navigate('/salon', { replace: true });
    } catch {
      setError('No se pudo conectar. Revisa la conexión a internet.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <FullScreen title="Vincular equipo de salón">
      <p className="m-0 text-muted">
        Escribe el código de 6 dígitos que te dio coordinación. El equipo quedará asignado a ese
        grupo.
      </p>
      {staffSession ? (
        <Notice tone="warn">
          Hay una sesión de Google abierta en este equipo. Al vincularlo se cerrará.
        </Notice>
      ) : null}
      <form onSubmit={submit} className="flex flex-col gap-4">
        <DigitInput
          label="Código de vinculación"
          length={6}
          value={code}
          onChange={setCode}
          autoFocus
        />
        {error ? <Notice tone="error">{error}</Notice> : null}
        <button type="submit" className={buttonClass.primary} disabled={busy || code.length !== 6}>
          {busy ? 'Vinculando…' : 'Vincular'}
        </button>
      </form>
      <Link to="/entrar" className="text-[15px] font-bold text-accent">
        Soy maestro: entrar con Google
      </Link>
    </FullScreen>
  );
}
