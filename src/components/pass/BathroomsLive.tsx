import { Loading, Notice } from '@/components/ui/Page';
import { formatElapsed } from '@/lib/board';
import { errorMessage, useBathrooms, useServerNow, type BathroomsStatus } from '@/lib/live';

type Variant = 'cards' | 'panel' | 'dark';

type Props = {
  /** cards: pantalla Baños · panel: columna de la compu del salón · dark: pantalla bloqueada. */
  variant?: Variant;
  /** Nombre del grupo propio, para resaltarlo. */
  ownGroup?: string;
  /** Minutos para pintar en rojo a quien lleva mucho tiempo dentro. */
  alertMinutes?: number;
  /** Solo la vista de diseño de desarrollo. */
  preview?: BathroomsStatus;
};

/** Lista en tiempo real de los baños: quién está dentro (por grupo) y quién está en fila. */
export function BathroomsLive({ variant = 'cards', ownGroup, alertMinutes = 10, preview }: Props) {
  const query = useBathrooms();
  const data = preview ?? query.data;
  const now = useServerNow(data?.offsetMs ?? 0);

  if (!data && query.isError) return <Notice tone="error">{errorMessage(query.error)}</Notice>;
  if (!data) return <Loading />;

  const dark = variant === 'dark';
  const wrap = variant === 'cards' ? 'grid gap-4 sm:grid-cols-2' : 'flex flex-col gap-3';

  return (
    <div className="flex flex-col gap-3">
      <div className={wrap}>
        {data.bathrooms.map((b) => (
          <Bathroom
            key={b.id}
            b={b}
            now={now}
            variant={variant}
            ownGroup={ownGroup}
            alertMs={alertMinutes * 60_000}
          />
        ))}
      </div>
      <span className={`text-[14px] ${dark ? 'text-white/80' : 'text-muted'}`}>
        Enfermería: {data.nurse} {data.nurse === 1 ? 'alumno' : 'alumnos'} ahora · no hace fila
      </span>
    </div>
  );
}

function Bathroom({
  b,
  now,
  variant,
  ownGroup,
  alertMs,
}: {
  b: BathroomsStatus['bathrooms'][number];
  now: number;
  variant: Variant;
  ownGroup?: string;
  alertMs: number;
}) {
  const dark = variant === 'dark';
  const compact = variant !== 'cards';
  const occ = b.occupants.length;
  const full = b.capacity !== null && occ >= b.capacity;
  const box = dark
    ? 'rounded-card border border-white/15 bg-white/5 text-white'
    : 'rounded-card border border-line bg-surface';
  const muted = dark ? 'text-white/70' : 'text-muted';
  const mine = (g: string) => ownGroup !== undefined && g === ownGroup;

  return (
    <section
      aria-label={b.label}
      className={`flex flex-col gap-2 ${compact ? 'p-3.5' : 'p-5'} ${box}`}
    >
      <div className="flex items-center justify-between gap-2">
        <h2 className={`m-0 font-display font-bold ${compact ? 'text-[18px]' : 'text-[22px]'}`}>
          {b.label}
        </h2>
        <span
          className={`rounded-chip px-2.5 py-0.5 text-[13px] font-bold ${
            full ? (dark ? 'bg-white text-ink' : 'bg-ink text-white') : 'bg-free-bg text-free-fg'
          }`}
        >
          {occ}
          {b.capacity !== null ? ` / ${b.capacity}` : ''} · {full ? 'Lleno' : 'Con lugar'}
        </span>
      </div>

      <div className="flex flex-col gap-1">
        <span className={`text-[12px] font-bold uppercase tracking-[0.08em] ${muted}`}>Dentro</span>
        {occ === 0 ? <span className={muted}>Nadie</span> : null}
        {b.occupants.map((o, i) => {
          const ms = now - new Date(o.since).getTime();
          const late = o.status === 'out' && ms >= alertMs;
          return (
            <span
              key={i}
              className={`flex items-center justify-between gap-2 rounded-btn px-3 py-1.5 ${
                late
                  ? 'border-2 border-alert-bd bg-alert-bg text-alert-fg'
                  : mine(o.group_name)
                    ? dark
                      ? 'border-2 border-white/60'
                      : 'border-2 border-ink'
                    : dark
                      ? 'border border-white/15'
                      : 'border border-line'
              }`}
            >
              <span className="font-bold">
                {o.group_name}
                {mine(o.group_name) ? ' · tu grupo' : ''}
              </span>
              <span className="font-mono tabular-nums">
                {o.status === 'called'
                  ? 'su turno'
                  : `${late ? 'Alerta · ' : ''}${formatElapsed(ms)}`}
              </span>
            </span>
          );
        })}
      </div>

      <div className="flex flex-col gap-1">
        <span
          className={`text-[12px] font-bold uppercase tracking-[0.08em] ${dark ? 'text-[#FFD08A]' : 'text-wait-fg'}`}
        >
          Fila · {b.queue.length}
        </span>
        {b.queue.length === 0 ? (
          <span className={dark ? 'text-[#8FE0B0]' : 'text-free-fg'}>
            {full ? 'Sin fila' : 'Sin fila: si sale alguien ahora, entra directo'}
          </span>
        ) : null}
        {b.queue.map((q, i) => (
          <span
            key={i}
            className={`flex items-center justify-between gap-2 rounded-btn px-3 py-1.5 ${
              dark ? 'border border-[#FFD08A]/40' : 'border border-wait-bd/50 bg-wait-bg/40'
            } ${mine(q.group_name) ? 'font-bold' : ''}`}
          >
            <span>
              {i + 1}. <strong>{q.group_name}</strong>
              {mine(q.group_name) ? ' · tu grupo' : ''}
            </span>
            <span className={`font-mono tabular-nums ${dark ? 'text-[#FFD08A]' : 'text-wait-fg'}`}>
              espera {formatElapsed(now - new Date(q.since).getTime())}
            </span>
          </span>
        ))}
        {b.group_wait ? (
          <span className={`text-[13px] ${muted}`}>{b.group_wait} en espera de su grupo</span>
        ) : null}
      </div>
    </section>
  );
}
