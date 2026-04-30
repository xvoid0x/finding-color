extends Node2D
class_name FloorHub
## FloorHub — One persistent scene containing an entire floor.
##
## Responsible for:
##   • Reading the floor map and converting grid positions to world positions
##   • Spawning RoomBase instances (visuals + content per room)
##   • Building wall colliders (outer perimeter + internal blocked passages)
##   • Building TileMap floor with large-format tiles
##   • Spawning shared entities (guardian, companion, camera, HUD)
##   • Tracking which room the player is in and activating rooms on first entry

const ROOM_W: float = 1920.0
const ROOM_H: float = 1080.0
const WALL_THICK: float = 160.0
const TILE_SIZE: int = 128

var _rooms: Dictionary = {}
var _active_room_id: int = -1
var _guardian: CharacterBody2D
var _companion: Node2D
var _camera: Camera2D


func _ready() -> void:
	add_to_group("floor_hub")
	if FloorManager.current_map.is_empty():
		FloorManager.generate_floor(GameManager.current_floor)
	_build_tilemap()
	_build_wall_tilemap()
	_build_rooms()
	_build_wall_colliders()
	_spawn_shared_entities()
	_setup_post_process()
	_activate_start_room()


# =============================================================================
# TileMap Floor
# =============================================================================

func _build_tilemap() -> void:
	"""Build a TileMap floor for the entire floor level.
	Uses 128x128 tiles for readability at 1920x1080 resolution.
	Each room is 15x8 tiles with a 2-tile void gap between rooms.
	
	Key fix for seam lines:
	  • separation: 2px gap between atlas cells prevents texture bleeding
	  • use TextureFilter set to NEAREST (pixel art crispness)
	"""
	var tm := TileMap.new()
	tm.name = "FloorTileMap"
	tm.z_index = -100
	tm.tile_set = _create_floor_tileset()
	
	var map: Dictionary = FloorManager.current_map
	
	# Room dimensions in tiles
	var room_tiles_x: int = int(ROOM_W / TILE_SIZE)  # 15
	var room_tiles_y: int = int(ROOM_H / TILE_SIZE)  # 8
	var gap_tiles: int = 2
	
	for rid in map.grid_pos:
		var gp: Vector2i = map.grid_pos[rid]
		var origin_x: int = gp.x * (room_tiles_x + gap_tiles)
		var origin_y: int = gp.y * (room_tiles_y + gap_tiles)
		
		for tx in room_tiles_x:
			for ty in room_tiles_y:
				tm.set_cell(0, Vector2i(origin_x + tx, origin_y + ty), 0, Vector2i(0, 0))
		
		# Fill doorways between connected rooms
		var cxns: Array = map.connections.get(rid, [])
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var neighbor_gp: Vector2i = gp + dir
			var neighbor_id := -1
			for other in map.grid_pos:
				if map.grid_pos[other] == neighbor_gp:
					neighbor_id = other
					break
			if not neighbor_id in cxns:
				continue
			
			# Connected in this direction — fill the gap tiles as floor
			if dir == Vector2i.RIGHT:
				for gx in gap_tiles:
					for gy in room_tiles_y:
						tm.set_cell(0, Vector2i(origin_x + room_tiles_x + gx, origin_y + gy), 0, Vector2i(0, 0))
			elif dir == Vector2i.DOWN:
				for gy in gap_tiles:
					for gx in room_tiles_x:
						tm.set_cell(0, Vector2i(origin_x + gx, origin_y + room_tiles_y + gy), 0, Vector2i(0, 0))
	
	# Nearest-neighbor filtering for pixel art crispness
	tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	add_child(tm)
	print("[FLOOR_HUB] TileMap built")


func _create_floor_tileset() -> TileSet:
	"""Create a TileSet with a single 128x128 flagstone floor tile.
	
	Uses 2px separation between atlas cells to prevent seam artifacts.
	Uses NEAREST filter for crisp pixel art rendering.
	"""
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	
	var texture: Texture2D = load("res://assets/tiles/flagstone/floor_128.png") as Texture2D
	if not texture:
		push_error("[FLOOR_HUB] Failed to load floor tile")
		return ts

	
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	# Single-tile atlas — no margins/separation needed, tile fills the texture exactly
	source.separation = Vector2i(0, 0)
	source.margins = Vector2i(0, 0)
	

	
	ts.add_source(source)
	source.create_tile(Vector2i(0, 0))
	
	return ts


func _load_tile_texture(path: String) -> Texture2D:
	"""Load PNG as raw bytes → ImageTexture (headless CI compatible)."""
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[FLOOR_HUB] Cannot open: %s" % path)
		return null
	
	var png_bytes := file.get_buffer(file.get_length())
	var img := Image.new()
	var err := img.load_png_from_buffer(png_bytes)
	if err != OK:
		push_error("[FLOOR_HUB] Failed to decode PNG: %d" % err)
		return null
	
	return ImageTexture.create_from_image(img)


