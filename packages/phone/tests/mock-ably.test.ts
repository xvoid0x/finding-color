/**
 * Tests for MockAblyManager.
 */

import { describe, it, expect, beforeEach } from 'vitest'
import { MockAblyManager } from '../src/lib/mock-ably'

describe('MockAblyManager', () => {
  let mock: MockAblyManager

  beforeEach(() => {
    mock = new MockAblyManager()
  })

  it('starts disconnected', () => {
    expect(mock.isConnected()).toBe(false)
  })

  it('connects and sends initial state', async () => {
    const messages: unknown[] = []
    mock.onMessage((msg) => messages.push(msg))

    await mock.connect('TEST')

    expect(mock.isConnected()).toBe(true)
    expect(messages.length).toBe(1)
    expect((messages[0] as Record<string, unknown>).type).toBe('state')
  })

  it('injectMessage delivers to handlers', () => {
    const messages: unknown[] = []
    mock.onMessage((msg) => messages.push(msg))

    mock.injectMessage({
      type: 'event_start',
      event: 'heal',
      window: 5,
      floor: 1,
      guardian_hp: 5,
      guardian_max_hp: 5,
    })

    expect(messages.length).toBe(1)
    expect((messages[0] as Record<string, unknown>).type).toBe('event_start')
  })

  it('queues outgoing messages via send', async () => {
    await mock.send({
      type: 'event_response',
      event: 'heal',
      score: 3,
      max_score: 3,
    })

    const outgoing = mock.peekOutgoing()
    expect(outgoing.length).toBe(1)
    expect(outgoing[0]).toEqual({
      type: 'event_response',
      event: 'heal',
      score: 3,
      max_score: 3,
    })
  })

  it('drainOutgoing clears the queue', async () => {
    await mock.send({ type: 'event_response', event: 'heal', score: 3, max_score: 3 })
    const drained = mock.drainOutgoing()
    expect(drained.length).toBe(1)
    expect(mock.peekOutgoing().length).toBe(0)
  })

  it('reset clears all state', () => {
    mock.onMessage(() => {})
    mock.onDisconnect(() => {})
    mock.connect('TEST')

    mock.reset()
    expect(mock.isConnected()).toBe(false)
    expect(mock.peekOutgoing().length).toBe(0)

    // Handlers should be gone — injecting shouldn't error
    expect(() => mock.injectMessage({ type: 'state' as never })).not.toThrow()
  })
})
