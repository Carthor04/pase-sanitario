import type { Config } from 'tailwindcss';

// Tokens de docs/DESIGN.md. Los valores viven como variables CSS en src/index.css
// para que el color de acento pueda cambiarse por el del colegio sin recompilar.
const token = (name: string) => `rgb(var(--${name}) / <alpha-value>)`;

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    screens: {
      sm: '640px', // por debajo: versiones Movil*
      md: '768px',
      lg: '1024px',
      xl: '1280px',
      '2xl': '1440px',
    },
    extend: {
      colors: {
        ground: token('ground'),
        surface: token('surface'),
        line: { DEFAULT: token('line'), strong: token('line-strong') },
        ink: token('ink'),
        muted: token('muted'),
        accent: token('accent'),
        dark: token('dark'),
        free: { fg: token('free-fg'), bg: token('free-bg') },
        wait: { fg: token('wait-fg'), bg: token('wait-bg'), bd: token('wait-bd') },
        alert: { fg: token('alert-fg'), bg: token('alert-bg'), bd: token('alert-bd') },
        nurse: { fg: token('nurse-fg'), bg: token('nurse-bg'), bd: token('nurse-bd') },
      },
      fontFamily: {
        display: ['"Bricolage Grotesque"', 'system-ui', 'sans-serif'],
        sans: ['"Atkinson Hyperlegible"', 'system-ui', 'sans-serif'],
        mono: ['"Atkinson Hyperlegible Mono"', 'ui-monospace', 'monospace'],
      },
      borderRadius: {
        btn: '10px',
        'btn-lg': '12px',
        card: '14px',
        'card-lg': '16px',
        chip: '999px',
      },
      minHeight: {
        touch: '44px',
        btn: '48px',
        'btn-critical': '52px',
      },
      maxWidth: {
        container: '1360px',
      },
    },
  },
  plugins: [],
} satisfies Config;
