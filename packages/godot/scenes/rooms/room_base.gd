class_name RoomBase
extends Node2D
## RoomBase - Base class for all rooms.
## Handles enemy spawning, room clear detection, interactables.

@export var enemy_spawn_positions: Array[Vector2] = []
@export var has_chest: bool = false
@export var has_shrine: bool = false

var _enemies_alive: int = 0
var _room_cleared: bool = false
var _guardian: CharacterBody2D = null
var _companion: Node2D = null

# Scenes to instantiate
var _shadow_walker_scene: PackedScene = null
var _shadow_lurker_scene: PackedScene = null
var _swarmer_scene: PackedScene = null
var _stalker_scene: PackedScene = null
var _breakable_scene: PackedScene = null

# How many pots to scatter. Override per room subclass if desired.
@export var pot_count_min: int = 0
@export var pot_count_max: int = 3

# Playfield bounds for random pot placement (inside walls, away from spawn)
const POT_AREA_MIN := Vector2(200, 200)
const POT_AREA_MAX := Vector2(1720, 880)
const POT_GUARDIAN_CLEARANCE := 180.0  # Don't spawn within this radius of guardian spawn


func _ready() -> void:
	_shadow_walker_scene = load("res://characters/enemies/shadow_walker.tscn")
	_shadow_lurker_scene = load("res://characters/enemies/shadow_lurker.tscn")
	_swarmer_scene = load("res://characters/enemies/swarmer.tscn") if \
		ResourceLoader.exists("res://characters/enemies/swarmer.tscn") else _shadow_walker_scene
	_stalker_scene = load("res://characters/enemies/stalker.tscn") if \
		ResourceLoader.exists("res://characters/enemies/stalker.tscn") else _shadow_lurker_scene
	_breakable_scene = load("res://scenes/interactables/breakable.tscn") if \
		ResourceLoader.exists("res://scenes/interactables/breakable.tscn") else null

	# Read room configuration from floor map
	_configure_from_floor_map()

	# Camera — centred on room, registered for shake
	var cam := Camera2D.new()
	cam.position = Vector2(960, 540)  # Room centre
	cam.enabled = true
	add_child(cam)
	CameraShaker.register_camera(cam)

	# Add pause menu overlay
	var pause_scene: PackedScene = load("res://scenes/ui/pause_menu.tscn")
	var pause_menu := pause_scene.instantiate()
	add_child(pause_menu)

	# Spawn doors FIRST so guardian spawn can find entrance
	_setup_doors()

	# Safety: if no doors spawned, create a default exit door
	var has_doors := false
	for child in $Interactables.get_children():
		if child.has_meta("to_room_id"):
			has_doors = true
			break
	if not has_doors:
		print("[ROOM] No doors found — spawning default exit door")
		_spawn_door(-1, Vector2(960, 150))

	# Spawn guardian and companion (positioned near entrance)
	_spawn_player_characters()

	# Spawn enemies
	_spawn_enemies()

	# Safety: if no enemies spawned (e.g. empty override), clear the room immediately
	if _enemies_alive == 0:
		call_deferred("_on_all_enemies_cleared")

	# Setup interactables
	_setup_chest_node()
	_spawn_breakables()

	EventBus.room_entered.emit(GameManager.rooms_cleared_this_floor)
	print("[ROOM] Entered room ", FloorManager.current_room_id, " (", FloorManager.get_current_room_type(), ") | entered from ", FloorManager.entered_from_room_id)


func _spawn_player_characters() -> void:
	# Guardian
	var guardian_scene: PackedScene = load("res://characters/guardian/guardian.tscn")
	_guardian = guardian_scene.instantiate()
	_guardian.position = _get_guardian_spawn()
	_guardian.add_to_group("guardian")
	# Face toward room center (or toward doors if entering from bottom)
	var to_center: Vector2 = Vector2(960, 540) - _guardian.position
	if to_center.length() > 1.0:
		_guardian._aim_dir = to_center.normalized()
		_guardian._facing = _guardian._aim_dir
	add_child(_guardian)

	# Companion
	var companion_scene: PackedScene = load("res://characters/companion/companion.tscn")
	_companion = companion_scene.instantiate()
	_companion.position = _guardian.position + Vector2(-50, 30)
	_companion.add_to_group("companion")
	add_child(_companion)
	if _companion.has_method("initialize"):
		_companion.initialize(_guardian)


# =============================================================================
# Floor Map Configuration
# =============================================================================

func _configure_from_floor_map() -> void:
	"""Set room properties based on FloorManager's current room type."""
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
			# combat or combat_elite
			has_chest = false
			has_shrine = false


func _setup_doors() -> void:
	"""Spawn doors for each connected room in the floor map."""
	var connections: Array = FloorManager.get_connected_rooms(FloorManager.current_room_id)
	if connections.is_empty():
		return

	# Remove template door — we'll spawn fresh ones
	var template_door := get_node_or_null("Interactables/ExitDoor")
	if template_door:
		template_door.queue_free()

	# Position doors evenly across top wall
	var door_count: int = connections.size()
	var spacing: float = 720.0 / max(1, door_count + 1)
	var start_x: float = 960.0 - (spacing * (door_count - 1)) / 2.0

	for i in range(door_count):
		var target_room_id: int = connections[i]
		var door_x: float = start_x + spacing * i
		_spawn_door(target_room_id, Vector2(door_x, 150))


