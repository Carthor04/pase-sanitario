-- Fase 1 · Catálogos, acceso y RLS.
-- Diferencias con docs/DATA_MODEL.md (explicadas en el commit):
--   * El hash del PIN vive en staff_pins (sin GRANT a nadie) en vez de staff.pin_hash,
--     para que leer `staff` nunca exponga hashes. staff.pin_set_at indica si tiene PIN.
--   * students: (group_id, list_number) es único solo entre alumnos activos, para poder
--     dar de baja a un alumno sin borrarlo y reutilizar su número de lista.
--   * devices.revoked_at y device_pairings (códigos de 6 dígitos para vincular equipos).
--   * security_attempts: bitácora de intentos (PIN, vinculación) para limitar abusos.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------
-- Personal
-- ---------------------------------------------------------------------------
create table public.staff (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete set null,
  full_name text not null check (btrim(full_name) <> ''),
  email text not null check (position('@' in email) > 1),
  roles text[] not null check (
    cardinality(roles) > 0
    and roles <@ array['teacher', 'prefect', 'nurse', 'coordinator', 'director', 'admin']
  ),
  whatsapp text,
  active boolean not null default true,
  pin_set_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index staff_email_key on public.staff (lower(email));

create table public.staff_pins (
  staff_id uuid primary key references public.staff (id),
  pin_hash text not null,
  updated_at timestamptz not null default now()
);

create table public.security_attempts (
  id bigserial primary key,
  kind text not null check (kind in ('set_pin', 'pair_device', 'unlock')),
  auth_user_id uuid,
  device_id uuid,
  ok boolean not null,
  at timestamptz not null default now()
);
create index security_attempts_lookup on public.security_attempts (kind, auth_user_id, at desc);

-- ---------------------------------------------------------------------------
-- Grupos y alumnos
-- ---------------------------------------------------------------------------
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text unique not null check (btrim(name) <> ''),
  room text,
  sort int
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id),
  list_number int not null check (list_number between 1 and 99),
  full_name text not null check (btrim(full_name) <> ''),
  sex char(1) not null check (sex in ('H', 'M')),
  rfid_tag text unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index students_group_list_active on public.students (group_id, list_number)
  where active;
create index students_group on public.students (group_id);

-- ---------------------------------------------------------------------------
-- Horario
-- ---------------------------------------------------------------------------
create table public.periods (
  id uuid primary key default gen_random_uuid(),
  weekday int not null check (weekday between 1 and 5),
  starts time not null,
  ends time not null,
  check (ends > starts),
  unique (weekday, starts, ends)
);

create table public.schedule_entries (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id),
  period_id uuid not null references public.periods (id),
  subject text not null check (btrim(subject) <> ''),
  teacher_id uuid references public.staff (id),
  unique (group_id, period_id)
);
create index schedule_entries_teacher on public.schedule_entries (teacher_id);
create index schedule_entries_period on public.schedule_entries (period_id);

-- ---------------------------------------------------------------------------
-- Lugares y reglas (los valores se cambian aquí, nunca en código)
-- ---------------------------------------------------------------------------
create table public.destinations (
  id text primary key,
  label text not null,
  kind text not null check (kind in ('bathroom', 'nurse')),
  sex char(1) check (sex in ('H', 'M')),
  capacity int check (capacity > 0),
  per_group_limit int check (per_group_limit > 0),
  uses_group_slot boolean not null default true,
  queue_enabled boolean not null default true
);

create table public.settings (
  id int primary key default 1 check (id = 1),
  alert_minutes int not null default 10 check (alert_minutes > 0),
  escalate_minutes int not null default 5 check (escalate_minutes > 0),
  confirm_turn_minutes int not null default 2 check (confirm_turn_minutes > 0),
  auto_lock_after_class_minutes int not null default 5 check (auto_lock_after_class_minutes >= 0),
  undo_seconds int not null default 10 check (undo_seconds > 0),
  review_alerts_threshold int not null default 2,
  review_exits_threshold int not null default 8,
  pin_max_attempts int not null default 5 check (pin_max_attempts > 0),
  pin_lockout_seconds int not null default 60 check (pin_lockout_seconds > 0),
  pairing_code_minutes int not null default 15 check (pairing_code_minutes > 0),
  sheets_spreadsheet_id text,
  sheets_daily_export_time time not null default '15:00'
);

