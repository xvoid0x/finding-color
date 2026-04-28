import Phaser from 'phaser'
import { ablyManager } from '../lib/ably'
import { vibrateSuccess, vibrateFailure } from '../lib/haptic'

/**
 * HealScene - HEAL event minigame.
 *
 * Three timing rings pulse outward one at a time (sequential, not simultaneous).
 * Tap / press SPACE when the ring reaches the outer circle.
 * Score: 0–3 based on hits landed.
 *
 * Timing window per beat: ring travels for RING_TRAVEL_MS, then stays briefly
 * at target for HIT_LINGER_MS before counting as a miss. Tap during either
 * window counts as a hit.
 *
 * Launched over GameScene as an overlay.
 */

const BEAT_COUNT = 3

// Ring travel time: how long the ring expands from centre → target
const RING_TRAVEL_MS = 800

// How long the ring lingers at target before auto-missing
const HIT_LINGER_MS = 300

// Gap between beats (time from one beat finishing to the next spawning)
const INTER_BEAT_GAP_MS = 350

const RING_COLOUR   = 0x3a7bd5
const TARGET_COLOUR = 0xffffff
const HIT_COLOUR    = 0x44ff88
const MISS_COLOUR   = 0xff4444

export class HealScene extends Phaser.Scene {
  private window: number = 5

  private cx: number = 0
  private cy: number = 0
  private targetRadius: number = 0

  private beatsLanded: number = 0
  private currentBeat: number = 0   // Index of the beat currently in flight (0-based)
  private beatActive: boolean = false  // True while a ring is in flight and tappable

  private timerText: Phaser.GameObjects.Text | null = null
  private resultText: Phaser.GameObjects.Text | null = null

  private windowTimer: Phaser.Time.TimerEvent | null = null
  private _finished: boolean = false

  // Active ring tween — cancel it on hit
  private _activeTween: Phaser.Tweens.Tween | null = null
  private _lingerTimer: Phaser.Time.TimerEvent | null = null
  private _activeRing: Phaser.GameObjects.Arc | null = null

  constructor() {
    super({ key: 'HealScene' })
  }

  init(data: { window: number }): void {
    this.window = data.window
    // Reset all state — Phaser reuses scene instances on relaunch
    this.beatsLanded = 0
    this.currentBeat = 0
    this.beatActive = false
    this._finished = false
    this.timerText = null
    this.resultText = null
    this.windowTimer = null
    this._activeTween = null
    this._lingerTimer = null
    this._activeRing = null
  }

  create(): void {
    const { width, height } = this.scale
    this.cx = width / 2
    this.cy = height * 0.44
    this.targetRadius = Math.min(width, height) * 0.30

    // Semi-transparent dark overlay
    this.add.rectangle(0, 0, width, height, 0x07050f, 0.88).setOrigin(0)

    // Title
    this.add.text(this.cx, height * 0.08, 'HEAL', {
      fontSize: '32px',
      color: '#3a7bd5',
      fontFamily: 'monospace',
      fontStyle: 'bold',
    }).setOrigin(0.5)

    // Instruction
    this.add.text(this.cx, height * 0.15, 'Tap when the ring hits the circle', {
      fontSize: '14px',
      color: '#7777aa',
      fontFamily: 'monospace',
      align: 'center',
      wordWrap: { width: width * 0.85 },
    }).setOrigin(0.5)

    // Static outer target ring
    this.add.arc(this.cx, this.cy, this.targetRadius, 0, 360, false, 0x000000, 0)
      .setStrokeStyle(4, TARGET_COLOUR, 0.3)

    // Beat dots (bottom, left of centre)
    this._buildBeatDots(width, height)

    // Keyboard hint (desktop)
    this.add.text(this.cx, height * 0.76, '[SPACE] or tap', {
      fontSize: '13px',
      color: '#444466',
      fontFamily: 'monospace',
    }).setOrigin(0.5)

    // Timer text
    this.timerText = this.add.text(this.cx, height * 0.88, '', {
      fontSize: '18px',
      color: '#444466',
      fontFamily: 'monospace',
    }).setOrigin(0.5)

    // Result text (hidden until finish)
    this.resultText = this.add.text(this.cx, this.cy + this.targetRadius + 28, '', {
      fontSize: '26px',
      fontFamily: 'monospace',
      fontStyle: 'bold',
    }).setOrigin(0.5).setVisible(false)

    // Input: tap or spacebar
    this.input.on('pointerdown', this._onInput, this)
    this.input.keyboard?.on('keydown-SPACE', this._onInput, this)

    // Window countdown — fires if all beats haven't resolved in time
    this.windowTimer = this.time.addEvent({
      delay: this.window * 1000,
      callback: this._onWindowExpired,
      callbackScope: this,
    })

    // Spawn first beat
    this.time.delayedCall(300, () => this._spawnBeat())
  }

  update(): void {
    const remaining = this.windowTimer?.getRemainingSeconds() ?? 0
    if (this.timerText) {
      this.timerText.setText(remaining.toFixed(1))
      // Colour shifts red as time runs out
      const ratio = Math.min(1, remaining / this.window)
      const lerp = (a: number, b: number, t: number) => a + (b - a) * t
      const r = Math.floor(lerp(255, 68, ratio))
      const g = Math.floor(lerp(68, 68, ratio))
      const b = Math.floor(lerp(68, 170, ratio))
      this.timerText.setColor(`rgb(${r},${g},${b})`)
    }
  }

