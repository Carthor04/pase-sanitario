// Historial FICTICIO para presentar reportes (solo grupos de ejemplo, nunca 2°C).
//   node scripts/demo-history.mjs            → borra el historial de ejemplo anterior y carga uno nuevo
//   node scripts/demo-history.mjs --limpiar  → solo borra el historial de ejemplo
// Cada pase lleva {"ejemplo": true} en su evento "requested"; así se identifica para borrarlo.
// Respeta las reglas (1 niño y 3 niñas dentro a la vez, fila, un lugar por grupo y sexo) y
// usa como "autorizó" al maestro que tenía clase según el horario. Incluye incidencias:
// alumnos con alertas, con demasiadas salidas, con visitas frecuentes a enfermería y un
// lugar liberado por prefectura. Los avisos push se desactivan mientras se carga.
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { connectionString } from './db-connection.mjs';

const DAYS = [
  '2026-10-05',
  '2026-10-06',
  '2026-10-07',
  '2026-10-08',
  '2026-10-09',
  '2026-10-12',
  '2026-10-13',
  '2026-10-14',
  '2026-10-15',
];
const EXCLUDE_GROUPS = ['2°C']; // grupo real del piloto
const ALERT_MIN = 10;
const PER_DAY = { bath_h: 44, bath_m: 38, nurse: 6 };
const CAPACITY = { bath_h: 1, bath_m: 3 };
// Peso relativo por hora de clase (más salidas a media mañana).
const HOUR_WEIGHT = { 7: 2, 8: 5, 9: 7, 10: 11, 11: 9, 12: 7, 13: 5 };
const NOTES = [
  'Dolor de cabeza, agua y reposo.',
  'Dolor de estómago; se le dio té.',
  'Raspón en la rodilla, se limpió y vendó.',
  'Mareo leve; recostado 15 min.',
  'Se tomó la temperatura: normal.',
];

