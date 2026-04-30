extends CanvasLayer
## HUD - Guardian hearts top-left, floor top-right, event flash centre.
## Pillars: play space sacred, corners only, feedback instant+gone.

@onready var _hearts_container: HBoxContainer  = $HeartsContainer
@onready var _companion_hp_container: HBoxContainer = $CompanionHPContainer
@onready var _companion_dots: Label            = $CompanionHPContainer/CompanionDots
@onready var _floor_label: Label               = $FloorLabel
@onready var _fragment_label: Label            = $FragmentLabel
@onready var _phone_status_label: Label        = $PhoneStatusLabel
@onready var _event_flash: Label               = $EventFlash

var _flash_tween: Tween = null


func _ready() -> void:
	EventBus.guardian_hearts_changed.connect(_on_hearts_changed)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.floor_cleared.connect(_on_floor_cleared)
	EventBus.phone_event_triggered.connect(_on_event_triggered)
	EventBus.phone_event_completed.connect(_on_event_completed)
	EventBus.phone_event_expired.connect(_on_event_expired)
	EventBus.companion_damaged.connect(_on_companion_damaged)
	EventBus.companion_freed.connect(_on_companion_freed)
	EventBus.companion_retreated.connect(_on_companion_retreated)
	EventBus.phone_player_joined.connect(_on_phone_joined)
	EventBus.phone_player_left.connect(_on_phone_left)
	if EventBus.has_signal("dreamer_fragments_changed"):
		EventBus.dreamer_fragments_changed.connect(_on_fragments_changed)

	_build_hearts()
	_companion_hp_container.visible = false
	_event_flash.visible = false
	_update_floor_label()
	_update_fragment_label()
	_update_phone_status(false)


# ---------------------------------------------------------------------------
# Hearts
# ---------------------------------------------------------------------------

func _build_hearts() -> void:
	for child in _hearts_container.get_children():
		child.queue_free()

	var max_hp: float  = GameManager.guardian_max_hearts
	var cur_hp: float  = GameManager.guardian_hearts

	for i in int(max_hp):
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 28)

		var threshold_full := float(i) + 1.0
		var threshold_half := float(i) + 0.5

		if cur_hp >= threshold_full:
			lbl.text = "♥"
			lbl.modulate = Color(0.35, 0.55, 1.0, 1.0)
			# Subtle glow on full hearts via alpha pulse — done via self_modulate
		elif cur_hp >= threshold_half:
			lbl.text = "♥"
			lbl.modulate = Color(0.35, 0.55, 1.0, 0.55)
		else:
			lbl.text = "♡"
			lbl.modulate = Color(0.35, 0.4, 0.55, 0.35)

		_hearts_container.add_child(lbl)


func _on_hearts_changed(_current: float, _maximum: float) -> void:
	_build_hearts()


# ---------------------------------------------------------------------------
# Floor label
# ---------------------------------------------------------------------------

func _update_floor_label() -> void:
	_floor_label.text = "Floor  %d" % GameManager.current_floor


func _on_room_entered(_room_index: int) -> void:
	_update_floor_label()


func _on_floor_cleared(_floor_number: int) -> void:
	_update_floor_label()


func _update_fragment_label() -> void:
	_fragment_label.text = "◆ %d" % GameManager.dreamer_fragments


func _on_fragments_changed(_amount: int) -> void:
	_update_fragment_label()


func _update_phone_status(connected: bool) -> void:
	if connected:
		_phone_status_label.text = "phone ●"
		_phone_status_label.modulate = Color(0.27, 0.87, 0.53, 0.85)
	else:
		_phone_status_label.text = "no phone"
		_phone_status_label.modulate = Color(0.6, 0.3, 0.3, 0.7)


func _on_phone_joined(_peer_id: int) -> void:
	_update_phone_status(true)


func _on_phone_left(_peer_id: int) -> void:
	_update_phone_status(false)


# ---------------------------------------------------------------------------
# Companion HP (only visible while anchored)
# ---------------------------------------------------------------------------

func _on_companion_damaged(hits_remaining: int) -> void:
	_companion_hp_container.visible = true
	_companion_dots.text = "♦".repeat(hits_remaining)


func _on_companion_freed() -> void:
	_companion_hp_container.visible = false


func _on_companion_retreated() -> void:
	_companion_hp_container.visible = false


# ---------------------------------------------------------------------------
# Event flash — large, centred, self-dismissing (Pillar 6)
# ---------------------------------------------------------------------------

func _on_event_triggered(event_type: String) -> void:
	var text: String
	var colour: Color
	match event_type:
		"heal":
			text = "HEAL"
			colour = Color(0.35, 0.65, 1.0)
		"chest_unlock":
			text = "OPENING"
			colour = Color(0.9, 0.75, 0.2)
		"power_attack":
			text = "POWER"
			colour = Color(0.8, 0.4, 1.0)
		_:
			text = "EVENT"
			colour = Color(0.6, 0.6, 0.8)

	_show_flash(text, colour, 1.2)


func _on_event_completed(event_type: String, score: int, max_score: int) -> void:
	var ratio := float(score) / float(max_score) if max_score > 0 else 0.0
	var text: String
	var colour: Color

	if ratio >= 1.0:
		text = "Perfect!"
		colour = Color(0.4, 1.0, 0.55)
	elif ratio > 0.0:
		text = "%d / %d" % [score, max_score]
		colour = Color(1.0, 0.8, 0.3)
	else:
		text = "Missed"
		colour = Color(1.0, 0.35, 0.35)

	_show_flash(text, colour, 1.5)


func _on_event_expired(_event_type: String) -> void:
	_show_flash("Missed", Color(1.0, 0.35, 0.35), 1.2)


func _show_flash(text: String, colour: Color, duration: float) -> void:
	# Kill any existing flash tween
	if _flash_tween:
		_flash_tween.kill()

	_event_flash.text = text
	_event_flash.modulate = Color(colour.r, colour.g, colour.b, 0.0)
	_event_flash.visible = true

	_flash_tween = create_tween()
	# Fade in fast
	_flash_tween.tween_property(_event_flash, "modulate:a", 1.0, 0.12)
	# Hold
	_flash_tween.tween_interval(duration)
	# Fade out
	_flash_tween.tween_property(_event_flash, "modulate:a", 0.0, 0.3)
	_flash_tween.tween_callback(func(): _event_flash.visible = false)
