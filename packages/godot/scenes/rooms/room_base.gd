class_name RoomBase
extends Node2D
## RoomBase - Base class for all rooms.
## Handles enemy spawning, room clear detection, interactables.
##
## Two modes:
##   - Scene-per-room (persistent_mode = false): legacy, full self-contained room
##   - Persistent floor (persistent_mode = true): room is part of FloorHub,
##     shared guardian/camera/HUD, walls have door gaps, enemies spawn on activation

@export var enemy_spawn_positions: Array[Vector2] = []
@export var has_chest: bool = false
@export var has_shrine: bool = false
@export var persistent_mode: bool = false  ## Set by FloorHub when instantiating

## Persistent-mode state
var room_id: int = -1
var is_exit_room: bool = false
var _activated: bool = false
var _barriers: Array[StaticBody2D] = []

## Runtime state
var _enemies_alive: int = 0
var _room_cleared: bool = false
var _guardian: CharacterBody2D = null
var _companion: Node2D = null

## Scenes to instantiate
var _shadow_walker_scene: PackedScene = null
var _shadow_lurker_scene: PackedScene = null
var _swarmer_scene: PackedScene = null
var _stalker_scene: PackedScene = null
var _breakable_scene: PackedScene = null

@export var pot_count_min: int = 0
@export var pot_count_max: int = 3

const POT_AREA_MIN := Vector2(200, 200)
const POT_AREA_MAX := Vector2(1720, 880)
const POT_GUARDIAN_CLEARANCE := 180.0


func _ready() -> void:
	_load_scenes()

	if persistent_mode:
		_setup_persistent_mode()
	else:
		_setup_scene_mode()


## ---------------------------------------------------------------------------
## Scene loading
## ---------------------------------------------------------------------------

func _load_scenes() -> void:
	_shadow_walker_scene = load("res://characters/enemies/shadow_walker.tscn")
	_shadow_lurker_scene = load("res://characters/enemies/shadow_lurker.tscn")
	_swarmer_scene = load("res://characters/enemies/swarmer.tscn") if \
		ResourceLoader.exists("res://characters/enemies/swarmer.tscn") else _shadow_walker_scene
	_stalker_scene = load("res://characters/enemies/stalker.tscn") if \
		ResourceLoader.exists("res://characters/enemies/stalker.tscn") else _shadow_lurker_scene
	_breakable_scene = load("res://scenes/interactables/breakable.tscn") if \
		ResourceLoader.exists("res://scenes/interactables/breakable.tscn") else null


## ---------------------------------------------------------------------------
## Scene-per-room mode (legacy)
## ---------------------------------------------------------------------------

func _setup_scene_mode() -> void:
	_configure_from_floor_map()

	## Camera
	var cam := Camera2D.new()
	cam.position = Vector2(960, 540)
	cam.enabled = true
	add_child(cam)
	CameraShaker.register_camera(cam)

	## Pause menu
	var pause_scene: PackedScene = load("res://scenes/ui/pause_menu.tscn")
	var pause_menu := pause_scene.instantiate()
	add_child(pause_menu)

	## Doors
	_setup_doors()

	## Safety fallback
	var has_doors := false
	for child in $Interactables.get_children():
		if child.has_meta("to_room_id"):
			has_doors = true
			break
	if not has_doors:
		_spawn_door(-1, Vector2(960, 150))

	## Guardian + companion
	_spawn_player_characters()

	## Enemies
	_spawn_enemies()
	if _enemies_alive == 0:
		call_deferred("_on_all_enemies_cleared")

	## Interactables
	_setup_chest_node()
	_spawn_breakables()

	EventBus.room_entered.emit(GameManager.rooms_cleared_this_floor)
	print("[ROOM] Entered room ", FloorManager.current_room_id)


## ---------------------------------------------------------------------------
## Persistent mode (part of FloorHub)
## ---------------------------------------------------------------------------

func _setup_persistent_mode() -> void:
	_configure_from_floor_map()
	_setup_chest_node()
	_spawn_breakables()
	## Enemies, camera, guardian, pause menu are handled by FloorHub


