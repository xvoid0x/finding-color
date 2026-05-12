/**
 * Chest unlock minigame logic — pure functions, no Phaser dependency.
 * Extracted from ChestScene for testability.
 */

export function angleInArc(angle: number, start: number, size: number): boolean {
  const tau = Math.PI * 2
  const end = (start + size) % tau
  const a = ((angle % tau) + tau) % tau
  const s = ((start % tau) + tau) % tau

  if (s <= end) {
    return a >= s && a <= end
  } else {
    // Arc wraps around 0
    return a >= s || a <= end
  }
}

export interface DialState {
  angle: number
  speed: number
  targetStart: number
  targetSize: number
  held: boolean
}

export function updateDial(dial: DialState, dt: number): DialState {
  if (!dial.held) {
    dial.angle += dial.speed * dt
  }
  // Normalize
  const tau = Math.PI * 2
  dial.angle = ((dial.angle % tau) + tau) % tau
  return dial
}

export function isDialLocked(dial: DialState): boolean {
  return dial.held && angleInArc(dial.angle, dial.targetStart, dial.targetSize)
}

export function getChestResult(dialCount: number, lockedCount: number, success: boolean): { label: string; color: string } {
  if (success) {
    return { label: 'Unlocked!', color: '#44dd88' }
  }
  if (lockedCount > 0) {
    return { label: `${lockedCount}/${dialCount}`, color: '#ffcc44' }
  }
  return { label: 'Failed', color: '#d84040' }
}

export function getDialCount(window: number): number {
  return window >= 7 ? 3 : 4
}
