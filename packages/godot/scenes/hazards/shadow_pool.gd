class_name ShadowPool
extends Area2D
## Shadow Pool — Area hazard that slows and chips damage.
##
## Dark puddle on the floor. Guardian inside takes slow + damage over time.
## Companion takes damage too if anchored.
## Not destructible — navigated around or dodged through.
##
## Visual: dark rippling puddle with faint amber flickers underneath.

signal body_entered_pool(body: Node)
signal body_exited_pool(body: Node)

@export var pool_radius: float = 80.0
@export var slow_multiplier: float = 0.45       # Guardian moves at 45% speed inside
@export var damage_per_second: float = 0.5
@export var damage_interval: float = 1.0          # Ticks once per second
@export var ripple_speed: float = 1.0
@export var base_alpha: float = 0.6

var _damage_timer: float = 0.0
var _guardian_inside: Node2D = null
var _original_speed: float = 0.0
var _ripple_time: float = 0.0

## Visual nodes
var _pool_sprite: Polygon2D
var _glow_sprite: Polygon2D
var _inner_ring: Polygon2D


func _ready() -> void:
	add_to_group("hazards")
	collision_layer = 0
	collision_mask = 0  # No auto-collision — we use body_entered/exited manually
	monitoring = true
	monitorable = false
	
	_build_visuals()
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _build_visuals() -> void:
	## Main pool shape — dark oval
	_pool_sprite = Polygon2D.new()
	_pool_sprite.polygon = _oval_polygon(pool_radius, pool_radius * 0.65, 24)
	_pool_sprite.color = Color(0.06, 0.03, 0.09, base_alpha)
	_pool_sprite.z_index = 0
	add_child(_pool_sprite)
	
	## Inner glow — hint of warmth underneath (the child's colour bleeding through?)
	_glow_sprite = Polygon2D.new()
	_glow_sprite.polygon = _oval_polygon(pool_radius * 0.5, pool_radius * 0.35, 16)
	_glow_sprite.color = Color(0.25, 0.12, 0.08, 0.15)
	_glow_sprite.z_index = 1
	add_child(_glow_sprite)
	
	## Ripple ring — subtle animated ring
	_inner_ring = Polygon2D.new()
	_inner_ring.polygon = _oval_polygon(pool_radius * 0.7, pool_radius * 0.5, 16)
	_inner_ring.color = Color(0.1, 0.04, 0.15, 0.0)
	_inner_ring.z_index = 0
	add_child(_inner_ring)
	
	## Collision shape
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = pool_radius
	shape.shape = circle
	add_child(shape)


func _oval_polygon(rx: float, ry: float, points: int) -> PackedVector2Array:
	var verts := PackedVector2Array()
	for i in range(points):
		var a := TAU * i / points
		verts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return verts


func _process(delta: float) -> void:
	_ripple_time += delta * ripple_speed
	
	# Animate ripple ring
	var ring_alpha: float = abs(sin(_ripple_time)) * 0.15
	_inner_ring.color.a = ring_alpha
	
	# Subtle pool shimmer
	var shimmer: float = sin(_ripple_time * 0.7) * 0.08 + base_alpha
	_pool_sprite.color.a = shimmer
	
	# Damage tick
	if _guardian_inside:
		_damage_timer -= delta
		if _damage_timer <= 0.0:
			_damage_timer = damage_interval
			_apply_damage_tick()


# =============================================================================
# Slow
# =============================================================================

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("guardian"):
		_guardian_inside = body
		_original_speed = body.move_speed
		body.move_speed = body.move_speed * slow_multiplier
		_damage_timer = damage_interval
		body_entered_pool.emit(body)
		print("[POOL] Guardian entered at %v — speed: %.0f → %.0f" % [global_position, _original_speed, body.move_speed])


func _on_body_exited(body: Node) -> void:
	if body == _guardian_inside:
		body.move_speed = _original_speed
		_guardian_inside = null
		body_exited_pool.emit(body)
		print("[POOL] Guardian exited — speed restored to %.0f" % _original_speed)


# =============================================================================
# Damage
# =============================================================================

func _apply_damage_tick() -> void:
	if not _guardian_inside:
		return
	print("[POOL] Damage tick: %.1f" % damage_per_second)
	
	# Damage the guardian
	if _guardian_inside.has_method("take_damage"):
		_guardian_inside.take_damage(damage_per_second, "shadow_pool")
	
	# Damage companion if anchored inside
	var companion := get_tree().get_first_node_in_group("companion") as Node2D
	if companion:
		var companion_body := companion as Node2D
		if companion_body and companion_body.get("_state") and str(companion_body._state) == "ANCHORED":
			# Check if companion is inside this pool's radius
			var dist := global_position.distance_to(companion_body.global_position)
			if dist <= pool_radius:
				if companion_body.has_method("take_hit"):
					companion_body.take_hit(damage_per_second)
	
	# Visual feedback — pool flashes brighter on damage tick
	var flash_tween := create_tween()
	_pool_sprite.color.a = base_alpha + 0.2
	flash_tween.tween_property(_pool_sprite, "color:a", base_alpha, 0.3)


# =============================================================================
# Cleanup on exit
# =============================================================================

func _exit_tree() -> void:
	"""If the pool is removed (room transition), restore speed to guardian."""
	if _guardian_inside and is_instance_valid(_guardian_inside):
		_guardian_inside.move_speed = _original_speed