func activate() -> void:
	"""Called by FloorHub when player first enters this room."""
	if _activated:
		return
	_activated = true

	_spawn_enemies()
	if _enemies_alive == 0:
		call_deferred("_on_all_enemies_cleared")

	print("[ROOM] Activated room %d (%s)" % [room_id, FloorManager.current_map.room_types.get(room_id, "combat")])


## ---------------------------------------------------------------------------
## Wall building with door gaps (persistent mode)
## ---------------------------------------------------------------------------

func build_walls(open_directions: Array[String]) -> void:
	"""Build room walls with gaps at connection points. Only called in persistent mode."""
	## Remove existing walls
	var walls := $Walls
	for child in walls.get_children():
		child.queue_free()

	const GAP_SIZE := 120.0
	const WALL_THICKNESS := 160.0
	const W := 1920.0
	const H := 1080.0

	## Top wall
	if "up" in open_directions:
		_build_wall_segment(walls, Vector2(0, 0), Vector2((W - GAP_SIZE) / 2, WALL_THICKNESS))
		_build_wall_segment(walls, Vector2((W + GAP_SIZE) / 2, 0), Vector2((W - GAP_SIZE) / 2, WALL_THICKNESS))
		_build_barrier("up", Vector2(W / 2, 0), Vector2(GAP_SIZE, WALL_THICKNESS))
	else:
		_build_wall_segment(walls, Vector2(0, 0), Vector2(W, WALL_THICKNESS))

	## Bottom wall
	if "down" in open_directions:
		_build_wall_segment(walls, Vector2(0, H - WALL_THICKNESS), Vector2((W - GAP_SIZE) / 2, WALL_THICKNESS))
		_build_wall_segment(walls, Vector2((W + GAP_SIZE) / 2, H - WALL_THICKNESS), Vector2((W - GAP_SIZE) / 2, WALL_THICKNESS))
		_build_barrier("down", Vector2(W / 2, H - WALL_THICKNESS), Vector2(GAP_SIZE, WALL_THICKNESS))
	else:
		_build_wall_segment(walls, Vector2(0, H - WALL_THICKNESS), Vector2(W, WALL_THICKNESS))

	## Left wall
	if "left" in open_directions:
		_build_wall_segment(walls, Vector2(0, 0), Vector2(WALL_THICKNESS, (H - GAP_SIZE) / 2))
		_build_wall_segment(walls, Vector2(0, (H + GAP_SIZE) / 2), Vector2(WALL_THICKNESS, (H - GAP_SIZE) / 2))
		_build_barrier("left", Vector2(0, H / 2), Vector2(WALL_THICKNESS, GAP_SIZE))
	else:
		_build_wall_segment(walls, Vector2(0, 0), Vector2(WALL_THICKNESS, H))

	## Right wall
	if "right" in open_directions:
		_build_wall_segment(walls, Vector2(W - WALL_THICKNESS, 0), Vector2(WALL_THICKNESS, (H - GAP_SIZE) / 2))
		_build_wall_segment(walls, Vector2(W - WALL_THICKNESS, (H + GAP_SIZE) / 2), Vector2(WALL_THICKNESS, (H - GAP_SIZE) / 2))
		_build_barrier("right", Vector2(W - WALL_THICKNESS, H / 2), Vector2(WALL_THICKNESS, GAP_SIZE))
	else:
		_build_wall_segment(walls, Vector2(W - WALL_THICKNESS, 0), Vector2(WALL_THICKNESS, H))


