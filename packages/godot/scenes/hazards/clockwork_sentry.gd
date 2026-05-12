extends Area2D
## Clockwork Sentry — Rotating turret hazard.
##
## Continuously rotates clockwise. Fires a line-projectile every full rotation.
## Only vulnerable from behind (120° arc opposite facing direction).
## 8HP, projectile deals 1 damage.

@export var rotate_speed: float = 60.0  # degrees per second (~6s full rotation)
@export var fire_interval: float = 6.0  # fires once per full rotation
@export var max_hp: int = 8
@export var projectile_length: float = 200.0
@export var projectile_speed: float = 0.0  # instant line (appears/disappears)
@export var projectile_duration: float = 1.2
@export var projectile_damage: float = 1.0
@export var vulnerable_arc: float = 120.0  # degrees behind where damage works

var _hp: int
var _is_dead: bool = false
var _rotation_deg: float = 0.0
var _fire_timer: float = 0.0

## Visual nodes
var _body: ColorRect
var _arm: Polygon2D          # gun arm pointing in facing direction
var _arm_glow: ColorRect     # small glow at arm tip

## Projectile
var _projectile: ColorRect = null

## Hitbox
var _hitbox_area: Area2D


func _ready() -> void:
	_hp = max_hp
	add_to_group("hazards")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	
	_build_visuals()
	_build_hitbox()
	
	_fire_timer = fire_interval * 0.5  # stagger first fire so not all synced
	print("[SENTRY] Ready")


func _build_visuals() -> void:
	## Body — central orb
	_body = ColorRect.new()
	_body.size = Vector2(40, 40)
	_body.position = Vector2(-20, -20)
	_body.color = Color(0.08, 0.04, 0.12, 1.0)
	_body.z_index = 1
	add_child(_body)
	
	## Inner glow circle
	var inner := ColorRect.new()
	inner.size = Vector2(20, 20)
	inner.position = Vector2(-10, -10)
	inner.color = Color(0.15, 0.05, 0.2, 0.6)
	inner.z_index = 2
	_body.add_child(inner)
	
	## Arm — extends in facing direction
	_arm = Polygon2D.new()
	_arm.color = Color(0.06, 0.03, 0.08, 1.0)
	_arm.z_index = 2
	add_child(_arm)
	
	## Arm tip glow
	_arm_glow = ColorRect.new()
	_arm_glow.size = Vector2(14, 14)
	_arm_glow.position = Vector2(-7, -7)
	_arm_glow.color = Color(0.3, 0.08, 0.4, 0.5)
	_arm_glow.z_index = 3
	add_child(_arm_glow)
	
	_update_arm_visual()
	
	## Projectile (line) — hidden until fired
	_projectile = ColorRect.new()
	_projectile.size = Vector2(projectile_length, 8)
	_projectile.position = Vector2(20, -4)
	_projectile.color = Color(0.02, 0.01, 0.04, 0.0)
	_projectile.z_index = 2
	add_child(_projectile)


func _build_hitbox() -> void:
	_hitbox_area = Area2D.new()
	_hitbox_area.position = Vector2(0, 0)
	
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(50, 50)
	shape.shape = rect
	_hitbox_area.add_child(shape)
	
	_hitbox_area.area_entered.connect(_on_hitbox_area_entered)
	add_child(_hitbox_area)


func _process(delta: float) -> void:
	if _is_dead:
		return
	
	_rotation_deg += rotate_speed * delta
	if _rotation_deg >= 360.0:
		_rotation_deg -= 360.0
	
	_update_arm_visual()
	
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_fire()


