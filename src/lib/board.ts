// Tablero de un grupo (RPC group_board) y la lógica de presentación que no decide nada:
// las reglas viven en Postgres; aquí solo se arman textos, etiquetas y cronómetros.
import type { Json } from './database.types';

export type ActiveStatus = 'group_wait' | 'queued' | 'called' | 'out' | 'arrived' | 'returning';
export type Sex = 'H' | 'M';

export type BoardPass = {
  id: string;
  student_id: string;
  list_number: number;
  full_name: string;
  sex: Sex;
  /** Grupo del alumno (en una clase por nivel el salón mezcla grupos). */
  group_name?: string;
  /** Salón de donde salió: el lugar del baño se cuenta por salón. */
  room_group_id?: string | null;
  status: ActiveStatus;
  destination_id: string;
  destination_kind: 'bathroom' | 'nurse';
  destination_label: string;
  requested_at: string;
  queue_ts: string | null;
  called_at: string | null;
  started_at: string | null;
  arrived_at: string | null;
  /** Cuando la enfermera lo mandó de regreso al salón. */
  left_nurse_at?: string | null;
  period_subject: string | null;
  opened_by_name: string | null;
  queue_position: number | null;
  waiting_for: { list_number: number; full_name: string } | null;
  alert?: {
    id: string;
    level: 1 | 2;
    acknowledged_by_name: string | null;
  } | null;
};

/** Baño en pausa (limpieza u otro motivo): no se piden pases y la fila no avanza. */
export type BathroomPause = { since: string; by: string | null; reason: string | null };

/** "Baño de hombres en pausa · Limpieza" */
export const pausedText = (label: string, p: BathroomPause) =>
  `${label} en pausa${p.reason ? ` · ${p.reason}` : ''}`;

/**
 * Tiempo de espera de quien está en fila: con el baño en pausa el reloj se detiene en el
 * momento de la pausa.
 */
export function waitElapsed(since: string, now: number, pause?: BathroomPause | null): number {
  const end = pause ? Math.min(now, new Date(pause.since).getTime()) : now;
  return Math.max(0, end - new Date(since).getTime());
}

export type Bathroom = {
  id: string;
  label: string;
  sex: Sex;
  capacity: number | null;
  paused?: BathroomPause | null;
  occupants: { group_name: string; own: boolean; status: 'called' | 'out'; since: string }[];
  queue: { group_name: string; own: boolean }[];
};

export type BoardSettings = {
  alert_minutes: number;
  confirm_turn_minutes: number;
  undo_seconds: number;
  auto_lock_after_class_minutes: number;
};

export type Board = {
  now: string;
  settings: BoardSettings;
  passes: BoardPass[];
  bathrooms: Bathroom[];
};

export const parseBoard = (raw: Json) => raw as unknown as Board;

export type StudentRef = {
  id: string;
  list_number: number;
  full_name: string;
  sex: Sex;
  /** Solo en clases por nivel: el grupo del alumno. */
  group_name?: string;
};

/**
 * En una clase por nivel la lista se numera aparte; los pases del tablero usan el número de
 * esa lista para que coincida con lo que el maestro ve y teclea.
 */
export function withListNumbers<B extends Board>(board: B, students: StudentRef[]): B {
  const num = new Map(students.map((s) => [s.id, s.list_number]));
  return {
    ...board,
    passes: board.passes.map((p) => ({
      ...p,
      list_number: num.get(p.student_id) ?? p.list_number,
    })),
  };
}

// ---------------------------------------------------------------------------
// Tiempo
// ---------------------------------------------------------------------------

