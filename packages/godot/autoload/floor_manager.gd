extends Node
## FloorManager — Procedural floor map generation and traversal state.
##
## Generates a room graph using grid-based random walk.
## Each room has a grid position (integer x,y) and connections to neighbours.
## FloorHub reads this to place rooms in world space.
##
## Room types: start, combat, combat_elite, chest, shrine, exit

signal floor_map_generated(map: Dictionary)
signal room_entered(room_id: int, room_type: String)
signal room_cleared(room_id: int)
signal fog_of_war_updated(discovered: Array[int])
signal all_rooms_cleared()

# --- Map State ---
var current_map: Dictionary = {}
var current_room_id: int = 0
var entered_from_room_id: int = -1
var discovered_rooms: Array[int] = []
var cleared_rooms: Array[int] = []

const ROOM_COUNTS := {"early": 4, "mid": 5, "late": 6}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# =============================================================================
# Floor Generation
# =============================================================================

func generate_floor(floor_number: int) -> Dictionary:
	"""Generate a new floor map. Call at start of each floor."""
	var room_count := _get_room_count(floor_number)
	var map := _build_grid_map(room_count, floor_number)
	current_map = map
	current_room_id = map.start_room
	entered_from_room_id = -1
	discovered_rooms.clear()
	cleared_rooms.clear()
	_discover_room(map.start_room)
	floor_map_generated.emit(map)
	print("[FLOOR] Generated floor %d: %d rooms" % [floor_number, room_count])
	return map


func _get_room_count(floor_number: int) -> int:
	if floor_number <= 3:
		return ROOM_COUNTS["early"]
	elif floor_number <= 6:
		return ROOM_COUNTS["mid"]
	return ROOM_COUNTS["late"]


func _build_grid_map(room_count: int, floor_number: int) -> Dictionary:
	"""Build a connected room graph via random walk on a grid.
	
	Algorithm:
		1. Place start room at (0,0)
		2. Random walk: pick random direction, place new room if empty
		3. Continue until we have room_count rooms
		4. Main path = rooms 0 to room_count-1
		5. Last room = exit
		6. Rooms with only 1 connection (dead ends) → chest or shrine
		7. Main path rooms → combat (with occasional elite)
	
	Returns: {
		"room_count": int,
		"start_room": int,
		"exit_room": int,
		"connections": {room_id: [room_id, ...]},      -- undirected adjacency
		"room_types": {room_id: String},
		"grid_pos": {room_id: Vector2i}              -- grid coordinates
	}
	"""
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	var grid_to_id: Dictionary = {}          ## Vector2i -> room_id
	var id_to_grid: Dictionary = {}          ## room_id -> Vector2i
	var connections: Dictionary = {}
	var room_types: Dictionary = {}
	
	const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	
	## 1. Place start
	var current_pos := Vector2i.ZERO
	var next_id := 0
	grid_to_id[current_pos] = next_id
	id_to_grid[next_id] = current_pos
	connections[next_id] = []
	next_id += 1
	
	## 2. Random walk to fill rooms
	while next_id < room_count:
		## Pick random direction
		var dir: Vector2i = DIRS[rng.randi_range(0, 3)]
		var new_pos: Vector2i = current_pos + dir
		
		## If occupied, keep walking from a random existing room
		while grid_to_id.has(new_pos):
			var rand_id := rng.randi_range(0, next_id - 1)
			current_pos = id_to_grid[rand_id]
			dir = DIRS[rng.randi_range(0, 3)]
			new_pos = current_pos + dir
		
		## Connect new room to current
		var new_id: int = next_id
		grid_to_id[new_pos] = new_id
		id_to_grid[new_id] = new_pos
		connections[new_id] = []
		
		var from_id: int = grid_to_id[current_pos]
		connections[from_id].append(new_id)
		connections[new_id].append(from_id)
		
		current_pos = new_pos
		next_id += 1
	
	## 3. Reposition to ensure connected graph (BFS from room 0)
	## Some rooms from random walk might not be connected to start if we
	## jumped to random room. Let's rebuild properly:
	## Actually, the above algorithm always connects to existing room,
	## so ALL rooms are connected. Good.
	
	## 4. Find the room furthest from start → that's the exit
	var exit_id := _find_furthest_room(connections, 0)
	
	## 5. Assign room types
	for id in id_to_grid:
		var conn_count: int = connections[id].size()
		if id == 0:
			room_types[id] = "start"
		elif id == exit_id:
			room_types[id] = "exit"
		elif conn_count == 1 and id != exit_id:
			## Dead end = optional reward room
			room_types[id] = "chest" if rng.randi() % 2 == 0 else "shrine"
		else:
			## Combat room (with elite chance on later floors)
			var is_elite := floor_number >= 3 and rng.randf() < 0.25
			room_types[id] = "combat_elite" if is_elite else "combat"
	
	## 6. Convert grid positions to world positions (for minimap)
	## Normalise so min x,y = 0
	var min_x := 9999
	var min_y := 9999
	for pos in id_to_grid.values():
		min_x = mini(min_x, pos.x)
		min_y = mini(min_y, pos.y)
	
	var grid_pos: Dictionary = {}
	for id in id_to_grid:
		var pos: Vector2i = id_to_grid[id]
		grid_pos[id] = Vector2i(pos.x - min_x, pos.y - min_y)
	
	return {
		"room_count": room_count,
		"start_room": 0,
		"exit_room": exit_id,
		"connections": connections,
		"room_types": room_types,
		"grid_pos": grid_pos,
	}