func _build_wall_segment(parent: Node, pos: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.position = pos + size / 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	parent.add_child(wall)


func _build_barrier(direction: String, pos: Vector2, size: Vector2) -> void:
	"""Create a temporary barrier in a door gap. Removed when room is cleared."""
	var barrier := StaticBody2D.new()
	barrier.name = "Barrier_%s" % direction
	barrier.position = pos + size / 2
	barrier.collision_layer = 1
	barrier.collision_mask = 1

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	barrier.add_child(shape)

	## Visual: closed door
	var visual := ColorRect.new()
	visual.offset_left = -size.x / 2
	visual.offset_top = -size.y / 2
	visual.offset_right = size.x / 2
	visual.offset_bottom = size.y / 2
	visual.color = Color(0.8, 0.1, 0.1, 0.6)
	barrier.add_child(visual)

	$Walls.add_child(barrier)
	_barriers.append(barrier)


func _remove_barriers() -> void:
	"""Remove all door barriers (called when room is cleared)."""
	for barrier in _barriers:
		if is_instance_valid(barrier):
			barrier.queue_free()
	_barriers.clear()


## ---------------------------------------------------------------------------
## Floor map configuration
## ---------------------------------------------------------------------------

func _configure_from_floor_map() -> void:
	var room_type: String = FloorManager.get_current_room_type()
	match room_type:
		"chest":
			has_chest = true
			has_shrine = false
		"shrine":
			has_chest = false
			has_shrine = true
		"exit":
			has_chest = false
			has_shrine = false
		_:
			has_chest = false
			has_shrine = false


## ---------------------------------------------------------------------------
## Doors (scene-per-room mode)
## ---------------------------------------------------------------------------

func _setup_doors() -> void:
	var connections: Array = FloorManager.get_connected_rooms(FloorManager.current_room_id)
	if connections.is_empty():
		return

	var template_door := get_node_or_null("Interactables/ExitDoor")
	if template_door:
		template_door.queue_free()

	var door_count: int = connections.size()
	var spacing: float = 720.0 / max(1, door_count + 1)
	var start_x: float = 960.0 - (spacing * (door_count - 1)) / 2.0

	for i in range(door_count):
		var target_room_id: int = connections[i]
		var door_x: float = start_x + spacing * i
		_spawn_door(target_room_id, Vector2(door_x, 150))


func _spawn_door(target_room_id: int, door_pos: Vector2) -> void:
	var door := Node2D.new()
	door.position = door_pos
	door.name = "Door_%d" % target_room_id

	var visual := ColorRect.new()
	visual.name = "DoorVisual"
	visual.offset_left = -30.0
	visual.offset_top = -40.0
	visual.offset_right = 30.0
	visual.offset_bottom = 40.0
	visual.color = Color(0.2, 0.18, 0.3, 1)
	door.add_child(visual)

	var detector := Area2D.new()
	detector.name = "PlayerDetector"
	detector.monitoring = false
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60, 80)
	shape_node.shape = rect
	detector.add_child(shape_node)
	door.add_child(detector)

	var locked: bool = true
	var unlock_callable := func() -> void:
		if not locked:
			return
		locked = false
		detector.monitoring = true
		var tween := door.create_tween()
		tween.tween_property(visual, "color", Color(0.2, 0.7, 0.4, 1.0), 0.4)

	door.set_meta("unlock", unlock_callable)
	door.set_meta("to_room_id", target_room_id)

	detector.body_entered.connect(func(body: Node) -> void:
		if not body.is_in_group("guardian"):
			return
		var is_exit: bool = false
		if target_room_id == -1:
			is_exit = true
		elif FloorManager.current_map.has("room_types"):
			var rt: String = FloorManager.current_map.room_types.get(target_room_id, "combat")
			is_exit = (rt == "exit")
		if is_exit:
			GameManager.exit_room()
		else:
			FloorManager.enter_room(target_room_id)
			get_tree().call_deferred("change_scene_to_file", "res://scenes/rooms/room_template.tscn")
	)

	$Interactables.add_child(door)


## ---------------------------------------------------------------------------
## Player spawn (scene-per-room mode)
## ---------------------------------------------------------------------------

func _spawn_player_characters() -> void:
	var guardian_scene: PackedScene = load("res://characters/guardian/guardian.tscn")
	_guardian = guardian_scene.instantiate()
	_guardian.position = _get_guardian_spawn()
	_guardian.add_to_group("guardian")
	var to_center: Vector2 = Vector2(960, 540) - _guardian.position
	if to_center.length() > 1.0:
		_guardian._aim_dir = to_center.normalized()
		_guardian._facing = _guardian._aim_dir
	add_child(_guardian)

	var companion_scene: PackedScene = load("res://characters/companion/companion.tscn")
	_companion = companion_scene.instantiate()
	_companion.position = _guardian.position + Vector2(-50, 30)
	_companion.add_to_group("companion")
	add_child(_companion)
	if _companion.has_method("initialize"):
		_companion.initialize(_guardian)


