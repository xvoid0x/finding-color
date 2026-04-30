import type { THapticPattern } from '@finding-colour/shared'

/**
 * HapticManager - Wraps the Web Vibration API.
 * Patterns teach the phone player to recognise events by feel.
 */

const PATTERNS: Record<THapticPattern, number[]> = {
  short_triple:  [80, 60, 80, 60, 80],        // heal -- three short
  long_double:   [200, 100, 200],              // power attack -- two heavy
  long_single:   [300],                        // chest/door -- one long
  escalating:    [100, 50, 150, 50, 250],      // boss -- building intensity
}

export function vibrate(pattern: THapticPattern): void {
  if (!navigator.vibrate) return
  navigator.vibrate(PATTERNS[pattern])
}

export function vibrateSuccess(): void {
  if (!navigator.vibrate) return
  navigator.vibrate([50, 30, 50, 30, 100])
}

export function vibrateFailure(): void {
  if (!navigator.vibrate) return
  navigator.vibrate([300])
}
