extends Node
## HitstopManager — Autoload
## Briefly freezes Engine.time_scale to 0.0 on impact for weight/punch feel.
## Dead Cells lead dev called this "level zero" game feel. ~40ms on hit, ~80ms on kill.
##
## Correctly handles coexistence with slow-mo:
##   - Saves time_scale before freeze, restores it after
##   - If a new hitstop arrives during an existing one, extends it (doesn't stack badly)
##   - process_mode = ALWAYS so it ticks even when time_scale = 0

const DEFAULT_HIT_DURATION:  float = 0.06   # 60ms — light hit (bumped from 40ms for perceptibility)
const DEFAULT_KILL_DURATION: float = 0.10   # 100ms — enemy kill
const DEFAULT_HEAVY_DURATION: float = 0.14  # 140ms — guardian takes damage

var _active: bool = false
var _duration: float = 0.0
var _start_ms: int = 0
var _restore_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if not _active:
		return
	# Engine.time_scale = 0 means _delta is also 0 (scaled).
	# Use Time.get_ticks_msec() for real elapsed time instead.
	var now_ms := Time.get_ticks_msec()
	var elapsed := (now_ms - _start_ms) / 1000.0
	if elapsed >= _duration:
		_end()


func hit() -> void:
	"""Light hitstop — guardian lands a hit on enemy."""
	_begin(DEFAULT_HIT_DURATION)


func kill() -> void:
	"""Stronger hitstop — enemy dies."""
	_begin(DEFAULT_KILL_DURATION)


func heavy() -> void:
	"""Heaviest hitstop — guardian takes damage."""
	_begin(DEFAULT_HEAVY_DURATION)


func trigger(duration: float) -> void:
	"""Custom duration in seconds."""
	_begin(duration)


func _begin(duration: float) -> void:
	# Capture current scale before we stomp it
	# (may be 0.25 if slow-mo is active, 1.0 normally)
	if not _active:
		_restore_scale = Engine.time_scale
		_start_ms = Time.get_ticks_msec()
		_duration = duration
	else:
		# Extend: recalculate end time from now
		var elapsed := (Time.get_ticks_msec() - _start_ms) / 1000.0
		var remaining := maxf(0.0, _duration - elapsed)
		if duration > remaining:
			_start_ms = Time.get_ticks_msec()
			_duration = duration

	_active = true
	Engine.time_scale = 0.0
	print("[HITSTOP] Freeze %.0fms" % (_duration * 1000))


func _end() -> void:
	_active = false
	_duration = 0.0
	Engine.time_scale = _restore_scale
	print("[HITSTOP] Released → scale=", _restore_scale)
