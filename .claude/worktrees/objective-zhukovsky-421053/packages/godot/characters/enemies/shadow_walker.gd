extends EnemyBase
## ShadowWalker - Basic enemy type 1.
## Moves directly toward the guardian. Simple and readable.

var _guardian: Node2D = null


func _on_ready() -> void:
	# Find guardian in scene
	await get_tree().process_frame
	_guardian = get_tree().get_first_node_in_group("guardian")

	# Connect contact damage
	var area := get_node_or_null("ContactArea")
	if area:
		area.body_entered.connect(_on_body_entered_base)
		# Expand contact shape so it overlaps guardian even when bodies are just touching
		var contact_shape := area.get_node_or_null("ContactShape") as CollisionShape2D
		if contact_shape:
			var shape := CircleShape2D.new()
			shape.radius = 22.0
			contact_shape.shape = shape


func _on_physics_process(_delta: float) -> void:
	if not _guardian:
		_guardian = get_tree().get_first_node_in_group("guardian")
		return

	# Move toward guardian
	var dir: Vector2 = (_guardian.global_position - global_position).normalized()
	velocity = dir * move_speed
	move_and_slide()
