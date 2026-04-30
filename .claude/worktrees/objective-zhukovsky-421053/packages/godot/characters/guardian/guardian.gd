extends CharacterBody2D
## Guardian - The Dream Guardian. Controller player character.
## Top-down movement, arc melee attack, dodge roll with iframes.

# --- Movement ---
@export var move_speed: float = 280.0
@export var dodge_speed: float = 600.0
@export var dodge_duration: float = 0.18
@export var dodge_cooldown: float = 0.6

# --- Attack ---
@export var attack_arc_angle: float = 90.0   # Degrees, cone in front
@export var attack_range: float = 80.0
@export var attack_damage: float = 1.0
@export var attack_cooldown: float = 0.4
@export var attack_duration: float = 0.15    # How long the hitbox is active

# --- Ghost Heart (Steady Breathing upgrade) ---
var _ghost_heart: bool = false

# --- State ---
enum State { IDLE, MOVING, ATTACKING, DODGING, KNOCKBACK, DEAD }
var _state: State = State.IDLE
var _facing: Vector2 = Vector2.DOWN

var _move_dir: Vector2 = Vector2.ZERO   # Direction of movement (left stick / WASD)
var _aim_dir: Vector2 = Vector2.DOWN    # Direction of aim (right stick / mouse)

var _dodge_timer: float = 0.0
var _dodge_cooldown_timer: float = 0.0
var _dodge_direction: Vector2 = Vector2.ZERO
var _is_invincible: bool = false

var _attack_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0
var _attack_active: bool = false

var _using_controller: bool = false

var _knockback_timer: float = 0.0
const KNOCKBACK_DURATION: float = 0.12

# --- Nodes ---
@onready var _sprite: Node2D = $Sprite
@onready var _attack_area: Area2D = $AttackArea
@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _animator: Node = $GuardianAnimator

var _facing_indicator: Polygon2D
var _dodge_break_area: Area2D  # Active during dodge roll; smashes breakable pots


func _ready() -> void:
	EventBus.guardian_died.connect(_on_died)
	_attack_area.monitoring = false
	_attack_area.body_entered.connect(_on_attack_body_entered)
	_build_facing_indicator()
	_build_dodge_break_area()
	print("[GUARDIAN] Ready")


func _build_dodge_break_area() -> void:
	"""Small sensor active only while dodging — smashes any breakable rolled through."""
	_dodge_break_area = Area2D.new()
	_dodge_break_area.collision_layer = 0
	_dodge_break_area.collision_mask = 1  # Same layer as environment/statics
	_dodge_break_area.monitoring = false
	var shape_node := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	shape_node.shape = shape
	_dodge_break_area.add_child(shape_node)
	add_child(_dodge_break_area)
	_dodge_break_area.body_entered.connect(_on_dodge_break_body_entered)


func _on_dodge_break_body_entered(body: Node) -> void:
	if body.is_in_group("breakable") and body.has_method("smash"):
		body.smash("dodge")


func _build_facing_indicator() -> void:
	_facing_indicator = Polygon2D.new()
	_facing_indicator.polygon = PackedVector2Array([
		Vector2(0, -12),
		Vector2(-6, 6),
		Vector2(6, 6),
	])
	_facing_indicator.color = Color(0.9, 0.95, 1.0, 0.9)
	add_child(_facing_indicator)


func _process(delta: float) -> void:
	match _state:
		State.ATTACKING:
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				_end_attack()
		State.DODGING:
			_dodge_timer -= delta
			if _dodge_timer <= 0.0:
				_end_dodge()

	if _dodge_cooldown_timer > 0.0:
		_dodge_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta

	# Update aim direction from right stick or mouse
	_update_aim()

	# Update facing indicator to track aim, not movement
	if _facing_indicator and _state != State.DEAD:
		_facing_indicator.rotation = _aim_dir.angle() + PI * 0.5

	# Drive animator
	if _animator and _state != State.DEAD:
		var enemies_nearby := not get_tree().get_nodes_in_group("enemies").is_empty()
		_animator.update_from_state(_state, _aim_dir, _move_dir, enemies_nearby)


