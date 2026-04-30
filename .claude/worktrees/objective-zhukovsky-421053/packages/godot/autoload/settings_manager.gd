extends Node
## SettingsManager — Autoload
## Holds all user settings. Persists to user://settings.cfg.
## All systems read from here. Default values are playtest-safe.

const SAVE_PATH := "user://settings.cfg"

# --- Display ---
var fullscreen: bool = false

# --- Audio ---
var volume_master: float = 1.0   # 0.0 – 1.0
var volume_sfx: float = 1.0
var volume_music: float = 0.8

# --- Gameplay ---
var screen_shake: int = 1        # 0 = off, 1 = low, 2 = high
var controller_rumble: bool = true

# --- Accessibility ---
var reduce_flashing: bool = false

# --- Phone ---
var room_code: String = ""       # Set at runtime by PhoneManager, not persisted


func _ready() -> void:
	load_settings()
	_apply_all()


# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

func _apply_all() -> void:
	_apply_display()
	_apply_audio()


func _apply_display() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_audio() -> void:
	_set_bus_volume("Master", volume_master)
	_set_bus_volume("SFX", volume_sfx)
	_set_bus_volume("Music", volume_music)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return  # Bus doesn't exist yet — placeholder safe
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
	AudioServer.set_bus_mute(idx, linear <= 0.0)


# ---------------------------------------------------------------------------
# Convenience setters (call these from UI — they apply + save)
# ---------------------------------------------------------------------------

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_display()
	save_settings()


func set_volume_master(value: float) -> void:
	volume_master = clampf(value, 0.0, 1.0)
	_apply_audio()
	save_settings()


func set_volume_sfx(value: float) -> void:
	volume_sfx = clampf(value, 0.0, 1.0)
	_apply_audio()
	save_settings()


func set_volume_music(value: float) -> void:
	volume_music = clampf(value, 0.0, 1.0)
	_apply_audio()
	save_settings()


func set_screen_shake(value: int) -> void:
	screen_shake = clampi(value, 0, 2)
	save_settings()


func set_controller_rumble(value: bool) -> void:
	controller_rumble = value
	save_settings()


func set_reduce_flashing(value: bool) -> void:
	reduce_flashing = value
	save_settings()


# ---------------------------------------------------------------------------
# Helpers for other systems
# ---------------------------------------------------------------------------

func get_shake_multiplier() -> float:
	match screen_shake:
		0: return 0.0
		1: return 0.5
		2: return 1.0
	return 0.5


# ---------------------------------------------------------------------------
# Persist
# ---------------------------------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("audio", "volume_master", volume_master)
	cfg.set_value("audio", "volume_sfx", volume_sfx)
	cfg.set_value("audio", "volume_music", volume_music)
	cfg.set_value("gameplay", "screen_shake", screen_shake)
	cfg.set_value("gameplay", "controller_rumble", controller_rumble)
	cfg.set_value("accessibility", "reduce_flashing", reduce_flashing)
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # No save file yet — use defaults
	fullscreen         = cfg.get_value("display",       "fullscreen",        fullscreen)
	volume_master      = cfg.get_value("audio",         "volume_master",     volume_master)
	volume_sfx         = cfg.get_value("audio",         "volume_sfx",        volume_sfx)
	volume_music       = cfg.get_value("audio",         "volume_music",      volume_music)
	screen_shake       = cfg.get_value("gameplay",      "screen_shake",      screen_shake)
	controller_rumble  = cfg.get_value("gameplay",      "controller_rumble", controller_rumble)
	reduce_flashing    = cfg.get_value("accessibility", "reduce_flashing",   reduce_flashing)
