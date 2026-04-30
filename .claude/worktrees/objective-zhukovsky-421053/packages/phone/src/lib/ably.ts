import Ably from 'ably'
import {
  ServerMessage,
  ClientMessage,
  type TServerMessage,
  type TClientMessage,
} from '@finding-colour/shared'
import { vibrate } from './haptic'

/**
 * AblyManager - Handles connection to Ably relay.
 * Godot publishes to topic "server", phone subscribes.
 * Phone publishes to topic "client", Godot subscribes.
 */

// Replace with real key from Ably dashboard (free tier is fine)
const ABLY_API_KEY = import.meta.env.VITE_ABLY_API_KEY as string

type ServerMessageHandler = (msg: TServerMessage) => void
type VoidHandler = () => void

export class AblyManager {
  private client: Ably.Realtime | null = null
  private channel: Ably.RealtimeChannel | null = null
  private roomCode: string = ''
  private handlers: ServerMessageHandler[] = []
  private disconnectHandlers: VoidHandler[] = []
  private reconnectHandlers: VoidHandler[] = []
  private peerId: string = this._generateId()

  private _generateId(): string {
    // crypto.randomUUID() requires HTTPS — fallback for HTTP dev
    if (typeof crypto !== 'undefined' && crypto.randomUUID) {
      return crypto.randomUUID()
    }
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = Math.random() * 16 | 0
      return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16)
    })
  }

  async connect(roomCode: string): Promise<void> {
    this.roomCode = roomCode.toUpperCase()

    this.client = new Ably.Realtime({
      key: ABLY_API_KEY,
      clientId: this.peerId,
    })

    await new Promise<void>((resolve, reject) => {
      this.client!.connection.on('connected', resolve)
      this.client!.connection.on('failed', reject)
    })

    // Wire disconnect/reconnect events
    this.client!.connection.on('disconnected', () => {
      this.disconnectHandlers.forEach(h => h())
    })
    this.client!.connection.on('suspended', () => {
      this.disconnectHandlers.forEach(h => h())
    })
    this.client!.connection.on('connected', () => {
      this.reconnectHandlers.forEach(h => h())
    })

    this.channel = this.client.channels.get(`game-${this.roomCode}`)

    // Subscribe to server messages (Godot -> Phone)
    await this.channel.subscribe('server', (msg) => {
      try {
        const data = typeof msg.data === 'string' ? JSON.parse(msg.data) : msg.data
        const result = ServerMessage.safeParse(data)
        if (!result.success) {
          console.warn('Invalid server message:', result.error.flatten())
          return
        }
        // Handle haptic immediately before dispatching
        if (result.data.type === 'haptic') {
          vibrate(result.data.pattern)
        }
        this.handlers.forEach(h => h(result.data))
      } catch (e) {
        console.error('Failed to parse server message:', e)
      }
    })
  }

  onMessage(handler: ServerMessageHandler): void {
    this.handlers.push(handler)
  }

  onDisconnect(handler: VoidHandler): void {
    this.disconnectHandlers.push(handler)
  }

  onReconnect(handler: VoidHandler): void {
    this.reconnectHandlers.push(handler)
  }

  async reconnect(roomCode: string): Promise<void> {
    await this.disconnect()
    await this.connect(roomCode)
  }

  async send(message: TClientMessage): Promise<void> {
    if (!this.channel) {
      console.warn('AblyManager: not connected, cannot send')
      return
    }
    // Validate before sending
    const result = ClientMessage.safeParse(message)
    if (!result.success) {
      console.error('Invalid client message:', result.error.flatten())
      return
    }
    await this.channel.publish('client', JSON.stringify(result.data))
  }

  async disconnect(): Promise<void> {
    this.channel?.unsubscribe()
    this.client?.close()
    this.channel = null
    this.client = null
  }

  getPeerId(): string {
    return this.peerId
  }

  isConnected(): boolean {
    return this.client?.connection.state === 'connected'
  }
}

// Singleton
export const ablyManager = new AblyManager()
