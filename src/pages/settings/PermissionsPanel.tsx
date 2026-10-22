import { useState } from 'react';
import { Card, Loading, Notice, SectionLabel } from '@/components/ui/Page';
import { buttonClass } from '@/components/ui/styles';
import { errorMessage } from '@/lib/live';
import { GRANTABLE_TABS, ROLES, ROLE_LABELS, type Role } from '@/lib/nav';
import {
  matchesStaff,
  sameSet,
  toggle,
  usePermissions,
  useSavePermission,
  type PermissionStaff,
} from '@/lib/permissions';
import { useStaff } from '@/lib/session';

/** Botón de sí/no: la palomita también dice si está activo, no solo el color. */
function Chip({ on, label, onClick }: { on: boolean; label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-pressed={on}
      onClick={onClick}
      className={`inline-flex min-h-btn items-center gap-1.5 rounded-btn border px-3.5 text-[15px] font-bold ${
        on ? 'border-ink bg-ink text-white' : 'border-line-strong bg-surface text-muted'
      }`}
    >
      <span aria-hidden="true">{on ? '✓' : '+'}</span>
      {label}
    </button>
  );
}

function RoleTabs({ role, saved }: { role: Role; saved: string[] }) {
  const [tabs, setTabs] = useState(saved);
  const save = useSavePermission();
  const dirty = !sameSet(tabs, saved);

  return (
    <div className="flex flex-col gap-2 border-t border-line pt-3 first:border-t-0 first:pt-0">
      <strong className="text-[17px]">{ROLE_LABELS[role]}</strong>
      <div className="flex flex-wrap gap-2">
        {GRANTABLE_TABS.map((t) => (
          <Chip
            key={t.id}
            on={tabs.includes(t.id)}
            label={t.label}
            onClick={() => setTabs((x) => toggle(x, t.id))}
          />
        ))}
      </div>
      {save.isError ? <Notice tone="error">{errorMessage(save.error)}</Notice> : null}
      {dirty ? (
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            disabled={save.isPending}
            onClick={() => save.mutate({ kind: 'role', role, tabs })}
            className={buttonClass.primary}
          >
            Guardar {ROLE_LABELS[role]}
          </button>
          <button type="button" onClick={() => setTabs(saved)} className={buttonClass.secondary}>
            Deshacer
          </button>
        </div>
      ) : null}
    </div>
  );
}

function PersonRoles({ person, isMe }: { person: PermissionStaff; isMe: boolean }) {
  const [roles, setRoles] = useState<Role[]>(person.roles);
  const save = useSavePermission();
  const dirty = !sameSet(roles, person.roles);

  return (
    <li className="flex flex-col gap-2 border-t border-line pt-3 first:border-t-0 first:pt-0">
      <span className="flex min-w-0 flex-col">
        <strong className="truncate">
          {person.full_name}
          {isMe ? ' · tú' : ''}
          {person.active ? '' : ' · dado de baja'}
        </strong>
        <span className="truncate text-[13px] text-muted">{person.email}</span>
      </span>
      <div className="flex flex-wrap gap-2">
        {ROLES.map((r) => (
          <Chip
            key={r}
            on={roles.includes(r)}
            label={ROLE_LABELS[r]}
            onClick={() => setRoles((x) => toggle(x, r))}
          />
        ))}
      </div>
      {save.isError ? <Notice tone="error">{errorMessage(save.error)}</Notice> : null}
      {dirty ? (
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            disabled={save.isPending || roles.length === 0}
            onClick={() => save.mutate({ kind: 'staff', staffId: person.id, roles })}
            className={buttonClass.primary}
          >
            Guardar roles
          </button>
          <button
            type="button"
            onClick={() => setRoles(person.roles)}
            className={buttonClass.secondary}
          >
            Deshacer
          </button>
        </div>
      ) : null}
      {roles.length === 0 ? (
        <span className="text-[14px] text-alert-fg">Elige al menos un rol.</span>
      ) : null}
    </li>
  );
}

/** Ajustes → Permisos (solo admin): pestañas que ve cada rol y roles de cada persona. */
export function PermissionsPanel() {
  const me = useStaff();
  const query = usePermissions();
  const [search, setSearch] = useState('');

  if (query.isError) return <Notice tone="error">{errorMessage(query.error)}</Notice>;
  if (!query.data) return <Loading />;
  const { role_tabs, staff } = query.data;
  const people = staff.filter((p) => matchesStaff(p, search));

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <SectionLabel>Pestañas por rol</SectionLabel>
        <p className="m-0 text-[15px] text-muted">
          Lo que puede hacer cada quien dentro de una pantalla depende de su rol. Quien ve En vivo
          ya tiene ahí Baños y Alertas. Perfil y Ajustes no se cambian aquí.
        </p>
        {ROLES.map((r) => {
          const saved = role_tabs[r] ?? [];
          // La key reinicia el borrador cuando cambia lo guardado.
          return <RoleTabs key={`${r}:${[...saved].sort().join(',')}`} role={r} saved={saved} />;
        })}
      </Card>

      <Card>
        <SectionLabel>Roles por persona</SectionLabel>
        <label className="flex flex-col gap-1">
          <span className="font-bold">Buscar</span>
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Nombre o correo"
            className="min-h-btn rounded-btn border border-line-strong px-3 text-[17px]"
          />
        </label>
        {people.length === 0 ? <p className="m-0 text-muted">Nadie con ese nombre.</p> : null}
        <ul className="m-0 flex list-none flex-col gap-3 p-0">
          {people.map((p) => (
            <PersonRoles
              key={`${p.id}:${[...p.roles].sort().join(',')}`}
              person={p}
              isMe={p.id === me.id}
            />
          ))}
        </ul>
      </Card>
    </div>
  );
}
