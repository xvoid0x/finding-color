import Phaser from 'phaser'
import { ablyManager } from '../lib/ably'
import type { TServerMessage, TGameStateMessage } from '@finding-colour/shared'

/**
 * GameScene - Phone companion screen. Landscape layout. Option A breathing.
 *
 * IDLE STATE:
 *   Thin top bar: hearts | floor | room code
 *   Centre: large companion with glow, status text below
 *   Thin bottom bar: enemies | fragments | companion state
 *
 * EVENT STATE:
 *   Top strip (squished): hearts | floor | fragments | tiny companion
 *   Centre: minigame fills everything below the strip
 *
 * Colour pillars (UI_PILLARS.md):
 *   Blue  #3a7bd5 — guardian / events
 *   Gold  #f5c842 — companion
 *   Purple #a050dc — fragments / dreamer
 *   Green #44dd88 — success / connected
 *   Red   #d84040 — damage / danger
 *   Base  #07050f — background
 */

const C = {
  bg:       0x07050f,
  panel:    0x0d0a1c,
  sep:      0x1c1630,
  blue:     0x3a7bd5,
  blueDim:  0x1a3a6a,
  gold:     0xf5c842,
  goldDim:  0x6e550f,
  purple:   0xa050dc,
  green:    0x44dd88,
  red:      0xd84040,
  white:    0xdcdce8,
  dim:      0x50506e,
}

const TOP_BAR_H_IDLE   = 0.13   // fraction of screen height
const TOP_STRIP_H_EVENT = 0.09
const BOT_BAR_H        = 0.13

export class GameScene extends Phaser.Scene {
  private roomCode: string = ''
  private gameState: TGameStateMessage | null = null
  private eventActive: boolean = false

  // Layout
  private W: number = 0
  private H: number = 0

  // Top bar (idle)
  private topBarBg!: Phaser.GameObjects.Rectangle
  private heartObjects: Phaser.GameObjects.Arc[] = []
  private floorText!: Phaser.GameObjects.Text
  private roomCodeText!: Phaser.GameObjects.Text

  // Top strip (event — squished)
  private topStripBg!: Phaser.GameObjects.Rectangle
  private stripHearts: Phaser.GameObjects.Arc[] = []
  private stripFloorText!: Phaser.GameObjects.Text
  private stripFragText!: Phaser.GameObjects.Text
  private stripCompanion!: Phaser.GameObjects.Arc

  // Centre — companion idle
  private companionGlow!: Phaser.GameObjects.Arc
  private companionBody!: Phaser.GameObjects.Arc
  private companionEyeL!: Phaser.GameObjects.Arc
  private companionEyeR!: Phaser.GameObjects.Arc
  private companionStatus!: Phaser.GameObjects.Text
  private idleGroup!: Phaser.GameObjects.Group

  // Bottom bar
  private botBarBg!: Phaser.GameObjects.Rectangle
  private enemiesText!: Phaser.GameObjects.Text
  private fragText!: Phaser.GameObjects.Text
  private companionStateText!: Phaser.GameObjects.Text

  // Transition state
  private _idleVisible: boolean = true
  private _transitionTween: Phaser.Tweens.TweenChain | null = null


  constructor() {
    super({ key: 'GameScene' })
  }

  init(data: { roomCode: string }): void {
    this.roomCode = data.roomCode
  }

  create(): void {
    this.W = this.scale.width
    this.H = this.scale.height

    this._buildBackground()
    this._buildTopBar()
    this._buildTopStrip()
    this._buildCentre()
    this._buildBottomBar()

    // Strip starts hidden (idle mode)
    this._setEventMode(false, false)

    this._startIdleAnimation()

    // Connect Ably — fire-and-forget, update UI on resolve/reject
    this._connectAbly()
  }

  private _connectAbly(): void {
    this.companionStatus.setText('Connecting...').setColor('#888899')
    ablyManager.connect(this.roomCode)
      .then(() => {
        ablyManager.onMessage((msg) => this._onServerMessage(msg))
        ablyManager.onDisconnect(() => this._onDisconnected())
        ablyManager.onReconnect(() => this._onReconnected())
        return ablyManager.send({
          type: 'join',
          name: 'Dreamer',
          peer_id: ablyManager.getPeerId(),
        })
      })
      .then(() => {
        this.companionStatus.setText('Connected').setColor('#44dd88')
        this.time.delayedCall(2000, () => {
          if (!this.eventActive) this.companionStatus.setText('Ready')
        })
      })
      .catch(() => {
        this.companionStatus.setText('No connection').setColor('#d84040')
        this._onDisconnected()
      })
  }

