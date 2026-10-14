type Props = { title: string; phase: number; description?: string };

export function Placeholder({ title, phase, description }: Props) {
  return (
    <section className="flex flex-col gap-3">
      <h1 className="m-0 font-display text-[22px] font-bold sm:text-[28px]">{title}</h1>
      <div className="flex flex-col gap-1 rounded-card border border-line bg-surface p-5">
        <span className="font-bold">Esta pantalla todavía no está lista.</span>
        <span className="text-muted">{description ?? `Se construye en la Fase ${phase}.`}</span>
      </div>
    </section>
  );
}