  // ---------------------------------------------------------------------------
  // Beat lifecycle
  // ---------------------------------------------------------------------------

  private _spawnBeat(): void {
    if (this._finished || this.currentBeat >= BEAT_COUNT) return

    this.beatActive = true

    // Create ring at centre, expand to targetRadius
    const ring = this.add.arc(this.cx, this.cy, 4, 0, 360, false, 0x000000, 0)
      .setStrokeStyle(3, RING_COLOUR, 1)
    this._activeRing = ring

    // Tween: expand to target radius
    this._activeTween = this.tweens.add({
      targets: ring,
      radius: this.targetRadius,
      duration: RING_TRAVEL_MS,
      ease: 'Sine.easeIn',
      onComplete: () => {
        // Ring reached target — linger briefly, still tappable
        if (!this.beatActive) return  // Already hit
        ring.setStrokeStyle(4, TARGET_COLOUR, 0.9)  // Highlight at target
        this._lingerTimer = this.time.delayedCall(HIT_LINGER_MS, () => {
          if (this.beatActive) {
            // Player didn't tap in time — miss
            this._resolveBeat(false)
          }
        })
      },
    })
  }

  private _onInput(): void {
    if (!this.beatActive || this._finished) return
    this._resolveBeat(true)
  }

  private _resolveBeat(hit: boolean): void {
    if (!this.beatActive) return
    this.beatActive = false

    // Cancel any pending linger timer
    this._lingerTimer?.destroy()
    this._lingerTimer = null

    // Stop the tween
    this._activeTween?.stop()
    this._activeTween = null

    const beatIndex = this.currentBeat
    this.currentBeat++

    if (hit) {
      this.beatsLanded++
      vibrateSuccess()
      this._flashDot(beatIndex, HIT_COLOUR)
      this._showHitFlash()
    } else {
      vibrateFailure()
      this._flashDot(beatIndex, MISS_COLOUR)
    }

    // Destroy ring
    this._activeRing?.destroy()
    this._activeRing = null

    // Check if all beats done
    if (this.currentBeat >= BEAT_COUNT) {
      this.time.delayedCall(300, () => this._finish())
    } else {
      // Spawn next beat after gap
      this.time.delayedCall(INTER_BEAT_GAP_MS, () => this._spawnBeat())
    }
  }

  // ---------------------------------------------------------------------------
  // Visuals
  // ---------------------------------------------------------------------------

  private _buildBeatDots(width: number, height: number): void {
    const dotY = height * 0.70
    const spacing = 44
    const startX = this.cx - ((BEAT_COUNT - 1) * spacing) / 2
    for (let i = 0; i < BEAT_COUNT; i++) {
      this.add.arc(startX + i * spacing, dotY, 9, 0, 360, false, 0x222244)
        .setStrokeStyle(2, 0x333366, 1)
        .setName(`dot-${i}`)
    }
  }

  private _flashDot(index: number, color: number): void {
    const dot = this.children.getByName(`dot-${index}`) as Phaser.GameObjects.Arc | null
    if (!dot) return
    dot.setFillStyle(color)
    // Pulse outward briefly
    this.tweens.add({
      targets: dot,
      scaleX: 1.5, scaleY: 1.5,
      duration: 150,
      yoyo: true,
      ease: 'Sine.easeOut',
    })
  }

  private _showHitFlash(): void {
    // Green ripple from target ring position
    const ripple = this.add.arc(this.cx, this.cy, this.targetRadius - 4, 0, 360, false, 0x000000, 0)
      .setStrokeStyle(6, HIT_COLOUR, 0.9)
    this.tweens.add({
      targets: ripple,
      radius: this.targetRadius + 20,
      alpha: 0,
      duration: 300,
      ease: 'Sine.easeOut',
      onComplete: () => ripple.destroy(),
    })
  }

  // ---------------------------------------------------------------------------
  // Finish
  // ---------------------------------------------------------------------------

  private _onWindowExpired(): void {
    if (this._finished) return
    // If a beat is mid-flight, count it as a miss and finish
    if (this.beatActive) {
      this._resolveBeat(false)
    } else {
      this._finish()
    }
  }

  private _finish(): void {
    if (this._finished) return
    this._finished = true

    this.beatActive = false
    this._activeTween?.stop()
    this._lingerTimer?.destroy()
    this.windowTimer?.destroy()
    this._activeRing?.destroy()

    // Remove input listeners
    this.input.off('pointerdown', this._onInput, this)
    this.input.keyboard?.off('keydown-SPACE', this._onInput, this)

    const ratio = this.beatsLanded / BEAT_COUNT
    let msg: string
    let color: string

    if (ratio >= 1) {
      msg = 'Perfect!'
      color = '#44ff88'
    } else if (ratio > 0) {
      msg = `${this.beatsLanded} / ${BEAT_COUNT}`
      color = '#ffcc44'
    } else {
      msg = 'Missed'
      color = '#ff4444'
    }

    this.resultText?.setText(msg).setColor(color).setVisible(true)

    // Send result to Godot
    ablyManager.send({
      type: 'event_response',
      event: 'heal',
      score: this.beatsLanded,
      max_score: BEAT_COUNT,
    })

    // Close after result display
    this.time.delayedCall(1400, () => {
      this.scene.stop('HealScene')
    })
  }
}
