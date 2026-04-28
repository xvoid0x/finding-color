import Phaser from 'phaser'

/**
 * LobbyScene - Room code entry using native HTML input.
 * Shows a DOM overlay, hides it when code is submitted.
 */
export class LobbyScene extends Phaser.Scene {
  private _overlay: HTMLElement | null = null
  private _input: HTMLInputElement | null = null
  private _status: HTMLElement | null = null

  constructor() {
    super({ key: 'LobbyScene' })
  }

  create(): void {
    this._overlay = document.getElementById('lobby-overlay')
    this._input   = document.getElementById('room-code-input') as HTMLInputElement
    this._status  = document.getElementById('lobby-status')

    if (!this._overlay || !this._input) return

    // Show the overlay
    this._overlay.style.display = 'flex'
    this._input.value = ''
    this._input.focus()

    // Submit on 4 chars entered or Enter key
    this._input.addEventListener('input',   this._onInput)
    this._input.addEventListener('keydown', this._onKeydown)
  }

  private _onInput = (): void => {
    if (!this._input) return
    // Force uppercase
    this._input.value = this._input.value.toUpperCase().replace(/[^A-Z]/g, '')
    if (this._input.value.length === 4) {
      this._submit()
    }
  }

  private _onKeydown = (e: KeyboardEvent): void => {
    if (e.key === 'Enter' && this._input && this._input.value.length === 4) {
      this._submit()
    }
  }

  private _submit(): void {
    const code = this._input?.value ?? ''
    if (code.length !== 4) {
      if (this._status) this._status.textContent = 'Need 4 letters'
      return
    }
    this._cleanup()
    this.scene.start('GameScene', { roomCode: code })
  }

  private _cleanup(): void {
    this._input?.removeEventListener('input',   this._onInput)
    this._input?.removeEventListener('keydown', this._onKeydown)
    if (this._overlay) this._overlay.style.display = 'none'
  }

  shutdown(): void {
    this._cleanup()
  }
}
