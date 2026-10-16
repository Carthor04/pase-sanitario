import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useId, useState, type FormEvent } from 'react';
import { Card, Loading, Notice, SectionLabel } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { useGroups } from '@/lib/queries';
import { supabase } from '@/lib/supabase';

type Row = { id: string; list_number: number; full_name: string; sex: 'H' | 'M'; active: boolean };
type Draft = { list_number: string; full_name: string; sex: 'H' | 'M' };

const inputClass = 'min-h-btn rounded-btn border border-line-strong bg-surface px-3 text-[16px]';

/** Error de Supabase → mensaje claro. */
function friendly(
  err: { code?: string; message?: string } | null,
  what: 'alumno' | 'grupo',
): string {
  if (!err) return '';
  if (err.code === '23505') {
    return what === 'alumno'
      ? 'Ya hay un alumno activo con ese número de lista en el grupo.'
      : 'Ya existe un grupo con ese nombre.';
  }
  if (err.code === '23514') return 'Revisa los datos: número de lista de 1 a 99 y nombre no vacío.';
  return err.message ?? 'No se pudo guardar.';
}

/**
 * Configuración → Alumnos: la lista de cada grupo con agregar, editar y quitar. Quitar es
 * "dar de baja" (no se borra: el historial del alumno se conserva y se puede reactivar).
 */
