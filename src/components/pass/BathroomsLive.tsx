import { PauseBanner, PauseControl } from '@/components/pass/BathroomPause';
import { Loading, Notice } from '@/components/ui/Page';
import { formatElapsed, waitElapsed } from '@/lib/board';
import {
  errorMessage,
  isWaiting,
  useBathrooms,
  useServerNow,
  type BathroomsStatus,
  type WaitItem,
} from '@/lib/live';

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
  /** Al tocar a alguien que todavía no sale (solo llega con id para el personal). */
  onPick?: (item: WaitItem & { id: string }) => void;
  /** Muestra el botón para pausar o reanudar cada baño (pantalla Baños). */
  canPause?: boolean;
};

/**
 * Baños y enfermería en tiempo real: quién está dentro y quién espera. El personal ve
 * nombre, grupo y clase; la compu del salón (a la vista de los alumnos) solo el grupo.
 */
export function BathroomsLive({
  variant = 'cards',
  ownGroup,
  alertMinutes = 10,
  preview,
  onPick,
  canPause = false,
}: Props) {
  const query = useBathrooms();
  const data = preview ?? query.data;
  const now = useServerNow(data?.offsetMs ?? 0);

  if (!data && query.isError) return <Notice tone="error">{errorMessage(query.error)}</Notice>;
  if (!data) return <Loading />;

  const wrap =
    variant === 'cards' ? 'grid gap-4 md:grid-cols-2 xl:grid-cols-3' : 'flex flex-col gap-3';
  const ctx: Ctx = { now, variant, ownGroup, alertMs: alertMinutes * 60_000, onPick, canPause };

  return (
    <div className={wrap}>
      {data.bathrooms.map((b) => (
        <Bathroom key={b.id} b={b} ctx={ctx} />
      ))}
      <Nurse data={data} ctx={ctx} />
    </div>
  );
}

type Ctx = {
  now: number;
  variant: Variant;
  ownGroup?: string;
  alertMs: number;
  onPick?: Props['onPick'];
  canPause: boolean;
};

function box(variant: Variant) {
  return variant === 'dark'
    ? 'rounded-card border border-white/15 bg-white/5 text-white'
    : 'rounded-card border border-line bg-surface';
}

function Heading({
  text,
  tone,
  variant,
}: {
  text: string;
  tone: 'muted' | 'wait' | 'nurse';
  variant: Variant;
}) {
  const dark = variant === 'dark';
  const color =
    tone === 'wait'
      ? dark
        ? 'text-[#FFD08A]'
        : 'text-wait-fg'
      : tone === 'nurse'
        ? dark
          ? 'text-[#A9C4F0]'
          : 'text-nurse-fg'
        : dark
          ? 'text-white/70'
          : 'text-muted';
  return (
    <span className={`text-[12px] font-bold uppercase tracking-[0.08em] ${color}`}>{text}</span>
  );
}

/** Un renglón: posición, alumno (o grupo), clase y tiempo. */
function Row({
  item,
  ctx,
  position,
  timeLabel,
  late,
  tone,
}: {
  item: WaitItem;
  ctx: Ctx;
  position?: number;
  timeLabel: string;
  late?: boolean;
  tone: 'plain' | 'wait' | 'nurse';
}) {
  const dark = ctx.variant === 'dark';
  const mine = ctx.ownGroup !== undefined && item.group_name === ctx.ownGroup;
  const frame = late
    ? 'border-2 border-alert-bd bg-alert-bg text-alert-fg'
    : mine
      ? dark
        ? 'border-2 border-white/60'
        : 'border-2 border-ink'
      : tone === 'wait'
        ? dark
          ? 'border border-[#FFD08A]/40'
          : 'border border-wait-bd/50 bg-wait-bg/40'
        : tone === 'nurse'
          ? dark
            ? 'border border-[#A9C4F0]/40'
            : 'border border-nurse-bd/50'
          : dark
            ? 'border border-white/15'
            : 'border border-line';
  const detail = item.full_name
    ? [
        item.subject ? `salió en ${item.subject}` : null,
        item.opened_by ? `autorizó ${item.opened_by}` : null,
      ]
        .filter(Boolean)
        .join(' · ')
    : '';
  const body = (
    <>
      <span className="flex min-w-0 flex-col">
        <span className="truncate">
          {position ? `${position}. ` : ''}
          {item.full_name ? (
            <>
              <strong>{item.full_name}</strong> · {item.group_name}
            </>
          ) : (
            <strong>{item.group_name}</strong>
          )}
          {mine ? ' · tu grupo' : ''}
        </span>
        {detail ? (
          <span
            className={`truncate text-[12px] ${late ? '' : dark ? 'text-white/70' : 'text-muted'}`}
          >
            {detail}
          </span>
        ) : null}
      </span>
      <span className="shrink-0 font-mono tabular-nums">{timeLabel}</span>
    </>
  );
  const { onPick } = ctx;
  const id = item.id;
  if (onPick && id && isWaiting(item.status)) {
    return (
      <button
        type="button"
        onClick={() => onPick({ ...item, id })}
        className={`flex min-h-btn items-center justify-between gap-2 rounded-btn px-3 py-1.5 text-left ${frame}`}
      >
        {body}
      </button>
    );
  }
  return (
    <span className={`flex items-center justify-between gap-2 rounded-btn px-3 py-1.5 ${frame}`}>
      {body}
    </span>
  );
}

