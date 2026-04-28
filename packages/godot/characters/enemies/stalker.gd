extends EnemyBase
## Stalker - Ignores the guardian entirely. Walks directly toward the companion.
##
## Lock-on telegraph: brief 0.4s glow on spawn before moving. Gives the guardian
## time to notice and react before the threat advances.
##
## Cannot be kited — must be intercepted. Forces the guardian to leave the
## perimeter briefly to deal with it, creating a meaningful positioning decision:
##   "Do I chase the stalker and leave the companion exposed, or let it get closer?"

var _lock_on_timer: float = 0.0
const LOCK_ON_DURATION: float = 0.4
var _locked_on: bool = false

@onready var _body_rect: ColorRect = $Sprite2D/Body


func _on_ready() -> void:
	max_hp = 2.0
	hp = 2.0
	move_speed = 70.0
	damage_on_contact = 0.75
	contact_cooldown = 1.0
	target_priority = TargetPriority.COMPANION  # always — never switches

	await get_tree().process_frame

	var area := get_node_or_null("ContactArea")
	if area:
		area.body_entered.connect(_on_contact_body_entered)
		var contact_shape := area.get_node_or_null("ContactShape") as CollisionShape2D
		if contact_shape:
			var shape := CircleShape2D.new()
			shape.radius = 22.0
			contact_shape.shape = shape

	# Lock-on telegraph: bright glow, then begin moving
	_lock_on_timer = LOCK_ON_DURATION
	if _light:
		_light.energy = 2.5
	if _body_rect:
		_body_rect.color = Color(0.4, 0.3, 1.0, 1.0)


func _on_process(delta: float) -> void:
	if not _locked_on:
		_lock_on_timer -= delta
		if _lock_on_timer <= 0.0:
			_locked_on = true
			# Reset visuals to normal
			if _light:
				var tween := create_tween()
				tween.tween_property(_light, "energy", 0.7, 0.3)
			if _body_rect:
				var tween := create_tween()
				tween.tween_property(_body_rect, "color", Color(0.15, 0.1, 0.6, 1.0), 0.3)


func _on_physics_process(_delta: float) -> void:
	if not _locked_on:
		# Brief pause — barely drift
		velocity = velocity.move_toward(Vector2.ZERO, 600.0 * _delta)
		move_and_slide()
		return

	var target := get_chase_target()  # Always returns companion
	if not target:
		# Companion not present (solo mode) — fall back to guardian
		var guardian := get_tree().get_first_node_in_group("guardian") as Node2D
		if guardian:
			velocity = (guardian.global_position - global_position).normalized() * move_speed
			move_and_slide()
		return

	var dir: Vector2 = (target.global_position - global_position).normalized()
	velocity = dir * move_speed
	move_and_slide()


func _on_contact_body_entered(body: Node) -> void:
	## Stalker damages both companion and guardian on contact.
	## Companion damage is handled via take_hit on companion node.
	if _is_dead or _contact_timer > 0.0:
		return

	if body.is_in_group("companion") and body.has_method("take_hit"):
		body.take_hit()
		_contact_timer = contact_cooldown
		return

	if body.is_in_group("guardian"):
		if body.has_method("take_hit"):
			body.take_hit(damage_on_contact, global_position)
		elif body.has_method("take_damage"):
			body.take_damage(damage_on_contact)
		_contact_timer = contact_cooldown