func _update_arm_visual() -> void:
	var rad := deg_to_rad(_rotation_deg)
	
	# Arm polygon pointing in facing direction
	var arm_len: float = 50.0
	_arm.polygon = PackedVector2Array([
		Vector2(6, -4),
		Vector2(arm_len, -2),
		Vector2(arm_len, 2),
		Vector2(6, 4),
	])
	# Rotate arm
	var rot_mat := Transform2D().rotated(rad)
	for i in _arm.polygon.size():
		_arm.polygon[i] = rot_mat * _arm.polygon[i]
	
	# Arm tip glow follows
	var tip_pos := Vector2(cos(rad), sin(rad)) * arm_len
	_arm_glow.position = tip_pos - Vector2(7, 7)


func _fire() -> void:
	if not _projectile:
		return
	
	var rad := deg_to_rad(_rotation_deg)
	var dir := Vector2(cos(rad), sin(rad))
	
	# Position projectile at arm tip
	_projectile.position = dir * 55.0 - Vector2(0, 4)
	_projectile.size = Vector2(projectile_length, 8)
	_projectile.rotation = rad
	_projectile.color.a = 0.7
	
	print("[SENTRY] Fired at %.0f°" % _rotation_deg)
	
	# Create a sensor at the projectile
	# Since it's a line, make a thin CollisionShape2D
	var proj_area := Area2D.new()
	proj_area.position = dir * (55.0 + projectile_length / 2.0) - Vector2(0, 4)
	
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(projectile_length, 8)
	shape.shape = rect
	proj_area.add_child(shape)
	
	proj_area.rotation = rad
	
	proj_area.body_entered.connect(func(body: Node) -> void:
		if body.is_in_group("guardian") and body.has_method("take_hit"):
			body.take_hit(projectile_damage, global_position)
		if is_instance_valid(proj_area):
			proj_area.queue_free()
	)
	
	add_child(proj_area)
	
	# Fade projectile after duration
	var tween := create_tween()
	tween.tween_property(_projectile, "color:a", 0.0, projectile_duration)
	tween.tween_callback(func():
		_projectile.color.a = 0.0
		if is_instance_valid(proj_area):
			proj_area.queue_free()
	)


func _on_hitbox_area_entered(area: Area2D) -> void:
	if _is_dead:
		return
	var parent := area.get_parent()
	if not parent or not parent.is_in_group("guardian"):
		return
	
	# Check if attack is from behind (vulnerable arc)
	var attacker_dir: Vector2 = (global_position - parent.global_position).normalized()
	var sentry_facing := Vector2(cos(deg_to_rad(_rotation_deg)), sin(deg_to_rad(_rotation_deg)))
	
	# Behind = opposite of facing (with 120° arc)
	var behind_dir := -sentry_facing
	var dot := attacker_dir.dot(behind_dir)
	var cos_half := cos(deg_to_rad(vulnerable_arc * 0.5))
	
	if dot < cos_half:
		# Hit the front — no damage
		_front_clink()
		return
	
	_hp -= 1
	_hit_flash()
	
	if _hp <= 0:
		_destroy()


func _hit_flash() -> void:
	_body.color = Color(0.4, 0.4, 0.4, 1.0)
	var tween := create_tween()
	tween.tween_interval(0.08)
	tween.tween_callback(func():
		if is_instance_valid(self):
			_body.color = Color(0.08, 0.04, 0.12, 1.0)
	)


func _front_clink() -> void:
	# Visual feedback for hitting the front — brief white flash on arm
	_arm.color = Color(0.5, 0.5, 0.5, 1.0)
	var tween := create_tween()
	tween.tween_interval(0.06)
	tween.tween_callback(func():
		if is_instance_valid(self):
			_arm.color = Color(0.06, 0.03, 0.08, 1.0)
	)
	print("[SENTRY] Blocked — hit front")


func _destroy() -> void:
	_is_dead = true
	_hitbox_area.monitoring = false
	
	var tween := create_tween()
	tween.tween_property(_body, "modulate:a", 0.0, 0.3)
	tween.tween_property(_arm, "modulate:a", 0.0, 0.3)
	tween.tween_property(_arm_glow, "color:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
	
	print("[SENTRY] Destroyed")
