extends Node2D
class_name FloorHub
## FloorHub — One persistent scene containing an entire floor.
##
## Responsible for:
##   • Reading the floor map and converting grid positions to world positions
##   • Spawning RoomBase instances (visuals + content per room)
##   • Building all walls globally (outer perimeter + internal blocked passages)
##   • Spawning shared entities (guardian, companion, camera, HUD)
##   • Tracking which room the player is in and activating rooms on first entry

const ROOM_W: float = 1920.0
const ROOM_H: float = 1080.0
const WALL_THICK: float = 160.0

var _rooms: Dictionary = {}  ## room_id -> RoomBase
var _active_room_id: int = -1
var _guardian: CharacterBody2D
var _companion: Node2D
var _camera: Camera2D


func _ready() -> void:
	add_to_group("floor_hub")
	if FloorManager.current_map.is_empty():
		FloorManager.generate_floor(GameManager.current_floor)
	_build_rooms()
	_build_global_walls()
	_spawn_shared_entities()
	_setup_post_process()
	_activate_start_room()


# =============================================================================
# Room Spawning
# =============================================================================

func _build_rooms() -> void:
	var map: Dictionary = FloorManager.current_map
	for rid in map.room_types:
		var room := _create_room(rid)
		var grid_pos: Vector2i = map.grid_pos.get(rid, Vector2i.ZERO)
		room.position = Vector2(grid_pos.x * ROOM_W, grid_pos.y * ROOM_H)
		room.name = "Room_%d" % rid
		add_child(room)
		_rooms[rid] = room
		print("[FLOOR_HUB] Room %d (%s) at %v" % [rid, map.room_types[rid], room.position])


func _create_room(rid: int) -> RoomBase:
	var scene: PackedScene = load("res://scenes/rooms/room_template.tscn")
	var room: RoomBase = scene.instantiate()
	room.room_id = rid
	room.persistent_mode = true
	room.room_type = FloorManager.get_room_type(rid)
	return room


# =============================================================================
# Global Wall Building (the key fix)
# =============================================================================

func _build_global_walls() -> void:
	"""Build all walls for the entire floor.
	
	For every edge of every room, check if there is a connected room.
	If connected → no wall (opening).
	If not connected → build wall (perimeter or blocked).
	"""
	var walls := Node2D.new()
	walls.name = "Walls"
	add_child(walls)
	
	var map: Dictionary = FloorManager.current_map

	
	for rid in map.grid_pos:
		var grid_pos: Vector2i = map.grid_pos[rid]
		var world_x: float = grid_pos.x * ROOM_W
		var world_y: float = grid_pos.y * ROOM_H
		
		## Check each of 4 directions
		var has_up := _has_connection(rid, "up")
		var has_down := _has_connection(rid, "down")
		var has_left := _has_connection(rid, "left")
		var has_right := _has_connection(rid, "right")
		
		## Build walls for edges WITHOUT connections
		if not has_up:
			_add_wall(walls, rid, "up", world_x, world_y, WALL_THICK)
		if not has_down:
			_add_wall(walls, rid, "down", world_x, world_y, WALL_THICK)
		if not has_left:
			_add_wall(walls, rid, "left", world_x, world_y, WALL_THICK)
		if not has_right:
			_add_wall(walls, rid, "right", world_x, world_y, WALL_THICK)


func _has_connection(rid: int, direction: String) -> bool:
	var map: Dictionary = FloorManager.current_map
	var grid_pos: Vector2i = map.grid_pos.get(rid, Vector2i.ZERO)
	var neighbor_grid: Vector2i
	match direction:
		"up":    neighbor_grid = grid_pos + Vector2i.UP
		"down":  neighbor_grid = grid_pos + Vector2i.DOWN
		"left":  neighbor_grid = grid_pos + Vector2i.LEFT
		"right": neighbor_grid = grid_pos + Vector2i.RIGHT
	## Check if any room exists at that grid position
	for other_id in map.grid_pos:
		if map.grid_pos[other_id] == neighbor_grid:
			## Is there a bidirectional connection?
			var conns: Array = map.connections.get(rid, [])
			if other_id in conns:
				return true
	return false


