// Hexágono de Tellus (viewBox 0 0 636 766). Mismas figuras en public/icon.svg y scripts/make-icons.mjs.
const TELLUS_MARK = [
  'M1 191 319 0l317 191v149L382 190v381l128-85V302l126 74v188L319 766l-65-40V190L1 340Z',
  'M1 376l126-74v184l97 61v158L0 564Z',
];

export function BrandMark() {
  return (
    <div
      aria-hidden="true"
      className="flex h-10 w-10 shrink-0 items-center justify-center rounded-btn bg-accent"
    >
      <svg viewBox="0 0 636 766" className="h-[22px] w-auto fill-white">
        {TELLUS_MARK.map((d) => (
          <path key={d} d={d} />
        ))}
      </svg>
    </div>
  );
}

/** Nombre de la app: "Pase Sanitario" con "by Tellus" debajo. */
export function BrandName({ className = '' }: { className?: string }) {
  return (
    <span className="flex flex-col gap-1">
      <span className={`font-display font-bold leading-none ${className}`}>Pase Sanitario</span>
      <span className="text-[12px] font-bold leading-none text-muted">by Tellus</span>
    </span>
  );
}
