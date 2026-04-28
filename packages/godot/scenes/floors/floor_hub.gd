extends Node2D
class_name FloorHub
## FloorHub - Persistent floor with all rooms loaded simultaneously.
##
## Rooms are placed adjacent to each other with open doorways.
## Player physically walks between rooms through door gaps.
## Only the current room is active (spawns enemies on first entry).
##
## One shared camera follows the guardian across the entire floor.
## One shared HUD, pause menu, and post-process layer.

const ROOM_WIDTH := 1920.0
const ROOM_HEIGHT := 1080.0
const CORRIDOR_SIZE := 120.0
const WORLD_SCALE_X := (ROOM_WIDTH + CORRIDOR_SIZE) / 80.0  ## 25.5
const WORLD_SCALE_Y := (ROOM_HEIGHT + CORRIDOR_SIZE) / 80.0  ## 15.0

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
	_spawn_shared_entities()
	_setup_post_process()
	_activate_start_room()


# =============================================================================
# Room Building
# =============================================================================

func _build_rooms() -> void:
	var map: Dictionary = FloorManager.current_map
	for room_id in map.room_types:
		var room_type: String = map.room_types[room_id]
		var room := _create_room(room_id, room_type)
		var minimap_pos: Vector2 = map.positions.get(room_id, Vector2.ZERO)
		room.position = Vector2(minimap_pos.x * WORLD_SCALE_X, minimap_pos.y * WORLD_SCALE_Y)
		add_child(room)
		_rooms[room_id] = room

		var open_dirs: Array[String] = _get_connection_directions(room_id)
		room.build_walls(open_dirs)

		print("[FLOOR_HUB] Built room %d (%s) at %s | open: %s" % [
			room_id, room_type, room.position, ",".join(open_dirs)
		])


func _get_connection_directions(room_id: int) -> Array[String]:
	var directions: Array[String] = []
	var map := FloorManager.current_map
	var room_pos: Vector2 = map.positions.get(room_id, Vector2.ZERO)
	for other_id in map.connections.get(room_id, []):
		var other_pos: Vector2 = map.positions.get(other_id, Vector2.ZERO)
		var dx := other_pos.x - room_pos.x
		var dy := other_pos.y - room_pos.y
		if abs(dx) > abs(dy):
			directions.append("right" if dx > 0 else "left")
		else:
			directions.append("down" if dy > 0 else "up")
	return directions


func _create_room(room_id: int, room_type: String) -> RoomBase:
	var scene := load("res://scenes/rooms/room_template.tscn")
	var room: RoomBase = scene.instantiate()
	room.room_id = room_id
	room.persistent_mode = true
	match room_type:
		"chest":
			room.has_chest = true
		"shrine":
			room.has_shrine = true
		"exit":
			room.is_exit_room = true
	return room


# =============================================================================
# Shared Entities (spawned once for the whole floor)
# =============================================================================

func _spawn_shared_entities() -> void:
	## Guardian
	var guardian_scene := load("res://characters/guardian/guardian.tscn")
	_guardian = guardian_scene.instantiate()
	_guardian.add_to_group("guardian")
	add_child(_guardian)

	## Companion
	var companion_scene := load("res://characters/companion/companion.tscn")
	_companion = companion_scene.instantiate()
	_companion.add_to_group("companion")
	add_child(_companion)
	if _companion.has_method("initialize"):
		_companion.initialize(_guardian)

	## Camera
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	add_child(_camera)
	CameraShaker.register_camera(_camera)

	## Pause menu
	var pause_scene := load("res://scenes/ui/pause_menu.tscn")
	var pause_menu: Node = pause_scene.instantiate()
	add_child(pause_menu)

	## HUD
	if ResourceLoader.exists("res://scenes/ui/hud.tscn"):
		var hud_scene := load("res://scenes/ui/hud.tscn")
		var hud: Node = hud_scene.instantiate()
		add_child(hud)


func _setup_post_process() -> void:
	## One shared desaturation post-process layer for the entire floor
	var post_layer := CanvasLayer.new()
	post_layer.layer = 10
	post_layer.name = "PostProcessLayer"

	var desat_rect := ColorRect.new()
	desat_rect.anchors_preset = Control.PRESET_FULL_RECT
	desat_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://shaders/world_desaturate.gdshader")
	desat_rect.material = shader_mat

	post_layer.add_child(desat_rect)
	add_child(post_layer)


# =============================================================================
# Room Activation
# =============================================================================

func _activate_start_room() -> void:
	var start_id: int = FloorManager.current_map.start_room
	_active_room_id = start_id
	FloorManager.enter_room(start_id)
	_rooms[start_id].activate()
	_position_player_at_room(start_id)


func _position_player_at_room(room_id: int) -> void:
	var room: RoomBase = _rooms[room_id]
	var spawn_pos: Vector2 = room.global_position + Vector2(960, 700)
	_guardian.global_position = spawn_pos
	_companion.global_position = spawn_pos + Vector2(-50, 30)

	## Face room center
	var to_center: Vector2 = room.global_position + Vector2(960, 540) - spawn_pos
	if to_center.length() > 1.0:
		_guardian._aim_dir = to_center.normalized()
		_guardian._facing = _guardian._aim_dir


func _process(_delta: float) -> void:
	## Camera follows guardian
	if _camera and _guardian:
		_camera.global_position = _guardian.global_position

	## Detect which room the player is in
	var new_room_id := _get_room_at_position(_guardian.global_position)
	if new_room_id != _active_room_id and new_room_id >= 0:
		_on_player_entered_room(new_room_id)


func _get_room_at_position(pos: Vector2) -> int:
	for room_id in _rooms:
		var room: RoomBase = _rooms[room_id]
		var local_pos: Vector2 = pos - room.global_position
		if local_pos.x >= 0 and local_pos.x <= ROOM_WIDTH \
			and local_pos.y >= 0 and local_pos.y <= ROOM_HEIGHT:
			return room_id
	return -1


func _on_player_entered_room(room_id: int) -> void:
	_active_room_id = room_id
	FloorManager.enter_room(room_id)
	_rooms[room_id].activate()
	print("[FLOOR_HUB] Player entered room %d" % room_id)


## Legacy compatibility — not used in persistent mode
func on_door_used(_from_room_id: int, _to_room_id: int) -> void:
	pass
