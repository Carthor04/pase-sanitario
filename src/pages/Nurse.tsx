import { useEffect, useId, useRef, useState } from 'react';
import { Loading, Notice, PageTitle } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { formatElapsed } from '@/lib/board';
import { playTurnSound, useAudioUnlock } from '@/lib/device';
import { errorMessage, useLivePasses, usePassAction, useServerNow } from '@/lib/live';
import { alertStatusText, hm, useAlertSound, useNurseToday, type NursePass } from '@/lib/monitor';
import { useStaff } from '@/lib/session';

/**
 * Enfermería en celular: en camino → Llegó; en enfermería → nota y Regresa al salón; de
 * regreso → el maestro marca su regreso al llegar al salón.
 */
export function Nurse() {
  const staff = useStaff();
  const today = useNurseToday();
  const online = useLivePasses();
  const action = usePassAction();
  const [error, setError] = useState<string | null>(null);
  useAudioUnlock();

  const data = today.data;
  const now = useServerNow(data?.offsetMs ?? 0);
  const passes = data?.passes ?? [];
  // Lista de espera: el que lleva más tiempo en camino primero.
  const onTheWay = passes
    .filter((p) => p.status === 'out')
    .sort((a, b) => (a.started_at ?? '').localeCompare(b.started_at ?? ''));
  const here = passes.filter((p) => p.status === 'arrived');
  const goingBack = passes.filter((p) => p.status === 'returning');
  const done = passes.filter((p) => p.status === 'returned' || p.status === 'released');
  useAlertSound(
    onTheWay.filter((p) => p.alert).map((p) => ({ id: p.alert!.id, level: p.alert!.level })),
  );
  // Suena cuando llega una solicitud nueva a la lista de espera.
  const waitingKey = onTheWay.map((p) => p.id).join(',');
  const seenWaiting = useRef<Set<string> | null>(null);
  useEffect(() => {
    const ids = new Set(waitingKey ? waitingKey.split(',') : []);
    if (seenWaiting.current && [...ids].some((id) => !seenWaiting.current!.has(id)))
      playTurnSound();
    seenWaiting.current = ids;
  }, [waitingKey]);

  const durations = done
    .filter((p) => p.started_at && p.ended_at)
    .map((p) => new Date(p.ended_at!).getTime() - new Date(p.started_at!).getTime());
  const avgMin = durations.length
    ? Math.round(durations.reduce((a, b) => a + b, 0) / durations.length / 60_000)
    : null;

  async function run(a: Parameters<typeof action.mutateAsync>[0]) {
    setError(null);
    try {
      await action.mutateAsync(a);
      return true;
    } catch (err) {
      setError(errorMessage(err));
      return false;
    }
  }

  if (today.isPending) return <Loading />;
  if (today.isError) return <Notice tone="error">{errorMessage(today.error)}</Notice>;

  return (
    <div className="flex max-w-[640px] flex-col gap-4">
      <PageTitle aside={<span className="text-[15px] text-muted">{staff.full_name}</span>}>
        Enfermería
      </PageTitle>
      {!online ? (
        <Notice tone="warn">Sin conexión en vivo: los datos pueden estar atrasados.</Notice>
      ) : null}
      {error ? <Notice tone="error">{error}</Notice> : null}

      <div className="grid grid-cols-3 gap-2" aria-label="Resumen">
        <Count label="En espera" value={onTheWay.length} tone="nurse" />
        <Count label="En atención" value={here.length} tone="ink" />
        <Count label="De regreso" value={goingBack.length} tone="wait" />
      </div>

      <Section title={`Lista de espera · ${onTheWay.length}`}>
        <p className="m-0 text-[14px] text-muted">
          Alumnos que un maestro mandó y vienen en camino, en orden de llegada. Toca
          &quot;Llegó&quot; cuando estén contigo.
        </p>
        {onTheWay.length === 0 ? <Empty>Nadie viene en camino</Empty> : null}
        <ol className="m-0 flex list-none flex-col gap-2 p-0">
          {onTheWay.map((p, i) => (
            <li
              key={p.id}
              className={`flex items-center gap-3 rounded-card border-2 bg-surface p-3 ${
                p.alert ? 'border-alert-bd bg-alert-bg' : 'border-nurse-bd'
              }`}
            >
              <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-nurse-bg font-bold text-nurse-fg">
                {i + 1}
              </span>
              <div className="flex min-w-0 flex-1 flex-col">
                <span className="truncate text-[17px] font-bold">
                  {p.full_name} · {p.group_name}
                </span>
                <span className="text-[13px] text-muted">
                  {p.period_subject ? `Salió de ${p.period_subject}` : 'Salió de clase'}
                  {p.opened_by_name ? ` · lo mandó ${p.opened_by_name}` : ''} · {hm(p.started_at)}
                </span>
                {p.alert ? (
                  <span className="text-[13px] font-bold text-alert-fg">
                    Alerta: no ha llegado · {alertStatusText(p.alert)}
                  </span>
                ) : null}
              </div>
              <span
                className={`font-mono text-[20px] font-semibold tabular-nums ${p.alert ? 'text-alert-fg' : ''}`}
              >
                {p.started_at ? formatElapsed(now - new Date(p.started_at).getTime()) : ''}
              </span>
              <button
                type="button"
                disabled={action.isPending}
                onClick={() => void run({ type: 'arrived', passId: p.id })}
                className="min-h-btn shrink-0 rounded-btn bg-accent px-4 text-[16px] font-bold text-white disabled:opacity-50"
              >
                Llegó
              </button>
            </li>
          ))}
        </ol>
      </Section>

      <Section title={`En atención · ${here.length}`}>
        {here.length === 0 ? <Empty>Nadie en atención</Empty> : null}
        {here.map((p) => (
          <HereCard key={p.id} p={p} now={now} busy={action.isPending} run={run} />
        ))}
      </Section>

      {goingBack.length ? (
        <Section title={`De regreso al salón · ${goingBack.length}`}>
          <p className="m-0 text-[14px] text-muted">
            Ya salieron de enfermería; su maestro marca el regreso cuando lleguen al salón.
          </p>
          {goingBack.map((p) => (
            <div
              key={p.id}
              className={`flex flex-col gap-1 rounded-card border-2 bg-surface p-3 ${
                p.alert ? 'border-alert-bd bg-alert-bg' : 'border-wait-bd'
              }`}
            >
              <Head
                p={p}
                now={now}
                since={p.left_nurse_at}
                sub={`salió de enfermería ${hm(p.left_nurse_at)}`}
              />
              {p.alert ? (
                <span className="text-[14px] font-bold text-alert-fg">
                  Alerta: no ha llegado al salón · {alertStatusText(p.alert)}
                </span>
              ) : null}
            </div>
          ))}
        </Section>
      ) : null}

      {done.length ? (
        <Section title={`Atendidos hoy · ${done.length}`}>
          <ul className="m-0 flex list-none flex-col gap-1.5 p-0">
            {done.map((p) => (
              <li
                key={p.id}
                className="flex flex-wrap justify-between gap-2 rounded-btn border border-line bg-surface px-3 py-2 text-[15px]"
              >
                <span>
                  <strong>{p.full_name}</strong> · {p.group_name}
                  {p.note ? <span className="text-muted"> · {p.note}</span> : null}
                </span>
                <span className="font-mono tabular-nums text-muted">
                  {hm(p.started_at)}–{hm(p.ended_at)}
                </span>
              </li>
            ))}
          </ul>
        </Section>
      ) : null}

      <div className="flex justify-between rounded-card border border-line bg-surface px-4 py-3 text-[15px]">
        <span>
          Hoy atendidos <strong>{done.length + here.length + goingBack.length}</strong>
        </span>
        <span>
          Promedio <strong>{avgMin === null ? '—' : `${avgMin} min`}</strong>
        </span>
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-2">
      <h2 className="m-0 text-[13px] font-bold uppercase tracking-[0.08em] text-muted">{title}</h2>
      {children}
    </section>
  );
}

