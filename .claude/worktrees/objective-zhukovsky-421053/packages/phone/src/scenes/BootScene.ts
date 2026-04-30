import Phaser from 'phaser'

/**
 * BootScene - Minimal boot. Reads room code from URL, connects, launches app.
 * URL format: /XKQZ or /?room=XKQZ
 */
export class BootScene extends Phaser.Scene {
  constructor() {
    super({ key: 'BootScene' })
  }

  preload(): void {
    // Placeholder assets -- replace with real sprites later
    this.load.setBaseURL('/assets')
  }

  create(): void {
    // Extract room code from URL
    const params = new URLSearchParams(window.location.search)
    let roomCode = params.get('room') ?? ''

    // Also check path: /XKQZ
    if (!roomCode) {
      const pathMatch = window.location.pathname.match(/\/([A-Z]{4})$/i)
      if (pathMatch) roomCode = pathMatch[1].toUpperCase()
    }

    if (roomCode && roomCode.length === 4) {
      this.scene.start('GameScene', { roomCode: roomCode.toUpperCase() })
    } else {
      this.scene.start('LobbyScene')
    }
  }
}
