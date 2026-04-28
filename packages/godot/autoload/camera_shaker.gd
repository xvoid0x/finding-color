extends Node
## CameraShaker — Autoload
## Any system calls CameraShaker.shake(intensity, duration) to trigger screen shake.
## Respects SettingsManager.get_shake_multiplier() — off/low/high.
##
## Usage:
##   CameraShaker.shake(8.0, 0.25)   # light hit
##   CameraShaker.shake(16.0, 0.4)   # heavy hit / guardian damaged
##   CameraShaker.shake(24.0, 0.5)   # boss hit / death

var _camera: Camera2D = null

var _trauma: float = 0.0        # 0–1, decays over time
var _trauma_decay: float = 2.8  # how fast trauma drains per second

# Max pixel offset / rotation at full trauma
const MAX_OFFSET_X: float = 18.0
const MAX_OFFSET_Y: float = 14.0
const MAX_ROLL: float     = 0.025  # radians

var _noise: FastNoiseLite = null
var _noise_t: float = 0.0
const NOISE_SPEED: float = 60.0


func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.seed = randi()
	_noise.frequency = 0.5


func register_camera(cam: Camera2D) -> void:
	_camera = cam


func shake(intensity: float, duration: float) -> void:
	"""
	intensity: pixel-scale strength (8 = light, 16 = medium, 24 = heavy)
	duration: seconds — converted to trauma decay target
	Trauma is additive so rapid hits stack.
	"""
	var multiplier := SettingsManager.get_shake_multiplier()
	if multiplier <= 0.0:
		return
	# Convert intensity + duration to trauma (0–1)
	# trauma = intensity / 24.0, capped at 1.0, then multiplied by setting
	var new_trauma := clampf((intensity / 24.0) * multiplier, 0.0, 1.0)
	_trauma = minf(_trauma + new_trauma, 1.0)
	# Adjust decay so shake lasts roughly `duration` seconds
	if duration > 0.0:
		_trauma_decay = 1.0 / duration


func _process(delta: float) -> void:
	if _camera == null or _trauma <= 0.0:
		return

	_noise_t += delta * NOISE_SPEED
	var t2 := _trauma * _trauma  # square for more pronounced falloff

	var offset_x := MAX_OFFSET_X * t2 * _noise.get_noise_2d(_noise_t, 0.0)
	var offset_y := MAX_OFFSET_Y * t2 * _noise.get_noise_2d(0.0, _noise_t)
	var roll     := MAX_ROLL     * t2 * _noise.get_noise_2d(_noise_t, _noise_t)

	_camera.offset = Vector2(offset_x, offset_y)
	_camera.rotation = roll

	# Decay trauma
	_trauma = maxf(0.0, _trauma - _trauma_decay * delta)

	# Reset camera when trauma hits zero
	if _trauma <= 0.0:
		_camera.offset = Vector2.ZERO
		_camera.rotation = 0.0
