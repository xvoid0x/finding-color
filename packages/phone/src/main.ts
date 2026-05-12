import Phaser from 'phaser'
import { BootScene } from './scenes/BootScene'
import { LobbyScene } from './scenes/LobbyScene'
import { GameScene } from './scenes/GameScene'
import { HealScene } from './scenes/HealScene'
import { ChestScene } from './scenes/ChestScene'
import { ablyManager } from './lib/ably'
import { mockAblyManager } from './lib/mock-ably'

/**
 * Finding Colour -- Phone App
 * Phaser 3 game running in mobile browser.
 * Connects to Godot via Ably relay using room code.
 *
 * Test mode: add ?mock=true to URL to use in-memory mock transport.
 * Exposes mockAblyManager globally for Playwright injection.
 */

const params = new URLSearchParams(window.location.search)
const mockMode = params.get('mock') === 'true'

// In mock mode, monkey-patch the real ablyManager's methods with mock versions.
// Scenes import `ablyManager` directly and work unchanged.
if (mockMode) {
  const ma = mockAblyManager
  const ra = ablyManager as typeof ablyManager & Record<string, unknown>
  ra.connect = ma.connect.bind(ma)
  ra.disconnect = ma.disconnect.bind(ma)
  ra.reconnect = ma.reconnect.bind(ma)
  ra.send = ma.send.bind(ma)
  ra.onMessage = ma.onMessage.bind(ma)
  ra.onDisconnect = ma.onDisconnect.bind(ma)
  ra.onReconnect = ma.onReconnect.bind(ma)
  ra.getPeerId = ma.getPeerId.bind(ma)
  ra.isConnected = ma.isConnected.bind(ma)
}

if (mockMode) {
  ;(window as unknown as Record<string, unknown>).__phoneTest = {
    injectMessage: mockAblyManager.injectMessage.bind(mockAblyManager),
    drainOutgoing: mockAblyManager.drainOutgoing.bind(mockAblyManager),
    reset: mockAblyManager.reset.bind(mockAblyManager),
  }
}

const W = 800
const H = 400

const config: Phaser.Types.Core.GameConfig = {
  type: Phaser.CANVAS,
  width: W,
  height: H,
  backgroundColor: '#07050f',
  parent: 'game-container',
  scale: {
    mode: Phaser.Scale.FIT,
    autoCenter: Phaser.Scale.CENTER_BOTH,
    width: W,
    height: H,
  },
  scene: [
    BootScene,
    LobbyScene,
    GameScene,
    HealScene,
    ChestScene,
  ],
  render: {
    pixelArt: false,
    antialias: true,
  },
  input: {
    activePointers: 4,
  },
}

const game = new Phaser.Game(config)
