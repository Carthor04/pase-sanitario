-- pg_cron guarda una fila en cron.job_run_details por cada corrida: con pase-tick cada 30 s
-- y pase-push cada minuto son unas 4,300 filas al día, y nadie las borraba (al 2026-11-02
-- ya ocupaban 17 MB de 39 MB de la base). Se conserva una semana para revisar fallas.
-- cron.log_statement (lo que cada corrida escribe en el log) es de arranque del servidor y
-- no se puede cambiar desde una migración.
delete from cron.job_run_details where end_time < now() - interval '7 days';

-- Todos los días a las 03:00 de León (cron.timezone es GMT).
select cron.schedule('pase-cron-cleanup', '0 9 * * *', $cron$
  delete from cron.job_run_details where end_time < now() - interval '7 days'
$cron$);