insert into public.destinations (id, label, kind, sex, capacity, per_group_limit, uses_group_slot, queue_enabled)
values
  ('bath_h', 'Baño hombres', 'bathroom', 'H', 1, 1, true, true),
  ('bath_m', 'Baño mujeres', 'bathroom', 'M', 3, 1, true, true),
  ('nurse', 'Enfermería', 'nurse', null, null, null, false, false);

insert into public.settings (id) values (1);

-- ---------------------------------------------------------------------------
-- Equipos de salón
-- ---------------------------------------------------------------------------
create table public.devices (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id),
  label text,
  auth_user_id uuid unique references auth.users (id) on delete set null,
  created_by uuid references public.staff (id),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  revoked_at timestamptz
);

create table public.device_pairings (
  id uuid primary key default gen_random_uuid(),
  code text not null check (code ~ '^\d{6}$'),
  group_id uuid not null references public.groups (id),
  label text,
  created_by uuid not null references public.staff (id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  claimed_at timestamptz,
  device_id uuid references public.devices (id)
);
create index device_pairings_code on public.device_pairings (code) where claimed_at is null;

create table public.device_unlocks (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null references public.devices (id),
  staff_id uuid not null references public.staff (id),
  unlocked_at timestamptz not null default now(),
  expires_at timestamptz not null,
  locked_at timestamptz,
  lock_reason text check (lock_reason in ('manual', 'auto', 'pin_change', 'revoked'))
);
create index device_unlocks_device on public.device_unlocks (device_id, unlocked_at desc);

-- ---------------------------------------------------------------------------
-- Ayudantes para RLS (schema private: no expuesto por la API)
-- ---------------------------------------------------------------------------
create function private.current_staff_id() returns uuid
language sql stable security definer set search_path = ''
as $$
  select s.id from public.staff s where s.auth_user_id = auth.uid() and s.active;
$$;

create function private.has_any_role(p_roles text[]) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.staff s
    where s.auth_user_id = auth.uid() and s.active and s.roles && p_roles
  );
$$;

create function private.can_manage() returns boolean
language sql stable security definer set search_path = ''
as $$
  select private.has_any_role(array['coordinator', 'director', 'admin']);
$$;

create function private.current_device_id() returns uuid
language sql stable security definer set search_path = ''
as $$
  select d.id from public.devices d where d.auth_user_id = auth.uid() and d.revoked_at is null;
$$;

create function private.current_device_group_id() returns uuid
language sql stable security definer set search_path = ''
as $$
  select d.group_id from public.devices d where d.auth_user_id = auth.uid() and d.revoked_at is null;
$$;

create function private.is_member() returns boolean
language sql stable security definer set search_path = ''
as $$
  select private.current_staff_id() is not null or private.current_device_id() is not null;
$$;

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- ---------------------------------------------------------------------------
-- Login con Google: solo correos de personal activo (los equipos de salón entran
-- como usuario anónimo y se vinculan con un código).
-- ---------------------------------------------------------------------------
create function private.before_auth_user_insert() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if coalesce(new.is_anonymous, false) then
    return new;
  end if;
  if new.email is null or not exists (
    select 1 from public.staff s where lower(s.email) = lower(new.email) and s.active
  ) then
    raise exception 'Correo no registrado como personal activo' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create function private.after_auth_user_insert() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not coalesce(new.is_anonymous, false) and new.email is not null then
    update public.staff
       set auth_user_id = new.id
     where lower(email) = lower(new.email) and auth_user_id is null;
  end if;
  return new;
end;
$$;

revoke all on function private.before_auth_user_insert() from public, anon, authenticated;
revoke all on function private.after_auth_user_insert() from public, anon, authenticated;

create trigger staff_only_before_insert
  before insert on auth.users
  for each row execute function private.before_auth_user_insert();

create trigger link_staff_after_insert
  after insert on auth.users
  for each row execute function private.after_auth_user_insert();

-- Al dar de baja a alguien se borra su PIN (evita PIN repetidos al reactivarlo)
-- y se cierran los desbloqueos que tenga abiertos.
create function private.on_staff_deactivated() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.staff_pins where staff_id = new.id;
  new.pin_set_at := null;
  update public.device_unlocks
     set locked_at = now(), lock_reason = 'pin_change'
   where staff_id = new.id and locked_at is null and expires_at > now();
  return new;
end;
$$;
revoke all on function private.on_staff_deactivated() from public, anon, authenticated;

create trigger staff_deactivated
  before update of active on public.staff
  for each row when (old.active and not new.active)
  execute function private.on_staff_deactivated();