/** Cronómetro hacia arriba: 06:12, 12:40, 1:05:09. */
export function formatElapsed(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const mm = String(m).padStart(2, '0');
  const ss = String(s).padStart(2, '0');
  return h ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

/** Cuenta regresiva corta: 1:42, 0:05. */
export function formatCountdown(ms: number): string {
  const total = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
}

const ms = (iso: string | null | undefined) => (iso ? new Date(iso).getTime() : NaN);

/** Milisegundos fuera del salón (desde started_at). */
export const elapsedMs = (p: BoardPass, now: number) => now - ms(p.started_at);

/** Milisegundos de regreso desde enfermería (desde left_nurse_at). */
export const returningMs = (p: BoardPass, now: number) => now - ms(p.left_nurse_at);

/** Tiempo que le queda al turno para confirmarse. */
export const turnLeftMs = (p: BoardPass, now: number, s: BoardSettings) =>
  ms(p.called_at) + s.confirm_turn_minutes * 60_000 - now;

/**
 * ¿Lleva más de alert_minutes fuera? Solo para pintar la tarjeta: las alertas reales las
 * genera tick(). En enfermería cuentan los trayectos: de ida (hasta "Llegó") y de regreso
 * al salón (desde que la enfermera lo manda hasta que el maestro marca su regreso).
 */
export const isOverdue = (p: BoardPass, now: number, s: BoardSettings) =>
  (p.status === 'out' && elapsedMs(p, now) >= s.alert_minutes * 60_000) ||
  (p.status === 'returning' && returningMs(p, now) >= s.alert_minutes * 60_000);

// ---------------------------------------------------------------------------
// Lugares del grupo
// ---------------------------------------------------------------------------

/** El pase que ocupa el lugar del grupo para ese sexo (en fila, con turno o fuera). */
export function slotPass(passes: BoardPass[], sex: Sex, roomId?: string): BoardPass | undefined {
  return passes.find(
    (p) =>
      p.destination_kind === 'bathroom' &&
      p.sex === sex &&
      (!roomId || !p.room_group_id || p.room_group_id === roomId) &&
      (p.status === 'out' || p.status === 'called' || p.status === 'queued'),
  );
}

export const nursePasses = (passes: BoardPass[]) =>
  passes.filter((p) => p.destination_kind === 'nurse');

export const turnPasses = (passes: BoardPass[]) => passes.filter((p) => p.status === 'called');

export const passForStudent = (passes: BoardPass[], studentId: string) =>
  passes.find((p) => p.student_id === studentId);

export const bathroomFor = (board: Board, sex: Sex) => board.bathrooms.find((b) => b.sex === sex);

export function occupancy(b: Bathroom) {
  return b.occupants.length;
}

// ---------------------------------------------------------------------------
// Etiquetas (siempre con texto: el color nunca es la única señal)
// ---------------------------------------------------------------------------

export type Tone = 'out' | 'wait' | 'alert' | 'nurse' | 'free';

export function passTag(
  p: BoardPass,
  now: number,
  s: BoardSettings,
): { label: string; tone: Tone } {
  if (p.destination_kind === 'nurse') {
    if (p.status === 'arrived') return { label: 'En atención', tone: 'nurse' };
    if (p.status === 'returning') {
      return isOverdue(p, now, s)
        ? { label: `Alerta · de regreso ${formatElapsed(returningMs(p, now))}`, tone: 'alert' }
        : { label: `De regreso · ${formatElapsed(returningMs(p, now))}`, tone: 'wait' };
    }
    if (isOverdue(p, now, s))
      return { label: `Alerta · ${formatElapsed(elapsedMs(p, now))}`, tone: 'alert' };
    return { label: `Enfermería · ${formatElapsed(elapsedMs(p, now))}`, tone: 'nurse' };
  }
  switch (p.status) {
    case 'out':
      return isOverdue(p, now, s)
        ? { label: `Alerta · ${formatElapsed(elapsedMs(p, now))}`, tone: 'alert' }
        : { label: `Fuera · ${formatElapsed(elapsedMs(p, now))}`, tone: 'out' };
    case 'called':
      return { label: `Su turno · ${formatCountdown(turnLeftMs(p, now, s))}`, tone: 'wait' };
    case 'queued':
      return { label: `En fila · lugar ${p.queue_position ?? '—'}`, tone: 'wait' };
    case 'group_wait':
      return {
        label: p.waiting_for ? `Espera · sale al regresar #${p.waiting_for.list_number}` : 'Espera',
        tone: 'wait',
      };
    default:
      return { label: '', tone: 'free' };
  }
}

const SEX_WORD: Record<Sex, { kid: string; one: string }> = {
  H: { kid: 'niño', one: 'un niño' },
  M: { kid: 'niña', one: 'una niña' },
};

export const sexLabel = (sex: Sex) => (sex === 'H' ? 'Niño' : 'Niña');

/**
 * Aviso que acompaña la opción "Baño" del menú: anticipa qué va a pasar. Es solo un aviso;
 * el resultado real lo decide request_pass en la BD.
 */
export function bathroomHint(
  student: StudentRef,
  board: Board,
  roomId?: string,
): { text: string; tone: 'free' | 'wait' | 'blocked' } {
  if (passForStudent(board.passes, student.id)) {
    return { text: 'Ya tiene un pase activo', tone: 'blocked' };
  }
  const bath = bathroomFor(board, student.sex);
  if (!bath) return { text: 'No hay baño configurado', tone: 'blocked' };
  if (bath.paused) return { text: pausedText(bath.label, bath.paused), tone: 'blocked' };
  // El lugar es por salón (en Inglés, el salón del nivel aunque mezcle grupos).
  const holder = slotPass(board.passes, student.sex, roomId);
  if (holder) {
    const who = `${holder.full_name} (#${holder.list_number})`;
    return holder.status === 'out'
      ? { text: `Queda en espera: ${who} sigue fuera. Sale en cuanto regrese.`, tone: 'wait' }
      : { text: `Queda en espera: ${who} está en la fila del baño.`, tone: 'wait' };
  }
  const occ = occupancy(bath);
  if (bath.capacity === null || (occ < bath.capacity && bath.queue.length === 0)) {
    const cap = bath.capacity === null ? '' : ` (${occ} de ${bath.capacity} ocupados)`;
    return { text: `${bath.label} · entra directo${cap}`, tone: 'free' };
  }
  const ahead = bath.queue.length;
  return {
    text: `${bath.label} lleno · queda en fila${ahead ? ` (${ahead} antes)` : ''}`,
    tone: 'wait',
  };
}

/** Mensaje para el toast después de pedir un pase, según lo que respondió la BD. */
export function requestMessage(
  student: StudentRef,
  status: ActiveStatus,
  groupName: string,
  extra: { label?: string; queuePosition?: number | null } = {},
): string {
  const name = student.full_name;
  switch (status) {
    case 'out':
      return extra.label === 'Enfermería'
        ? `${name} va a enfermería`
        : `${name} salió al ${(extra.label ?? 'baño').toLowerCase()}`;
    case 'queued':
      return `${name} quedó en fila${extra.queuePosition ? ` (lugar ${extra.queuePosition})` : ''}`;
    case 'group_wait':
      return `Ya hay ${SEX_WORD[student.sex].one} de ${groupName} fuera; ${name} quedó en espera`;
    case 'called':
      return `Turno de ${name}`;
    default:
      return name;
  }
}