function Bathroom({ b, ctx }: { b: BathroomsStatus['bathrooms'][number]; ctx: Ctx }) {
  const { now, variant } = ctx;
  const dark = variant === 'dark';
  const compact = variant !== 'cards';
  const occ = b.occupants.length;
  const full = b.capacity !== null && occ >= b.capacity;
  const muted = dark ? 'text-white/70' : 'text-muted';
  const pause = b.paused ?? null;
  const pausedMark = pause ? '⏸ ' : '';

  return (
    <section
      aria-label={b.label}
      className={`flex min-w-0 flex-col gap-2 ${compact ? 'p-3.5' : 'p-5'} ${box(variant)}`}
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

      {variant === 'cards' ? (
        <PauseControl destination={b.id} label={b.label} pause={pause} canControl={ctx.canPause} />
      ) : pause ? (
        <PauseBanner pause={pause} dark={dark} />
      ) : null}

      <div className="flex flex-col gap-1">
        <Heading text="Dentro" tone="muted" variant={variant} />
        {occ === 0 ? <span className={muted}>Nadie</span> : null}
        {b.occupants.map((o, i) => {
          const ms = now - new Date(o.since).getTime();
          const late = o.status === 'out' && ms >= ctx.alertMs;
          return (
            <Row
              key={i}
              item={o}
              ctx={ctx}
              tone="plain"
              late={late}
              timeLabel={
                o.status === 'called'
                  ? `${pausedMark}su turno`
                  : `${late ? 'Alerta · ' : ''}${formatElapsed(ms)}`
              }
            />
          );
        })}
      </div>

      <div className="flex flex-col gap-1">
        <Heading text={`Lista de espera · ${b.queue.length}`} tone="wait" variant={variant} />
        {b.queue.length === 0 ? (
          <span className={dark ? 'text-[#8FE0B0]' : 'text-free-fg'}>
            {pause || full ? 'Sin fila' : 'Sin fila: si sale alguien ahora, entra directo'}
          </span>
        ) : null}
        {b.queue.map((q, i) => (
          <Row
            key={i}
            item={q}
            ctx={ctx}
            position={i + 1}
            tone="wait"
            timeLabel={`${pausedMark}espera ${formatElapsed(waitElapsed(q.since, now, pause))}`}
          />
        ))}
        {b.group_wait_list?.length ? (
          <>
            <Heading text="Esperan a su grupo" tone="muted" variant={variant} />
            {b.group_wait_list.map((q, i) => (
              <Row
                key={i}
                item={q}
                ctx={ctx}
                tone="plain"
                timeLabel={`${pausedMark}${formatElapsed(waitElapsed(q.since, now, pause))}`}
              />
            ))}
          </>
        ) : b.group_wait ? (
          <span className={`text-[13px] ${muted}`}>{b.group_wait} en espera de su grupo</span>
        ) : null}
      </div>
    </section>
  );
}

function Nurse({ data, ctx }: { data: BathroomsStatus; ctx: Ctx }) {
  const { now, variant } = ctx;
  const compact = variant !== 'cards';
  const muted = variant === 'dark' ? 'text-white/70' : 'text-muted';
  const queue = data.nurse_queue ?? [];
  const care = data.nurse_care ?? [];
  const back = data.nurse_returning ?? [];

  return (
    <section
      aria-label="Enfermería"
      className={`flex min-w-0 flex-col gap-2 ${compact ? 'p-3.5' : 'p-5'} ${box(variant)}`}
    >
      <div className="flex items-center justify-between gap-2">
        <h2 className={`m-0 font-display font-bold ${compact ? 'text-[18px]' : 'text-[22px]'}`}>
          Enfermería
        </h2>
        <span className="rounded-chip bg-nurse-bg px-2.5 py-0.5 text-[13px] font-bold text-nurse-fg">
          {care.length} en atención
        </span>
      </div>

      <div className="flex flex-col gap-1">
        <Heading text={`Lista de espera · ${queue.length}`} tone="nurse" variant={variant} />
        {queue.length === 0 ? <span className={muted}>Nadie en camino</span> : null}
        {queue.map((q, i) => {
          const ms = now - new Date(q.since).getTime();
          const late = ms >= ctx.alertMs;
          return (
            <Row
              key={i}
              item={q}
              ctx={ctx}
              position={i + 1}
              tone="nurse"
              late={late}
              timeLabel={`${late ? 'Alerta · ' : 'en camino '}${formatElapsed(ms)}`}
            />
          );
        })}
      </div>

      {care.length ? (
        <div className="flex flex-col gap-1">
          <Heading text={`En atención · ${care.length}`} tone="muted" variant={variant} />
          {care.map((q, i) => (
            <Row
              key={i}
              item={q}
              ctx={ctx}
              tone="plain"
              timeLabel={formatElapsed(now - new Date(q.since).getTime())}
            />
          ))}
        </div>
      ) : null}

      {back.length ? (
        <div className="flex flex-col gap-1">
          <Heading text={`De regreso al salón · ${back.length}`} tone="wait" variant={variant} />
          {back.map((q, i) => {
            const ms = now - new Date(q.since).getTime();
            const late = ms >= ctx.alertMs;
            return (
              <Row
                key={i}
                item={q}
                ctx={ctx}
                tone="wait"
                late={late}
                timeLabel={`${late ? 'Alerta · ' : ''}${formatElapsed(ms)}`}
              />
            );
          })}
        </div>
      ) : null}
    </section>
  );
}
