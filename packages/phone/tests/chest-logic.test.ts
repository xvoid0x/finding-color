/**
 * Tests for chest unlock minigame logic (pure functions, no Phaser dependency).
 */

import { describe, it, expect } from 'vitest'
import {
  angleInArc,
  updateDial,
  isDialLocked,
  getChestResult,
  getDialCount,
} from '../src/lib/chest-logic'

describe('angleInArc', () => {
  it('returns true when angle is inside arc (no wrap)', () => {
    expect(angleInArc(1.0, 0.5, 1.0)).toBe(true)
  })

  it('returns false when angle is outside arc (no wrap)', () => {
    expect(angleInArc(0.1, 0.5, 1.0)).toBe(false)
  })

  it('handles arc that wraps around 0', () => {
    // Arc from 5.5 rad to 6.5 rad (wraps past 2π ≈ 6.28)
    // With tau=2π≈6.283, start=5.5, size=1.0 => end≈0.217
    // angle=6.0 should be in the arc
    const tau = Math.PI * 2
    expect(angleInArc(6.0, 5.5, 1.0)).toBe(true)
  })

  it('returns false for angle outside wrapped arc', () => {
    // start=5.5, size=1.0 => wrapped arc [5.5, 6.283) ∪ [0, 0.217)
    // angle=3.0 should be outside
    expect(angleInArc(3.0, 5.5, 1.0)).toBe(false)
  })
})

describe('updateDial', () => {
  it('advances angle when not held', () => {
    const dial: import('../src/lib/chest-logic').DialState = {
      angle: 0,
      speed: 1.0,
      targetStart: 0,
      targetSize: 0.5,
      held: false,
    }
    const result = updateDial(dial, 0.5)
    expect(result.angle).toBeCloseTo(0.5)
  })

  it('freezes angle when held', () => {
    const dial: import('../src/lib/chest-logic').DialState = {
      angle: 1.0,
      speed: 1.0,
      targetStart: 0,
      targetSize: 0.5,
      held: true,
    }
    const result = updateDial(dial, 0.5)
    expect(result.angle).toBeCloseTo(1.0)
  })
})

describe('isDialLocked', () => {
  it('returns true when held and in zone', () => {
    const dial: import('../src/lib/chest-logic').DialState = {
      angle: 0.5,
      speed: 1.0,
      targetStart: 0,
      targetSize: 1.0,
      held: true,
    }
    expect(isDialLocked(dial)).toBe(true)
  })

  it('returns false when held but not in zone', () => {
    const dial: import('../src/lib/chest-logic').DialState = {
      angle: 3.0,
      speed: 1.0,
      targetStart: 0,
      targetSize: 1.0,
      held: true,
    }
    expect(isDialLocked(dial)).toBe(false)
  })

  it('returns false when in zone but not held', () => {
    const dial: import('../src/lib/chest-logic').DialState = {
      angle: 0.5,
      speed: 1.0,
      targetStart: 0,
      targetSize: 1.0,
      held: false,
    }
    expect(isDialLocked(dial)).toBe(false)
  })
})

describe('getChestResult', () => {
  it('returns Unlocked! on success', () => {
    const result = getChestResult(3, 3, true)
    expect(result.label).toBe('Unlocked!')
    expect(result.color).toBe('#44dd88')
  })

  it('returns fractional label on partial failure', () => {
    const result = getChestResult(3, 2, false)
    expect(result.label).toBe('2/3')
  })

  it('returns Failed on total failure', () => {
    const result = getChestResult(3, 0, false)
    expect(result.label).toBe('Failed')
    expect(result.color).toBe('#d84040')
  })
})

describe('getDialCount', () => {
  it('returns 3 for window >= 7', () => {
    expect(getDialCount(7)).toBe(3)
    expect(getDialCount(8)).toBe(3)
  })

  it('returns 4 for window < 7', () => {
    expect(getDialCount(6)).toBe(4)
    expect(getDialCount(3)).toBe(4)
  })
})
