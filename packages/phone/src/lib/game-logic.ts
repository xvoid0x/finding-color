/**
 * Heal minigame logic — pure functions, no Phaser dependency.
 * Extracted from HealScene for testability.
 */

export const HEAL_BEAT_COUNT = 3

export interface HealResult {
  label: string
  color: string
}

export function getHealResult(beatsLanded: number): HealResult {
  const ratio = beatsLanded / HEAL_BEAT_COUNT
  if (ratio >= 1) {
    return { label: 'Perfect!', color: '#44ff88' }
  } else if (ratio > 0) {
    return { label: `${beatsLanded} / ${HEAL_BEAT_COUNT}`, color: '#ffcc44' }
  } else {
    return { label: 'Missed', color: '#ff4444' }
  }
}

export function normalizeAngle(angle: number): number {
  const tau = Math.PI * 2
  return ((angle % tau) + tau) % tau
}