# =============================================================================
# Wall TileMap
# =============================================================================

func _build_wall_tilemap() -> void:
	"""Build a TileMap for wall visuals around room perimeters.
	Uses 32x32 wall tiles in their own coordinate space.
	The wall TileMap sits at z_index -99 (above floor at -100, below everything else).
	"""
	var ts: TileSet = _create_wall_tileset()
	if not ts or ts.get_source_count() == 0:
		push_error("[FLOOR_HUB] Failed to create wall tileset")
		return
	
	var tm := TileMap.new()
	tm.name = "WallTileMap"
	tm.z_index = -99
	tm.tile_set = ts
	tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	var map: Dictionary = FloorManager.current_map
	var gap_tiles: int = 2
	var room_tiles_x: int = int(ROOM_W / TILE_SIZE)
	var room_tiles_y: int = int(ROOM_H / TILE_SIZE)
	
	for rid in map.grid_pos:
		var gp: Vector2i = map.grid_pos[rid]
		var rx: int = gp.x * (room_tiles_x + gap_tiles) * TILE_SIZE
		var ry: int = gp.y * (room_tiles_y + gap_tiles) * TILE_SIZE
		
		var has_neighbor: Dictionary = {}
		for dir_name in ["up", "down", "left", "right"]:
			has_neighbor[dir_name] = _has_connection(rid, dir_name)
		
		var wt: int = int(WALL_THICK / 32)  # 5 wall tiles per 160px strip
		var wall_tile: Vector2i = Vector2i(0, 6)  # full flagstone wall
		
		# TOP WALL
		if not has_neighbor["up"]:
			var wtx_start: int = rx / 32
			var wty_start: int = (ry - wt * 32) / 32
			var wtx_end: int = (rx + int(ROOM_W)) / 32
			for wx in range(wtx_start, wtx_end):
				for wy in range(wty_start, wty_start + wt):
					tm.set_cell(0, Vector2i(wx, wy), 0, wall_tile)
		
		# BOTTOM WALL
		if not has_neighbor["down"]:
			var wtx_start: int = rx / 32
			var wty_start: int = (ry + int(ROOM_H)) / 32
			var wtx_end: int = (rx + int(ROOM_W)) / 32
			for wx in range(wtx_start, wtx_end):
				for wy in range(wty_start, wty_start + wt):
					tm.set_cell(0, Vector2i(wx, wy), 0, wall_tile)
		
		# LEFT WALL
		if not has_neighbor["left"]:
			var wtx_start: int = (rx - wt * 32) / 32
			var wty_start: int = ry / 32
			var wty_end: int = (ry + int(ROOM_H)) / 32
			for wy in range(wty_start, wty_end):
				for wx in range(wtx_start, wtx_start + wt):
					tm.set_cell(0, Vector2i(wx, wy), 0, wall_tile)
		
		# RIGHT WALL
		if not has_neighbor["right"]:
			var wtx_start: int = (rx + int(ROOM_W)) / 32
			var wty_start: int = ry / 32
			var wty_end: int = (ry + int(ROOM_H)) / 32
			for wy in range(wty_start, wty_end):
				for wx in range(wtx_start, wtx_start + wt):
					tm.set_cell(0, Vector2i(wx, wy), 0, wall_tile)
		
		# CORNER BLOCKS
		if not has_neighbor["up"] and not has_neighbor["left"]:
			var cx: int = (rx - wt * 32) / 32
			var cy: int = (ry - wt * 32) / 32
			for wx in range(cx, cx + wt):
				for wy in range(cy, cy + wt):
					tm.set_cell(0, Vector2i(wx, wy), 0, wall_tile)
		if not has_neighbor["up"] and not has_neighbor["right"]:
			var cx: int = (rx + int(ROOM_W)) / 32
			var cy: int = (ry - wt * 32) / 32
			for wx in range(cx, cx + wt):
				for wy in range(cy, cy + wt):
					tm.set_cell(0, Vector2i(wx, wy), 0, wall_tile)
		if not has_neighbor["down"] and not has_neighbor["left"]:
			var cx: int = (rx - wt * 32) / 32
			var cy: int = (ry + int(ROOM_H)) / 32
			for wx in range(cx, cx + wt):
				for wy in range(cy, cy + wt):
					tm.set_cell(0, Vector2i(wx, wy), 0, wall_tile)
		if not has_neighbor["down"] and not has_neighbor["right"]:
			var cx: int = (rx + int(ROOM_W)) / 32
			var cy: int = (ry + int(ROOM_H)) / 32
			for wx in range(cx, cx + wt):
				for wy in range(cy, cy + wt):
					tm.set_cell(0, Vector2i(wx, wy), 0, wall_tile)
	
	add_child(tm)
	print("[FLOOR_HUB] Wall TileMap built")


