extends StaticBody2D
## Push Wall — Arena shrink hazard.
##
## A wall section that slides inward after a delay, shrinking the room.
## Selects a random room edge (north or south) and pushes toward center.
## Companion gets gently displaced (not crushed).

enum WallOrientation { NORTH, SOUTH }

@export var wall_width: float = 160.0
@export var wall_height: float = 200.0
@export var push_distance: float = 160.0
@export var delay_duration: float = 3.0
@export var push_duration: float = 4.0
@export var push_speed: float = 40.0  # push_distance / push_duration approx

var _orientation: WallOrientation
var _start_y: float
var _end_y: float
var _is_pushing: bool = false
var _is_stopped: bool = false
var _direction: int = 0  # -1 (upward) or 1 (downward)

## Visual
var _wall_rect: ColorRect
var _warning_glow: ColorRect


func _ready() -> void:
	add_to_group("hazards")
	
	# Random orientation
	_orientation = WallOrientation.NORTH if randi() % 2 == 0 else WallOrientation.SOUTH
	
	match _orientation:
		WallOrientation.NORTH:
			position = Vector2(960, 180)
			_direction = 1  # push down
			_start_y = 180
			_end_y = 180 + push_distance
		WallOrientation.SOUTH:
			position = Vector2(960, 900)
			_direction = -1  # push up
			_start_y = 900
			_end_y = 900 - push_distance
	
	_build_visuals()
	_build_collision()
	
	# Start delay timer
	var tween := create_tween()
	tween.tween_interval(delay_duration)
	tween.tween_callback(_begin_push)
	
	# Warning flash during delay
	_warning_flash_loop()


func _build_visuals() -> void:
	_wall_rect = ColorRect.new()
	_wall_rect.size = Vector2(wall_width, wall_height)
	_wall_rect.position = Vector2(-wall_width / 2, -wall_height / 2)
	_wall_rect.color = Color(0.08, 0.04, 0.1, 0.9)
	_wall_rect.z_index = 0
	add_child(_wall_rect)
	
	# Darker edge line
	var edge := ColorRect.new()
	edge.size = Vector2(wall_width, 6)
	edge.position = Vector2(-wall_width / 2, -wall_height / 2)
	edge.color = Color(0.02, 0.01, 0.03, 1.0)
	_wall_rect.add_child(edge)
	
	_warning_glow = ColorRect.new()
	_warning_glow.size = Vector2(wall_width + 20, 20)
	_warning_glow.position = Vector2(-(wall_width + 20) / 2, -10)
	_warning_glow.color = Color(0.3, 0.05, 0.4, 0.0)
	_warning_glow.z_index = 1
	add_child(_warning_glow)


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(wall_width, wall_height)
	shape.shape = rect
	add_child(shape)
	
	## Companion displacement sensor
	var push_area := Area2D.new()
	push_area.name = "PushArea"
	
	var push_shape := CollisionShape2D.new()
	var push_rect := RectangleShape2D.new()
	push_rect.size = Vector2(wall_width, wall_height + 40)
	push_shape.shape = push_rect
	push_area.add_child(push_shape)
	
	push_area.body_entered.connect(_on_body_entered)
	add_child(push_area)


func _warning_flash_loop() -> void:
	if _is_pushing:
		return
	var flash := create_tween()
	var glow: float = 0.3
	flash.tween_property(_warning_glow, "color:a", glow, 0.3)
	flash.tween_property(_warning_glow, "color:a", 0.0, 0.3)
	if not _is_pushing:
		get_tree().create_timer(0.6).timeout.connect(_warning_flash_loop, CONNECT_ONE_SHOT)


func _begin_push() -> void:
	_is_pushing = true
	print("[WALL] Pushing %s" % ["south" if _orientation == WallOrientation.NORTH else "north"])


func _physics_process(delta: float) -> void:
	if not _is_pushing or _is_stopped:
		return
	
	var movement: float = push_speed * delta * _direction
	var new_y: float = position.y + movement
	
	# Clamp to end position
	if (_direction > 0 and new_y >= _end_y) or (_direction < 0 and new_y <= _end_y):
		position.y = _end_y
		_is_stopped = true
		_is_pushing = false
		print("[WALL] Stopped")
	else:
		position.y = new_y


func _on_body_entered(body: Node) -> void:
	# Gently displace companion so it doesn't get crushed
	if body.is_in_group("companion"):
		var push_dir := Vector2(0, -_direction)  # opposite direction
		body.global_position += push_dir * 60.0
		print("[WALL] Displaced companion")
