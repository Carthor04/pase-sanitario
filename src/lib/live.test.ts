import { describe, expect, it } from 'vitest';
import { canPauseBathroom, canRemoveFromQueue, isWaiting } from './live';

describe('isWaiting', () => {
  it('solo los pases que todavía no salen', () => {
    expect(isWaiting('group_wait')).toBe(true);
    expect(isWaiting('queued')).toBe(true);
    expect(isWaiting('called')).toBe(true);
    expect(isWaiting('out')).toBe(false);
    expect(isWaiting('arrived')).toBe(false);
    expect(isWaiting('returning')).toBe(false);
  });
});

describe('canRemoveFromQueue', () => {
  it('maestros, prefectura, coordinación y admin', () => {
    expect(canRemoveFromQueue(['teacher'])).toBe(true);
    expect(canRemoveFromQueue(['prefect'])).toBe(true);
    expect(canRemoveFromQueue(['coordinator'])).toBe(true);
    expect(canRemoveFromQueue(['admin'])).toBe(true);
  });

  it('no dirección, psicopedagogía ni enfermería sin otro rol', () => {
    expect(canRemoveFromQueue(['director'])).toBe(false);
    expect(canRemoveFromQueue(['counselor'])).toBe(false);
    expect(canRemoveFromQueue(['nurse'])).toBe(false);
    expect(canRemoveFromQueue(['counselor', 'teacher'])).toBe(true);
  });
});

describe('canPauseBathroom', () => {
  it('maestros, prefectura, coordinación, dirección y admin', () => {
    expect(canPauseBathroom(['teacher'])).toBe(true);
    expect(canPauseBathroom(['director'])).toBe(true);
    expect(canPauseBathroom(['nurse'])).toBe(false);
    expect(canPauseBathroom(['counselor'])).toBe(false);
  });
});
