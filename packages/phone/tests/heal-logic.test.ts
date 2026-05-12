/**
 * Tests for heal minigame logic (pure functions, no Phaser dependency).
 */

import { describe, it, expect } from 'vitest'
import { getHealResult, HEAL_BEAT_COUNT, normalizeAngle } from '../src/lib/game-logic'

describe('getHealResult', () => {
  it('returns Perfect! for 3/3', () => {
    const result = getHealResult(3)
    expect(result.label).toBe('Perfect!')
    expect(result.color).toBe('#44ff88')
  })

  it('returns X / 3 for partial scores', () => {
    const result = getHealResult(2)
    expect(result.label).toBe('2 / 3')
    expect(result.color).toBe('#ffcc44')
  })

  it('returns Missed for 0/3', () => {
    const result = getHealResult(0)
    expect(result.label).toBe('Missed')
    expect(result.color).toBe('#ff4444')
  })

  it('handles 1/3 correctly', () => {
    const result = getHealResult(1)
    expect(result.label).toBe('1 / 3')
  })
})

describe('normalizeAngle', () => {
  it('normalizes 0 to 0', () => {
    expect(normalizeAngle(0)).toBeCloseTo(0)
  })

  it('wraps negative angles', () => {
    expect(normalizeAngle(-Math.PI)).toBeCloseTo(Math.PI)
  })

  it('wraps angles > 2π', () => {
    expect(normalizeAngle(Math.PI * 3)).toBeCloseTo(Math.PI)
  })

  it('keeps angles in [0, 2π) unchanged', () => {
    expect(normalizeAngle(1.5)).toBeCloseTo(1.5)
  })
})
