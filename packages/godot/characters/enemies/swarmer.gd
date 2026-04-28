extends EnemyBase
## Swarmer - Fast, low HP. Primary threat archetype.
##
## Normally chases the guardian. Switches to companion when it's anchored.
## Designed to pressure the guardian's perimeter through volume, not tankiness.
## A skilled guardian clears swarmers quickly; a struggling one gets overwhelmed.
##
## Tuning targets:
##   - Dies in 1 hit from guardian attack
##   - Fast enough to demand constant attention
##   - Switch to companion target is immediate when anchor state changes


var _companion: Node2D = null
var _companion_was_anchored: bool = false


func _on_ready() -> void:
	max_hp = 1.0
	hp = 1.0
	move_speed = 160.0
	damage_on_contact = 0.5
	contact_cooldown = 0.6
	target_priority = TargetPriority.GUARDIAN  # switches dynamically

	await get_tree().process_frame
	_companion = get_tree().get_first_node_in_group("companion")

	var area := get_node_or_null("ContactArea")
	if area:
		area.body_entered.connect(_on_body_entered_base)
		var contact_shape := area.get_node_or_null("ContactShape") as CollisionShape2D
		if contact_shape:
			var shape := CircleShape2D.new()
			shape.radius = 18.0
			contact_shape.shape = shape


func _on_process(_delta: float) -> void:
	# Dynamically switch target when companion becomes anchored/free
	if not _companion:
		_companion = get_tree().get_first_node_in_group("companion")
		return

	var is_anchored: bool = _companion.has_method("is_anchored") and _companion.is_anchored()
	if is_anchored != _companion_was_anchored:
		_companion_was_anchored = is_anchored
		var old_priority = target_priority
		target_priority = TargetPriority.COMPANION if is_anchored else TargetPriority.GUARDIAN
		# Flash on aggro switch
		if target_priority != old_priority:
			_flash_aggro_switch(target_priority)


func _flash_aggro_switch(new_priority: TargetPriority) -> void:
	"""Brief bright flash when switching target."""
	var light := $PointLight2D as PointLight2D
	var body := $Sprite2D/Body as ColorRect
	if new_priority == TargetPriority.COMPANION:
		# Flash amber toward companion
		if body:
			var tween := create_tween()
			tween.tween_property(body, "color", Color(1.0, 0.7, 0.2, 1.0), 0.1)
			tween.tween_property(body, "color", Color(0.9, 0.1, 0.3, 1.0), 0.2)
		if light:
			light.energy = 1.5
			var tween2 := create_tween()
			tween2.tween_property(light, "energy", 0.5, 0.3)
	else:
		# Flash back to red toward guardian
		if body:
			var tween := create_tween()
			tween.tween_property(body, "color", Color(1.0, 0.3, 0.5, 1.0), 0.1)
			tween.tween_property(body, "color", Color(0.9, 0.1, 0.3, 1.0), 0.2)
		if light:
			light.energy = 1.0
			var tween2 := create_tween()
			tween2.tween_property(light, "energy", 0.5, 0.25)

func _on_physics_process(_delta: float) -> void:
	var target := get_chase_target()
	if not target:
		return

	var dir: Vector2 = (target.global_position - global_position).normalized()
	velocity = dir * move_speed
	move_and_slide()
