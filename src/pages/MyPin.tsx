import { useQueryClient } from '@tanstack/react-query';
import { useState, type FormEvent } from 'react';
import { DigitInput } from '@/components/ui/DigitInput';
import { Card, Notice, PageTitle } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { pinResultError } from '@/lib/pin';
import { useStaff } from '@/lib/session';
import { supabase } from '@/lib/supabase';

/** Definir o cambiar el PIN propio (sirve para desbloquear la computadora del salón). */
export function MyPin() {
  const staff = useStaff();
  const queryClient = useQueryClient();
  const [pin, setPin] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSaved(false);
    if (pin !== confirm) {
      setError('Los dos PIN no coinciden.');
      return;
    }
    setBusy(true);
    const { data, error: err } = await supabase.rpc('set_my_pin', { p_pin: pin });
    setBusy(false);
    const message = err ? 'No se pudo conectar. Inténtalo de nuevo.' : pinResultError(data);
    if (message) {
      setError(message);
      return;
    }
    setPin('');
    setConfirm('');
    setSaved(true);
    await queryClient.invalidateQueries({ queryKey: ['me'] });
  }

  return (
    <div className="flex max-w-[480px] flex-col gap-4">
      <PageTitle>Mi PIN</PageTitle>
      <Card>
        <p className="m-0 text-muted">
          Con tu PIN de 4 dígitos desbloqueas la computadora de cualquier salón. Es personal: no lo
          compartas. Si lo cambias, los equipos que tengas abiertos se bloquean.
        </p>
        <span className="text-[15px]">
          Estado: <strong>{staff.has_pin ? 'tienes PIN definido' : 'todavía no tienes PIN'}</strong>
        </span>
        <form onSubmit={submit} className="flex flex-col gap-4">
          <DigitInput label="PIN nuevo" length={4} value={pin} onChange={setPin} secret />
          <DigitInput
            label="Repite el PIN"
            length={4}
            value={confirm}
            onChange={setConfirm}
            secret
          />
          {error ? <Notice tone="error">{error}</Notice> : null}
          {saved ? <Notice tone="ok">Listo: tu PIN quedó guardado.</Notice> : null}
          <button
            type="submit"
            className={buttonClass.primary}
            disabled={busy || pin.length !== 4 || confirm.length !== 4}
          >
            {busy ? 'Guardando…' : staff.has_pin ? 'Cambiar PIN' : 'Guardar PIN'}
          </button>
        </form>
      </Card>
    </div>
  );
}
