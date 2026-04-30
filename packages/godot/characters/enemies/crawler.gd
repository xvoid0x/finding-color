extends EnemyBase
## Crawler - Slow armoured enemy. Takes reduced damage from the front arc.
##
## Moves slowly toward the guardian. Has an armoured front face: attacks
## from the front deal only 50% damage. Must be flanked for full damage.
## Adds tactical positioning pressure — the player can't just face-tank everything.
##
## Tuning targets:
##   - 2 hits to kill (from front), 1 hit from behind/side
##   - Slow enough to easily circle around
##   - High contact damage to punish standing in front of it

var _guardian: Node2D = null
var _flank_angle: float = deg_to_rad(120.0)  # 120° front arc = armoured


func _on_ready() -> void:
	max_hp = 2.0
	hp = 2.0
	move_speed = 50.0
	damage_on_contact = 1.0
	contact_cooldown = 1.0
	target_priority = TargetPriority.GUARDIAN

	await get_tree().process_frame
	_guardian = get_tree().get_first_node_in_group("guardian")

	var area := get_node_or_null("ContactArea") as Area2D
	if area:
		area.body_entered.connect(_on_body_entered_base)
		var contact_shape := area.get_node_or_null("ContactShape") as CollisionShape2D
		if contact_shape:
			var shape := CircleShape2D.new()
			shape.radius = 18.0
			contact_shape.shape = shape

	# Crawler is bigger — make it visually distinct
	var body := $Sprite2D/Body as ColorRect
	if body:
		body.offset_left = -16.0
		body.offset_top = -16.0
		body.offset_right = 16.0
		body.offset_bottom = 16.0
		body.color = Color(0.3, 0.4, 0.1, 1.0)  # muddy green


func _on_physics_process(delta: float) -> void:
	if not _guardian:
		_guardian = get_tree().get_first_node_in_group("guardian")
		return

	var dir: Vector2 = (_guardian.global_position - global_position).normalized()
	velocity = dir * move_speed
	move_and_slide()


func take_damage(amount: float, knockback_dir: Vector2 = Vector2.ZERO) -> void:
	"""Override to apply frontal armour."""
	if _is_dead:
		return

	# Determine if attack hit from the front
	var from_front: bool = false
	if knockback_dir != Vector2.ZERO:
		# knockback_dir is the direction damage came from (attacker -> enemy)
		# If the attacker is in front of the crawler's facing direction, reduce damage
		var facing_dir: Vector2 = Vector2.RIGHT.rotated(global_rotation)
		var attack_angle: float = knockback_dir.angle_to(facing_dir)
		from_front = absf(attack_angle) < _flank_angle * 0.5

	if from_front:
		amount *= 0.5
		# Visual feedback: brief flash
		_flash_armor_hit()

	# Call base damage
	super.take_damage(amount, knockback_dir)


func _flash_armor_hit() -> void:
	"""Brief visual feedback when armor blocks half damage."""
	var body := $Sprite2D/Body as ColorRect
	if body:
		var tween := create_tween()
		tween.tween_property(body, "color", Color(0.8, 0.8, 0.1, 1.0), 0.1)
		tween.tween_property(body, "color", Color(0.3, 0.4, 0.1, 1.0), 0.2)
