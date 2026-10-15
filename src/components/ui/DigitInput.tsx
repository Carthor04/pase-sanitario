import { useId } from 'react';

type Props = {
  label: string;
  length: number;
  value: string;
  onChange: (value: string) => void;
  autoFocus?: boolean;
  /** Oculta los dígitos (PIN). */
  secret?: boolean;
};

/** Campo numérico grande para PIN (4) y código de vinculación (6). */
export function DigitInput({ label, length, value, onChange, autoFocus, secret }: Props) {
  const id = useId();
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="text-[15px] font-bold">
        {label}
      </label>
      <input
        id={id}
        type={secret ? 'password' : 'text'}
        inputMode="numeric"
        autoComplete={secret ? 'off' : 'one-time-code'}
        pattern={`\\d{${length}}`}
        maxLength={length}
        autoFocus={autoFocus}
        value={value}
        onChange={(e) => onChange(e.target.value.replace(/\D/g, '').slice(0, length))}
        className="min-h-[56px] rounded-btn border border-line-strong bg-surface px-4 text-center font-mono text-[28px] font-semibold tabular-nums tracking-[0.4em] outline-none focus:border-accent focus:ring-2 focus:ring-accent/30"
      />
    </div>
  );
}
