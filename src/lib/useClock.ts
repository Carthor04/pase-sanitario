import { useEffect, useState } from 'react';

const fmt = new Intl.DateTimeFormat('es-MX', {
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
  timeZone: 'America/Mexico_City',
});

export function formatClock(date: Date): string {
  return fmt.format(date);
}

/** Hora actual de México (HH:mm), actualizada cada 15 s. */
export function useClock(): string {
  const [now, setNow] = useState(() => formatClock(new Date()));
  useEffect(() => {
    const id = window.setInterval(() => setNow(formatClock(new Date())), 15_000);
    return () => window.clearInterval(id);
  }, []);
  return now;
}