  private _onDisconnected(): void {
    const overlay = document.getElementById('disconnect-overlay')
    if (overlay) overlay.style.display = 'flex'
    this.companionStatus.setText('Disconnected').setColor('#d84040')
    // Wire reconnect button
    const btn = document.getElementById('reconnect-btn')
    if (btn) {
      btn.onclick = () => {
        btn.textContent = 'Connecting...'
        ablyManager.reconnect(this.roomCode).then(() => {
          this._onReconnected()
        }).catch(() => {
          btn.textContent = 'Reconnect Now'
        })
      }
    }
  }

  private _onReconnected(): void {
    const disconnectOverlay = document.getElementById('disconnect-overlay')
    if (disconnectOverlay) disconnectOverlay.style.display = 'none'
    this.companionStatus.setText('Reconnected').setColor('#44dd88')
    // Re-announce presence
    ablyManager.send({
      type: 'join',
      name: 'Dreamer',
      peer_id: ablyManager.getPeerId(),
    })
    this.time.delayedCall(2000, () => {
      if (!this.eventActive) this.companionStatus.setText('Ready')
    })
  }

  // ---------------------------------------------------------------------------
  // Layout builders
  // ---------------------------------------------------------------------------

  private _buildBackground(): void {
    this.add.rectangle(0, 0, this.W, this.H, C.bg).setOrigin(0)
  }

  private _buildTopBar(): void {
    const h = Math.floor(this.H * TOP_BAR_H_IDLE)

    this.topBarBg = this.add.rectangle(0, 0, this.W, h, C.panel).setOrigin(0)
    this.add.rectangle(0, h - 1, this.W, 1, C.sep).setOrigin(0)

    // Hearts — left side
    const heartR = Math.floor(h * 0.26)
    const heartSpacing = heartR * 2.6
    const startX = 16 + heartR
    for (let i = 0; i < 5; i++) {
      const heart = this.add.arc(startX + i * heartSpacing, h / 2, heartR,
        0, 360, false, C.blue)
      this.heartObjects.push(heart)
    }

    // Floor — centre
    this.floorText = this.add.text(this.W / 2, h / 2, 'Floor 1', {
      fontSize: `${Math.floor(h * 0.38)}px`,
      color: '#9090b8',
      fontFamily: 'monospace',
    }).setOrigin(0.5)

    // Room code — right
    this.roomCodeText = this.add.text(this.W - 14, h / 2, this.roomCode, {
      fontSize: `${Math.floor(h * 0.42)}px`,
      color: '#44dd88',
      fontFamily: 'monospace',
    }).setOrigin(1, 0.5)
  }

  private _buildTopStrip(): void {
    const h = Math.floor(this.H * TOP_STRIP_H_EVENT)

    this.topStripBg = this.add.rectangle(0, 0, this.W, h, C.panel).setOrigin(0)
    this.add.rectangle(0, h - 1, this.W, 1, C.sep).setOrigin(0)

    // Tiny hearts
    const hr = Math.floor(h * 0.22)
    const hSpacing = hr * 2.4
    const hStart = 12 + hr
    for (let i = 0; i < 5; i++) {
      const heart = this.add.arc(hStart + i * hSpacing, h / 2, hr,
        0, 360, false, C.blue)
      this.stripHearts.push(heart)
    }

    // Floor
    this.stripFloorText = this.add.text(this.W / 2 - 40, h / 2, 'F1', {
      fontSize: `${Math.floor(h * 0.5)}px`,
      color: '#9090b8',
      fontFamily: 'monospace',
    }).setOrigin(0.5)

    // Fragments
    this.stripFragText = this.add.text(this.W / 2 + 20, h / 2, '◆0', {
      fontSize: `${Math.floor(h * 0.46)}px`,
      color: '#a050dc',
      fontFamily: 'monospace',
    }).setOrigin(0.5)

    // Tiny companion
    const cr = Math.floor(h * 0.28)
    this.stripCompanion = this.add.arc(this.W - 14 - cr, h / 2, cr,
      0, 360, false, C.gold)
  }

