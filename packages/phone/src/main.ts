import Phaser from 'phaser'
import { BootScene } from './scenes/BootScene'
import { LobbyScene } from './scenes/LobbyScene'
import { GameScene } from './scenes/GameScene'
import { HealScene } from './scenes/HealScene'
import { ChestScene } from './scenes/ChestScene'

/**
 * Finding Colour -- Phone App
 * Phaser 3 game running in mobile browser.
 * Connects to Godot via Ably relay using room code.
 */

// Landscape layout: wider than tall.
// On mobile, use full screen dimensions (landscape lock handled via CSS/manifest).
// On desktop browser (second player on PC), use a sensible landscape window.
// Use a fixed logical resolution in landscape.
// Phaser Scale.FIT will letterbox/fit to the actual screen.
// This avoids dimension issues when phone loads in portrait.
const W = 800
const H = 400

const config: Phaser.Types.Core.GameConfig = {
  type: Phaser.CANVAS,  // Force canvas — WebGL context fails silently on some mobile browsers
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
    pixelArt: false,  // phone UI uses smooth rendering
    antialias: true,
  },
  input: {
    activePointers: 4,  // support multi-touch
  },
}

new Phaser.Game(config)
