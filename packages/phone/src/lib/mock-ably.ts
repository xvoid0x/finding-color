/**
 * MockAblyManager — Drop-in replacement for AblyManager in test/dev mode.
 *
 * Activated by adding `?mock=true` to the phone app URL (or in tests).
 * Instead of connecting to Ably, it queues messages in memory and exposes
 * injection methods so tests can simulate Godot messages.
 */

import type { TServerMessage, TClientMessage } from '@finding-colour/shared'

type ServerMessageHandler = (msg: TServerMessage) => void
type VoidHandler = () => void

export class MockAblyManager {
  private handlers: ServerMessageHandler[] = []
  private disconnectHandlers: VoidHandler[] = []
  private reconnectHandlers: VoidHandler[] = []
  private outgoing: TClientMessage[] = []
  private _connected = false
  private _peerId = 'mock-phone'

  getPeerId(): string {
    return this._peerId
  }

  isConnected(): boolean {
    return this._connected
  }

  async connect(_roomCode: string): Promise<void> {
    this._connected = true
    this.reconnectHandlers.forEach(h => h())
    // Send an initial state to simulate Godot joining
    this.injectMessage({
      type: 'state',
      floor: 1,
      guardian_hp: 5,
      guardian_max_hp: 5,
      event_active: false,
      event_type: null,
      enemies_alive: 0,
      companion_anchored: false,
      dreamer_fragments: 0,
    })
  }

  async disconnect(): Promise<void> {
    this._connected = false
    this.disconnectHandlers.forEach(h => h())
  }

  async reconnect(roomCode: string): Promise<void> {
    await this.disconnect()
    await this.connect(roomCode)
  }

  /** Inject a message as if it came from Godot over Ably */
  injectMessage(msg: TServerMessage): void {
    this.handlers.forEach(h => h(msg))
  }

  /** Register handler for incoming (Godot → Phone) messages */
  onMessage(handler: ServerMessageHandler): void {
    this.handlers.push(handler)
  }

  onDisconnect(handler: VoidHandler): void {
    this.disconnectHandlers.push(handler)
  }

  onReconnect(handler: VoidHandler): void {
    this.reconnectHandlers.push(handler)
  }

  /** "Send" a message as if the phone sent it to Godot */
  async send(message: TClientMessage): Promise<void> {
    this.outgoing.push(message)
  }

  /** Pop all outgoing messages sent by the phone app since last check */
  drainOutgoing(): TClientMessage[] {
    const msgs = [...this.outgoing]
    this.outgoing = []
    return msgs
  }

  /** Peek at outgoing without clearing */
  peekOutgoing(): TClientMessage[] {
    return [...this.outgoing]
  }

  /** Clear all state (for test cleanup) */
  reset(): void {
    this.handlers = []
    this.disconnectHandlers = []
    this.reconnectHandlers = []
    this.outgoing = []
    this._connected = false
  }
}

/** Singleton — same pattern as the real ablyManager */
export const mockAblyManager = new MockAblyManager()
