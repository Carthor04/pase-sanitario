// Muestra de tokens de diseño (Fase 0). Se reemplaza por la redirección por rol en la Fase 1.
const chips = [
  { label: 'Libre', className: 'bg-free-bg text-free-fg' },
  { label: 'Fuera · 06:12', className: 'bg-ink text-white' },
  { label: 'Espera del grupo', className: 'bg-wait-bg text-wait-fg' },
  { label: 'Su turno · 1:42', className: 'border-2 border-wait-bd bg-wait-bg text-wait-fg' },
  { label: 'Alerta · 10 min', className: 'border-2 border-alert-bd bg-alert-bg text-alert-fg' },
  { label: 'Enfermería', className: 'border-2 border-nurse-bd bg-nurse-bg text-nurse-fg' },
];

export function Home() {
  return (
    <div className="flex flex-col gap-5">
      <h1 className="m-0 font-display text-[22px] font-bold sm:text-[28px]">Pase Sanitario</h1>

      <section
        aria-label="Estados"
        className="flex flex-col gap-3 rounded-card border border-line bg-surface p-5"
      >
        <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-muted">
          Estados
        </span>
        <div className="flex flex-wrap gap-2">
          {chips.map((c) => (
            <span
              key={c.label}
              className={`rounded-chip px-2.5 py-0.5 text-[13px] font-bold ${c.className}`}
            >
              {c.label}
            </span>
          ))}
        </div>
      </section>

      <section
        aria-label="Lugares del grupo"
        className="grid gap-4 sm:grid-cols-[repeat(auto-fit,minmax(280px,1fr))]"
      >
        <div className="flex flex-col gap-3 rounded-card border-2 border-ink bg-surface px-5 py-[18px]">
          <div className="flex items-center justify-between">
            <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-muted">
              Niño · Baño hombres
            </span>
            <span className="rounded-chip bg-ink px-2.5 py-0.5 text-[13px] font-bold text-white">
              Fuera
            </span>
          </div>
          <div className="flex items-end justify-between gap-3">
            <div className="flex min-w-0 flex-col gap-0.5">
              <span className="text-[22px] font-bold">Luis Martínez</span>
              <span className="text-muted">#14 · salió 10:25</span>
            </div>
            <span className="font-mono text-[40px] font-semibold tabular-nums leading-none">
              06:12
            </span>
          </div>
          <div className="h-1.5 overflow-hidden rounded-[3px] bg-[#E6EBF0]" aria-hidden="true">
            <div className="h-full w-[62%] bg-ink" />
          </div>
          <button
            type="button"
            className="min-h-btn rounded-btn bg-accent text-[17px] font-bold text-white"
          >
            Marcar regreso
          </button>
        </div>

        <div className="flex flex-col gap-3 rounded-card border border-line bg-surface px-5 py-[18px]">
          <div className="flex items-center justify-between">
            <span className="text-[13px] font-bold uppercase tracking-[0.08em] text-muted">
              Niña · Baño mujeres
            </span>
            <span className="rounded-chip bg-free-bg px-2.5 py-0.5 text-[13px] font-bold text-free-fg">
              Libre
            </span>
          </div>
          <span className="text-lg text-muted">Ninguna alumna fuera</span>
          <button
            type="button"
            className="min-h-btn rounded-btn border border-line-strong bg-surface text-[15px] font-bold"
          >
            Botón secundario
          </button>
        </div>
      </section>
    </div>
  );
}
