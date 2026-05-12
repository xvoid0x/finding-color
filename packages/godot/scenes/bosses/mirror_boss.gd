class_name MirrorBoss
extends Node2D
## The Mirror — Demo boss fight.
## Emotional theme: Self-doubt.
##
## Phase 1: Mirror moves slowly, sends reflection to fight. Mirror invulnerable
##   while reflection is alive. Kill reflection → mirror takes damage → respawns.
## Phase 2 (50% HP): Both mirror and reflection active simultaneously.
##   Mirror fires shards. Reflection is permanent.
## Death: big shatter + colour bloom, unlocks room.

const REFLECTION_SCENE := preload("res://characters/enemies/mirror_reflection.tscn")

# Room bounds — updated by set_room_bounds() for boss arenas
var _room_min := Vector2(400, 300)
var _room_max := Vector2(1520, 780)
const HITBOX_SCRIPT := preload("res://scenes/bosses/mirror_hitbox.gd")

signal boss_died()
signal phase_changed(phase: int)
signal mirror_hit()

enum Phase { ONE, TWO }

@export var mirror_hp: float = 12.0
@export var mirror_speed: float = 30.0
@export var reflection_speed: float = 200.0
@export var reflection_hp: float = 2.0
@export var reflection_respawn_delay: float = 1.5
@export var shard_speed: float = 300.0
@export var shard_interval: float = 1.5

var _hp: float
var _phase: Phase = Phase.ONE
var _is_dead: bool = false

# Reflection
var _reflection: Node2D = null
var _reflection_active: bool = false
var _reflection_speed_mult: float = 1.0

# Shards
var _shard_timer: float = 0.0

# Movement
var _move_target: Vector2
var _move_timer: float = 0.0
var _last_position: Vector2

# Nodes
@onready var _anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _animator: Node = $MirrorBossAnimator
@onready var _light: PointLight2D = $PointLight2D


func _ready() -> void:
	_hp = mirror_hp
	_last_position = global_position
	add_to_group("enemies")
	add_to_group("boss")
	add_to_group("wall")  # Shards collide with "wall" group

	_build_mirror_collision()
	_pick_new_move_target()

	EventBus.phone_event_completed.connect(_on_phone_event_completed)

	print("[MIRROR] Ready — HP: %.0f" % mirror_hp)
	get_tree().create_timer(1.0).timeout.connect(_spawn_reflection)


# =============================================================================
# Collision — StaticBody2D hitbox
# =============================================================================

func _build_mirror_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "MirrorBody"
	body.collision_layer = 4  # Layer 3, enemy layer (bit 2)
	body.add_to_group("enemies")

	var rect := RectangleShape2D.new()
	rect.size = Vector2(80, 120)
	var shape := CollisionShape2D.new()
	shape.shape = rect
	body.add_child(shape)
	add_child(body)

	if HITBOX_SCRIPT:
		body.set_script(HITBOX_SCRIPT)


func _receive_hit(damage: float) -> void:
	if _is_dead:
		return

	if _phase == Phase.ONE and _reflection_active:
		_front_clink()
		return

	_hp -= damage
	mirror_hit.emit()
	print("[MIRROR] HP: %.0f/%.0f" % [_hp, mirror_hp])

	# Flash white briefly
	_anim_sprite.modulate = Color(1.0, 0.85, 0.95, 0.95)
	var tween := create_tween()
	tween.tween_interval(0.08)
	tween.tween_callback(func():
		if is_instance_valid(self):
			_anim_sprite.modulate = Color.WHITE
	)

	CameraShaker.shake(8.0, 0.15)
	HitstopManager.hit()

	if _hp <= 0.0:
		_die()
	elif _hp <= mirror_hp * 0.5 and _phase == Phase.ONE:
		_enter_phase_two()


func _front_clink() -> void:
	print("[MIRROR] Blocked — reflection alive")


# =============================================================================
# Movement + Direction
# =============================================================================

func _process(delta: float) -> void:
	if _is_dead:
		return

	# Update direction from movement
	var move_vec := global_position - _last_position
	_last_position = global_position
	if move_vec.length() > 5.0 and _animator and _animator.has_method("get_dir_from_vector"):
		var dir: String = _animator.get_dir_from_vector(move_vec)
		_animator.set_direction(dir)

	# Pick new movement target
	_move_timer -= delta
	if _move_timer <= 0.0:
		_pick_new_move_target()

	# Move
	var to_target: Vector2 = _move_target - global_position
	if to_target.length() > 10.0:
		global_position += to_target.normalized() * mirror_speed * delta

	# Shards in phase 2
	if _phase == Phase.TWO:
		_shard_timer -= delta
		if _shard_timer <= 0.0:
			_fire_shard()


func set_room_bounds(room_w: float, room_h: float) -> void:
	var margin := Vector2(200, 200)
	_room_min = margin
	_room_max = Vector2(room_w - margin.x, room_h - margin.y)


func _pick_new_move_target() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_move_target = Vector2(
		rng.randf_range(_room_min.x, _room_max.x),
		rng.randf_range(_room_min.y, _room_max.y)
	)
	_move_timer = rng.randf_range(2.0, 4.0)


# =============================================================================
# Reflection
# =============================================================================

