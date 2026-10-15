import { NavLink } from 'react-router';
import type { NavItem } from '@/lib/nav';

type Props = { items: NavItem[]; badges?: Partial<Record<string, number>> };

export function BottomNav({ items, badges = {} }: Props) {
  return (
    <nav
      aria-label="Secciones"
      className="pb-safe fixed inset-x-0 bottom-0 z-20 grid border-t border-line bg-surface sm:hidden"
      style={{ gridTemplateColumns: `repeat(${items.length}, minmax(0, 1fr))` }}
    >
      {items.map((item) => {
        const badge = badges[item.to];
        return (
          <NavLink
            key={item.to}
            to={item.to}
            className={({ isActive }) =>
              [
                'flex min-h-[62px] flex-col items-center justify-center gap-0.5 border-t-[3px] text-[13px] font-bold no-underline',
                isActive ? 'border-accent text-ink' : 'border-transparent text-muted',
              ].join(' ')
            }
          >
            <span>{item.label}</span>
            {badge ? (
              <span className="rounded-chip bg-alert-fg px-1.5 text-[11px] text-white">
                {badge}
              </span>
            ) : null}
          </NavLink>
        );
      })}
    </nav>
  );
}
