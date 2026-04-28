extends Node
## FloorManager - Manages the floor map: room graph, traversal, fog of war.
##
## Replaces GameManager's linear room-sequence logic.
## Each floor is a small map of 4-6 interconnected rooms.
## Guardian explores freely by moving through doors.
## Phone player sees the full map; guardian sees minimal door indicators.
##
## Room types: combat, chest, shrine, exit
## Fog of war: rooms reveal as guardian enters them.

signal floor_map_generated(map_data: Dictionary)
signal room_entered(room_id: int, room_type: String)
signal room_cleared(room_id: int)
signal fog_of_war_updated(discovered_rooms: Array)
signal door_opened(from_room: int, to_room: int)
signal all_rooms_cleared()

# --- Map State ---
var current_map: Dictionary = {}       # Full map data (see _generate_map)
var current_room_id: int = 0
var entered_from_room_id: int = -1     # Which room we just came from (-1 = start)
var discovered_rooms: Array[int] = []  # Which rooms guardian has visited
var cleared_rooms: Array[int] = []     # Which combat rooms are cleared

# Room type pools per floor range
const ROOM_COUNTS := {
	"early":  4,   # Floors 1-3
	"mid":    5,   # Floors 4-6
	"late":   6,   # Floors 7+
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# =============================================================================
# Map Generation
# =============================================================================

func generate_floor(floor_number: int) -> Dictionary:
	"""Generate a new floor map. Call at start of each floor."""
	var room_count := _get_room_count(floor_number)
	var map := _build_map(room_count, floor_number)
	current_map = map
	current_room_id = map.start_room
	discovered_rooms.clear()
	cleared_rooms.clear()
	_discover_room(map.start_room)
	floor_map_generated.emit(map)
	print("[FLOOR] Generated floor %d: %d rooms | types: %s" % [
		floor_number, room_count,
		JSON.stringify(map.room_types)
	])
	return map


func _get_room_count(floor_number: int) -> int:
	if floor_number <= 3:
		return ROOM_COUNTS["early"]
	elif floor_number <= 6:
		return ROOM_COUNTS["mid"]
	else:
		return ROOM_COUNTS["late"]


func _build_map(room_count: int, floor_number: int) -> Dictionary:
	"""
	Build a small connected room graph.
	Structure: linear spine with optional branches.
	Room 0 is always the start (combat).
	One room is always the exit.
	1-2 optional rooms (chest/shrine) hang off the spine.
	"""
	var rooms := range(room_count)  # [0, 1, 2, ...]
	var connections: Dictionary = {}
	var room_types: Dictionary = {}
	var positions: Dictionary = {}  # For minimap layout

	# Initialise empty connection lists
	for i in rooms:
		connections[i] = []

	# --- Build spine (linear chain) ---
	# Required rooms: start + combat rooms + exit
	var spine_length := room_count - _count_optional_rooms(room_count)
	for i in range(spine_length - 1):
		_connect(connections, i, i + 1)

	# --- Hang optional rooms off spine ---
	var optional_count := _count_optional_rooms(room_count)
	for j in range(optional_count):
		var optional_id := spine_length + j
		# Pick a spine room to branch from (not the last — exit)
		var branch_from := randi_range(1, spine_length - 2)
		_connect(connections, branch_from, optional_id)

	# --- Assign room types ---
	# Room 0: combat (start)
	room_types[0] = "combat"
	# Last spine room: exit
	room_types[spine_length - 1] = "exit"
	# Optional rooms: chest or shrine
	for j in range(optional_count):
		var optional_id := spine_length + j
		room_types[optional_id] = "chest" if j % 2 == 0 else "shrine"
	# Remaining spine rooms: combat (with occasional elite)
	for i in range(1, spine_length - 1):
		var is_elite_room := floor_number >= 3 and randf() < 0.3
		room_types[i] = "combat_elite" if is_elite_room else "combat"

	# --- Layout positions for minimap (grid-based, simple) ---
	for i in range(spine_length):
		positions[i] = Vector2(i * 80, 0)
	for j in range(optional_count):
		var optional_id := spine_length + j
		var branch_from: int = -1
		for from_id in connections:
			if optional_id in connections[from_id]:
				branch_from = from_id
				break
		if branch_from >= 0:
			positions[optional_id] = positions[branch_from] + Vector2(0, 80)

	return {
		"room_count": room_count,
		"start_room": 0,
		"exit_room": spine_length - 1,
		"connections": connections,
		"room_types": room_types,
		"positions": positions,  # For phone minimap
	}


func _count_optional_rooms(room_count: int) -> int:
	match room_count:
		4: return 1
		5: return 2
		_: return 2


func _connect(connections: Dictionary, a: int, b: int) -> void:
	if b not in connections[a]:
		connections[a].append(b)
	if a not in connections[b]:
		connections[b].append(a)


# =============================================================================
# Room Traversal
# =============================================================================

func can_enter_room(room_id: int) -> bool:
	"""True if room is connected to current room and not locked."""
	if current_map.is_empty():
		return false
	var connections: Dictionary = current_map.get("connections", {})
	return room_id in connections.get(current_room_id, [])


func enter_room(room_id: int) -> void:
	"""Guardian walks through a door. Discovers room, emits signals."""
	if not can_enter_room(room_id):
		push_warning("[FLOOR] Tried to enter non-adjacent room: %d from %d" % [room_id, current_room_id])
		return

	var prev_room := current_room_id
	entered_from_room_id = prev_room
	current_room_id = room_id
	_discover_room(room_id)

	var room_type: String = current_map.room_types.get(room_id, "combat")
	door_opened.emit(prev_room, room_id)
	room_entered.emit(room_id, room_type)

	print("[FLOOR] Entered room %d (%s) from %d" % [room_id, room_type, prev_room])

	# Push updated map state to phone (deferred so PhoneManager is fully ready)
	call_deferred("_push_map_to_phone")


func on_room_cleared(room_id: int) -> void:
	"""Called by RoomBase when all enemies are dead."""
	if room_id not in cleared_rooms:
		cleared_rooms.append(room_id)
	room_cleared.emit(room_id)

	# Check if all combat rooms are cleared
	var all_clear := true
	for rid in current_map.room_types:
		var rtype: String = current_map.room_types[rid]
		if (rtype == "combat" or rtype == "combat_elite") and rid not in cleared_rooms:
			all_clear = false
			break

	if all_clear:
		all_rooms_cleared.emit()

	call_deferred("_push_map_to_phone")


func is_room_cleared(room_id: int) -> bool:
	return room_id in cleared_rooms


func get_current_room_type() -> String:
	if current_map.is_empty():
		return "combat"
	return current_map.room_types.get(current_room_id, "combat")


func get_connected_rooms(room_id: int) -> Array:
	if current_map.is_empty():
		return []
	return current_map.connections.get(room_id, [])


# =============================================================================
# Fog of War
# =============================================================================

func _push_map_to_phone() -> void:
	"""Safe deferred push — PhoneManager guaranteed loaded by call time."""
	if Engine.has_singleton("PhoneManager") or get_node_or_null("/root/PhoneManager"):
		PhoneManager.push_floor_map_state()


func _discover_room(room_id: int) -> void:
	if room_id not in discovered_rooms:
		discovered_rooms.append(room_id)
		fog_of_war_updated.emit(discovered_rooms)


func is_room_discovered(room_id: int) -> bool:
	return room_id in discovered_rooms


# =============================================================================
# Phone Map State
# =============================================================================

func get_map_state_for_phone() -> Dictionary:
	"""Serialise current map state for phone minimap."""
	if current_map.is_empty():
		return {}

	var rooms_data := []
	for room_id in current_map.room_types:
		var discovered := is_room_discovered(room_id)
		rooms_data.append({
			"id": room_id,
			"type": current_map.room_types[room_id] if discovered else "unknown",
			"discovered": discovered,
			"cleared": is_room_cleared(room_id),
			"current": room_id == current_room_id,
			"pos": {
				"x": current_map.positions.get(room_id, Vector2.ZERO).x,
				"y": current_map.positions.get(room_id, Vector2.ZERO).y,
			}
		})

	var connections_data := []
	for from_id in current_map.connections:
		for to_id in current_map.connections[from_id]:
			if to_id > from_id:  # Avoid duplicates
				connections_data.append({"from": from_id, "to": to_id})

	return {
		"rooms": rooms_data,
		"connections": connections_data,
		"current_room": current_room_id,
	}