let seed = 20261015;
const rnd = () => {
  seed |= 0;
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = (a) => a[Math.floor(rnd() * a.length)];
const between = (a, b) => a + rnd() * (b - a);
const MIN = 60_000;

/** Hora de México → Date (México no cambia de horario: UTC−6). */
const at = (day, minutes) => new Date(Date.parse(`${day}T00:00:00-06:00`) + minutes * MIN);
const toMin = (t) => {
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
};

const c = new pg.Client({
  connectionString: connectionString(),
  ssl: { rejectUnauthorized: false },
});
await c.connect();

async function clean() {
  const ids = `(select pass_id from public.pass_events where type = 'requested' and payload ->> 'ejemplo' = 'true')`;
  await c.query(`delete from public.nurse_notes where pass_id in ${ids}`);
  await c.query(`delete from public.notifications_outbox where pass_id in ${ids}`);
  await c.query(`delete from public.alerts where pass_id in ${ids}`);
  await c.query(`create temporary table ejemplo as ${ids.slice(1, -1)}`);
  await c.query('delete from public.pass_events where pass_id in (select pass_id from ejemplo)');
  const r = await c.query('delete from public.passes where id in (select pass_id from ejemplo)');
  await c.query('drop table ejemplo');
  return r.rowCount;
}

await c.query('begin');
try {
  const removed = await clean();
  if (process.argv.includes('--limpiar')) {
    await c.query('commit');
    console.log(`Historial de ejemplo borrado: ${removed} pases.`);
    process.exit(0);
  }

  const { rows: students } = await c.query(
    `select s.id, s.group_id, g.name as group_name, s.sex, s.list_number, s.full_name
       from public.students s join public.groups g on g.id = s.group_id
      where s.active and g.name <> all ($1)`,
    [EXCLUDE_GROUPS],
  );
  const { rows: schedule } = await c.query(
    `select se.group_id, p.weekday, p.starts::text, p.ends::text, se.subject, se.teacher_id
       from public.schedule_entries se join public.periods p on p.id = se.period_id`,
  );
  const staffId = async (email) =>
    (await c.query('select id from public.staff where email = $1', [email])).rows[0]?.id;
  const prefect = await staffId('juan.perez@colegio.edu.mx');
  const nurse = await staffId('rosa.campos@colegio.edu.mx');
  if (!students.length || !prefect || !nurse)
    throw new Error('Faltan los datos de ejemplo del seed.');

  const classAt = (groupId, day, minute) => {
    const wd = new Date(`${day}T12:00:00Z`).getUTCDay();
    return schedule.find(
      (e) =>
        e.group_id === groupId &&
        e.weekday === wd &&
        toMin(e.starts) <= minute &&
        minute < toMin(e.ends),
    );
  };
  // Minuto de solicitud dentro de una clase (no en receso), con más peso a media mañana.
  const requestMinute = (groupId, day) => {
    for (let i = 0; i < 50; i++) {
      const hours = Object.entries(HOUR_WEIGHT);
      let r = rnd() * hours.reduce((s, [, w]) => s + w, 0);
      const [h] = hours.find(([, w]) => (r -= w) < 0) ?? hours[0];
      const m = Number(h) * 60 + Math.floor(rnd() * 60);
      if (classAt(groupId, day, m)) return m;
    }
    return null;
  };

  // Incidencias fijas.
  const bySexGroup = (sex, group) =>
    students.filter((s) => s.sex === sex && s.group_name === group);
  const alertKid = bySexGroup('M', '2°B')[3]; // varias alertas
  const frequentKid = bySexGroup('H', '3°A')[2]; // demasiadas salidas
  const nurseKid = bySexGroup('H', '3°C')[4]; // visitas frecuentes a enfermería
  const alertKid2 = bySexGroup('H', '1°C')[1]; // dos alertas

  const passes = [];
  const events = [];
  const alerts = [];
  const notes = [];
  const busy = new Map(); // alumno → [inicio, fin][]
  const free = (sid, a, b) => !(busy.get(sid) ?? []).some(([x, y]) => a < y && x < b);
  const mark = (sid, a, b) => busy.set(sid, [...(busy.get(sid) ?? []), [a, b]]);

  for (const day of DAYS) {
    const thisWeek = day >= '2026-10-12';
    for (const dest of ['bath_h', 'bath_m']) {
      const sex = dest === 'bath_h' ? 'H' : 'M';
      const pool = students.filter((s) => s.sex === sex);
      const reqs = [];
      const n = Math.round(PER_DAY[dest] * between(0.85, 1.15));
      for (let i = 0; i < n; i++) {
        const st = pick(pool);
        const m = requestMinute(st.group_id, day);
        if (m !== null) reqs.push({ st, m, dur: between(2, 7.5) });
      }
      // Incidencias de este baño.
      if (sex === 'H' && thisWeek) {
        for (let k = 0; k < 3; k++) {
          const m = requestMinute(frequentKid.group_id, day);
          if (m !== null) reqs.push({ st: frequentKid, m, dur: between(4, 8) });
        }
      }
      if (sex === 'M' && ['2026-10-12', '2026-10-13', '2026-10-15'].includes(day)) {
        const m = requestMinute(alertKid.group_id, day);
        if (m !== null) reqs.push({ st: alertKid, m, dur: between(12, 15) });
      }
      if (sex === 'H' && ['2026-10-13', '2026-10-14'].includes(day)) {
        const m = requestMinute(alertKid2.group_id, day);
        if (m !== null) reqs.push({ st: alertKid2, m, dur: between(11, 13) });
      }
      if (sex === 'H' && rnd() < 0.5) {
        const st = pick(pool);
        const m = requestMinute(st.group_id, day);
        if (m !== null) reqs.push({ st, m, dur: between(10.5, 14) }); // alerta suelta
      }

      reqs.sort((a, b) => a.m - b.m);
      const inside = []; // fin (min) de quienes están dentro
      let lastQueuedStart = 0;
      for (const r of reqs) {
        const req = r.m;
        // Siguiente momento con lugar (y la fila es FIFO).
        let start = Math.max(req, lastQueuedStart);
        for (;;) {
          const active = inside.filter((e) => e > start);
          if (active.length < CAPACITY[dest]) break;
          start = Math.min(...active);
        }
        const queued = start > req + 0.2;
        const real = queued ? start + 0.6 : req; // tiempo para confirmar el turno
        const end = real + r.dur;
        // Un lugar por grupo y sexo, y el alumno libre.
        const sameGroupOut = passes.some(
          (p) =>
            p._day === day &&
            p.destination_id === dest &&
            p.group_id === r.st.group_id &&
            p._s < end &&
            real < p._e,
        );
        if (!free(r.st.id, real - 1, end + 1) || sameGroupOut) continue;
        if (queued) lastQueuedStart = start;
        inside.push(end);
        mark(r.st.id, real - 1, end + 1);

        const cls = classAt(r.st.group_id, day, req);
        const id = randomUUID();
        const teacher = cls?.teacher_id ?? null;
        const released = r.dur > 13.5 && !passes.some((p) => p.status === 'released');
        const p = {
          id,
          student_id: r.st.id,
          group_id: r.st.group_id,
          destination_id: dest,
          status: released ? 'released' : 'returned',
          requested_at: at(day, req),
          queue_ts: queued ? at(day, req) : null,
          called_at: queued ? at(day, start) : null,
          started_at: at(day, real),
          arrived_at: null,
          ended_at: at(day, end),
          opened_by: teacher,
          closed_by: released ? prefect : teacher,
          period_subject: cls?.subject ?? null,
          release_reason: released
            ? 'No estaba en el baño; prefectura lo encontró en la cancha'
            : null,
          _day: day,
          _s: real,
          _e: end,
        };
        passes.push(p);
        events.push({
          pass_id: id,
          type: 'requested',
          actor_id: teacher,
          at: p.requested_at,
          payload: { status: queued ? 'queued' : 'out', ejemplo: true },
        });
        if (queued) {
          events.push({
            pass_id: id,
            type: 'called',
            actor_id: null,
            at: p.called_at,
            payload: {},
          });
          events.push({
            pass_id: id,
            type: 'confirmed',
            actor_id: teacher,
            at: p.started_at,
            payload: {},
          });
        }
        if (r.dur >= ALERT_MIN) {
          const created = real + ALERT_MIN;
          const escalated = rnd() < 0.3;
          const ack = created + (escalated ? between(5.2, 6.5) : between(0.5, 2.8));
          const acked = ack < end;
          alerts.push({
            id: randomUUID(),
            pass_id: id,
            level: escalated && acked ? 2 : 1,
            created_at: at(day, created),
            escalated_at: escalated && acked ? at(day, created + 5) : null,
            acknowledged_by: acked ? prefect : null,
            acknowledged_at: acked ? at(day, ack) : null,
            resolved_at: p.ended_at,
            resolution: released ? 'released' : 'returned',
          });
          events.push({
            pass_id: id,
            type: 'alert',
            actor_id: null,
            at: at(day, created),
            payload: {},
          });
          if (escalated && acked)
            events.push({
              pass_id: id,
              type: 'escalated',
              actor_id: null,
              at: at(day, created + 5),
              payload: {},
            });
          if (acked)
            events.push({
              pass_id: id,
              type: 'alert_ack',
              actor_id: prefect,
              at: at(day, ack),
              payload: {},
            });
        }
        events.push(
          released
            ? {
                pass_id: id,
                type: 'released',
                actor_id: prefect,
                at: p.ended_at,
                payload: { from: 'out', reason: p.release_reason },
              }
            : {
                pass_id: id,
                type: 'returned',
                actor_id: teacher,
                at: p.ended_at,
                payload: { from: 'out' },
              },
        );
      }
    }

    // Enfermería.
    const nurseReqs = Array.from({ length: Math.round(PER_DAY.nurse * between(0.6, 1.3)) }, () =>
      pick(students),
    );
    if (thisWeek) nurseReqs.push(nurseKid);
    for (const st of nurseReqs) {
      const m = requestMinute(st.group_id, day);
      if (m === null) continue;
      const walk = between(2, 6);
      const stay = between(8, 25);
      if (!free(st.id, m - 1, m + walk + stay + 1)) continue;
      mark(st.id, m - 1, m + walk + stay + 1);
      const cls = classAt(st.group_id, day, m);
      const id = randomUUID();
      const p = {
        id,
        student_id: st.id,
        group_id: st.group_id,
        destination_id: 'nurse',
        status: 'returned',
        requested_at: at(day, m),
        queue_ts: null,
        called_at: null,
        started_at: at(day, m),
        arrived_at: at(day, m + walk),
        ended_at: at(day, m + walk + stay),
        opened_by: cls?.teacher_id ?? null,
        closed_by: nurse,
        period_subject: cls?.subject ?? null,
        release_reason: null,
      };
      passes.push(p);
      events.push({
        pass_id: id,
        type: 'requested',
        actor_id: p.opened_by,
        at: p.requested_at,
        payload: { status: 'out', ejemplo: true },
      });
      events.push({ pass_id: id, type: 'arrived', actor_id: nurse, at: p.arrived_at, payload: {} });
      if (rnd() < 0.6) {
        notes.push({
          pass_id: id,
          author_id: nurse,
          body: pick(NOTES),
          created_at: at(day, m + walk + 3),
        });
        events.push({
          pass_id: id,
          type: 'note',
          actor_id: nurse,
          at: at(day, m + walk + 3),
          payload: {},
        });
      }
      events.push({
        pass_id: id,
        type: 'returned',
        actor_id: nurse,
        at: p.ended_at,
        payload: { from: 'arrived' },
      });
    }
  }

  const clean2 = passes.map(({ _day, _s, _e, ...p }) => p);
  await c.query(
    `insert into public.passes (id, student_id, group_id, destination_id, status, requested_at, queue_ts,
       called_at, started_at, arrived_at, ended_at, opened_by, closed_by, period_subject, release_reason)
     select id, student_id, group_id, destination_id, status, requested_at, queue_ts, called_at,
            started_at, arrived_at, ended_at, opened_by, closed_by, period_subject, release_reason
       from jsonb_populate_recordset(null::public.passes, $1)`,
    [JSON.stringify(clean2)],
  );
  await c.query(
    `insert into public.pass_events (pass_id, type, actor_id, at, payload)
     select pass_id, type, actor_id, at, payload from jsonb_populate_recordset(null::public.pass_events, $1)`,
    [JSON.stringify(events)],
  );
  // Sin avisos push por alertas de días pasados.
  await c.query('alter table public.alerts disable trigger alerts_notify');
  await c.query(
    `insert into public.alerts (id, pass_id, level, created_at, escalated_at, acknowledged_by,
       acknowledged_at, resolved_at, resolution)
     select id, pass_id, level, created_at, escalated_at, acknowledged_by, acknowledged_at, resolved_at, resolution
       from jsonb_populate_recordset(null::public.alerts, $1)`,
    [JSON.stringify(alerts)],
  );
  await c.query('alter table public.alerts enable trigger alerts_notify');
  await c.query(
    `insert into public.nurse_notes (pass_id, author_id, body, created_at)
     select pass_id, author_id, body, created_at from jsonb_populate_recordset(null::public.nurse_notes, $1)`,
    [JSON.stringify(notes)],
  );
  await c.query('commit');

  const by = (k) => passes.filter((p) => p.destination_id === k).length;
  console.log(`Borrados ${removed} pases de ejemplo anteriores.`);
  console.log(
    `Cargados ${passes.length} pases (${by('bath_h')} hombres, ${by('bath_m')} mujeres, ${by('nurse')} enfermería), ` +
      `${passes.filter((p) => p.queue_ts).length} con fila, ${alerts.length} alertas, ${notes.length} notas.`,
  );
  console.log(
    `Incidencias: ${alertKid.full_name} (${alertKid.group_name}) con alertas; ` +
      `${frequentKid.full_name} (${frequentKid.group_name}) con muchas salidas; ` +
      `${nurseKid.full_name} (${nurseKid.group_name}) en enfermería; ${alertKid2.full_name} (${alertKid2.group_name}) con alertas.`,
  );
} catch (err) {
  await c.query('rollback');
  console.error('No se cargó nada:', err.message);
  process.exitCode = 1;
} finally {
  await c.end();
}
