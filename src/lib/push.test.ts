import { getPushState, isIos, urlBase64ToUint8Array } from './push';

vi.mock('./supabase', () => ({ supabase: { rpc: vi.fn() } }));

describe('push', () => {
  it('convierte la llave VAPID de base64url a bytes', () => {
    expect(Array.from(urlBase64ToUint8Array('AQID_-8'))).toEqual([1, 2, 3, 255, 239]);
  });

  it('reconoce iPhone y iPad', () => {
    expect(isIos('Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)')).toBe(true);
    expect(isIos('Mozilla/5.0 (Linux; Android 14; Pixel 8)')).toBe(false);
  });

  it('en iPhone sin instalar pide primero agregar a inicio', async () => {
    const ua = vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue('Mozilla/5.0 (iPhone)');
    window.matchMedia = vi.fn().mockReturnValue({ matches: false }) as never;
    await expect(getPushState()).resolves.toBe('ios-install');
    ua.mockRestore();
  });

  it('sin soporte de Web Push lo dice', async () => {
    window.matchMedia = vi.fn().mockReturnValue({ matches: false }) as never;
    await expect(getPushState()).resolves.toBe('unsupported');
  });
});
