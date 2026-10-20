import { getInstallState, promptInstall } from './install';

vi.mock('./supabase', () => ({ supabase: {} }));

describe('instalar app', () => {
  beforeEach(() => {
    window.matchMedia = vi.fn().mockReturnValue({ matches: false }) as never;
  });

  it('sin aviso del navegador da los pasos del menú; con aviso, el botón; cancelado, otra vez el menú', async () => {
    expect(getInstallState()).toBe('manual');

    const prompt = vi.fn().mockResolvedValue(undefined);
    const e = Object.assign(new Event('beforeinstallprompt'), {
      prompt,
      userChoice: Promise.resolve({ outcome: 'dismissed' }),
    });
    window.dispatchEvent(e);
    expect(getInstallState()).toBe('prompt');

    await expect(promptInstall()).resolves.toBe(false);
    expect(prompt).toHaveBeenCalled();
    expect(getInstallState()).toBe('manual');
  });

  it('en iPhone da los pasos de Safari', () => {
    const ua = vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue('Mozilla/5.0 (iPhone)');
    expect(getInstallState()).toBe('ios');
    ua.mockRestore();
  });

  it('abierta desde el ícono no muestra nada', () => {
    window.matchMedia = vi.fn().mockReturnValue({ matches: true }) as never;
    expect(getInstallState()).toBe('installed');
  });
});