func _get_guardian_spawn() -> Vector2:
	var entered_from: int = FloorManager.entered_from_room_id
	if entered_from < 0:
		return Vector2(960, 700)
	var door := get_node_or_null("Interactables/Door_%d" % entered_from)
	if door:
		return door.position + Vector2(0, 120)
	return Vector2(960, 700)


## ---------------------------------------------------------------------------
## Enemy spawning
## ---------------------------------------------------------------------------

func _spawn_enemies() -> void:
	"""Override in subclass to define enemy composition."""
	pass


func _spawn_enemy_at(scene: PackedScene, pos: Vector2) -> EnemyBase:
	var enemy: EnemyBase = scene.instantiate()
	enemy.position = pos
	add_child(enemy)
	_enemies_alive += 1
	enemy.tree_exited.connect(_on_enemy_died)
	return enemy


func _on_enemy_died() -> void:
	if not is_inside_tree() or _room_cleared:
		return
	_enemies_alive -= 1
	if _enemies_alive <= 0:
		_on_all_enemies_cleared()


func _on_all_enemies_cleared() -> void:
	_room_cleared = true
	print("[ROOM] All enemies cleared — unlocking")
	EventBus.room_cleared.emit()
	FloorManager.on_room_cleared(FloorManager.current_room_id if not persistent_mode else room_id)
	_open_exit()
	if persistent_mode:
		_remove_barriers()


func _open_exit() -> void:
	for child in $Interactables.get_children():
		if child.has_meta("unlock"):
			var unlock_callable: Callable = child.get_meta("unlock")
			if unlock_callable is Callable:
				unlock_callable.call()


## ---------------------------------------------------------------------------
## Breakables & chest
## ---------------------------------------------------------------------------

func _spawn_breakables() -> void:
	if _breakable_scene == null:
		return
	var count := randi_range(pot_count_min, pot_count_max)
	var guardian_spawn := Vector2(960, 700) if persistent_mode else _get_guardian_spawn()
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 30:
		attempts += 1
		var pos := Vector2(
			randf_range(POT_AREA_MIN.x, POT_AREA_MAX.x),
			randf_range(POT_AREA_MIN.y, POT_AREA_MAX.y)
		)
		if pos.distance_to(guardian_spawn) < POT_GUARDIAN_CLEARANCE:
			continue
		var pot: Breakable = _breakable_scene.instantiate()
		pot.position = pos
		add_child(pot)
		placed += 1
	if placed > 0:
		print("[ROOM] Spawned ", placed, " breakable pot(s)")


func _setup_chest_node() -> void:
	var chest := get_node_or_null("Interactables/Chest")
	if not chest:
		return
	if has_chest:
		chest.set_meta("object_type", "chest")
		if chest.has_method("enable"):
			chest.enable()
	else:
		chest.visible = false
		chest.process_mode = Node.PROCESS_MODE_DISABLED


## ---------------------------------------------------------------------------
## Nightmare Tendrils (soft time pressure)
## ---------------------------------------------------------------------------

var _tendril_timer: float = 0.0
const TENDRIL_SPAWN_INTERVAL: float = 12.0

func _process(delta: float) -> void:
	if _room_cleared or not _activated:
		return
	_tendril_timer += delta
	if _tendril_timer >= TENDRIL_SPAWN_INTERVAL:
		_tendril_timer = 0.0
		_spawn_tendril()


func _spawn_tendril() -> void:
	if _shadow_walker_scene:
		var pos: Vector2 = _get_random_wall_position()
		var tendril := _spawn_enemy_at(_shadow_walker_scene, pos)
		if tendril:
			tendril.move_speed = 60.0
			tendril.damage_on_contact = 0.5
			tendril.max_hp = 0.5
			tendril.hp = 0.5


func _get_random_wall_position() -> Vector2:
	var room_center := Vector2(960, 540)
	var angle := randf() * TAU
	return room_center + Vector2(cos(angle), sin(angle)) * 350.0
