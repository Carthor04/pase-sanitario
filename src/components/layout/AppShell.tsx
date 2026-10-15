import { NavLink, Outlet } from 'react-router';
import { env } from '@/lib/env';
import { navForRoles } from '@/lib/nav';
import { useStaff } from '@/lib/session';
import { useClock } from '@/lib/useClock';
import { BottomNav } from './BottomNav';
import { BrandMark } from './BrandMark';

export function AppShell() {
  const { roles } = useStaff();
  const items = navForRoles(roles);
  const clock = useClock();

  return (
    <div className="flex min-h-screen flex-col">
      {env.demoMode ? (
        <div className="bg-wait-bg px-4 py-1 text-center text-[13px] font-bold text-wait-fg">
          MODO DEMO · datos ficticios
        </div>
      ) : null}

      <header className="border-b border-line bg-surface">
        <div className="mx-auto flex max-w-container items-center gap-3 px-4 py-3 sm:gap-8 sm:px-6 sm:py-3.5">
          <div className="flex items-center gap-3">
            <BrandMark />
            <span className="font-display text-xl font-bold leading-none sm:text-[26px]">
              Pase Sanitario
            </span>
          </div>

          <nav aria-label="Secciones" className="hidden flex-1 gap-1 sm:flex">
            {items.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) =>
                  [
                    'inline-flex min-h-touch items-center rounded-btn px-3.5 text-[15px] font-bold',
                    isActive ? 'bg-ground text-ink' : 'text-muted hover:text-ink',
                  ].join(' ')
                }
              >
                {item.label}
              </NavLink>
            ))}
          </nav>

          <span className="ml-auto font-mono text-[22px] font-semibold tabular-nums">{clock}</span>
        </div>
      </header>

      <main className="pb-bottom-nav mx-auto w-full max-w-container flex-1 px-4 pt-4 sm:p-6">
        <Outlet />
      </main>

      <BottomNav items={items} />
    </div>
  );
}
