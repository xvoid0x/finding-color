extends Area2D
## Wailing Statue — Directed scream-wave hazard.
##
## Faces one direction (N/S/E/W based on spawn edge) and periodically emits
## a scream wave in a cone. Deals 1 damage + knockback within 500px and 90° cone.
## Has 5HP, can be destroyed by attacking from any direction.
## For prototype: cone check only (no raycast LOS).

enum StatueDir { UP, DOWN, LEFT, RIGHT }

@export var scream_interval: float = 3.5
@export var telegraph_duration: float = 0.8
@export var scream_duration: float = 0.3
@export var recover_duration: float = 1.0
@export var max_hp: int = 5
@export var scream_range: float = 500.0
@export var scream_angle: float = 90.0  # cone in degrees
@export var scream_damage: float = 1.0

var _state: int = 0  # 0=idle, 1=telegraph, 2=scream, 3=recover
var _state_timer: float = 0.0
var _hp: int
var _is_dead: bool = false
var _facing_dir: StatueDir
var _facing_angle: float = 0.0

## Visual nodes
var _body: ColorRect
var _face: ColorRect
var _telegraph_glow: ColorRect
var _scream_fan: Polygon2D

## Collision for damage
var _hitbox_area: Area2D


func _ready() -> void:
	_hp = max_hp
	add_to_group("hazards")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	
	# Pick facing, build visuals with that info
	_determine_facing()
	_build_visuals()
	_build_hitbox()
	
	_state_timer = scream_interval
	print("[STATUE] Facing: %s at %v" % [_facing_dir, global_position])


func _determine_facing() -> void:
	var mx: float = 960.0
	var my: float = 540.0
	var dx: float = global_position.x - mx
	var dy: float = global_position.y - my
	
	if abs(dx) > abs(dy):
		_facing_dir = StatueDir.LEFT if dx > 0 else StatueDir.RIGHT
	else:
		_facing_dir = StatueDir.UP if dy > 0 else StatueDir.DOWN
	
	match _facing_dir:
		StatueDir.UP:    _facing_angle = -PI / 2
		StatueDir.DOWN:  _facing_angle = PI / 2
		StatueDir.LEFT:  _facing_angle = PI
		StatueDir.RIGHT: _facing_angle = 0.0


func _face_offset() -> Vector2:
	match _facing_dir:
		StatueDir.UP:    return Vector2(0, -22)
		StatueDir.DOWN:  return Vector2(0, 22)
		StatueDir.LEFT:  return Vector2(-22, 0)
		StatueDir.RIGHT: return Vector2(22, 0)
	return Vector2.ZERO


func _build_visuals() -> void:
	## Body
	_body = ColorRect.new()
	_body.size = Vector2(40, 50)
	_body.position = Vector2(-20, -25)
	_body.color = Color(0.1, 0.05, 0.12, 0.9)
	_body.z_index = 0
	add_child(_body)
	
	## Face (the direction the scream fires)
	var foff := _face_offset()
	_face = ColorRect.new()
	_face.size = Vector2(12, 8)
	_face.position = foff - Vector2(6, 4)
	_face.color = Color(0.03, 0.01, 0.04, 1.0)
	_face.z_index = 1
	add_child(_face)
	
	## Telegraph glow
	_telegraph_glow = ColorRect.new()
	_telegraph_glow.size = Vector2(50, 60)
	_telegraph_glow.position = Vector2(-25, -30)
	_telegraph_glow.color = Color(0.25, 0.05, 0.3, 0.0)
	_telegraph_glow.z_index = 2
	add_child(_telegraph_glow)
	
	## Scream fan visual (hidden until scream)
	_scream_fan = Polygon2D.new()
	_scream_fan.color = Color(0.08, 0.02, 0.12, 0.0)
	_scream_fan.z_index = 2
	add_child(_scream_fan)


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
	_state_timer -= delta
	if _state_timer <= 0.0:
		_advance_state()


func _advance_state() -> void:
	match _state:
		0:  # IDLE
			_state = 1
			_state_timer = telegraph_duration
			_on_telegraph()
		1:  # TELEGRAPH
			_state = 2
			_state_timer = scream_duration
			_on_scream()
		2:  # SCREAM
			_state = 3
			_state_timer = recover_duration
			_on_recover()
		3:  # RECOVER
			_state = 0
			_state_timer = scream_interval


func _on_telegraph() -> void:
	var tween := create_tween()
	tween.tween_property(_telegraph_glow, "color:a", 0.4, telegraph_duration * 0.5)
	tween.tween_property(_telegraph_glow, "color:a", 0.0, telegraph_duration * 0.5)
	print("[STATUE] Telegraph")


func _on_scream() -> void:
	# Build cone visual
	_scream_fan.polygon = _build_cone_polygon(_facing_angle, scream_angle, scream_range)
	_scream_fan.color.a = 0.0  # start invisible
	
	var tween := create_tween()
	tween.tween_property(_scream_fan, "color:a", 0.4, 0.1)
	tween.tween_property(_scream_fan, "color:a", 0.0, 0.2)
	
	# Check guardian in cone
	var guardian := get_tree().get_first_node_in_group("guardian") as Node2D
	if not guardian:
		return
	
	if _is_in_cone(guardian.global_position):
		print("[STATUE] Scream hits guardian!")
		if guardian.has_method("take_hit"):
			guardian.take_hit(scream_damage, global_position)
		CameraShaker.shake(12.0, 0.25)
		HitstopManager.hit()
	else:
		print("[STATUE] Guardian outside cone")
	
	print("[STATUE] Scream!")


func _build_cone_polygon(angle: float, cone_deg: float, range_r: float) -> PackedVector2Array:
	var half_cone := deg_to_rad(cone_deg * 0.5)
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	var steps := 8
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := angle - half_cone + t * half_cone * 2.0
		points.append(Vector2(cos(a), sin(a)) * range_r)
	return points


func _on_recover() -> void:
	_scream_fan.color.a = 0.0


func _is_in_cone(target_pos: Vector2) -> bool:
	var to_target: Vector2 = target_pos - global_position
	var dist: float = to_target.length()
	if dist > scream_range:
		return false
	
	var half_angle := deg_to_rad(scream_angle * 0.5)
	var dir := to_target.normalized()
	var facing := Vector2(cos(_facing_angle), sin(_facing_angle))
	
	var dot := dir.dot(facing)
	var cos_half := cos(half_angle)
	
	return dot >= cos_half


func _on_hitbox_area_entered(area: Area2D) -> void:
	if _is_dead:
		return
	var parent := area.get_parent()
	if not parent or not parent.is_in_group("guardian"):
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
			_body.color = Color(0.1, 0.05, 0.12, 0.9)
	)


func _destroy() -> void:
	_is_dead = true
	_hitbox_area.monitoring = false
	
	var tween := create_tween()
	tween.tween_property(_body, "modulate:a", 0.0, 0.3)
	tween.tween_property(_face, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
	
	print("[STATUE] Destroyed")
