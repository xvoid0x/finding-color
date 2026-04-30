import Phaser from 'phaser'
import { ablyManager } from '../lib/ably'
import { vibrateSuccess, vibrateFailure } from '../lib/haptic'

/**
 * ChestScene — CHEST UNLOCK — Tumbler Rush minigame.
 *
 * 3–4 rotating dials, each with a marker drifting at a unique speed.
 * Each dial has a small target zone (arc). Hold a dial's marker in the zone
 * by pressing/holding its button. All dials must be held simultaneously
 * to unlock — a lock-open animation plays and success is sent.
 *
 * Partial credit: if time expires with some held, score reflects ratio.
 * Floor depth increases drift speed (passed via window duration — shorter = faster).
 *
 * Always different: drift speeds and starting angles randomised each time.
 */

const DIAL_COUNT_BASE = 3  // floor 1-3
// floor 4+ gets 4 dials (determined by window duration — shorter windows = deeper floor)

const COLOURS = [0x3a7bd5, 0xf5c842, 0xa050dc, 0x44dd88]
const BG      = 0x07050f
const PANEL   = 0x0d0a1c
const DIM     = 0x50506e
const WHITE   = 0xdcdce8

interface Dial {
  index:       number
  cx:          number
  cy:          number
  radius:      number
  speed:       number      // radians per second (sign = direction)
  angle:       number      // current marker angle
  targetStart: number      // target zone start angle
  targetSize:  number      // target zone arc width (radians)
  held:        boolean
  locked:      boolean     // marker is in zone AND button held
  color:       number

  // Phaser objects
  track:       Phaser.GameObjects.Arc
  marker:      Phaser.GameObjects.Arc
  targetArc:   Phaser.GameObjects.Graphics
  lockRing:    Phaser.GameObjects.Arc
  btn:         Phaser.GameObjects.Rectangle
  btnLabel:    Phaser.GameObjects.Text
  btnBorder:   Phaser.GameObjects.Rectangle
}

export class ChestScene extends Phaser.Scene {
  private window: number = 8
  private dials: Dial[] = []
  private allLocked: boolean = false
  private _finished: boolean = false
  private windowTimer: Phaser.Time.TimerEvent | null = null
  private timerText: Phaser.GameObjects.Text | null = null
  private statusText: Phaser.GameObjects.Text | null = null
  private titleText: Phaser.GameObjects.Text | null = null

  constructor() {
    super({ key: 'ChestScene' })
  }

  init(data: { window: number }): void {
    this.window = data.window
    this.dials = []
    this.allLocked = false
    this._finished = false
    this.windowTimer = null
    this.timerText = null
    this.statusText = null
    this.titleText = null
  }

  create(): void {
    const { width: W, height: H } = this.scale

    // Determine dial count from window duration (proxy for floor depth)
    // Longer window = early floor = 3 dials. Shorter = deeper = 4 dials.
    const dialCount = this.window >= 7 ? 3 : 4

    // Dark overlay
    this.add.rectangle(0, 0, W, H, BG, 0.92).setOrigin(0)

    // Title
    this.titleText = this.add.text(W / 2, H * 0.1, 'UNLOCK THE CHEST', {
      fontSize: `${Math.floor(H * 0.13)}px`,
      color: '#f5c842',
      fontFamily: 'monospace',
      fontStyle: 'bold',
    }).setOrigin(0.5)

    // Instruction
    this.add.text(W / 2, H * 0.22, 'Hold all buttons when the marker is in the zone', {
      fontSize: `${Math.floor(H * 0.07)}px`,
      color: '#50506e',
      fontFamily: 'monospace',
      align: 'center',
      wordWrap: { width: W * 0.85 },
    }).setOrigin(0.5)

    // Status text (centre, hidden until finish)
    this.statusText = this.add.text(W / 2, H * 0.5, '', {
      fontSize: `${Math.floor(H * 0.18)}px`,
      color: '#ffffff',
      fontFamily: 'monospace',
      fontStyle: 'bold',
    }).setOrigin(0.5)

    // Timer
    this.timerText = this.add.text(W / 2, H * 0.88, '', {
      fontSize: `${Math.floor(H * 0.09)}px`,
      color: '#50506e',
      fontFamily: 'monospace',
    }).setOrigin(0.5)

    // Build dials
    this._buildDials(W, H, dialCount)

    // Window timer
    this.windowTimer = this.time.addEvent({
      delay: this.window * 1000,
      callback: this._onTimeout,
      callbackScope: this,
    })
  }