-- ---------------------------------------------------------------------------
-- RLS. Las tablas no se exponen solas: cada GRANT es explícito y nada va a anon.
-- ---------------------------------------------------------------------------
alter table public.staff enable row level security;
alter table public.staff_pins enable row level security;
alter table public.security_attempts enable row level security;
alter table public.groups enable row level security;
alter table public.students enable row level security;
alter table public.periods enable row level security;
alter table public.schedule_entries enable row level security;
alter table public.destinations enable row level security;
alter table public.settings enable row level security;
alter table public.devices enable row level security;
alter table public.device_pairings enable row level security;
alter table public.device_unlocks enable row level security;

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

-- staff: lo lee cualquier miembro; lo escriben coordinación, dirección y admin.
-- pin_set_at y auth_user_id solo cambian por funciones.
grant select on public.staff to authenticated;
grant insert (full_name, email, roles, whatsapp, active) on public.staff to authenticated;
grant update (full_name, email, roles, whatsapp, active) on public.staff to authenticated;
create policy staff_select on public.staff for select to authenticated
  using ((select private.is_member()));
create policy staff_insert on public.staff for insert to authenticated
  with check ((select private.can_manage()));
create policy staff_update on public.staff for update to authenticated
  using ((select private.can_manage())) with check ((select private.can_manage()));

-- staff_pins y security_attempts: sin GRANT. Solo funciones security definer.

-- Catálogos: lectura para miembros; escritura para coordinación/dirección/admin.
grant select, insert, update on public.groups to authenticated;
create policy groups_select on public.groups for select to authenticated
  using ((select private.is_member()));
create policy groups_write on public.groups for insert to authenticated
  with check ((select private.can_manage()));
create policy groups_update on public.groups for update to authenticated
  using ((select private.can_manage())) with check ((select private.can_manage()));

-- Alumnos: el personal ve todos; un equipo de salón solo los de su grupo.
grant select, insert, update on public.students to authenticated;
create policy students_select on public.students for select to authenticated
  using (
    (select private.current_staff_id()) is not null
    or group_id = (select private.current_device_group_id())
  );
create policy students_insert on public.students for insert to authenticated
  with check ((select private.can_manage()));
create policy students_update on public.students for update to authenticated
  using ((select private.can_manage())) with check ((select private.can_manage()));

grant select, insert, update, delete on public.periods to authenticated;
create policy periods_select on public.periods for select to authenticated
  using ((select private.is_member()));
create policy periods_insert on public.periods for insert to authenticated
  with check ((select private.can_manage()));
create policy periods_update on public.periods for update to authenticated
  using ((select private.can_manage())) with check ((select private.can_manage()));
create policy periods_delete on public.periods for delete to authenticated
  using ((select private.can_manage()));

grant select, insert, update, delete on public.schedule_entries to authenticated;
create policy schedule_select on public.schedule_entries for select to authenticated
  using ((select private.is_member()));
create policy schedule_insert on public.schedule_entries for insert to authenticated
  with check ((select private.can_manage()));
create policy schedule_update on public.schedule_entries for update to authenticated
  using ((select private.can_manage())) with check ((select private.can_manage()));
create policy schedule_delete on public.schedule_entries for delete to authenticated
  using ((select private.can_manage()));

grant select, update on public.destinations to authenticated;
create policy destinations_select on public.destinations for select to authenticated
  using ((select private.is_member()));
create policy destinations_update on public.destinations for update to authenticated
  using ((select private.can_manage())) with check ((select private.can_manage()));

grant select, update on public.settings to authenticated;
create policy settings_select on public.settings for select to authenticated
  using ((select private.is_member()));
create policy settings_update on public.settings for update to authenticated
  using ((select private.can_manage())) with check ((select private.can_manage()));

-- Equipos: coordinación ve todos; cada equipo se ve a sí mismo. Escritura solo por RPC.
grant select on public.devices to authenticated;
create policy devices_select on public.devices for select to authenticated
  using ((select private.can_manage()) or auth_user_id = (select auth.uid()));

grant select on public.device_pairings to authenticated;
create policy device_pairings_select on public.device_pairings for select to authenticated
  using ((select private.can_manage()));

grant select on public.device_unlocks to authenticated;
create policy device_unlocks_select on public.device_unlocks for select to authenticated
  using (
    (select private.can_manage())
    or device_id = (select private.current_device_id())
    or staff_id = (select private.current_staff_id())
  );