export function StudentsPanel() {
  const queryClient = useQueryClient();
  const groups = useGroups();
  const ids = { group: useId() };
  const [groupId, setGroupId] = useState('');
  const selected = groupId || groups.data?.[0]?.id || '';
  const group = groups.data?.find((g) => g.id === selected);
  const [msg, setMsg] = useState<{ tone: 'ok' | 'error'; text: string } | null>(null);
  const [editing, setEditing] = useState<string | null>(null);
  const [showInactive, setShowInactive] = useState(false);
  const [groupForm, setGroupForm] = useState<'new' | 'edit' | null>(null);

  const students = useQuery({
    queryKey: ['students-admin', selected],
    enabled: Boolean(selected),
    queryFn: async () => {
      const { data, error } = await supabase
        .from('students')
        .select('id, list_number, full_name, sex, active')
        .eq('group_id', selected)
        .order('list_number')
        .order('full_name');
      if (error) throw error;
      return data as Row[];
    },
  });

  async function refresh() {
    await Promise.all(
      ['students-admin', 'students', 'groups', 'my_groups', 'board'].map((k) =>
        queryClient.invalidateQueries({ queryKey: [k] }),
      ),
    );
  }

  async function save(id: string | null, d: Draft) {
    setMsg(null);
    const n = Number(d.list_number);
    if (!Number.isInteger(n) || n < 1 || n > 99) {
      setMsg({ tone: 'error', text: 'El número de lista debe ser de 1 a 99.' });
      return false;
    }
    if (!d.full_name.trim()) {
      setMsg({ tone: 'error', text: 'Escribe el nombre completo.' });
      return false;
    }
    const row = { list_number: n, full_name: d.full_name.trim().replace(/\s+/g, ' '), sex: d.sex };
    const { error } = id
      ? await supabase.from('students').update(row).eq('id', id)
      : await supabase.from('students').insert({ ...row, group_id: selected });
    if (error) {
      setMsg({ tone: 'error', text: friendly(error, 'alumno') });
      return false;
    }
    setMsg({
      tone: 'ok',
      text: id ? 'Alumno actualizado.' : `${row.full_name} agregado a ${group?.name}.`,
    });
    await refresh();
    return true;
  }

  async function setActive(r: Row, active: boolean) {
    if (!active && !window.confirm(`¿Dar de baja a ${r.full_name}? Su historial se conserva.`))
      return;
    setMsg(null);
    const { error } = await supabase.from('students').update({ active }).eq('id', r.id);
    if (error) {
      setMsg({
        tone: 'error',
        text:
          error.code === '23505'
            ? `No se puede reactivar: el número ${r.list_number} ya lo tiene otro alumno. Cámbiale el número primero.`
            : friendly(error, 'alumno'),
      });
      return;
    }
    setMsg({
      tone: 'ok',
      text: active ? `${r.full_name} reactivado.` : `${r.full_name} dado de baja.`,
    });
    await refresh();
  }

  const active = (students.data ?? []).filter((r) => r.active);
  const inactive = (students.data ?? []).filter((r) => !r.active);
  const nextNumber = Math.min(99, Math.max(0, ...active.map((r) => r.list_number)) + 1);

  if (groups.isPending) return <Loading />;

  return (
    <Card>
      <div className="flex flex-wrap items-end justify-between gap-3">
        <SectionLabel>Listas de los grupos</SectionLabel>
        <div className="flex flex-wrap items-end gap-2">
          <div className="flex flex-col gap-1">
            <label htmlFor={ids.group} className="text-[14px] font-bold">
              Grupo
            </label>
            <select
              id={ids.group}
              value={selected}
              onChange={(e) => {
                setGroupId(e.target.value);
                setEditing(null);
                setMsg(null);
              }}
              className={`${inputClass} min-w-[120px] font-bold`}
            >
              {groups.data?.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </select>
          </div>
          <button
            type="button"
            className={buttonClass.secondary}
            onClick={() => setGroupForm('edit')}
          >
            Editar grupo
          </button>
          <button
            type="button"
            className={buttonClass.secondary}
            onClick={() => setGroupForm('new')}
          >
            Nuevo grupo
          </button>
        </div>
      </div>

      {groupForm ? (
        <GroupForm
          group={groupForm === 'edit' ? group : undefined}
          onDone={async (newId, text) => {
            setGroupForm(null);
            if (newId) setGroupId(newId);
            if (text) setMsg({ tone: 'ok', text });
            await refresh();
          }}
        />
      ) : null}

      {msg ? <Notice tone={msg.tone}>{msg.text}</Notice> : null}

      <span className="text-[15px] text-muted">
        {group?.name}
        {group?.room ? ` · ${group.room}` : ''} · {active.length} alumnos
      </span>

      {students.isPending ? <Loading /> : null}
      <ol className="m-0 flex list-none flex-col gap-1.5 p-0">
        {active.map((r) =>
          editing === r.id ? (
            <li key={r.id}>
              <StudentForm
                initial={{ list_number: String(r.list_number), full_name: r.full_name, sex: r.sex }}
                submitLabel="Guardar"
                onSubmit={async (d) => {
                  if (await save(r.id, d)) setEditing(null);
                }}
                onCancel={() => setEditing(null)}
              />
            </li>
          ) : (
            <li
              key={r.id}
              className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-btn-lg border border-line px-3 py-2"
            >
              <span className="w-7 text-right font-mono font-semibold tabular-nums text-muted">
                {r.list_number}
              </span>
              <span className="min-w-0 flex-1 break-words font-bold">{r.full_name}</span>
              <span
                className="rounded-[6px] border border-line px-1.5 text-[13px] font-bold text-muted"
                aria-label={r.sex === 'H' ? 'Hombre' : 'Mujer'}
              >
                {r.sex}
              </span>
              <span className="flex gap-1.5">
                <button
                  type="button"
                  className={`${buttonClass.secondary} min-h-touch px-3 text-[14px]`}
                  onClick={() => setEditing(r.id)}
                >
                  Editar
                </button>
                <button
                  type="button"
                  className={`${buttonClass.danger} min-h-touch px-3 text-[14px]`}
                  onClick={() => void setActive(r, false)}
                >
                  Quitar
                </button>
              </span>
            </li>
          ),
        )}
      </ol>
      {students.data && active.length === 0 ? (
        <span className="text-muted">Este grupo no tiene alumnos todavía.</span>
      ) : null}

      <div className="flex flex-col gap-2 rounded-card border border-dashed border-line-strong p-3">
        <span className="font-bold">Agregar alumno a {group?.name}</span>
        <StudentForm
          key={`${selected}-${nextNumber}`}
          initial={{ list_number: String(nextNumber), full_name: '', sex: 'H' }}
          submitLabel="Agregar"
          onSubmit={async (d) => {
            await save(null, d);
          }}
        />
      </div>

      {inactive.length ? (
        <div className="flex flex-col gap-1.5">
          <button
            type="button"
            className="min-h-touch self-start text-[15px] font-bold text-accent"
            onClick={() => setShowInactive((v) => !v)}
            aria-expanded={showInactive}
          >
            {showInactive ? 'Ocultar' : 'Ver'} dados de baja ({inactive.length})
          </button>
          {showInactive
            ? inactive.map((r) => (
                <div
                  key={r.id}
                  className="flex flex-wrap items-center gap-3 rounded-btn-lg border border-line bg-ground px-3 py-2"
                >
                  <span className="w-7 text-right font-mono tabular-nums text-muted">
                    {r.list_number}
                  </span>
                  <span className="min-w-0 flex-1 text-muted line-through">{r.full_name}</span>
                  <button
                    type="button"
                    className={`${buttonClass.secondary} min-h-touch px-3 text-[14px]`}
                    onClick={() => void setActive(r, true)}
                  >
                    Reactivar
                  </button>
                </div>
              ))
            : null}
        </div>
      ) : null}
    </Card>
  );
}

function StudentForm({
  initial,
  submitLabel,
  onSubmit,
  onCancel,
}: {
  initial: Draft;
  submitLabel: string;
  onSubmit: (d: Draft) => Promise<void>;
  onCancel?: () => void;
}) {
  const ids = { n: useId(), name: useId(), sex: useId() };
  const [d, setD] = useState<Draft>(initial);
  const [busy, setBusy] = useState(false);
  useEffect(() => setD(initial), [initial.list_number, initial.full_name, initial.sex]); // eslint-disable-line react-hooks/exhaustive-deps

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    await onSubmit(d);
    setBusy(false);
    if (!onCancel) setD((x) => ({ ...x, full_name: '' }));
  }

  return (
    <form onSubmit={submit} className="flex flex-wrap items-end gap-2">
      <div className="flex flex-col gap-1">
        <label htmlFor={ids.n} className="text-[13px] font-bold">
          Núm.
        </label>
        <input
          id={ids.n}
          type="number"
          inputMode="numeric"
          min={1}
          max={99}
          required
          value={d.list_number}
          onChange={(e) => setD({ ...d, list_number: e.target.value })}
          className={`${inputClass} w-[76px] font-mono tabular-nums`}
        />
      </div>
      <div className="flex min-w-[200px] flex-1 flex-col gap-1">
        <label htmlFor={ids.name} className="text-[13px] font-bold">
          Nombre completo
        </label>
        <input
          id={ids.name}
          required
          value={d.full_name}
          onChange={(e) => setD({ ...d, full_name: e.target.value })}
          placeholder="Apellidos y nombres"
          className={inputClass}
        />
      </div>
      <div className="flex flex-col gap-1">
        <label htmlFor={ids.sex} className="text-[13px] font-bold">
          Sexo (baño)
        </label>
        <select
          id={ids.sex}
          value={d.sex}
          onChange={(e) => setD({ ...d, sex: e.target.value as 'H' | 'M' })}
          className={inputClass}
        >
          <option value="H">H · hombres</option>
          <option value="M">M · mujeres</option>
        </select>
      </div>
      <button type="submit" disabled={busy} className={buttonClass.primary}>
        {busy ? 'Guardando…' : submitLabel}
      </button>
      {onCancel ? (
        <button type="button" onClick={onCancel} className={buttonClass.secondary}>
          Cancelar
        </button>
      ) : null}
    </form>
  );
}