func _update_aim() -> void:
	# Right stick always wins — explicit aim
	var right_stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if right_stick.length() > 0.2:
		_aim_dir = right_stick.normalized()
		_using_controller = true
		return

	# Mouse aim — check if mouse moved recently vs controller
	# Use mouse position every frame; if a joypad is connected AND left stick active, prefer stick
	var left_stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var joypads := Input.get_connected_joypads()
	var has_joypad := joypads.size() > 0

	if has_joypad and left_stick.length() > 0.2:
		# Controller moving but no right stick — aim follows movement
		_using_controller = true
		_aim_dir = left_stick.normalized()
	else:
		# Default: mouse aim (works with keyboard+mouse, and controller at rest)
		_using_controller = false
		var mouse_pos := get_global_mouse_position()
		var to_mouse := mouse_pos - global_position
		if to_mouse.length() > 8.0:
			_aim_dir = to_mouse.normalized()


func _physics_process(delta: float) -> void:
	match _state:
		State.IDLE, State.MOVING:
			_handle_movement()
			_handle_attack_input()
			_handle_dodge_input()
		State.DODGING:
			velocity = _dodge_direction * dodge_speed
			move_and_slide()
		State.ATTACKING:
			# Allow movement during attack at 40% speed — full stop feels like lag
			var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			velocity = dir * move_speed * 0.4
			move_and_slide()
		State.KNOCKBACK:
			_knockback_timer -= delta
			velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)
			move_and_slide()
			if _knockback_timer <= 0.0:
				_state = State.IDLE


# --- Movement ---

func _handle_movement() -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * move_speed
	move_and_slide()

	if dir != Vector2.ZERO:
		_move_dir = dir.normalized()
		_facing = _move_dir  # Keep _facing in sync for dodge fallback
		_state = State.MOVING
	else:
		_state = State.IDLE


# --- Attack ---

func _handle_attack_input() -> void:
	if Input.is_action_just_pressed("attack") and _attack_cooldown_timer <= 0.0:
		_begin_attack()


func _begin_attack() -> void:
	_state = State.ATTACKING
	_attack_timer = attack_duration
	_attack_cooldown_timer = attack_cooldown
	_attack_active = true

	# Favourite Song upgrade: +40% arc angle, +15% range
	var arc := attack_arc_angle * (1.4 if GameManager.has_upgrade("favourite_song") else 1.0)
	var range_bonus := attack_range * (0.15 if GameManager.has_upgrade("favourite_song") else 0.0)

	# Attack fires toward aim direction (right stick / mouse), not movement
	var angle := _aim_dir.angle()
	_attack_area.rotation = angle
	# Offset attack to originate from sprite center
	_attack_area.position = _aim_dir * (35.0 + range_bonus) + Vector2(0, -25)
	_attack_area.monitoring = true

	# Visual: arc flash
	_show_attack_arc(arc, attack_range + range_bonus)

	# Birthday Candle upgrade: leave a damage trail at attack position
	if GameManager.has_upgrade("birthday_candle"):
		_spawn_candle_trail()

	print("[ATTACK] Swung toward ", _aim_dir, " | hp: ", GameManager.guardian_hearts)


func _on_attack_body_entered(body: Node) -> void:
	if not _attack_active:
		return
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(attack_damage, _aim_dir)
		HitstopManager.hit()           # 40ms freeze — weight on impact
		CameraShaker.shake(5.0, 0.12)  # Light hit confirm shake
		print("[ATTACK] Hit enemy: ", body.name)
	# Breakable pots — attack smashes them
	if body.is_in_group("breakable") and body.has_method("smash"):
		body.smash("attack")


func _show_attack_arc(arc_angle: float = -1.0, range_override: float = -1.0) -> void:
	if arc_angle < 0.0:
		arc_angle = attack_arc_angle
	var draw_range := range_override if range_override >= 0.0 else attack_range
	var polygon := Polygon2D.new()
	var half_arc := deg_to_rad(arc_angle * 0.5)
	var base_angle := _aim_dir.angle()
	var points := PackedVector2Array()
	# Arc originates from sprite center, not feet
	var origin := Vector2(0, -25)
	points.append(origin)
	var steps := 10
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := base_angle - half_arc + t * half_arc * 2.0
		points.append(origin + Vector2(cos(a), sin(a)) * draw_range)
	polygon.polygon = points
	polygon.color = Color(0.4, 0.65, 1.0, 0.55)
	add_child(polygon)
	var tween := create_tween()
	tween.tween_property(polygon, "modulate:a", 0.0, 0.18)
	tween.tween_callback(polygon.queue_free)