func _spawn_reflection() -> void:
	if _is_dead:
		return

	_reflection = REFLECTION_SCENE.instantiate()
	_reflection.name = "MirrorReflection"
	_reflection.add_to_group("enemies")
	_reflection.global_position = global_position + Vector2(80, 0)

	if "move_speed" in _reflection:
		_reflection.set("move_speed", reflection_speed * _reflection_speed_mult)
	if "hp" in _reflection:
		_reflection.set("hp", reflection_hp)

	if _reflection.died.is_connected(_on_reflection_died):
		_reflection.died.disconnect(_on_reflection_died)
	_reflection.died.connect(_on_reflection_died)

	_reflection_active = true
	add_child(_reflection)
	_reflection_speed_mult += 0.15
	print("[MIRROR] Reflection spawned (speed x%.2f)" % _reflection_speed_mult)


func _on_reflection_died() -> void:
	if not _reflection_active:
		return
	_reflection_active = false
	_reflection = null

	CameraShaker.shake(10.0, 0.2)
	HitstopManager.kill()

	if _phase == Phase.ONE:
		_hp -= 1.0
		mirror_hit.emit()
		print("[MIRROR] Reflection shattered — HP: %.0f/%.0f" % [_hp, mirror_hp])

		if _hp <= 0.0:
			_die()
		elif _hp <= mirror_hp * 0.5:
			_enter_phase_two()
		else:
			get_tree().create_timer(reflection_respawn_delay).timeout.connect(_spawn_reflection)
	else:
		get_tree().create_timer(1.0).timeout.connect(_spawn_reflection)


# =============================================================================
# Phase 2
# =============================================================================

func _enter_phase_two() -> void:
	_phase = Phase.TWO
	phase_changed.emit(2)
	print("[MIRROR] Phase 2 — shards start")

	# Glow pulse
	if _light:
		_light.color = Color(0.6, 0.2, 0.4, 1)
		_light.energy = 3.0

	if not _reflection_active or not is_instance_valid(_reflection):
		_reflection_speed_mult = 1.0
		_spawn_reflection()

	_shard_timer = shard_interval
	mirror_speed = 45.0
	CameraShaker.shake(16.0, 0.4)

	_trigger_boss_phase_event()


func _trigger_boss_phase_event() -> void:
	PhoneManager.trigger_event("boss_phase", 8.0)
	print("[MIRROR] Boss phase event triggered")


# =============================================================================
# Shards
# =============================================================================

func _fire_shard() -> void:
	var guardian := get_tree().get_first_node_in_group("guardian") as Node2D
	if not guardian:
		return

	var shard := ColorRect.new()
	shard.size = Vector2(8, 20)
	shard.color = Color(0.4, 0.15, 0.35, 0.9)
	shard.z_index = 5
	var dir: Vector2 = (guardian.global_position - global_position).normalized()
	shard.rotation = dir.angle()
	shard.position = global_position + dir * 70.0
	get_parent().add_child(shard)

	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(shard): shard.queue_free()
	, CONNECT_ONE_SHOT)

	var proj_area := Area2D.new()
	proj_area.collision_layer = 0
	proj_area.collision_mask = 1  # Detect guardian body
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(8, 20)
	var col_shape := CollisionShape2D.new()
	col_shape.shape = rect_shape
	proj_area.add_child(col_shape)
	shard.add_child(proj_area)

	proj_area.body_entered.connect(func(body: Node) -> void:
		if not is_instance_valid(shard): return
		if body.is_in_group("guardian") and body.has_method("take_hit"):
			body.take_hit(1.0, global_position)
		shard.queue_free()
	)

	# Wall collision
	proj_area.body_entered.connect(func(body: Node) -> void:
		if not is_instance_valid(shard): return
		if body is StaticBody2D:
			shard.queue_free()
	, CONNECT_ONE_SHOT)

	_shard_timer = shard_interval


# =============================================================================
# Death
# =============================================================================

func _die() -> void:
	_is_dead = true
	print("[MIRROR] Defeated!")

	if _reflection and is_instance_valid(_reflection):
		_reflection.queue_free()
		_reflection = null

	CameraShaker.shake(20.0, 0.5)
	HitstopManager.kill()

	# Big light burst
	if _light:
		_light.color = Color(0.8, 0.4, 1.0, 1)
		_light.energy = 8.0

	var tween := create_tween()
	tween.tween_property(_anim_sprite, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_finish_death)


func _finish_death() -> void:
	boss_died.emit()
	queue_free()


# =============================================================================
# Phone Event — Companion Stun
# =============================================================================

func _on_phone_event_completed(event_type: String, _score: int, _max_score: int) -> void:
	if _is_dead or event_type != "boss_phase":
		return
	_stun(3.0)


func _stun(duration: float) -> void:
	if _is_dead:
		return
	print("[MIRROR] Stunned for %.1f seconds" % duration)
	mirror_speed = 0.0
	_anim_sprite.modulate = Color(0.6, 0.5, 0.8, 0.95)

	get_tree().create_timer(duration).timeout.connect(_end_stun)


func _end_stun() -> void:
	if _is_dead or not is_instance_valid(self):
		return
	mirror_speed = 30.0 if _phase == Phase.ONE else 45.0
	_anim_sprite.modulate = Color.WHITE
	print("[MIRROR] Stun ended")