  private _buildCentre(): void {
    const topH  = Math.floor(this.H * TOP_BAR_H_IDLE)
    const botH  = Math.floor(this.H * BOT_BAR_H)
    const midH  = this.H - topH - botH
    const cx    = this.W / 2
    const cy    = topH + midH / 2

    const glowR = Math.min(this.W, midH) * 0.26
    const bodyR = glowR * 0.52

    this.companionGlow = this.add.arc(cx, cy, glowR, 0, 360, false, C.goldDim, 0.18)
    this.companionBody = this.add.arc(cx, cy, bodyR, 0, 360, false, C.gold)

    const ew = Math.max(3, bodyR * 0.13)
    this.companionEyeL = this.add.arc(cx - bodyR * 0.3, cy - bodyR * 0.18, ew,
      0, 360, false, 0xffffff)
    this.companionEyeR = this.add.arc(cx + bodyR * 0.3, cy - bodyR * 0.18, ew,
      0, 360, false, 0xffffff)

    this.companionStatus = this.add.text(cx, cy + bodyR + 22, 'Connecting...', {
      fontSize: `${Math.floor(midH * 0.1)}px`,
      color: '#50506e',
      fontFamily: 'monospace',
    }).setOrigin(0.5)

    this.idleGroup = this.add.group([
      this.companionGlow, this.companionBody,
      this.companionEyeL, this.companionEyeR,
      this.companionStatus,
    ])
  }

  private _buildBottomBar(): void {
    const h = Math.floor(this.H * BOT_BAR_H)
    const y = this.H - h

    this.botBarBg = this.add.rectangle(0, y, this.W, h, C.panel).setOrigin(0)
    this.add.rectangle(0, y, this.W, 1, C.sep).setOrigin(0)

    const cy  = y + h / 2
    const fs  = `${Math.floor(h * 0.28)}px`
    const fsh = `${Math.floor(h * 0.22)}px`

    // Enemies (left third)
    this.add.text(this.W * 0.07, cy - h * 0.14, 'ENEMIES', {
      fontSize: fsh, color: '#50506e', fontFamily: 'monospace',
    }).setOrigin(0.5)
    this.enemiesText = this.add.text(this.W * 0.07, cy + h * 0.14, '—', {
      fontSize: fs, color: '#d84040', fontFamily: 'monospace',
    }).setOrigin(0.5)

    // Fragments (centre third)
    this.add.text(this.W * 0.5, cy - h * 0.14, 'FRAGMENTS', {
      fontSize: fsh, color: '#50506e', fontFamily: 'monospace',
    }).setOrigin(0.5)
    this.fragText = this.add.text(this.W * 0.5, cy + h * 0.14, '◆ 0', {
      fontSize: fs, color: '#a050dc', fontFamily: 'monospace',
    }).setOrigin(0.5)

    // Companion state (right third)
    this.add.text(this.W * 0.86, cy - h * 0.14, 'COMPANION', {
      fontSize: fsh, color: '#50506e', fontFamily: 'monospace',
    }).setOrigin(0.5)
    this.companionStateText = this.add.text(this.W * 0.86, cy + h * 0.14, '—', {
      fontSize: fs, color: '#f5c842', fontFamily: 'monospace',
    }).setOrigin(0.5)
  }

  // ---------------------------------------------------------------------------
  // Idle animation
  // ---------------------------------------------------------------------------

  private _startIdleAnimation(): void {
    // Gentle bob
    this.tweens.add({
      targets: [this.companionBody, this.companionGlow,
                this.companionEyeL, this.companionEyeR],
      y: '-=7',
      duration: 1900,
      yoyo: true,
      repeat: -1,
      ease: 'Sine.easeInOut',
    })
    // Glow pulse
    this.tweens.add({
      targets: this.companionGlow,
      fillAlpha: 0.32,
      duration: 2400,
      yoyo: true,
      repeat: -1,
      ease: 'Sine.easeInOut',
    })
  }

  // ---------------------------------------------------------------------------
  // Idle ↔ Event mode transition
  // ---------------------------------------------------------------------------

  private _setEventMode(active: boolean, animate: boolean): void {
    this.eventActive = active

    const topIdleAlpha  = active ? 0 : 1
    const topStripAlpha = active ? 1 : 0
    const idleAlpha     = active ? 0 : 1

    const duration = animate ? 200 : 0

    const targets = [
      this.topBarBg, this.floorText, this.roomCodeText,
      ...this.heartObjects,
    ]
    const stripTargets = [
      this.topStripBg, this.stripFloorText, this.stripFragText,
      this.stripCompanion, ...this.stripHearts,
    ]

    if (animate) {
      this.tweens.add({ targets, alpha: topIdleAlpha, duration })
      this.tweens.add({ targets: stripTargets, alpha: topStripAlpha, duration })
      this.tweens.add({
        targets: [this.companionGlow, this.companionBody,
                  this.companionEyeL, this.companionEyeR, this.companionStatus],
        alpha: idleAlpha,
        duration,
      })
    } else {
      targets.forEach(t => t.setAlpha(topIdleAlpha))
      stripTargets.forEach(t => t.setAlpha(topStripAlpha))
      ;[this.companionGlow, this.companionBody,
        this.companionEyeL, this.companionEyeR, this.companionStatus
      ].forEach(t => t.setAlpha(idleAlpha))
    }
  }

