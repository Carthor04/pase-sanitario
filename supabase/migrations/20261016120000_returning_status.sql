-- Enfermería → salón: al dar de alta, el alumno queda "de regreso" (returning) hasta que el
-- maestro marca su regreso. Esta migración solo agrega el valor del enum y columnas; el
-- valor nuevo se usa en la siguiente migración (Postgres pide confirmarlo antes).
alter type public.pass_status add value if not exists 'returning' after 'arrived';

alter table public.passes add column left_nurse_at timestamptz;

alter table public.pass_events drop constraint pass_events_type_check;
alter table public.pass_events add constraint pass_events_type_check check (type in (
  'requested', 'promoted', 'called', 'confirmed', 'ceded', 'turn_expired',
  'arrived', 'sent_back', 'returned', 'released', 'cancelled', 'undo', 'alert', 'escalated',
  'alert_ack', 'note'));

alter table public.notifications_outbox drop constraint notifications_outbox_kind_check;
alter table public.notifications_outbox add constraint notifications_outbox_kind_check
  check (kind in ('alert', 'escalated', 'acknowledged', 'resolved', 'returning', 'test'));