  private _buildDials(W: number, H: number, count: number): void {
    // Dials arranged horizontally across the centre zone
    const dialZoneTop = H * 0.28
    const dialZoneH   = H * 0.52
    const dialR       = Math.min((W / (count + 1)) * 0.36, dialZoneH * 0.32)
    const btnH        = Math.floor(dialZoneH * 0.28)
    const spacing     = W / (count + 1)

    for (let i = 0; i < count; i++) {
      const cx = spacing * (i + 1)
      const dialCY = dialZoneTop + dialR + 4
      const btnY   = dialCY + dialR + 18

      const speed = this._randomSpeed(i, count)
      const startAngle = Math.random() * Math.PI * 2
      const targetStart = Math.random() * Math.PI * 2
      const targetSize = 0.52  // ~30 degrees — tight but fair

      const color = COLOURS[i % COLOURS.length]

      // Track ring
      const track = this.add.arc(cx, dialCY, dialR, 0, 360, false, 0x000000, 0)
        .setStrokeStyle(3, 0x1c1630, 1)

      // Target zone arc (drawn via Graphics for arc segment)
      const targetArc = this.add.graphics()
      this._drawTargetArc(targetArc, cx, dialCY, dialR, targetStart, targetSize, color)

      // Lock ring (glows when locked)
      const lockRing = this.add.arc(cx, dialCY, dialR + 6, 0, 360, false, 0x000000, 0)
        .setStrokeStyle(4, color, 0)

      // Marker dot
      const mx = cx + Math.cos(startAngle) * dialR
      const my = dialCY + Math.sin(startAngle) * dialR
      const marker = this.add.arc(mx, my, Math.max(6, dialR * 0.18),
        0, 360, false, color)

      // Hold button
      const btnW = Math.floor(dialR * 2.2)
      const btnBorder = this.add.rectangle(cx, btnY + btnH / 2, btnW + 4, btnH + 4,
        color, 0.25)
      const btn = this.add.rectangle(cx, btnY + btnH / 2, btnW, btnH, PANEL)
        .setInteractive({ useHandCursor: true })
      const btnLabel = this.add.text(cx, btnY + btnH / 2, 'HOLD', {
        fontSize: `${Math.floor(btnH * 0.45)}px`,
        color: '#' + color.toString(16).padStart(6, '0'),
        fontFamily: 'monospace',
        fontStyle: 'bold',
      }).setOrigin(0.5)

      const dial: Dial = {
        index: i, cx, cy: dialCY, radius: dialR,
        speed, angle: startAngle, targetStart, targetSize,
        held: false, locked: false, color,
        track, marker, targetArc, lockRing, btn, btnLabel, btnBorder,
      }
      this.dials.push(dial)

      // Button input — pointer down/up for hold mechanic
      btn.on('pointerdown', () => this._onDialHold(i, true))
      btn.on('pointerup', () => this._onDialHold(i, false))
      btn.on('pointerout', () => this._onDialHold(i, false))
    }

    // Keyboard fallback for desktop (1/2/3/4 keys)
    this.input.keyboard?.on('keydown', (e: KeyboardEvent) => {
      const idx = parseInt(e.key) - 1
      if (idx >= 0 && idx < this.dials.length) this._onDialHold(idx, true)
    })
    this.input.keyboard?.on('keyup', (e: KeyboardEvent) => {
      const idx = parseInt(e.key) - 1
      if (idx >= 0 && idx < this.dials.length) this._onDialHold(idx, false)
    })
  }

  private _randomSpeed(index: number, total: number): number {
    // Each dial gets a distinct speed in range [0.8, 2.2] rad/s
    // Alternate direction so they're not all moving the same way
    const base = 0.8 + (index / total) * 1.4
    const jitter = (Math.random() - 0.5) * 0.4
    const dir = index % 2 === 0 ? 1 : -1
    return (base + jitter) * dir
  }

