import { useId, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router';
import { Card, Loading, Notice, PageTitle } from '@/components/ui/Page';
import { hhmm, useMyGroups, useStudents } from '@/lib/queries';

const RANK_LABELS = ['Ahora', 'Mis grupos', 'Otros grupos'] as const;

const normalize = (s: string) =>
  s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');

/**
 * Mi grupo (celular): por defecto el grupo de la hora actual; se puede cambiar a cualquier
 * grupo para suplencias. Los pases se agregan en la Fase 3.
 */
export function MyGroup() {
  const selectId = useId();
  const searchId = useId();
  const [params, setParams] = useSearchParams();
  const [query, setQuery] = useState('');
  const groups = useMyGroups();

  const list = groups.data ?? [];
  const selected = list.find((g) => g.group_id === params.get('g')) ?? list[0];
  const students = useStudents(selected?.group_id);

  const filtered = useMemo(() => {
    const q = normalize(query.trim());
    const all = students.data ?? [];
    if (!q) return all;
    return all.filter((s) => normalize(s.full_name).includes(q) || String(s.list_number) === q);
  }, [students.data, query]);

  if (groups.isPending) return <Loading />;
  if (groups.isError) return <Notice tone="error">No se pudieron cargar los grupos.</Notice>;
  if (!selected) {
    return (
      <div className="flex flex-col gap-4">
        <PageTitle>Mi grupo</PageTitle>
        <Notice>Todavía no hay grupos. Coordinación los importa en Ajustes → Grupos.</Notice>
      </div>
    );
  }

  const byRank = [0, 1, 2].map((rank) => list.filter((g) => g.rank === rank));

  return (
    <div className="flex flex-col gap-4">
      <Card className="gap-2 p-4">
        <div className="flex flex-wrap items-center gap-3">
          <label htmlFor={selectId} className="sr-only">
            Grupo
          </label>
          <select
            id={selectId}
            value={selected.group_id}
            onChange={(e) => setParams({ g: e.target.value }, { replace: true })}
            className="min-h-btn rounded-btn border border-line-strong bg-surface px-3 font-display text-[22px] font-bold"
          >
            {byRank.map((items, rank) =>
              items.length ? (
                <optgroup key={rank} label={RANK_LABELS[rank]}>
                  {items.map((g) => (
                    <option key={g.group_id} value={g.group_id}>
                      {g.name}
                      {g.rank === 0 && g.subject ? ` · ${g.subject}` : ''}
                    </option>
                  ))}
                </optgroup>
              ) : null,
            )}
          </select>
          <div className="flex min-w-0 flex-col">
            {selected.subject ? (
              <>
                <span className="text-[17px] font-bold">{selected.subject}</span>
                <span className="font-mono text-[15px] tabular-nums text-muted">
                  {hhmm(selected.starts)} – {hhmm(selected.ends)}
                  {selected.teacher_name ? ` · ${selected.teacher_name}` : ''}
                </span>
              </>
            ) : (
              <span className="text-muted">Sin clase en este momento</span>
            )}
          </div>
          {selected.rank === 0 ? (
            <span className="ml-auto rounded-chip bg-free-bg px-2.5 py-0.5 text-[13px] font-bold text-free-fg">
              Tu clase ahora
            </span>
          ) : null}
        </div>
        {selected.room ? <span className="text-[15px] text-muted">{selected.room}</span> : null}
      </Card>

      <div className="flex flex-col gap-1.5">
        <label htmlFor={searchId} className="text-[15px] font-bold">
          Buscar alumno
        </label>
        <input
          id={searchId}
          type="search"
          placeholder="Buscar nombre o # de lista"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="min-h-btn rounded-btn border border-line-strong bg-surface px-4 text-[17px]"
        />
      </div>

      {students.isPending ? <Loading /> : null}
      {students.isError ? <Notice tone="error">No se pudo cargar la lista.</Notice> : null}
      {students.data && !students.data.length ? (
        <Notice>Este grupo no tiene alumnos. Coordinación los importa en Ajustes → Alumnos.</Notice>
      ) : null}

      <ul className="m-0 grid list-none gap-2 p-0 sm:grid-cols-[repeat(auto-fill,minmax(260px,1fr))]">
        {filtered.map((s) => (
          <li
            key={s.id}
            className="flex min-h-[52px] items-center gap-3 rounded-btn-lg border border-line bg-surface px-3"
          >
            <span className="w-7 text-right font-mono text-[15px] font-semibold tabular-nums text-muted">
              {s.list_number}
            </span>
            <span className="min-w-0 flex-1 truncate text-[17px]">{s.full_name}</span>
            <span
              className="rounded-chip border border-line px-2 text-[13px] font-bold text-muted"
              aria-label={s.sex === 'H' ? 'Hombre' : 'Mujer'}
            >
              {s.sex}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
