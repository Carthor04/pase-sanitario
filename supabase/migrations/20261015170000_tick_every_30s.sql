-- tick() cada 30 segundos (antes cada minuto): las alertas y los turnos vencidos se
-- detectan con a lo más 30 s de retraso. pg_cron acepta intervalos en segundos.
select cron.schedule('pase-tick', '30 seconds', 'select private.tick()');
