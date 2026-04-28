extends Node2D
## FloorHub - Container scene for a full floor.
##
## Generates the floor map, instantiates rooms as sub-scenes,
## and manages door connections between them.
## Guardian transitions between rooms by walking through doors.
## Phone player sees the full minimap; guardian sees door indicators on HUD.
##
## Each room is a RoomBase scene placed in a grid layout.
## Only the current room is "active" — others are frozen (process_mode=DISABLED)
## to keep performance clean.

const ROOM_SPACING := Vector2(2200, 0)  # Rooms laid out horizontally, off-screen

# Room scene pool — looked up by room type
const ROOM_SCENES := {
	"combat":       "res://scenes/rooms/room_combat.tscn",
	"combat_elite": "res://scenes/rooms/room_combat_elite.tscn",
	"chest":        "res://scenes/rooms/room_chest.tscn",
	"shrine":       "res://scenes/rooms/room_shrine.tscn",
	"exit":         "res://scenes/rooms/room_exit.tscn",
}
const ROOM_FALLBACK := "res://scenes/rooms/room_template.tscn"

var _rooms: Dictionary = {}          # room_id -> Node2D (instantiated room)
var _doors: Dictionary = {}          # "from_to" -> DoorNode
var _active_room_id: int = -1


func _ready() -> void:
	add_to_group("floor_hub")

	# Generate map if not already done (first floor of a run)
	if FloorManager.current_map.is_empty():
		FloorManager.generate_floor(GameManager.current_floor)

	_build_rooms()
	_enter_room(FloorManager.current_map.start_room)

	FloorManager.room_entered.connect(_on_floor_manager_room_entered)


func _build_rooms() -> void:
	"""Instantiate all rooms and position them off-screen in a grid."""
	var map: Dictionary = FloorManager.current_map
	for room_id in map.room_types:
		var room_type: String = map.room_types[room_id]
		var scene_path: String = ROOM_SCENES.get(room_type, ROOM_FALLBACK)

		# Fall back to template if specific scene doesn't exist yet
		if not ResourceLoader.exists(scene_path):
			scene_path = ROOM_FALLBACK

		var scene: PackedScene = load(scene_path)
		var room: Node2D = scene.instantiate()

		# Position rooms spaced out horizontally so they don't overlap
		room.position = Vector2(room_id, 0) * ROOM_SPACING
		room.set_meta("room_id", room_id)
		room.set_meta("room_type", room_type)

		# Start all rooms frozen — only active room processes
		room.process_mode = Node.PROCESS_MODE_DISABLED

		add_child(room)
		_rooms[room_id] = room

		print("[FLOOR_HUB] Built room %d (%s)" % [room_id, room_type])


func _enter_room(room_id: int) -> void:
	"""Activate a room and freeze the previous one. Move camera to it."""
	# Freeze previous room
	if _active_room_id >= 0 and _rooms.has(_active_room_id):
		_rooms[_active_room_id].process_mode = Node.PROCESS_MODE_DISABLED

	_active_room_id = room_id
	var room: Node2D = _rooms[room_id]

	# Unfreeze
	room.process_mode = Node.PROCESS_MODE_INHERIT

	# Move camera to this room's position
	_pan_camera_to(room.position)

	# Notify FloorManager (triggers fog-of-war + phone map update)
	FloorManager.enter_room(room_id)

	# Respawn guardian + companion in this room if they exist
	_reposition_characters(room)


func _reposition_characters(room: Node2D) -> void:
	"""Move guardian and companion to this room's spawn point."""
	var spawn_pos: Vector2 = room.position + Vector2(960, 700)  # default centre-bottom

	# Try room's own spawn marker first
	var spawn_marker := room.get_node_or_null("GuardianSpawn")
	if spawn_marker:
		spawn_pos = spawn_marker.global_position

	var guardian := get_tree().get_first_node_in_group("guardian")
	var companion := get_tree().get_first_node_in_group("companion")

	if guardian:
		guardian.global_position = spawn_pos
	if companion:
		companion.global_position = spawn_pos + Vector2(-50, 30)


func _pan_camera_to(target_pos: Vector2) -> void:
	"""Tween camera to the new room's centre."""
	var cam := get_tree().get_first_node_in_group("main_camera") as Camera2D
	if not cam:
		return
	var room_centre := target_pos + Vector2(960, 540)
	var tween := create_tween()
	tween.tween_property(cam, "global_position", room_centre, 0.4)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


# =============================================================================
# Door interaction — called by exit_door.gd when guardian walks through
# =============================================================================

func on_door_used(from_room_id: int, to_room_id: int) -> void:
	"""Guardian walked through a door. Transition to the connected room."""
	if not FloorManager.can_enter_room(to_room_id):
		push_warning("[FLOOR_HUB] Door used to non-adjacent room: %d → %d" % [from_room_id, to_room_id])
		return

	var to_type: String = FloorManager.current_map.room_types.get(to_room_id, "combat")
	if to_type == "exit":
		# This is the exit room — floor is done
		GameManager.exit_room()
		return

	_enter_room(to_room_id)


func _on_floor_manager_room_entered(_room_id: int, _room_type: String) -> void:
	pass  # Future: trigger room entry animations, music change, etc.
