// Sonido de turno y pantalla siempre encendida para la computadora del salón.
import { useEffect } from 'react';

let audio: AudioContext | null = null;

/** Los navegadores solo dejan sonar audio después de un toque: se llama al primer toque. */
export function unlockAudio() {
  if (audio) return;
  const Ctx =
    window.AudioContext ??
    (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (Ctx) audio = new Ctx();
}

/** Dos tonos cortos ("¡ding-dong!") para "Su turno". */
export function playTurnSound() {
  if (!audio) return;
  const start = audio.currentTime;
  [880, 660].forEach((freq, i) => {
    const osc = audio!.createOscillator();
    const gain = audio!.createGain();
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.0001, start + i * 0.22);
    gain.gain.exponentialRampToValueAtTime(0.25, start + i * 0.22 + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + i * 0.22 + 0.2);
    osc.connect(gain).connect(audio!.destination);
    osc.start(start + i * 0.22);
    osc.stop(start + i * 0.22 + 0.21);
  });
}

/** Tres pitidos agudos para una alerta de tiempo. */
export function playAlertSound() {
  if (!audio) return;
  const start = audio.currentTime;
  [0, 0.18, 0.36].forEach((t) => {
    const osc = audio!.createOscillator();
    const gain = audio!.createGain();
    osc.type = 'square';
    osc.frequency.value = 988;
    gain.gain.setValueAtTime(0.0001, start + t);
    gain.gain.exponentialRampToValueAtTime(0.18, start + t + 0.01);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + t + 0.14);
    osc.connect(gain).connect(audio!.destination);
    osc.start(start + t);
    osc.stop(start + t + 0.15);
  });
}

/** Activa el audio con el primer toque o tecla de la página. */
export function useAudioUnlock() {
  useEffect(() => {
    const handler = () => unlockAudio();
    window.addEventListener('pointerdown', handler, { once: true });
    window.addEventListener('keydown', handler, { once: true });
    return () => {
      window.removeEventListener('pointerdown', handler);
      window.removeEventListener('keydown', handler);
    };
  }, []);
}

/** Mantiene la pantalla encendida (Wake Lock API) mientras la página esté visible. */
export function useWakeLock(enabled = true) {
  useEffect(() => {
    if (!enabled || !('wakeLock' in navigator)) return;
    let sentinel: WakeLockSentinel | null = null;
    let cancelled = false;
    const request = async () => {
      try {
        sentinel = await navigator.wakeLock.request('screen');
        if (cancelled) void sentinel.release();
      } catch {
        // Sin permiso o batería baja: no pasa nada, solo no se mantiene encendida.
      }
    };
    const onVisible = () => {
      if (document.visibilityState === 'visible') void request();
    };
    void request();
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', onVisible);
      void sentinel?.release();
    };
  }, [enabled]);
}
