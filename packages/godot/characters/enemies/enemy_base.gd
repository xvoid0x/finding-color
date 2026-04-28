class_name EnemyBase
extends CharacterBody2D
## EnemyBase - Base class for all enemies.
## Handles: health, crack shader, death shatter, damage dealing to guardian.
## Extend this for each enemy type.

## Target priority — who does this enemy chase?
enum TargetPriority { GUARDIAN, COMPANION, NEAREST }

@export var max_hp: float = 1.0
@export var move_speed: float = 80.0
@export var damage_on_contact: float = 1.0
@export var contact_cooldown: float = 0.8
@export var target_priority: TargetPriority = TargetPriority.GUARDIAN

var hp: float = 1.0
var _contact_timer: float = 0.0
var _is_dead: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _light: PointLight2D = $PointLight2D

var _facing_indicator: Polygon2D


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	_on_ready()
	_build_facing_indicator()
	# Duplicate the shader material so each enemy instance has its own.
	# Without this, all enemies share one ShaderMaterial and health_percent
	# changes on one affect all others visually.
	if _sprite and _sprite.material:
		_sprite.material = _sprite.material.duplicate()
	_assign_crack_texture()


func _assign_crack_texture() -> void:
	"""Assign the procedural crack texture and body colour to the shader material.
	Also ensures Sprite2D has a white texture so the shader has something to render."""
	if not _sprite or not _sprite.material:
		return
	if not _sprite.material is ShaderMaterial:
		return
	var mat := _sprite.material as ShaderMaterial

	# Assign crack texture from autoload
	if CrackTextureGen:
		mat.set_shader_parameter("crack_texture", CrackTextureGen.get_texture())

	# Read body colour from ColorRect child of Sprite2D (placeholder visual)
	var body_rect := _sprite.get_node_or_null("Body") as ColorRect
	if body_rect:
		mat.set_shader_parameter("body_color", body_rect.color)
		# Resize Sprite2D to match ColorRect so shader covers it
		var rect_size := body_rect.size
		# ColorRect uses offset_left/top/right/bottom — compute actual size
		var half_w: float = (body_rect.offset_right - body_rect.offset_left) * 0.5
		var half_h: float = (body_rect.offset_bottom - body_rect.offset_top) * 0.5
		var w: int = int(half_w * 2.0)
		var h: int = int(half_h * 2.0)
		if w > 0 and h > 0:
			# Create a white texture the size of the body rect
			var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
			_sprite.texture = ImageTexture.create_from_image(img)
			# Hide the ColorRect — shader renders the colour now
			body_rect.visible = false


func _build_facing_indicator() -> void:
	_facing_indicator = Polygon2D.new()
	_facing_indicator.polygon = PackedVector2Array([
		Vector2(0, -10),
		Vector2(-5, 5),
		Vector2(5, 5),
	])
	_facing_indicator.color = Color(1.0, 1.0, 0.2, 0.85)
	add_child(_facing_indicator)


func _on_ready() -> void:
	"""Override in subclass for additional setup."""
	pass


func _process(delta: float) -> void:
	if _is_dead:
		return
	if _contact_timer > 0.0:
		_contact_timer -= delta
	_update_crack_shader()
	_on_process(delta)


func _check_contact_damage() -> void:
	"""Poll-based contact damage. More reliable than body_entered for sustained overlap."""
	if _contact_timer > 0.0:
		return
	var area := get_node_or_null("ContactArea") as Area2D
	if not area:
		return
	for body in area.get_overlapping_bodies():
		if body.is_in_group("guardian"):
			print("[ENEMY] ", name, " contact damage: ", damage_on_contact)
			if body.has_method("take_hit"):
				body.take_hit(damage_on_contact, global_position)
			elif body.has_method("take_damage"):
				body.take_damage(damage_on_contact)
			_contact_timer = contact_cooldown
			return


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_on_physics_process(delta)
	_check_contact_damage()
	# Update facing indicator
	if _facing_indicator and velocity.length() > 10.0:
		_facing_indicator.rotation = velocity.angle() + PI * 0.5


# --- Override these in subclasses ---

func _on_process(_delta: float) -> void:
	pass


func _on_physics_process(_delta: float) -> void:
	pass


# --- Damage System ---

