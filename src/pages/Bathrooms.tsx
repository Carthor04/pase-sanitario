import { BathroomsLive } from '@/components/pass/BathroomsLive';
import { PageTitle } from '@/components/ui/Page';
import { useLivePasses } from '@/lib/live';

/** Baños (celular y escritorio): quién está dentro y en fila, por grupo, en tiempo real. */
export function Bathrooms() {
  const online = useLivePasses();
  return (
    <div className="flex flex-col gap-4">
      <PageTitle
        aside={
          <span className={`text-[14px] font-bold ${online ? 'text-free-fg' : 'text-alert-fg'}`}>
            {online ? '● En vivo' : 'Sin conexión'}
          </span>
        }
      >
        Baños
      </PageTitle>
      <BathroomsLive />
    </div>
  );
}
