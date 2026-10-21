import type { ReactNode } from 'react';
import { BrandMark, BrandName } from '@/components/layout/BrandMark';

export function PageTitle({ children, aside }: { children: ReactNode; aside?: ReactNode }) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-2">
      <h1 className="m-0 font-display text-[22px] font-bold sm:text-[28px]">{children}</h1>
      {aside}
    </div>
  );
}

export function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <section
      className={`flex flex-col gap-3 rounded-card border border-line bg-surface p-5 ${className}`}
    >
      {children}
    </section>
  );
}

export function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-muted">{children}</span>
  );
}

type Tone = 'info' | 'ok' | 'warn' | 'error';
const TONES: Record<Tone, string> = {
  info: 'border-line bg-surface text-ink',
  ok: 'border-free-fg/30 bg-free-bg text-free-fg',
  warn: 'border-wait-bd bg-wait-bg text-wait-fg',
  error: 'border-alert-bd bg-alert-bg text-alert-fg',
};

/** Mensaje con texto siempre visible (el color nunca es la única señal). */
export function Notice({ tone = 'info', children }: { tone?: Tone; children: ReactNode }) {
  return (
    <div
      role={tone === 'error' ? 'alert' : 'status'}
      className={`rounded-btn border px-4 py-3 text-[15px] ${TONES[tone]}`}
    >
      {children}
    </div>
  );
}

/** Pantalla centrada sin navegación (login, sin acceso, cargando, vinculación). */
export function FullScreen({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-ground px-4 py-8">
      <div className="flex w-full max-w-[420px] flex-col gap-5 rounded-card-lg border border-line bg-surface p-6">
        <div className="flex items-center gap-3">
          <BrandMark />
          <BrandName className="text-[22px]" />
        </div>
        {title ? <h1 className="m-0 font-display text-[22px] font-bold">{title}</h1> : null}
        {children}
      </div>
    </div>
  );
}

export function Loading({ label = 'Cargando…' }: { label?: string }) {
  return (
    <p role="status" className="m-0 text-muted">
      {label}
    </p>
  );
}