  private _drawTargetArc(
    g: Phaser.GameObjects.Graphics,
    cx: number, cy: number, r: number,
    startAngle: number, size: number, color: number
  ): void {
    g.clear()
    const r8 = ((color >> 16) & 0xff)
    const g8 = ((color >> 8) & 0xff)
    const b8 = (color & 0xff)
    g.lineStyle(5, color, 0.8)
    g.beginPath()
    const steps = 16
    for (let s = 0; s <= steps; s++) {
      const a = startAngle + (size * s / steps)
      const x = cx + Math.cos(a) * r
      const y = cy + Math.sin(a) * r
      if (s === 0) g.moveTo(x, y)
      else g.lineTo(x, y)
    }
    g.strokePath()
    // Subtle fill glow
    g.fillStyle(color, 0.12)
    g.beginPath()
    g.moveTo(cx, cy)
    for (let s = 0; s <= steps; s++) {
      const a = startAngle + (size * s / steps)
      g.lineTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r)
    }
    g.closePath()
    g.fillPath()
  }

  update(time: number, delta: number): void {
    if (this._finished) return

    const dt = delta / 1000
    let allLocked = true

    for (const dial of this.dials) {
      // Advance angle if not held (held = frozen)
      if (!dial.held) {
        dial.angle += dial.speed * dt
      }

      // Normalise angle to [0, TAU)
      dial.angle = ((dial.angle % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2)

      // Update marker position
      const mx = dial.cx + Math.cos(dial.angle) * dial.radius
      const my = dial.cy + Math.sin(dial.angle) * dial.radius
      dial.marker.setPosition(mx, my)

      // Check if marker is in target zone
      const inZone = this._angleInArc(dial.angle, dial.targetStart, dial.targetSize)
      const wasLocked = dial.locked
      dial.locked = dial.held && inZone

      // Visual feedback for lock state
      if (dial.locked !== wasLocked) {
        dial.lockRing.setStrokeStyle(4, dial.color, dial.locked ? 0.9 : 0)
        dial.marker.setFillStyle(dial.locked ? 0xffffff : dial.color)
        if (dial.locked) {
          this.tweens.add({
            targets: dial.lockRing,
            scaleX: 1.08, scaleY: 1.08,
            duration: 80, yoyo: true,
          })
        }
      }

      if (!dial.locked) allLocked = false
    }

    // All locked simultaneously — success!
    if (allLocked && !this.allLocked && this.dials.length > 0) {
      this.allLocked = true
      this._finish(true)
    }

    // Update timer
    const remaining = this.windowTimer?.getRemainingSeconds() ?? 0
    if (this.timerText) {
      this.timerText.setText(remaining.toFixed(1))
      const ratio = remaining / this.window
      const r = Math.floor(215 * (1 - ratio) + 80 * ratio)
      const g = Math.floor(68 * ratio)
      const b = Math.floor(68 * ratio)
      this.timerText.setColor(`rgb(${r},${g},${b})`)
    }
  }

  private _angleInArc(angle: number, start: number, size: number): boolean {
    // Normalise everything to [0, TAU)
    const tau = Math.PI * 2
    const end = (start + size) % tau
    const a   = ((angle % tau) + tau) % tau
    const s   = ((start % tau) + tau) % tau

    if (s <= end) {
      return a >= s && a <= end
    } else {
      // Arc wraps around 0
      return a >= s || a <= end
    }
  }

  private _onDialHold(index: number, held: boolean): void {
    if (this._finished || index >= this.dials.length) return
    const dial = this.dials[index]
    dial.held = held

    // Visual: button pressed state
    dial.btn.setFillStyle(held ? dial.color * 0.3 : PANEL)
    dial.btnLabel.setColor(held ? '#ffffff' : '#' + dial.color.toString(16).padStart(6, '0'))
  }

  private _onTimeout(): void {
    if (!this._finished) this._finish(false)
  }

  private _finish(success: boolean): void {
    if (this._finished) return
    this._finished = true

    this.windowTimer?.destroy()

    // Remove input
    this.input.keyboard?.removeAllListeners()

    // Stop all dial movement (freeze state)
    // (update loop checks _finished)

    if (success) {
      vibrateSuccess()
      // Flash all lock rings
      this.dials.forEach(d => {
        this.tweens.add({
          targets: d.lockRing,
          strokeAlpha: 0,
          scaleX: 1.4, scaleY: 1.4,
          duration: 500, ease: 'Sine.easeOut',
        })
      })
      this.statusText?.setText('Unlocked!').setColor('#44dd88').setVisible(true)
    } else {
      vibrateFailure()
      // How many dials were locked at timeout (partial credit)
      const locked = this.dials.filter(d => d.locked).length
      this.statusText?.setText(
        locked > 0 ? `${locked}/${this.dials.length}` : 'Failed'
      ).setColor(locked > 0 ? '#ffcc44' : '#d84040').setVisible(true)
    }

    // Send result to Godot
    ablyManager.send({
      type: 'event_response',
      event: 'chest_unlock',
      score: success ? 1 : 0,
      max_score: 1,
    })

    this.time.delayedCall(1200, () => this.scene.stop('ChestScene'))
  }
}
