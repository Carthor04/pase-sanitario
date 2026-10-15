// Prueba de concurrencia (CLAUDE.md, regla 1): dos maestros piden el último lugar del baño
// de hombres al mismo tiempo, desde dos conexiones distintas. Solo uno debe salir.
//
// A diferencia de supabase/tests/*.sql, aquí las transacciones SÍ se confirman (es la
// única forma de probar el candado entre conexiones). Por eso usa grupos y un maestro de
// prueba que se borran al final, y se omite si el baño de hombres ya tiene gente.
import pg from 'pg';
import { connectionString } from './db-connection.mjs';

const conn = { connectionString: connectionString(), ssl: { rejectUnauthorized: false } };
const STAFF = '00000000-0000-4000-fc00-000000000001';
const EMAIL = 'concurrencia@test.mx';
const GROUP = 'ZZ prueba concurrencia';

const admin = new pg.Client(conn);
const a = new pg.Client(conn);
const b = new pg.Client(conn);
await Promise.all([admin.connect(), a.connect(), b.connect()]);

async function cleanup() {
  const like = [`${GROUP}%`];
  await admin.query(
    `delete from public.pass_events where pass_id in (select p.id from public.passes p
       join public.groups g on g.id = p.group_id where g.name like $1)`,
    like,
  );
  await admin.query(
    'delete from public.passes where group_id in (select id from public.groups where name like $1)',
    like,
  );
  await admin.query(
    'delete from public.students where group_id in (select id from public.groups where name like $1)',
    like,
  );
  await admin.query('delete from public.groups where name like $1', like);
  await admin.query('delete from public.staff where id = $1', [STAFF]);
  await admin.query('delete from auth.users where id = $1', [STAFF]);
}

async function actAsTeacher(client) {
  await client.query('begin');
  await client.query(
    `select set_config('request.jwt.claims', $1, true), set_config('role', 'authenticated', true)`,
    [JSON.stringify({ sub: STAFF, role: 'authenticated', email: EMAIL })],
  );
}

let failed = false;
try {
  await cleanup(); // por si quedó algo de una corrida interrumpida

  const {
    rows: [state],
  } = await admin.query(
    `select capacity, (select count(*) from public.passes where destination_id = 'bath_h'
       and status in ('queued', 'called', 'out'))::int as busy
       from public.destinations where id = 'bath_h'`,
  );
  if (state.capacity !== 1 || state.busy > 0) {
    console.log('- concurrencia: omitida (el baño de hombres está en uso o su capacidad no es 1)');
  } else {
    await admin.query('begin');
    await admin.query(
      `insert into public.staff (id, full_name, email, roles)
       values ($1, 'Prueba concurrencia', $2, array['teacher'])`,
      [STAFF, EMAIL],
    );
    await admin.query(
      `insert into auth.users (id, email, aud, role) values ($1, $2, 'authenticated', 'authenticated')`,
      [STAFF, EMAIL],
    );
    // Dos niños de grupos distintos, para que el lugar del grupo no los separe.
    const students = [];
    for (const suffix of ['A', 'B']) {
      const {
        rows: [s],
      } = await admin.query(
        `with g as (insert into public.groups (name, sort) values ($1, 999) returning id)
         insert into public.students (group_id, list_number, full_name, sex)
         select id, 1, $2, 'H' from g returning id`,
        [`${GROUP} ${suffix}`, `Niño ${suffix}`],
      );
      students.push(s.id);
    }
    await admin.query('commit');

    await actAsTeacher(a);
    await actAsTeacher(b);

    // A toma el candado del baño y crea su pase, sin confirmar todavía.
    const ra = await a.query(`select public.request_pass($1, 'bathroom') as r`, [students[0]]);
    // B pide al mismo tiempo: debe quedarse esperando el candado de A.
    let bDone = false;
    const pb = b
      .query(`select public.request_pass($1, 'bathroom') as r`, [students[1]])
      .then((res) => {
        bDone = true;
        return res;
      });
    await new Promise((r) => setTimeout(r, 1500));
    const waited = !bDone;
    await a.query('commit');
    const rb = await pb;
    await b.query('commit');

    const sa = ra.rows[0].r.status;
    const sb = rb.rows[0].r.status;
    failed = !(waited && sa === 'out' && sb === 'queued');
    console.log(
      `${failed ? '✘' : '✔'} concurrencia: A=${sa}, B=${sb}, B esperó el candado de A=${waited}`,
    );
  }
} catch (err) {
  failed = true;
  console.log(`✘ concurrencia: ${err.message}`);
  await Promise.all([a, b, admin].map((c) => c.query('rollback').catch(() => {})));
} finally {
  await cleanup();
  await Promise.all([admin.end(), a.end(), b.end()]);
}
process.exit(failed ? 1 : 0);
