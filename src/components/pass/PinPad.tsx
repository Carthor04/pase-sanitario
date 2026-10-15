import { useEffect, useState } from 'react';

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'Borrar', '0', 'Listo'] as const;

type Props = {
  /** Devuelve un mensaje de error, o null si desbloqueó. */
  onSubmit: (pin: string) => Promise<string | null>;
  disabled?: boolean;
};

/** Teclado de PIN de 4 dígitos (también acepta el teclado físico). Se envía solo al completar. */
export function PinPad({ onSubmit, disabled }: Props) {
  const [pin, setPin] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(value: string) {
    setBusy(true);
    const message = await onSubmit(value);
    setBusy(false);
    setPin('');
    setError(message);
  }

  function press(key: string) {
    if (busy || disabled) return;
    if (key === 'Borrar') {
      setPin((p) => p.slice(0, -1));
      return;
    }
    if (key === 'Listo') {
      if (pin.length === 4) void submit(pin);
      return;
    }
    setError(null);
    const next = (pin + key).slice(0, 4);
    setPin(next);
    if (next.length === 4) void submit(next);
  }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (/^\d$/.test(e.key)) press(e.key);
      else if (e.key === 'Backspace') press('Borrar');
      else if (e.key === 'Enter') press('Listo');
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  return (
    <div className="flex flex-col items-center gap-4">
      <div role="status" aria-label={`${pin.length} de 4 dígitos`} className="flex gap-3">
        {[0, 1, 2, 3].map((i) => (
          <span
            key={i}
            className={`h-4 w-4 rounded-full border-2 border-muted ${i < pin.length ? 'bg-ink' : ''}`}
          />
        ))}
      </div>
      <div className="grid grid-cols-3 gap-2.5">
        {KEYS.map((k) => (
          <button
            key={k}
            type="button"
            aria-label={k}
            disabled={busy || disabled}
            onClick={() => press(k)}
            className={`h-[58px] w-[92px] rounded-btn border border-line-strong text-[24px] font-bold disabled:opacity-50 ${
              k.length > 1 ? 'bg-ground text-[20px]' : 'bg-surface font-mono'
            }`}
          >
            {k === 'Borrar' ? '⌫' : k === 'Listo' ? '✓' : k}
          </button>
        ))}
      </div>
      {error ? (
        <p role="alert" className="m-0 text-center font-bold text-alert-fg">
          {error}
        </p>
      ) : null}
    </div>
  );
}
