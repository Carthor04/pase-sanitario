-- Horarios sin baño (dirección, 2026-10-23): de lunes a viernes, en esas horas no se entra a
-- los baños ni se agrega a nadie a las listas de espera. Funciona como una pausa de los dos
-- baños: no se piden pases, la fila no avanza, no se confirma turno ni corre su tiempo. Quien
-- ya está fuera sigue con su cronómetro. Los horarios los cambia el admin en Configuración.

create table public.bathroom_closures (
  id bigint generated always as identity primary key,
  starts time not null,
  ends time not null,
  check (ends > starts)
);
alter table public.bathroom_closures enable row level security;
grant select on public.bathroom_closures to authenticated;
create policy bathroom_closures_select on public.bathroom_closures for select to authenticated
  using ((select private.is_member()));

insert into public.bathroom_closures (starts, ends) values ('10:30', '11:00'), ('12:10', '12:35');

-- Cada cambio queda registrado (nada se borra).
create table public.bathroom_closure_changes (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor_id uuid references public.staff (id),
  before jsonb not null,
  after jsonb not null
);
alter table public.bathroom_closure_changes enable row level security;

-- Horario sin baño vigente en ese momento (hora de México, lunes a viernes).
create function private.closure_at(p_at timestamptz default clock_timestamp())
returns table (starts timestamptz, ends timestamptz)
language sql stable security definer set search_path = ''
as $$
  select (d + c.starts) at time zone 'America/Mexico_City', (d + c.ends) at time zone 'America/Mexico_City'
    from public.bathroom_closures c,
         lateral (select (p_at at time zone 'America/Mexico_City')::date as d) x
   where extract(isodow from p_at at time zone 'America/Mexico_City') between 1 and 5
     and (p_at at time zone 'America/Mexico_City')::time >= c.starts
     and (p_at at time zone 'America/Mexico_City')::time < c.ends
   order by c.starts
   limit 1;
$$;
revoke all on function private.closure_at(timestamptz) from public, anon, authenticated;

-- Pausa manual o, si no hay, el horario sin baño vigente.
create or replace function private.paused_since(p_destination text) returns timestamptz
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select paused_at from public.bathroom_pauses
      where destination_id = p_destination and resumed_at is null),
    (select c.starts from private.closure_at() c
      where exists (select 1 from public.destinations where id = p_destination and kind = 'bathroom')));
$$;

-- El tiempo para confirmar turno vuelve a contar desde que terminó la pausa o el horario sin
-- baño más reciente de hoy.
create or replace function private.last_resume(p_destination text) returns timestamptz
language sql stable security definer set search_path = ''
as $$
  select greatest(
    (select max(resumed_at) from public.bathroom_pauses where destination_id = p_destination),
    (select max(((now() at time zone 'America/Mexico_City')::date + c.ends) at time zone 'America/Mexico_City')
       from public.bathroom_closures c
      where extract(isodow from now() at time zone 'America/Mexico_City') between 1 and 5
        and c.ends <= (now() at time zone 'America/Mexico_City')::time));
$$;

-- Para las pantallas. Con horario sin baño: scheduled = true y hasta qué hora (no se reanuda
-- a mano).
create or replace function private.pause_json(p_destination text) returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select jsonb_build_object('since', bp.paused_at, 'by', s.full_name, 'reason', bp.reason)
       from public.bathroom_pauses bp left join public.staff s on s.id = bp.paused_by
      where bp.destination_id = p_destination and bp.resumed_at is null),
    (select jsonb_build_object(
       'since', c.starts, 'by', null, 'until', c.ends, 'scheduled', true,
       'reason', 'Horario sin baño hasta las '
                 || to_char(c.ends at time zone 'America/Mexico_City', 'HH24:MI'))
       from private.closure_at() c
      where exists (select 1 from public.destinations where id = p_destination and kind = 'bathroom')));
$$;

create or replace function private.require_not_paused(p_destination text) returns void
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_label text;
  v_reason text;
  v_until timestamptz;
begin
  select d.label, bp.reason into v_label, v_reason
    from public.bathroom_pauses bp join public.destinations d on d.id = bp.destination_id
   where bp.destination_id = p_destination and bp.resumed_at is null;
  if found then
    raise exception '% está en pausa%. Intenta cuando se reanude.',
      v_label, coalesce(' (' || v_reason || ')', '') using errcode = 'P0001';
  end if;
  select d.label, c.ends into v_label, v_until
    from public.destinations d, private.closure_at() c
   where d.id = p_destination and d.kind = 'bathroom';
  if found then
    raise exception 'Horario sin baño: % abre a las %.',
      v_label, to_char(v_until at time zone 'America/Mexico_City', 'HH24:MI') using errcode = 'P0001';
  end if;
end;
$$;

-- Configuración (solo admin desde su cuenta): reemplaza la lista de horarios.
create function public.set_bathroom_closures(p_ranges jsonb) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  a private.actor := private.current_actor();
  r jsonb;
  v_before jsonb;
  v_after jsonb := '[]';
  v_start time;
  v_end time;
begin
  perform private.require_admin_account(a);
  for r in select value from jsonb_array_elements(coalesce(p_ranges, '[]')) loop
    if coalesce(r ->> 'starts', '') !~ '^([01]?\d|2[0-3]):[0-5]\d$'
       or coalesce(r ->> 'ends', '') !~ '^([01]?\d|2[0-3]):[0-5]\d$' then
      raise exception 'Las horas deben ir como HH:MM' using errcode = '22023';
    end if;
    v_start := (r ->> 'starts')::time;
    v_end := (r ->> 'ends')::time;
    if v_end <= v_start then
      raise exception 'La hora de fin debe ser después del inicio (%)', r ->> 'starts' using errcode = '22023';
    end if;
    if exists (select 1 from jsonb_array_elements(v_after) x
                where v_start < (x ->> 'ends')::time and (x ->> 'starts')::time < v_end) then
      raise exception 'Dos horarios se empalman (%)', r ->> 'starts' using errcode = '22023';
    end if;
    v_after := v_after || jsonb_build_object('starts', to_char(v_start, 'HH24:MI'), 'ends', to_char(v_end, 'HH24:MI'));
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('starts', to_char(starts, 'HH24:MI'), 'ends', to_char(ends, 'HH24:MI'))
                  order by starts), '[]') into v_before
    from public.bathroom_closures;
  delete from public.bathroom_closures;
  insert into public.bathroom_closures (starts, ends)
  select (x ->> 'starts')::time, (x ->> 'ends')::time from jsonb_array_elements(v_after) x;
  insert into public.bathroom_closure_changes (actor_id, before, after) values (a.staff_id, v_before, v_after);

  -- Si el horario que estaba vigente se quitó, la fila avanza de inmediato.
  perform private.advance(d.id, a) from public.destinations d where d.kind = 'bathroom';
  return v_after;
end;
$$;

revoke all on function public.set_bathroom_closures(jsonb) from public, anon;
grant execute on function public.set_bathroom_closures(jsonb) to authenticated;

-- Para Configuración: los horarios vigentes.
create function public.bathroom_closures_list() returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'starts', to_char(starts, 'HH24:MI'), 'ends', to_char(ends, 'HH24:MI')) order by starts), '[]')
    from public.bathroom_closures
   where private.is_member();
$$;
revoke all on function public.bathroom_closures_list() from public, anon;
grant execute on function public.bathroom_closures_list() to authenticated;