func _find_furthest_room(connections: Dictionary, from_id: int) -> int:
	"""BFS to find room with longest path from start. Returns that room's ID."""
	var dist: Dictionary = {}
	var queue: Array[int] = [from_id]
	dist[from_id] = 0
	
	var head := 0
	while head < queue.size():
		var rid: int = queue[head]
		head += 1
		for nb in connections.get(rid, []):
			if not dist.has(nb):
				dist[nb] = dist[rid] + 1
				queue.append(nb)
	
	var furthest_id := from_id
	var max_dist := 0
	for rid in dist:
		if dist[rid] > max_dist:
			max_dist = dist[rid]
			furthest_id = rid
	return furthest_id


# =============================================================================
# Room Traversal
# =============================================================================

func enter_room(room_id: int) -> void:
	"""Player physically entered this room."""
	if current_map.is_empty():
		return
	var prev := current_room_id
	entered_from_room_id = prev
	current_room_id = room_id
	_discover_room(room_id)
	room_entered.emit(room_id, get_current_room_type())
	print("[FLOOR] Entered room %d from %d" % [room_id, prev])
	call_deferred("_push_map_to_phone")


func on_room_cleared(room_id: int) -> void:
	if room_id not in cleared_rooms:
		cleared_rooms.append(room_id)
	room_cleared.emit(room_id)
	var all_clear := true
	for rid in current_map.room_types:
		var rt: String = current_map.room_types[rid]
		if (rt == "combat" or rt == "combat_elite") and rid not in cleared_rooms:
			all_clear = false
			break
	if all_clear:
		all_rooms_cleared.emit()
	call_deferred("_push_map_to_phone")


func get_current_room_type() -> String:
	if current_map.is_empty():
		return "combat"
	return current_map.room_types.get(current_room_id, "combat")


# =============================================================================
# Queries
# =============================================================================

func get_grid_pos(room_id: int) -> Vector2i:
	if current_map.is_empty():
		return Vector2i.ZERO
	return current_map.grid_pos.get(room_id, Vector2i.ZERO)


func get_room_type(room_id: int) -> String:
	if current_map.is_empty():
		return "combat"
	return current_map.room_types.get(room_id, "combat")


func get_connections(room_id: int) -> Array:
	if current_map.is_empty():
		return []
	return current_map.connections.get(room_id, [])


func is_room_cleared(room_id: int) -> bool:
	return room_id in cleared_rooms


# =============================================================================
# Fog of War
# =============================================================================

func _discover_room(room_id: int) -> void:
	if room_id not in discovered_rooms:
		discovered_rooms.append(room_id)
		fog_of_war_updated.emit(discovered_rooms)


func is_room_discovered(room_id: int) -> bool:
	return room_id in discovered_rooms


func _push_map_to_phone() -> void:
	if Engine.has_singleton("PhoneManager") or get_node_or_null("/root/PhoneManager"):
		PhoneManager.push_floor_map_state()


# =============================================================================
# Phone serialisation
# =============================================================================

func get_map_state_for_phone() -> Dictionary:
	if current_map.is_empty():
		return {}
	var rooms_data := []
	for rid in current_map.room_types:
		var discovered := is_room_discovered(rid)
		var pos: Vector2i = current_map.grid_pos.get(rid, Vector2i.ZERO)
		rooms_data.append({
			"id": rid,
			"type": current_map.room_types[rid] if discovered else "unknown",
			"discovered": discovered,
			"cleared": is_room_cleared(rid),
			"current": rid == current_room_id,
			"pos": {"x": pos.x, "y": pos.y}
		})
	var conn_data := []
	for from_id in current_map.connections:
		for to_id in current_map.connections[from_id]:
			if to_id > from_id:
				conn_data.append({"from": from_id, "to": to_id})
	return {"rooms": rooms_data, "connections": conn_data, "current_room": current_room_id}