func _spawn_candle_trail() -> void:
	"""Birthday Candle upgrade: leaves a glowing area at attack point.
	Enemies entering it take 0.5 damage. Lasts 1.2 seconds."""
	var trail := Area2D.new()
	# Spawn trail from sprite center, not feet
	trail.position = global_position + _aim_dir * 55.0 + Vector2(0, -25)
	trail.collision_layer = 0
	trail.collision_mask = 4  # enemy layer
	trail.monitoring = true

	var shape_node := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 36.0
	shape_node.shape = shape
	trail.add_child(shape_node)

	# Visual glow
	var glow := Polygon2D.new()
	glow.polygon = _circle_polygon(36.0, 16)
	glow.color = Color(1.0, 0.85, 0.3, 0.45)
	trail.add_child(glow)

	# Track which enemies already hit (once per trail instance)
	var hit_set: Array = []
	trail.body_entered.connect(func(body: Node) -> void:
		if body.is_in_group("enemies") and body not in hit_set:
			hit_set.append(body)
			if body.has_method("take_damage"):
				body.take_damage(0.75)
	)

	get_tree().current_scene.add_child(trail)

	var tween := get_tree().current_scene.create_tween()
	tween.tween_property(glow, "modulate:a", 0.0, 1.8)
	tween.tween_callback(trail.queue_free)


func _circle_polygon(radius: float, points: int) -> PackedVector2Array:
	var verts := PackedVector2Array()
	for i in points:
		var a := TAU * i / points
		verts.append(Vector2(cos(a), sin(a)) * radius)
	return verts


func add_ghost_heart() -> void:
	"""Steady Breathing upgrade: absorbs one hit then disappears."""
	_ghost_heart = true
	# Visual indicator — a faint extra heart glow on sprite
	if _sprite:
		var ghost_glow := PointLight2D.new()
		ghost_glow.name = "GhostHeartGlow"
		ghost_glow.color = Color(0.6, 0.8, 1.0)
		ghost_glow.energy = 0.8
		ghost_glow.texture_scale = 1.2
		_sprite.add_child(ghost_glow)


func _end_attack() -> void:
	_attack_active = false
	_attack_area.monitoring = false
	if _state == State.ATTACKING:
		_state = State.IDLE


# --- Dodge ---

func _handle_dodge_input() -> void:
	if Input.is_action_just_pressed("dodge") and _dodge_cooldown_timer <= 0.0:
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if dir == Vector2.ZERO:
			dir = _facing
		_begin_dodge(dir.normalized())


func _begin_dodge(direction: Vector2) -> void:
	_state = State.DODGING
	_dodge_direction = direction
	_dodge_timer = dodge_duration
	_dodge_cooldown_timer = dodge_cooldown
	_is_invincible = true
	_collision.disabled = true

	# Enable dodge-break sensor — smashes any breakable we roll through
	_dodge_break_area.monitoring = true

	# Smell of Rain upgrade: colour bloom on dodge that slows enemies
	if GameManager.has_upgrade("smell_of_rain"):
		_spawn_dodge_bloom()

	print("[DODGE] Rolling ", direction)


func _spawn_dodge_bloom() -> void:
	"""Smell of Rain: expanding colour circle that briefly slows enemies inside."""
	var bloom := Area2D.new()
	bloom.position = global_position
	bloom.collision_layer = 0
	bloom.collision_mask = 4
	bloom.monitoring = true

	var shape_node := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 72.0
	shape_node.shape = shape
	bloom.add_child(shape_node)

	# Visual: expanding coloured ring
	var ring := Polygon2D.new()
	ring.polygon = _circle_polygon(72.0, 20)
	ring.color = Color(0.4, 0.8, 0.6, 0.4)
	bloom.add_child(ring)

	# Slow enemies on enter
	var slowed: Array = []
	bloom.body_entered.connect(func(body: Node) -> void:
		if body.is_in_group("enemies") and body not in slowed:
			slowed.append(body)
			if "move_speed" in body:
				var original_speed: float = body.move_speed
				body.move_speed *= 0.35
				get_tree().create_timer(2.5).timeout.connect(func():
					if is_instance_valid(body):
						body.move_speed = original_speed
				)
	)

	get_tree().current_scene.add_child(bloom)

	var tween := get_tree().current_scene.create_tween()
	tween.tween_property(ring, "modulate:a", 0.0, 0.8)
	tween.tween_callback(bloom.queue_free)