func _spawn_door(target_room_id: int, door_pos: Vector2) -> void:
	"""Create a door node leading to target_room_id at the given position."""
	var door := Node2D.new()
	door.position = door_pos
	door.name = "Door_%d" % target_room_id

	# Visual
	var visual := ColorRect.new()
	visual.name = "DoorVisual"
	visual.offset_left = -30.0
	visual.offset_top = -40.0
	visual.offset_right = 30.0
	visual.offset_bottom = 40.0
	visual.color = Color(0.2, 0.18, 0.3, 1)
	door.add_child(visual)

	# Player detector
	var detector := Area2D.new()
	detector.name = "PlayerDetector"
	detector.monitoring = false
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60, 80)
	shape_node.shape = rect
	detector.add_child(shape_node)
	door.add_child(detector)

	# Door state
	var locked: bool = true

	# Unlock callback — brightens visual and enables detector
	var unlock_callable := func() -> void:
		if not locked:
			return
		locked = false
		detector.monitoring = true
		var tween := door.create_tween()
		tween.tween_property(visual, "color", Color(0.2, 0.7, 0.4, 1.0), 0.4)

	# Store unlock callable on door for RoomBase to call
	door.set_meta("unlock", unlock_callable)
	door.set_meta("to_room_id", target_room_id)

	# On body entered — transition
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


func _get_guardian_spawn() -> Vector2:
	"""Spawn guardian near the entrance door (the one we came through)."""
	var entered_from: int = FloorManager.entered_from_room_id
	if entered_from < 0:
		# First room — spawn at default position
		return Vector2(960, 700)

	# Find the door that leads back to the room we came from
	var door := get_node_or_null("Interactables/Door_%d" % entered_from)
	if door:
		# Spawn below that door, facing up
		return door.position + Vector2(0, 120)

	# Fallback: spawn at center-bottom
	return Vector2(960, 700)


func _spawn_enemies() -> void:
	"""Override in subclass to define enemy composition."""
	pass


func _spawn_enemy_at(scene: PackedScene, pos: Vector2) -> EnemyBase:
	var enemy: EnemyBase = scene.instantiate()
	enemy.position = pos
	add_child(enemy)
	_enemies_alive += 1
	# Use tree_exited (post-removal) not tree_exiting (mid-removal)
	# to avoid spurious clears during scene teardown.
	enemy.tree_exited.connect(_on_enemy_died)
	return enemy


func _on_enemy_died() -> void:
	# Guard: if the room itself is being freed, ignore enemy deaths.
	# (scene teardown removes all children, which fires tree_exited on each enemy)
	if not is_inside_tree() or _room_cleared:
		return
	_enemies_alive -= 1
	if _enemies_alive <= 0:
		_on_all_enemies_cleared()


func _on_all_enemies_cleared() -> void:
	_room_cleared = true
	print("[ROOM] All enemies cleared — door unlocking")
	EventBus.room_cleared.emit()
	# Notify FloorManager so it can track cleared rooms and push map state
	FloorManager.on_room_cleared(FloorManager.current_room_id)
	_open_exit()


func _open_exit() -> void:
	"""Unlock all doors in the room."""
	for child in $Interactables.get_children():
		if child.has_meta("unlock"):
			var unlock_callable: Callable = child.get_meta("unlock")
			if unlock_callable is Callable:
				unlock_callable.call()


func _spawn_breakables() -> void:
	if _breakable_scene == null:
		return
	var count := randi_range(pot_count_min, pot_count_max)
	var guardian_spawn := _get_guardian_spawn()
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 30:
		attempts += 1
		var pos := Vector2(
			randf_range(POT_AREA_MIN.x, POT_AREA_MAX.x),
			randf_range(POT_AREA_MIN.y, POT_AREA_MAX.y)
		)
		# Don't crowd the guardian spawn point
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
		# Hide chest in rooms that don't have one
		chest.visible = false
		chest.process_mode = Node.PROCESS_MODE_DISABLED


# --- Nightmare Tendrils (soft time pressure) ---

var _tendril_timer: float = 0.0
const TENDRIL_SPAWN_INTERVAL: float = 12.0

func _process(delta: float) -> void:
	if _room_cleared:
		return
	_tendril_timer += delta
	if _tendril_timer >= TENDRIL_SPAWN_INTERVAL:
		_tendril_timer = 0.0
		_spawn_tendril()


func _spawn_tendril() -> void:
	"""Spawn a weak tendril enemy to pressure the player to keep moving."""
	if _shadow_walker_scene:
		var pos: Vector2 = _get_random_wall_position()
		var tendril := _spawn_enemy_at(_shadow_walker_scene, pos)
		if tendril:
			tendril.move_speed = 60.0  # Slow but relentless
			tendril.damage_on_contact = 0.5
			tendril.max_hp = 0.5
			tendril.hp = 0.5


func _get_random_wall_position() -> Vector2:
	"""Return a position near the room edge."""
	var room_center := Vector2(960, 540)
	var angle := randf() * TAU
	return room_center + Vector2(cos(angle), sin(angle)) * 350.0
