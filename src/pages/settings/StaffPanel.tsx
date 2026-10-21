import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState, type FormEvent } from 'react';
import { DigitInput } from '@/components/ui/DigitInput';
import { Card, Loading, Notice, SectionLabel } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { ROLE_LABELS, type Role } from '@/lib/nav';
import { pinResultError } from '@/lib/pin';
import { useStaff } from '@/lib/session';
import { supabase } from '@/lib/supabase';

type StaffRow = {
  id: string;
  full_name: string;
  email: string;
  roles: Role[];
  active: boolean;
  pin_set_at: string | null;
  auth_user_id: string | null;
};

function PinForm({ person, onDone }: { person: StaffRow; onDone: () => void }) {
  const [pin, setPin] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const queryClient = useQueryClient();

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    const { data, error: err } = await supabase.rpc('set_staff_pin', {
      p_staff_id: person.id,
      p_pin: pin,
    });
    setBusy(false);
    const message = err ? 'No se pudo conectar.' : pinResultError(data);
    if (message) {
      setError(message);
      return;
    }
    await queryClient.invalidateQueries({ queryKey: ['staff'] });
    onDone();
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-3 rounded-btn bg-ground p-3">
      <DigitInput
        label={`PIN nuevo para ${person.full_name}`}
        length={4}
        value={pin}
        onChange={setPin}
        secret
        autoFocus
      />
      {error ? <Notice tone="error">{error}</Notice> : null}
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={buttonClass.primary} disabled={busy || pin.length !== 4}>
          Guardar PIN
        </button>
        <button type="button" className={buttonClass.secondary} onClick={onDone}>
          Cancelar
        </button>
      </div>
    </form>
  );
}

export function StaffPanel() {
  const me = useStaff();
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState<string | null>(null);
  const [showInactive, setShowInactive] = useState(false);

  const staff = useQuery({
    queryKey: ['staff'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('staff')
        .select('id, full_name, email, roles, active, pin_set_at, auth_user_id')
        .order('full_name');
      if (error) throw error;
      return data as StaffRow[];
    },
  });

  const toggleActive = useMutation({
    mutationFn: async (p: StaffRow) => {
      const { error } = await supabase.from('staff').update({ active: !p.active }).eq('id', p.id);
      if (error) throw error;
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: ['staff'] }),
  });

  const clearPin = useMutation({
    mutationFn: async (p: StaffRow) => {
      const { error } = await supabase.rpc('clear_staff_pin', { p_staff_id: p.id });
      if (error) throw error;
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: ['staff'] }),
  });

  const rows = (staff.data ?? []).filter((p) => showInactive || p.active);

  return (
    <Card>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <SectionLabel>Personal y PIN</SectionLabel>
        <label className="flex min-h-touch items-center gap-2 text-[15px]">
          <input
            type="checkbox"
            checked={showInactive}
            onChange={(e) => setShowInactive(e.target.checked)}
            className="h-5 w-5"
          />
          Mostrar dados de baja
        </label>
      </div>
      <p className="m-0 text-[15px] text-muted">
        Cada persona define su PIN en Perfil → Mi PIN. Desde aquí puedes asignarlo o quitarlo. Los
        PIN son únicos: si alguien ya lo usa, se pide otro.
      </p>
      {staff.isPending ? <Loading /> : null}
      {staff.isError ? <Notice tone="error">No se pudo cargar el personal.</Notice> : null}
      {toggleActive.isError || clearPin.isError ? (
        <Notice tone="error">No se pudo guardar el cambio.</Notice>
      ) : null}

      <ul className="m-0 flex list-none flex-col gap-2 p-0">
        {rows.map((p) => (
          <li key={p.id} className="flex flex-col gap-2 rounded-btn-lg border border-line p-3">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div className="flex min-w-0 flex-col">
                <span className="font-bold">
                  {p.full_name}
                  {p.active ? '' : ' · dado de baja'}
                </span>
                <span className="break-all text-[15px] text-muted">{p.email}</span>
                <span className="text-[15px] text-muted">
                  {p.roles.map((r) => ROLE_LABELS[r] ?? r).join(' · ')}
                </span>
              </div>
              <div className="flex flex-wrap gap-1.5">
                <span
                  className={`rounded-chip px-2.5 py-0.5 text-[13px] font-bold ${
                    p.pin_set_at ? 'bg-free-bg text-free-fg' : 'bg-wait-bg text-wait-fg'
                  }`}
                >
                  {p.pin_set_at ? 'Con PIN' : 'Sin PIN'}
                </span>
                <span className="rounded-chip border border-line px-2.5 py-0.5 text-[13px] font-bold text-muted">
                  {p.auth_user_id ? 'Ya entró' : 'No ha entrado'}
                </span>
              </div>
            </div>

            {editing === p.id ? (
              <PinForm person={p} onDone={() => setEditing(null)} />
            ) : (
              <div className="flex flex-wrap gap-2">
                {p.active ? (
                  <button
                    type="button"
                    className={buttonClass.secondary}
                    onClick={() => setEditing(p.id)}
                  >
                    {p.pin_set_at ? 'Cambiar PIN' : 'Asignar PIN'}
                  </button>
                ) : null}
                {p.pin_set_at ? (
                  <button
                    type="button"
                    className={buttonClass.secondary}
                    onClick={() => clearPin.mutate(p)}
                    disabled={clearPin.isPending}
                  >
                    Quitar PIN
                  </button>
                ) : null}
                {p.id !== me.id ? (
                  <button
                    type="button"
                    className={p.active ? buttonClass.danger : buttonClass.secondary}
                    onClick={() => {
                      if (
                        !p.active ||
                        window.confirm(`¿Dar de baja a ${p.full_name}? Ya no podrá entrar.`)
                      ) {
                        toggleActive.mutate(p);
                      }
                    }}
                    disabled={toggleActive.isPending}
                  >
                    {p.active ? 'Dar de baja' : 'Reactivar'}
                  </button>
                ) : null}
              </div>
            )}
          </li>
        ))}
      </ul>
    </Card>
  );
}