func take_damage(amount: float, _knockback_dir: Vector2 = Vector2.ZERO) -> void:
	if _is_dead:
		return
	hp -= amount

	# Hit flash — briefly boost health_percent to 0 in shader, then restore
	# (simpler: just flash the shader's crack_glow_intensity for a frame)
	if _sprite and _sprite.material is ShaderMaterial:
		var mat := _sprite.material as ShaderMaterial
		mat.set_shader_parameter("crack_glow_intensity", 3.0)
		var tween := create_tween()
		tween.tween_interval(0.1)
		tween.tween_callback(func(): 
			if is_instance_valid(self) and _sprite and _sprite.material is ShaderMaterial:
				(_sprite.material as ShaderMaterial).set_shader_parameter("crack_glow_intensity", 1.5)
		)

	# Knockback
	if _knockback_dir != Vector2.ZERO:
		velocity = _knockback_dir * 200.0

	if hp <= 0.0:
		_die()


func _update_crack_shader() -> void:
	"""Drive the crack shader uniform based on current HP ratio."""
	if not _sprite or not _sprite.material:
		return
	var ratio: float = hp / max_hp
	_sprite.material.set_shader_parameter("health_percent", ratio)
	# Intensify glow through cracks near death
	if _light:
		_light.energy = lerp(0.0, 1.5, 1.0 - ratio)


func _die() -> void:
	_is_dead = true
	_collision.set_deferred("disabled", true)

	print("[ENEMY] ", name, " died | floor: ", GameManager.current_floor)
	GameManager.stat_enemies_killed += 1

	# Death: stronger hitstop + shake
	HitstopManager.kill()
	CameraShaker.shake(10.0, 0.2)

	# Shatter effect -- particles + screen flash
	_play_shatter_effect()

	# Drop pickups
	_on_death_drops()

	# Remove after effect plays
	var tween := create_tween()
	tween.tween_interval(0.4)
	tween.tween_callback(queue_free)


func _play_shatter_effect() -> void:
	# Spawn shatter particles if available
	var particles := get_node_or_null("ShatterParticles")
	if particles and particles is GPUParticles2D:
		particles.emitting = true
		particles.set_meta("keep_alive", true)

	# Fade out sprite
	var fade_time := 0.3
	if SettingsManager.reduce_flashing:
		# Skip flash, just fade out immediately
		_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate:a", 0.0, fade_time)

	# Bloom: PointLight2D fades with sprite naturally.
	# With reduce_flashing, cap glow energy so it doesn't spike on death.
	if SettingsManager.reduce_flashing and _light:
		_light.energy = minf(_light.energy, 0.4)


## Returns the current chase target based on target_priority.
## Swarmer switches to companion when anchored; Stalker always targets companion.
func get_chase_target() -> Node2D:
	match target_priority:
		TargetPriority.COMPANION:
			var companion := get_tree().get_first_node_in_group("companion") as Node2D
			return companion
		TargetPriority.NEAREST:
			var guardian := get_tree().get_first_node_in_group("guardian") as Node2D
			var companion := get_tree().get_first_node_in_group("companion") as Node2D
			if not guardian:
				return companion
			if not companion:
				return guardian
			var d_guardian := global_position.distance_squared_to(guardian.global_position)
			var d_companion := global_position.distance_squared_to(companion.global_position)
			return companion if d_companion < d_guardian else guardian
		_: # GUARDIAN default
			return get_tree().get_first_node_in_group("guardian") as Node2D


func _on_death_drops() -> void:
	"""Override to customise drops. Base: small chance of heart fragment."""
	if randf() < 0.4:
		_spawn_drop("heart_fragment")
	if randf() < 0.6:
		_spawn_drop("dream_fragment")


func _spawn_drop(drop_type: String) -> void:
	# Placeholder -- instantiate drop scene at position
	# TODO: Load actual drop scenes
	pass


# --- Contact Damage ---

func _on_body_entered_base(body: Node) -> void:
	"""Call this from subclass body_entered signal."""
	if _is_dead or _contact_timer > 0.0:
		return
	if body.is_in_group("guardian"):
		print("[ENEMY] ", name, " hit guardian for ", damage_on_contact)
		if body.has_method("take_hit"):
			body.take_hit(damage_on_contact, global_position)
		elif body.has_method("take_damage"):
			body.take_damage(damage_on_contact)
		_contact_timer = contact_cooldown
