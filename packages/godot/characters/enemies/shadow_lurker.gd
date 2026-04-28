extends EnemyBase
## ShadowLurker - Basic enemy type 2.
## Circles the guardian at a distance, then dashes in to attack.
## Slightly more interesting pattern than ShadowWalker.

@export var circle_radius: float = 160.0
@export var circle_speed: float = 1.8   # Radians per second
@export var dash_speed: float = 320.0
@export var dash_duration: float = 0.25
@export var dash_cooldown: float = 2.5

enum LurkerState { CIRCLING, WINDUP, DASHING, RECOVERING }
var _lurker_state: LurkerState = LurkerState.CIRCLING
var _circle_angle: float = 0.0
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _windup_timer: float = 0.0
const WINDUP_DURATION: float = 0.35
var _dash_direction: Vector2 = Vector2.ZERO
var _guardian: Node2D = null

@onready var _body_rect: ColorRect = $Sprite2D/Body



func _on_ready() -> void:
	max_hp = 2.0
	hp = 2.0
	damage_on_contact = 1.0
	move_speed = 60.0

	await get_tree().process_frame
	_guardian = get_tree().get_first_node_in_group("guardian")
	if _guardian:
		# Start at a random angle around guardian
		_circle_angle = randf() * TAU

	var area := get_node_or_null("ContactArea")
	if area:
		area.body_entered.connect(_on_body_entered_base)
		var contact_shape := area.get_node_or_null("ContactShape") as CollisionShape2D
		if contact_shape:
			var shape := CircleShape2D.new()
			shape.radius = 24.0
			contact_shape.shape = shape


func _on_process(delta: float) -> void:
	if _dash_cooldown_timer > 0.0:
		_dash_cooldown_timer -= delta
	if _lurker_state == LurkerState.WINDUP:
		_windup_timer -= delta
		if _windup_timer <= 0.0:
			_begin_dash()
	if _lurker_state == LurkerState.DASHING:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_lurker_state = LurkerState.RECOVERING
			_dash_cooldown_timer = dash_cooldown


func _on_physics_process(delta: float) -> void:
	if not _guardian:
		_guardian = get_tree().get_first_node_in_group("guardian")
		return

	match _lurker_state:
		LurkerState.CIRCLING:
			_circle_angle += circle_speed * delta
			var target: Vector2 = _guardian.global_position + Vector2(
				cos(_circle_angle) * circle_radius,
				sin(_circle_angle) * circle_radius
			)
			velocity = (target - global_position).normalized() * move_speed * 3.0
			move_and_slide()

			# Windup when cooldown is ready
			if _dash_cooldown_timer <= 0.0:
				_start_windup()

		LurkerState.WINDUP:
			# Brief pause — velocity decays, face target
			velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
			move_and_slide()

		LurkerState.DASHING:
			velocity = _dash_direction * dash_speed
			move_and_slide()

		LurkerState.RECOVERING:
			velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
			move_and_slide()
			if velocity.length() < 10.0:
				_lurker_state = LurkerState.CIRCLING


func _start_windup() -> void:
	_lurker_state = LurkerState.WINDUP
	_windup_timer = WINDUP_DURATION
	# Telegraph: brighten body + pulse light
	if _body_rect:
		var tween := create_tween()
		tween.tween_property(_body_rect, "color", Color(1.0, 0.8, 0.6, 1.0), 0.15)
		tween.tween_property(_body_rect, "color", Color(0.95, 0.35, 0.1, 1.0), 0.2)
	if _light:
		_light.energy = 2.0

func _begin_dash() -> void:
	_lurker_state = LurkerState.DASHING
	_dash_timer = dash_duration
	_dash_direction = (_guardian.global_position - global_position).normalized()
	if _light:
		_light.energy = 0.6  # Reset glow
