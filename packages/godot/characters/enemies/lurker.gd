extends EnemyBase
## Lurker - Ranged enemy. Circles the guardian and fires slow projectiles.
##
## Stays at medium range (200-300px), strafes to keep distance, fires
## a slow telegraphed projectile every 3 seconds. The projectile is dodge-able
## even at close range due to its speed. Adds pressure without requiring
## precise melee positioning from the player.
##
## Tuning targets:
##   - Dies in 1 guardian hit (same as swarmer)
##   - Projectile is slow enough to side-step consistently
##   - Must have line-of-sight to fire (ignored for prototype — no obstacles yet)

enum LurkerState { CIRCLING, FIRING, COOLDOWN }

var _guardian: Node2D = null
var _state: LurkerState = LurkerState.CIRCLING
var _state_timer: float = 0.0
var _circle_angle: float = 0.0
var _circle_radius: float = 250.0
var _orbit_speed: float = 1.2  # radians per second
var _fire_cooldown: float = 3.0

# Projectile placeholder
var _projectile_scene: PackedScene = null


func _on_ready() -> void:
	max_hp = 1.5
	hp = 1.5
	move_speed = 100.0
	damage_on_contact = 0.5
	target_priority = TargetPriority.GUARDIAN

	await get_tree().process_frame
	_guardian = get_tree().get_first_node_in_group("guardian")
	_circle_angle = randf() * TAU

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

	_state_timer -= delta

	match _state:
		LurkerState.CIRCLING:
			# Orbit around the guardian at fixed range
			_circle_angle += _orbit_speed * delta
			var target_pos: Vector2 = _guardian.global_position + \
				Vector2(cos(_circle_angle), sin(_circle_angle)) * _circle_radius
			var dir: Vector2 = (target_pos - global_position).normalized()
			velocity = dir * move_speed

			# Transition to firing after a random delay
			if _state_timer <= 0.0:
				_state = LurkerState.FIRING
				_state_timer = 0.6  # wind-up before projectile fires
				# Wind-up visual: flash the body brighter
				_flash_color(Color(1.0, 0.8, 0.4, 1.0), 0.15)

		LurkerState.FIRING:
			# Hold position, wind up animation plays, then fire projectile
			velocity = Vector2.ZERO

			if _state_timer <= 0.0:
				_fire_projectile()
				_state = LurkerState.COOLDOWN
				_state_timer = _fire_cooldown
				_circle_angle = (global_position - _guardian.global_position).angle()

		LurkerState.COOLDOWN:
			# Briefly drift before resuming orbit
			var dir := (global_position - _guardian.global_position).normalized()
			velocity = dir * move_speed * 0.3

			if _state_timer <= 0.0:
				_state = LurkerState.CIRCLING
				_state_timer = randf_range(1.5, 3.0)

	move_and_slide()


func _fire_projectile() -> void:
	"""Fire a slow projectile toward the guardian."""
	if not _guardian:
		return

	var dir: Vector2 = (_guardian.global_position - global_position).normalized()

	# Placeholder: spawn a ColorRect projectile
	# In real implementation, use an Area2D projectile scene
	var proj := ColorRect.new()
	proj.size = Vector2(10, 10)
	proj.color = Color(0.8, 0.3, 0.9, 1.0)  # purple
	proj.position = global_position - proj.size * 0.5
	get_parent().add_child(proj)

	# Animate the projectile with a tween
	var target_pos: Vector2 = global_position + dir * 600.0
	var tween := create_tween()
	tween.tween_property(proj, "position", target_pos - proj.size * 0.5, 1.0)
	tween.tween_callback(proj.queue_free)


func _flash_color(color: Color, duration: float) -> void:
	"""Brief flash of the body ColorRect."""
	var body := $Sprite2D/Body as ColorRect
	if body:
		var original := body.color
		var tween := create_tween()
		tween.tween_property(body, "color", color, duration * 0.5)
		tween.tween_property(body, "color", original, duration * 0.5)