const Empty = ({ children }: { children: string }) => (
  <p className="m-0 rounded-card border border-dashed border-line-strong px-4 py-3 text-muted">
    {children}
  </p>
);

function Head({
  p,
  now,
  since,
  sub,
}: {
  p: NursePass;
  now: number;
  since: string | null;
  sub: string;
}) {
  return (
    <div className="flex items-start justify-between gap-3">
      <div className="flex min-w-0 flex-col">
        <span className="truncate text-[20px] font-bold">{p.full_name}</span>
        <span className="text-[14px] text-muted">
          {p.group_name} · {sub}
        </span>
      </div>
      <span className="font-mono text-[26px] font-semibold tabular-nums">
        {since ? formatElapsed(now - new Date(since).getTime()) : ''}
      </span>
    </div>
  );
}

function HereCard({
  p,
  now,
  busy,
  run,
}: {
  p: NursePass;
  now: number;
  busy: boolean;
  run: (a: Parameters<ReturnType<typeof usePassAction>['mutateAsync']>[0]) => Promise<boolean>;
}) {
  const id = useId();
  const [note, setNote] = useState(p.note ?? '');
  const [saved, setSaved] = useState(false);
  useEffect(() => setNote(p.note ?? ''), [p.note]);
  const dirty = note.trim() !== (p.note ?? '').trim() && note.trim() !== '';

  async function returnToClass() {
    if (dirty && !(await run({ type: 'note', passId: p.id, body: note }))) return;
    await run({ type: 'sendBack', passId: p.id });
  }

  return (
    <div className="flex flex-col gap-3 rounded-card border border-line bg-surface p-4">
      <Head p={p} now={now} since={p.arrived_at} sub={`en atención desde ${hm(p.arrived_at)}`} />
      <label htmlFor={id} className="text-[15px] font-bold">
        Nota (opcional, solo personal)
      </label>
      <textarea
        id={id}
        rows={2}
        maxLength={500}
        value={note}
        onChange={(e) => {
          setNote(e.target.value);
          setSaved(false);
        }}
        placeholder="Ej. Dolor de cabeza, se le dio agua y reposo."
        className="rounded-btn border border-line-strong p-3 text-[16px]"
      />
      <div className="grid grid-cols-2 gap-2">
        <button
          type="button"
          disabled={busy || !dirty}
          onClick={async () => setSaved(await run({ type: 'note', passId: p.id, body: note }))}
          className={buttonClass.secondary}
        >
          {saved ? 'Nota guardada' : 'Guardar nota'}
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => void returnToClass()}
          className="min-h-btn rounded-btn bg-ink px-4 text-[16px] font-bold text-white disabled:opacity-60"
        >
          Regresa al salón
        </button>
      </div>
    </div>
  );
}

function Count({
  label,
  value,
  tone,
}: {
  label: string;
  value: number;
  tone: 'nurse' | 'ink' | 'wait';
}) {
  const color = tone === 'nurse' ? 'text-nurse-fg' : tone === 'wait' ? 'text-wait-fg' : 'text-ink';
  return (
    <div className="flex flex-col rounded-card border border-line bg-surface px-3 py-2">
      <span className="text-[12px] font-bold uppercase tracking-[0.06em] text-muted">{label}</span>
      <span className={`font-mono text-[28px] font-semibold tabular-nums ${color}`}>{value}</span>
    </div>
  );
}
