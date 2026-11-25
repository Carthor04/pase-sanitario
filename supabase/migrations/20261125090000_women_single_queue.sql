-- Baño de mujeres: una sola fila general para todos los salones, sin "espera de su grupo"
-- (decisión 2026-11-25), igual que el de hombres desde el 2026-10-23. Sale según su cupo.
-- Es la regla uses_group_slot del baño (Configuración → Baños y reglas); al apagarla, el
-- trigger de reglas pasa a la fila a quienes esperaban a su grupo, con la hora en que se
-- pidió su pase.
update public.destinations set uses_group_slot = false where id = 'bath_m';