func _add_wall(walls: Node2D, _rid: int, direction: String, wx: float, wy: float, thickness: float) -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	
	match direction:
		"up":
			rect.size = Vector2(ROOM_W, thickness)
			body.position = Vector2(wx + ROOM_W / 2, wy + thickness / 2)
		"down":
			rect.size = Vector2(ROOM_W, thickness)
			body.position = Vector2(wx + ROOM_W / 2, wy + ROOM_H - thickness / 2)
		"left":
			rect.size = Vector2(thickness, ROOM_H)
			body.position = Vector2(wx + thickness / 2, wy + ROOM_H / 2)
		"right":
			rect.size = Vector2(thickness, ROOM_H)
			body.position = Vector2(wx + ROOM_W - thickness / 2, wy + ROOM_H / 2)
	
	shape.shape = rect
	body.add_child(shape)
	walls.add_child(body)


# =============================================================================
# Shared Entities
# =============================================================================

func _spawn_shared_entities() -> void:
	## Global ambient light for the whole floor
	var ambient := CanvasModulate.new()
	ambient.color = Color(0.15, 0.14, 0.20, 1)
	add_child(ambient)
	
	## Guardian
	var g_scene: PackedScene = load("res://characters/guardian/guardian.tscn")
	_guardian = g_scene.instantiate()
	_guardian.add_to_group("guardian")
	add_child(_guardian)
	
	## Companion
	var c_scene: PackedScene = load("res://characters/companion/companion.tscn")
	_companion = c_scene.instantiate()
	_companion.add_to_group("companion")
	add_child(_companion)
	if _companion.has_method("initialize"):
		_companion.initialize(_guardian)
	
	## Camera
	_camera = Camera2D.new()
	_camera.enabled = true
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	add_child(_camera)
	CameraShaker.register_camera(_camera)
	
	## Pause menu
	var p_scene: PackedScene = load("res://scenes/ui/pause_menu.tscn")
	add_child(p_scene.instantiate())
	
	## HUD
	if ResourceLoader.exists("res://scenes/ui/hud.tscn"):
		var h_scene: PackedScene = load("res://scenes/ui/hud.tscn")
		add_child(h_scene.instantiate())


func _setup_post_process() -> void:
	var post := CanvasLayer.new()
	post.layer = 10
	post.name = "PostProcessLayer"
	var rect := ColorRect.new()
	rect.anchors_preset = Control.PRESET_FULL_RECT
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/world_desaturate.gdshader")
	rect.material = mat
	post.add_child(rect)
	add_child(post)


# =============================================================================
# Room Activation
# =============================================================================

func _activate_start_room() -> void:
	var start_id: int = FloorManager.current_map.get("start_room", 0)
	_active_room_id = start_id
	FloorManager.enter_room(start_id)
	_rooms[start_id].activate()
	_position_player_in_room(start_id, Vector2(960, 700))


func _position_player_in_room(room_id: int, local_pos: Vector2) -> void:
	var room: RoomBase = _rooms[room_id]
	var world_pos: Vector2 = room.global_position + local_pos
	_guardian.global_position = world_pos
	_companion.global_position = world_pos + Vector2(-50, 30)


func _process(_delta: float) -> void:
	## Camera follows guardian
	if _camera and _guardian:
		_camera.global_position = _guardian.global_position
	
	## Detect room entry
	var new_id := _get_room_at_position(_guardian.global_position)
	if new_id != _active_room_id and new_id >= 0:
		_on_player_entered_room(new_id)


func _get_room_at_position(pos: Vector2) -> int:
	## Brute force AABB check — usually 4-6 rooms, fast enough
	for rid in _rooms:
		var room: RoomBase = _rooms[rid]
		var local: Vector2 = pos - room.global_position
		if local.x >= 0 and local.x <= ROOM_W and local.y >= 0 and local.y <= ROOM_H:
			return rid
	return -1


func _on_player_entered_room(new_id: int) -> void:
	_active_room_id = new_id
	FloorManager.enter_room(new_id)
	if not _rooms[new_id]._activated:
		_rooms[new_id].activate()
	print("[FLOOR_HUB] Entered room %d" % new_id)