  // ---------------------------------------------------------------------------
  // Server message handling
  // ---------------------------------------------------------------------------

  private _onServerMessage(msg: TServerMessage): void {
    switch (msg.type) {
      case 'state':
        this._updateState(msg)
        break
      case 'event_start':
        this._launchMinigame(msg.event, msg.window)
        break
      case 'event_result':
        this._showResult(msg.score, msg.max_score)
        break
      case 'companion':
        this._updateCompanionVisual(msg.state)
        break
      case 'paused':
        this._onGamePaused(msg.paused)
        break
    }
  }

  private _onGamePaused(paused: boolean): void {
    const overlay = document.getElementById('pause-overlay')
    if (overlay) overlay.style.display = paused ? 'flex' : 'none'
  }

  private _updateState(state: TGameStateMessage): void {
    this.gameState = state

    // Floor
    this.floorText.setText(`Floor  ${state.floor}`)
    this.stripFloorText.setText(`F${state.floor}`)

    // Hearts
    const hp    = state.guardian_hp
    const maxHp = state.guardian_max_hp
    this.heartObjects.forEach((h, i) => {
      h.setFillStyle(hp > i ? C.blue : C.blueDim, hp > i ? 1 : 0.35)
    })
    this.stripHearts.forEach((h, i) => {
      h.setFillStyle(hp > i ? C.blue : C.blueDim, hp > i ? 1 : 0.3)
    })

    // Fragments
    const frags = state.dreamer_fragments ?? 0
    this.fragText.setText(`◆ ${frags}`)
    this.stripFragText.setText(`◆${frags}`)

    // Enemies
    this.enemiesText.setText(
      state.enemies_alive > 0
        ? `${state.enemies_alive} alive`
        : 'Cleared!'
    ).setColor(state.enemies_alive > 0 ? '#d84040' : '#44dd88')

    // Companion state in bottom bar
    if (state.companion_anchored) {
      this.companionStateText.setText('Anchored').setColor('#ffcc44')
    }
  }

  private _launchMinigame(eventType: string, window: number): void {
    this._setEventMode(true, true)

    switch (eventType) {
      case 'heal':
        this.scene.launch('HealScene', { window })
        break
      case 'chest_unlock':
        this.scene.launch('ChestScene', { window })
        break
    }
  }

  private _showResult(score: number, maxScore: number): void {
    this._setEventMode(false, true)
    const ratio = score / maxScore
    const msg   = ratio >= 1 ? 'Perfect!' : ratio > 0 ? `${score} / ${maxScore}` : 'Missed'
    const color = ratio >= 1 ? '#44dd88' : ratio > 0 ? '#ffcc44' : '#d84040'
    this.companionStatus.setText(msg).setColor(color)
    this.time.delayedCall(2200, () => {
      this.companionStatus.setText('Ready').setColor('#50506e')
    })
  }

  private _updateCompanionVisual(state: string): void {
    switch (state) {
      case 'anchored':
        this.companionBody.setFillStyle(C.goldDim)
        this.companionStateText.setText('Anchored').setColor('#ffcc44')
        this.companionStatus.setText('Working...').setColor('#ffcc44')
        break
      case 'celebrating':
        this.tweens.add({
          targets: [this.companionBody, this.companionGlow],
          scaleX: 1.3, scaleY: 1.3,
          duration: 150, yoyo: true, repeat: 2,
        })
        this.companionBody.setFillStyle(C.gold)
        this.companionStateText.setText('Following').setColor('#f5c842')
        break
      case 'hurt':
        this.companionBody.setFillStyle(0xff4444)
        this.time.delayedCall(300, () => this.companionBody?.setFillStyle(C.gold))
        break
      case 'retreating':
        this.companionStateText.setText('Retreating').setColor('#d84040')
        this.companionStatus.setText('Retreating...').setColor('#d84040')
        break
      case 'following':
        this.companionBody.setFillStyle(C.gold)
        this.companionStateText.setText('Following').setColor('#f5c842')
        this.companionStatus.setText('Ready').setColor('#50506e')
        break
    }
  }
}