func _end_dodge() -> void:
	_is_invincible = false
	_collision.disabled = false
	_dodge_break_area.monitoring = false
	_state = State.IDLE


# --- Take Damage ---

func take_hit(amount: float, from_position: Vector2) -> void:
	"""Called by enemies. Applies knockback away from attacker, then damage."""
	if _is_invincible or _state == State.DEAD:
		return

	# Steady Breathing: ghost heart absorbs one hit entirely
	if _ghost_heart:
		_ghost_heart = false
		var glow := _sprite.get_node_or_null("GhostHeartGlow")
		if glow:
			glow.queue_free()
		CameraShaker.shake(6.0, 0.2)
		# Brief iframes so the hit feels registered
		_is_invincible = true
		var t := create_tween()
		t.tween_interval(0.4)
		t.tween_callback(func(): _is_invincible = false)
		return

	var knockback_dir := (global_position - from_position).normalized()
	velocity = knockback_dir * 380.0
	_knockback_timer = KNOCKBACK_DURATION
	_state = State.KNOCKBACK
	# Shake + hitstop scales with damage
	HitstopManager.heavy()
	CameraShaker.shake(amount * 10.0, 0.35)
	take_damage(amount)


func take_damage(amount: float, _source: String = "enemy") -> void:
	"""Direct damage without knockback direction (use take_hit when position is known)."""
	if _is_invincible or _state == State.DEAD:
		return
	print("[GUARDIAN] Took damage: ", amount, " | hp before: ", GameManager.guardian_hearts)
	GameManager.damage_guardian(amount, _source)

	# Brief invincibility after hit
	_is_invincible = true
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_callback(func(): _is_invincible = false)

	# Flash
	_sprite.modulate = Color.WHITE
	var flash_tween := create_tween()
	flash_tween.tween_property(_sprite, "modulate", Color(0.4, 0.6, 1.0, 1.0), 0.3)

	# Heal event — brief delay so slow-mo doesn't snap in mid-hit
	var hp_ratio := GameManager.guardian_hearts / GameManager.guardian_max_hearts
	if hp_ratio <= 0.5 and not PhoneManager._event_active:
		get_tree().create_timer(0.8, true, false, true).timeout.connect(func():
			if not PhoneManager._event_active:
				print("[EVENT] HP low — triggering heal event")
				var window := PhoneManager.get_event_difficulty(5.0)
				PhoneManager.trigger_event("heal", window)
		, CONNECT_ONE_SHOT)


# --- Debug Drawing ---

const DEBUG_DRAW_COLLISION := true

func _draw() -> void:
	if not DEBUG_DRAW_COLLISION:
		return
	var col_shape := $CollisionShape2D
	if not col_shape or not col_shape.shape is CapsuleShape2D:
		return
	var capsule := col_shape.shape as CapsuleShape2D
	var radius: float = capsule.radius * col_shape.scale.x
	var height: float = capsule.height * col_shape.scale.y
	var points := _capsule_polygon(radius, height)
	for i in range(points.size()):
		points[i] += col_shape.position
	draw_colored_polygon(points, Color(1, 0, 0, 0.3))

func _capsule_polygon(radius: float, height: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments := 16
	var half_straight := (height - 2.0 * radius) / 2.0

	# Top semicircle (counter-clockwise: left → top → right)
	for i in range(segments + 1):
		var angle := PI + (PI * float(i) / float(segments))
		points.append(Vector2(cos(angle) * radius, -half_straight + sin(angle) * radius))

	# Bottom semicircle (counter-clockwise: right → bottom → left)
	for i in range(segments + 1):
		var angle := (PI * float(i) / float(segments))
		points.append(Vector2(cos(angle) * radius, half_straight + sin(angle) * radius))

	return points

func _on_died() -> void:
	print("[GUARDIAN] Died")
	_state = State.DEAD
	velocity = Vector2.ZERO
	CameraShaker.shake(24.0, 0.6)
