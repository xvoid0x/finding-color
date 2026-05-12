extends Area2D
## Sorrow Drip — Ceiling stalactite hazard.
##
## Drops a shadow projectile straight down every ~3.5s.
## Telegraphed by darkening before each drop.
## Projectile deals 1 damage, disappears on ground hit or guardian contact.

enum DripState { IDLE, TELEGRAPH, ACTIVE, RECOVER }

@export var drop_interval: float = 3.5
@export var telegraph_duration: float = 0.5
@export var drop_speed: float = 600.0
@export var drop_distance: float = 800.0
@export var recover_duration: float = 0.5
@export var projectile_radius: float = 14.0

var _state: DripState = DripState.IDLE
var _state_timer: float = 0.0
var _projectile: Area2D = null
var _is_destroyed: bool = false

## Visual nodes
var _stalactite: Polygon2D
var _telegraph_glow: ColorRect


func _ready() -> void:
	add_to_group("hazards")
	collision_layer = 0
	collision_mask = 0
	_build_visuals()
	
	_state_timer = drop_interval
	_state = DripState.IDLE


func _build_visuals() -> void:
	## Stalactite shape — dark cone pointing downward
	_stalactite = Polygon2D.new()
	_stalactite.polygon = PackedVector2Array([
		Vector2(-8, 0),    # top-left
		Vector2(8, 0),     # top-right
		Vector2(3, 60),    # bottom-right point
		Vector2(-3, 60),   # bottom-left point
	])
	_stalactite.color = Color(0.08, 0.04, 0.1, 0.9)
	_stalactite.z_index = 3
	add_child(_stalactite)
	
	## Telegraph glow — dark spot that grows before drop
	_telegraph_glow = ColorRect.new()
	_telegraph_glow.size = Vector2(30, 60)
	_telegraph_glow.position = Vector2(-15, 0)
	_telegraph_glow.color = Color(0.02, 0.01, 0.04, 0.0)
	_telegraph_glow.z_index = 2
	add_child(_telegraph_glow)


func _process(delta: float) -> void:
	if _is_destroyed:
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_advance_state()


func _advance_state() -> void:
	match _state:
		DripState.IDLE:
			_state = DripState.TELEGRAPH
			_state_timer = telegraph_duration
			_on_telegraph()
		
		DripState.TELEGRAPH:
			_state = DripState.ACTIVE
			_drop_projectile()
		
		DripState.ACTIVE:
			_state = DripState.RECOVER
			_state_timer = recover_duration
		
		DripState.RECOVER:
			_state = DripState.IDLE
			_state_timer = drop_interval


func _on_telegraph() -> void:
	var tween := create_tween()
	tween.tween_property(_telegraph_glow, "color:a", 0.5, telegraph_duration * 0.6)
	tween.tween_property(_telegraph_glow, "color:a", 0.0, telegraph_duration * 0.4)
	print("[DRIP] Telegraph")


func _drop_projectile() -> void:
	_state_timer = drop_distance / drop_speed  # active duration
	
	_projectile = Area2D.new()
	_projectile.position = Vector2(0, 60)
	
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = projectile_radius
	shape.shape = circle
	_projectile.add_child(shape)
	
	## Visual
	var vis := ColorRect.new()
	vis.size = Vector2(projectile_radius * 2, projectile_radius * 2)
	vis.position = Vector2(-projectile_radius, -projectile_radius)
	vis.color = Color(0.03, 0.01, 0.06, 0.85)
	vis.z_index = 4
	_projectile.add_child(vis)
	
	## Glow
	var glow := ColorRect.new()
	glow.size = Vector2(projectile_radius * 3.5, projectile_radius * 3.5)
	glow.position = Vector2(-projectile_radius * 1.75, -projectile_radius * 1.75)
	glow.color = Color(0.15, 0.04, 0.2, 0.3)
	glow.z_index = 4
	_projectile.add_child(glow)
	
	_projectile.body_entered.connect(_on_projectile_hit)
	add_child(_projectile)
	
	print("[DRIP] Drop")


func _on_projectile_hit(body: Node) -> void:
	if not _projectile or not is_instance_valid(_projectile):
		return
	if body.is_in_group("guardian") and body.has_method("take_hit"):
		body.take_hit(1.0, global_position)
	_projectile.queue_free()
	_projectile = null


func _physics_process(delta: float) -> void:
	if _state != DripState.ACTIVE or not _projectile:
		return
	_projectile.position += Vector2(0, drop_speed * delta)
	
	# Remove when below floor level
	if _projectile.position.y > drop_distance:
		_projectile.queue_free()
		_projectile = null
		# Advance state to recover
		_state_timer = recover_duration
		_state = DripState.RECOVER
