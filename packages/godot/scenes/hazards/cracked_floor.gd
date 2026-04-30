class_name CrackedFloor
extends Area2D
## Cracked Floor — Step-count hazard.
##
## Breaks after N guardian steps on it. On break: guardian drops briefly
## (teleported up, falls back) + chip damage. Then the tile is safe.
##
## Telegraphs: darkens slightly each step. Cracks show on the surface.
## After the final step, the floor visibly cracks then shatters.

signal floor_broken()

@export var steps_to_break: int = 3
@export var tile_width: float = 128.0
@export var tile_height: float = 128.0
@export var break_damage: float = 0.5
@export var drop_height: float = 100.0         # How far guardian "falls" (brief teleport)
@export var drop_duration: float = 0.15

var _steps_remaining: int
var _is_broken: bool = false
var _guardian_on_tile: bool = false
var _guardian_last_pos: Vector2 = Vector2.ZERO
var _step_debounce: float = 0.0

## Visual
var _tile_bg: ColorRect          # Base tile
var _crack_overlay: Polygon2D    # Crack lines overlay
var _glow: ColorRect             # Damage warning glow


func _ready() -> void:
	_steps_remaining = steps_to_break
	add_to_group("hazards")
	
	collision_layer = 0
	collision_mask = 0
	monitoring = true
	monitorable = false
	
	_build_visuals()
	
	body_entered.connect(_on_guardian_entered)
	body_exited.connect(_on_guardian_exited)


func _build_visuals() -> void:
	## Base tile — matches floor tile colour
	_tile_bg = ColorRect.new()
	_tile_bg.size = Vector2(tile_width, tile_height)
	_tile_bg.position = Vector2(-tile_width / 2, -tile_height / 2)
	_tile_bg.color = Color(0.28, 0.26, 0.38, 1.0)  # match Floor colour
	_tile_bg.z_index = -1  # Below everything except floor
	add_child(_tile_bg)
	
	## Subtle darkening overlay — intensifies with each step
	_glow = ColorRect.new()
	_glow.size = Vector2(tile_width, tile_height)
	_glow.position = Vector2(-tile_width / 2, -tile_height / 2)
	_glow.color = Color(0.05, 0.02, 0.1, 0.0)
	_glow.z_index = 0
	add_child(_glow)
	
	## Crack overlay — grows as steps are used
	_crack_overlay = Polygon2D.new()
	_crack_overlay.color = Color(0.04, 0.02, 0.06, 0.0)
	_crack_overlay.z_index = 1
	_crack_overlay.polygon = _build_crack_polygon(0.0)
	add_child(_crack_overlay)
	
	## Collision shape — invisible sensor
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(tile_width * 0.9, tile_height * 0.9)
	shape.shape = rect
	add_child(shape)


func _build_crack_polygon(intensity: float) -> PackedVector2Array:
	"""Generate a crack pattern that scales with intensity."""
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 1000 + global_position.y) % 65536  # Deterministic per position
	
	var half_w := tile_width * 0.4
	var half_h := tile_height * 0.4
	var center := Vector2.ZERO
	var points: PackedVector2Array = []
	
	# Generate 2-3 crack veins from center
	var num_veins: int = rng.randi_range(2, 3)
	for _v in range(num_veins):
		var x: float = center.x
		var y: float = center.y
		var angle: float = rng.randf() * TAU
		var len_steps: int = int(lerp(3, 10, intensity))
		points.append(Vector2(x, y))
		
		for _s in range(len_steps):
			angle += rng.randf_range(-0.4, 0.4)
			x += cos(angle) * lerp(4.0, 12.0, intensity)
			y += sin(angle) * lerp(4.0, 12.0, intensity)
			# Clamp to tile
			x = clampf(x, -half_w, half_w)
			y = clampf(y, -half_h, half_h)
			points.append(Vector2(x, y))
	
	return points


# =============================================================================
# Step Detection
# =============================================================================

func _on_guardian_entered(body: Node) -> void:
	if _is_broken:
		return
	if body.is_in_group("guardian"):
		_guardian_on_tile = true
		_guardian_last_pos = body.global_position
		_step_debounce = 0.0


func _on_guardian_exited(body: Node) -> void:
	if body.is_in_group("guardian"):
		_guardian_on_tile = false
		_step_debounce = 0.0


func _process(delta: float) -> void:
	if _is_broken or not _guardian_on_tile:
		return
	
	_step_debounce -= delta
	if _step_debounce > 0.0:
		return
	
	var guardian := get_tree().get_first_node_in_group("guardian") as Node2D
	if not guardian:
		return
	
	var moved := guardian.global_position.distance_squared_to(_guardian_last_pos) > 6400.0  # ~80px threshold
	if not moved:
		return
	
	_guardian_last_pos = guardian.global_position
	_step_debounce = 0.15  # Don't count steps faster than this (dodge rolls, knockback)
	
	_steps_remaining -= 1
	_update_step_visuals()
	print("[CRACKED] Step! %d remaining" % _steps_remaining)
	
	if _steps_remaining <= 0:
		_break()


# =============================================================================
# Telegraph & Break
# =============================================================================

func _update_step_visuals() -> void:
	var progress: float = 1.0 - (float(_steps_remaining) / float(steps_to_break))
	
	# Tile darkens
	_glow.color.a = progress * 0.35
	
	# Crack overlay becomes visible and more detailed
	_crack_overlay.color.a = progress * 0.55
	_crack_overlay.polygon = _build_crack_polygon(progress)


func _break() -> void:
	_is_broken = true
	print("[CRACKED] Floor breaks!")
	
	# Visual shatter
	var tween := create_tween()
	tween.tween_property(_tile_bg, "color:a", 0.0, 0.2)
	tween.tween_property(_glow, "color:a", 0.0, 0.1)
	tween.tween_property(_crack_overlay, "color:a", 0.0, 0.1)
	
	# Damage guardian if standing on it
	var guardian := get_tree().get_first_node_in_group("guardian") as Node2D
	if guardian and _guardian_on_tile:
		# Brief drop effect — teleport guardian down then back up
		if guardian.has_method("take_damage"):
			guardian.take_damage(break_damage, "cracked_floor")
		
		# Visual: drop the guardian briefly
		var final_guardian := guardian
		if is_instance_valid(final_guardian):
			var og_y: float = final_guardian.global_position.y
			var t := final_guardian.create_tween()
			t.tween_property(final_guardian, "global_position:y", og_y + drop_height, drop_duration * 0.5)
			t.tween_property(final_guardian, "global_position:y", og_y, drop_duration * 0.5)
		
		CameraShaker.shake(8.0, 0.2)
		HitstopManager.hit()
	
	# Breaks the collision — tile is now safe
	monitoring = false
	
	floor_broken.emit()
	
	# Clean up after shatter plays
	get_tree().create_timer(0.5).timeout.connect(func():
		if is_instance_valid(self):
			_guardian_on_tile = false
			queue_free()
	)