func _create_wall_tileset() -> TileSet:
	"""Create a TileSet from the wall spritesheet.
	Spritesheet: 128x256, 32x32 tiles, 4 columns x 8 rows.
	"""
	var wt := 32
	var cols := 4
	var rows := 8
	
	var texture: Texture2D = load("res://assets/tiles/wall/wall_tileset.png") as Texture2D
	if not texture:
		push_error("[FLOOR_HUB] Failed to load wall tileset texture")
		return null
	
	var ts := TileSet.new()
	ts.tile_size = Vector2i(wt, wt)
	
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(wt, wt)
	source.separation = Vector2i(0, 0)
	source.margins = Vector2i(0, 0)
	
	ts.add_source(source)
	
	for col in cols:
		for row in rows:
			source.create_tile(Vector2i(col, row))
	
	print("[FLOOR_HUB] Wall tileset created: %d tiles at %dx%d" % [cols * rows, wt, wt])
	return ts


# =============================================================================
# Room Spawning
# =============================================================================
# Room Spawning
# =============================================================================

func _build_rooms() -> void:
	var map: Dictionary = FloorManager.current_map
	# Room positions match the tilemap coords
	var room_tiles_x: int = int(ROOM_W / TILE_SIZE)
	var room_tiles_y: int = int(ROOM_H / TILE_SIZE)
	var gap_tiles: int = 2
	
	for rid in map.room_types:
		var room := _create_room(rid)
		var gp: Vector2i = map.grid_pos.get(rid, Vector2i.ZERO)
		room.position = Vector2(
			gp.x * (room_tiles_x + gap_tiles) * TILE_SIZE,
			gp.y * (room_tiles_y + gap_tiles) * TILE_SIZE
		)
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
# Wall Colliders
# =============================================================================

func _build_wall_colliders() -> void:
	"""Build StaticBody2D wall colliders on unconnected room edges."""
	var walls := Node2D.new()
	walls.name = "Walls"
	add_child(walls)
	
	var map: Dictionary = FloorManager.current_map
	
	for rid in map.grid_pos:
		var room: RoomBase = _rooms[rid]
		var wx: float = room.position.x
		var wy: float = room.position.y
		
		if not _has_connection(rid, "up"):
			_add_wall(walls, "up", wx, wy, WALL_THICK)
		if not _has_connection(rid, "down"):
			_add_wall(walls, "down", wx, wy, WALL_THICK)
		if not _has_connection(rid, "left"):
			_add_wall(walls, "left", wx, wy, WALL_THICK)
		if not _has_connection(rid, "right"):
			_add_wall(walls, "right", wx, wy, WALL_THICK)
	
	print("[FLOOR_HUB] Wall colliders built")


func _has_connection(rid: int, direction: String) -> bool:
	var map: Dictionary = FloorManager.current_map
	var gp: Vector2i = map.grid_pos.get(rid, Vector2i.ZERO)
	var ng: Vector2i
	match direction:
		"up":    ng = gp + Vector2i.UP
		"down":  ng = gp + Vector2i.DOWN
		"left":  ng = gp + Vector2i.LEFT
		"right": ng = gp + Vector2i.RIGHT
	for other in map.grid_pos:
		if map.grid_pos[other] == ng:
			if other in map.connections.get(rid, []):
				return true
	return false


func _add_wall(walls: Node2D, direction: String, wx: float, wy: float, thickness: float) -> void:
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
	var ambient := CanvasModulate.new()
	ambient.color = Color(0.5, 0.47, 0.55, 1)
	add_child(ambient)
	
	var g_scene: PackedScene = load("res://characters/guardian/guardian.tscn")
	_guardian = g_scene.instantiate()
	_guardian.add_to_group("guardian")
	add_child(_guardian)
	
	var c_scene: PackedScene = load("res://characters/companion/companion.tscn")
	_companion = c_scene.instantiate()
	_companion.add_to_group("companion")
	add_child(_companion)
	if _companion.has_method("initialize"):
		_companion.initialize(_guardian)
	
	_camera = Camera2D.new()
	_camera.enabled = true
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	add_child(_camera)
	CameraShaker.register_camera(_camera)
	
	var p_scene: PackedScene = load("res://scenes/ui/pause_menu.tscn")
	add_child(p_scene.instantiate())
	
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
	if _camera and _guardian:
		_camera.global_position = _guardian.global_position
	
	var new_id := _get_room_at_position(_guardian.global_position)
	if new_id != _active_room_id and new_id >= 0:
		_on_player_entered_room(new_id)


func _get_room_at_position(pos: Vector2) -> int:
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