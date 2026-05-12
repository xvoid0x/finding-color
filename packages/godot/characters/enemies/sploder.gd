extends EnemyBase
## Sploder - Fragile enemy that explodes on death, dealing area damage.
##
## Very fast, very low HP. Charges the guardian aggressively. When killed,
## explodes after a short delay dealing 1.0 damage to anything in range
## (including the guardian and companion). Creates interesting risk/reward:
## kill it at range? Dodge the explosion? Lure it near other enemies?
##
## Tuning targets:
##   - Dies in 1 hit (fragile)
##   - Fast enough to close distance quickly
##   - Explosion AOE large enough to threaten both guardian and companion
##   - Explosion is telegraphed (brief flash before detonation)

const EXPLOSION_RADIUS: float = 80.0
const EXPLOSION_DELAY: float = 0.4

var _guardian: Node2D = null


func _on_ready() -> void:
	max_hp = 0.5
	hp = 0.5
	move_speed = 180.0
	damage_on_contact = 0.5
	contact_cooldown = 0.6
	target_priority = TargetPriority.GUARDIAN

	# Load rotation sprites
	_setup_rotation_sprites("res://assets/characters/enemy_sploder/rotations/")

	await get_tree().process_frame
	_guardian = get_tree().get_first_node_in_group("guardian")

	var area := get_node_or_null("ContactArea") as Area2D
	if area:
		area.body_entered.connect(_on_body_entered_base)
		var contact_shape := area.get_node_or_null("ContactShape") as CollisionShape2D
		if contact_shape:
			var shape := CircleShape2D.new()
			shape.radius = 16.0
			contact_shape.shape = shape


func _on_physics_process(delta: float) -> void:
	if not _guardian:
		_guardian = get_tree().get_first_node_in_group("guardian")
		return

	var dir: Vector2 = (_guardian.global_position - global_position).normalized()
	velocity = dir * move_speed
	move_and_slide()


func take_damage(amount: float, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	"""Override to trigger explosion on death."""
	if _is_dead:
		return

	hp -= amount

	if hp <= 0.0:
		_start_explosion_sequence()
		return

	# Normal hit flash
	if _sprite and _sprite.material is ShaderMaterial:
		var mat := _sprite.material as ShaderMaterial
		mat.set_shader_parameter("crack_glow_intensity", 3.0)
		var tween := create_tween()
		tween.tween_interval(0.1)
		tween.tween_callback(func():
			if is_instance_valid(self) and _sprite and _sprite.material is ShaderMaterial:
				(_sprite.material as ShaderMaterial).set_shader_parameter("crack_glow_intensity", 1.5)
		)

	if knockback_dir != Vector2.ZERO:
		velocity = knockback_dir * 300.0


func _start_explosion_sequence() -> void:
	"""Telegraph then explode on death."""
	if _is_dead:
		return
	_is_dead = true
	_collision.set_deferred("disabled", true)

	print("[ENEMY] Sploder exploding | floor: ", GameManager.current_floor)
	GameManager.stat_enemies_killed += 1

	# Telegraph: flash bright, grow slightly
	if _sprite:
		var tween := create_tween()
		tween.tween_property(_sprite, "modulate", Color(1.0, 0.9, 0.3, 1.0), EXPLOSION_DELAY * 0.5)
		tween.parallel().tween_property(_sprite, "scale", Vector2(1.5, 1.5), EXPLOSION_DELAY)

	# Light ramps up
	if _light:
		var tween := create_tween()
		tween.tween_property(_light, "energy", 2.0, EXPLOSION_DELAY)
		tween.parallel().tween_property(_light, "texture_scale", 2.5, EXPLOSION_DELAY)

	# Explosion after delay
	var timer := get_tree().create_timer(EXPLOSION_DELAY)
	timer.timeout.connect(_detonate)


func _detonate() -> void:
	"""Deal AOE damage around position and queue free."""
	if not is_instance_valid(self):
		return

	# Visual: flash
	var flash := ColorRect.new()
	flash.size = Vector2(EXPLOSION_RADIUS * 2, EXPLOSION_RADIUS * 2)
	flash.position = global_position - flash.size * 0.5
	flash.color = Color(1.0, 0.5, 0.0, 0.6)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_parent().add_child(flash)

	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)

	# Hitstop + shake
	HitstopManager.kill()
	CameraShaker.shake(12.0, 0.25)

	# Deal AOE damage using group-based distance check (more reliable than physics-space queries)
	var guardian := get_tree().get_first_node_in_group("guardian")
	if guardian and global_position.distance_to(guardian.global_position) <= EXPLOSION_RADIUS:
		if guardian.has_method("take_hit"):
			guardian.take_hit(1.0, global_position)

	var companion := get_tree().get_first_node_in_group("companion")
	if companion and global_position.distance_to(companion.global_position) <= EXPLOSION_RADIUS:
		if companion.has_method("take_damage"):
			companion.take_damage(1.0)

	queue_free()