function GroupForm({
  group,
  onDone,
}: {
  group?: { id: string; name: string; room: string | null };
  onDone: (newId: string | null, message: string | null) => Promise<void>;
}) {
  const ids = { name: useId(), room: useId() };
  const [name, setName] = useState(group?.name ?? '');
  const [room, setRoom] = useState(group?.room ?? '');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    setBusy(true);
    setError(null);
    const values = { name: name.trim(), room: room.trim() || null };
    if (group) {
      const { error: err } = await supabase.from('groups').update(values).eq('id', group.id);
      setBusy(false);
      if (err) return setError(friendly(err, 'grupo'));
      await onDone(null, `Grupo ${values.name} actualizado.`);
    } else {
      const { data, error: err } = await supabase
        .from('groups')
        .insert({ ...values, sort: 100 })
        .select('id')
        .single();
      setBusy(false);
      if (err) return setError(friendly(err, 'grupo'));
      await onDone(data.id, `Grupo ${values.name} creado. Ahora agrega sus alumnos.`);
    }
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-2 rounded-card bg-ground p-3">
      <span className="font-bold">{group ? `Editar ${group.name}` : 'Nuevo grupo'}</span>
      <div className="flex flex-wrap items-end gap-2">
        <div className="flex flex-col gap-1">
          <label htmlFor={ids.name} className="text-[13px] font-bold">
            Nombre
          </label>
          <input
            id={ids.name}
            required
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="2°D"
            className={`${inputClass} w-[110px]`}
          />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor={ids.room} className="text-[13px] font-bold">
            Salón (opcional)
          </label>
          <input
            id={ids.room}
            value={room}
            onChange={(e) => setRoom(e.target.value)}
            placeholder="Salón 12"
            className={`${inputClass} w-[160px]`}
          />
        </div>
        <button type="submit" disabled={busy} className={buttonClass.primary}>
          Guardar
        </button>
        <button
          type="button"
          onClick={() => void onDone(null, null)}
          className={buttonClass.secondary}
        >
          Cancelar
        </button>
      </div>
      {error ? <Notice tone="error">{error}</Notice> : null}
    </form>
  );
}
