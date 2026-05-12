extends Node2D
## Companion - The child's dream-fragment. Follows the guardian automatically.
## Invulnerable while following. Vulnerable only when anchored to an interactable.

@export var follow_speed: float = 220.0
@export var follow_distance: float = 60.0   # How close it tries to stay
@export var anchor_hp: int = 3              # Hits before puzzle fails

enum State { FOLLOWING, STEERING, ANCHORED, RETREATING, INACTIVE }
var _state: State = State.FOLLOWING

var _guardian: Node2D = null
var _anchor_target: Node2D = null
var _current_hp: int = 0
var _is_vulnerable: bool = false
var _last_position: Vector2 = Vector2.ZERO

# Steering state — phone player tap target
var _steering_target: Vector2 = Vector2.ZERO
const STEERING_MAX_DISTANCE: float = 200.0
const STEERING_ARRIVE_THRESHOLD: float = 16.0
const STEERING_SPEED_MULTIPLIER: float = 1.4

# Visual state
var _glow_intensity: float = 1.0
var _target_glow: float = 1.0

@onready var _light: PointLight2D = $PointLight2D
@onready var _anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _animator: Node = $CompanionAnimator
@onready var _hp_bar: Control = $HPBar


func _ready() -> void:
	_hp_bar.visible = false
	_last_position = position
	EventBus.phone_event_completed.connect(_on_phone_event_completed)
	EventBus.phone_event_expired.connect(_on_phone_event_expired)


func initialize(guardian: Node2D) -> void:
	_guardian = guardian


func _process(delta: float) -> void:
	_update_glow(delta)
	_update_direction()

	match _state:
		State.FOLLOWING:
			_follow_guardian(delta)
		State.STEERING:
			_steer_to_target(delta)
		State.ANCHORED:
			pass
		State.RETREATING:
			_follow_guardian(delta)
			if _guardian and position.distance_to(_guardian.position) < follow_distance:
				_state = State.FOLLOWING


func _update_direction() -> void:
	var move_vec := position - _last_position
	_last_position = position
	if move_vec.length() < 2.0:
		return  # Not moving, keep facing
	var dir := _vector_to_direction(move_vec)
	if _animator and _animator.has_method("set_direction"):
		_animator.set_direction(dir)


func _vector_to_direction(vec: Vector2) -> String:
	return DirectionUtils.vector_to_direction(vec)


func _follow_guardian(delta: float) -> void:
	if not _guardian:
		return
	var target_pos: Vector2 = _guardian.position + Vector2(-follow_distance * 0.7, follow_distance * 0.5)
	var dist: float = position.distance_to(target_pos)
	if dist > 10.0:
		var speed := follow_speed if _state == State.FOLLOWING else follow_speed * 1.8
		position = position.move_toward(target_pos, speed * delta)


func _steer_to_target(delta: float) -> void:
	if not _guardian:
		_state = State.FOLLOWING
		return

	var clamped_target := _steering_target
	var to_target := _steering_target - _guardian.position
	if to_target.length() > STEERING_MAX_DISTANCE:
		clamped_target = _guardian.position + to_target.normalized() * STEERING_MAX_DISTANCE

	var dist := position.distance_to(clamped_target)
	if dist < STEERING_ARRIVE_THRESHOLD:
		EventBus.companion_steering_target_reached.emit(clamped_target)
		_state = State.FOLLOWING
		return

	position = position.move_toward(clamped_target, follow_speed * STEERING_SPEED_MULTIPLIER * delta)

	if position.distance_to(_guardian.position) > STEERING_MAX_DISTANCE * 1.5:
		_state = State.FOLLOWING


func set_steering_target(world_pos: Vector2) -> void:
	if _state == State.ANCHORED or _state == State.RETREATING:
		return
	_steering_target = world_pos
	_state = State.STEERING
	EventBus.companion_steering_target_set.emit(world_pos)


func gesture_at_door(door_id: int) -> void:
	if _state == State.ANCHORED or _state == State.RETREATING:
		return
	EventBus.companion_gesture_at_door.emit(door_id)
	_target_glow = 1.2


# --- Anchoring (vulnerable) ---

func anchor_to(target: Node2D) -> void:
	if _state != State.FOLLOWING:
		return
	_state = State.ANCHORED
	_anchor_target = target
	_current_hp = anchor_hp
	_is_vulnerable = true

	position = target.position + Vector2(0, -20)

	_update_hp_bar()
	_hp_bar.visible = true

	EventBus.companion_anchored.emit(target.get_meta("object_type", "unknown"))


func take_hit() -> void:
	if not _is_vulnerable:
		return
	_current_hp -= 1
	_update_hp_bar()

	# Flash red
	_anim_sprite.modulate = Color(1.0, 0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(_anim_sprite, "modulate", Color.WHITE, 0.2)

	_target_glow = 0.5

	EventBus.companion_damaged.emit(_current_hp)

	if _current_hp <= 0:
		_retreat()


func _retreat() -> void:
	_is_vulnerable = false
	_state = State.RETREATING
	_anchor_target = null
	_hp_bar.visible = false
	_target_glow = 0.6
	EventBus.companion_retreated.emit()
	EventBus.phone_event_expired.emit("chest_unlock")


func is_anchored() -> bool:
	return _state == State.ANCHORED


func retreat() -> void:
	_retreat()


func free_from_anchor() -> void:
	if _state != State.ANCHORED:
		print("[COMPANION] free_from_anchor ignored — state is: ", State.keys()[_state])
		return
	_is_vulnerable = false
	_state = State.FOLLOWING
	_anchor_target = null
	if _hp_bar:
		_hp_bar.visible = false
	_target_glow = 1.2
	_anim_sprite.modulate = Color.WHITE
	print("[COMPANION] Freed from anchor — emitting companion_freed")
	EventBus.companion_freed.emit()


# --- Glow ---

func _update_glow(delta: float) -> void:
	_glow_intensity = lerp(_glow_intensity, _target_glow, delta * 4.0)
	if _light:
		_light.energy = _glow_intensity
	if _target_glow > 1.0:
		_target_glow = move_toward(_target_glow, 1.0, delta * 1.5)
	elif _target_glow < 1.0 and _state == State.FOLLOWING:
		_target_glow = move_toward(_target_glow, 1.0, delta * 0.5)


func set_glow_for_performance(score: int, max_score: int) -> void:
	var ratio: float = float(score) / float(max_score) if max_score > 0 else 0.0
	if ratio >= 1.0:
		_target_glow = 1.5
	elif ratio >= 0.6:
		_target_glow = 1.1
	else:
		_target_glow = 0.7


# --- HP Bar ---

func _update_hp_bar() -> void:
	var hearts_label := _hp_bar.get_node_or_null("Label")
	if hearts_label:
		hearts_label.text = "o".repeat(_current_hp) + ".".repeat(anchor_hp - _current_hp)


# --- Event Listeners ---

func _on_phone_event_completed(event_type: String, score: int, max_score: int) -> void:
	print("[COMPANION] Event completed: ", event_type, " score: ", score, "/", max_score, " state: ", State.keys()[_state])
	if event_type == "chest_unlock":
		set_glow_for_performance(score, max_score)
		if score > 0:
			free_from_anchor()
		else:
			_retreat()


func _on_phone_event_expired(event_type: String) -> void:
	if event_type == "chest_unlock" and _state == State.ANCHORED:
		_retreat()
