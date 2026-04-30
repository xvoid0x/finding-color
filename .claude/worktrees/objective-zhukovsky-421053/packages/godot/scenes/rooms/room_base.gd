class_name RoomBase
extends Node2D
## RoomBase — One room on a persistent floor.
##
## Handles visual setup, enemy spawning, breakables, chest/shrine/exit content.
## Walls are built GLOBALLY by FloorHub — RoomBase never touches walls.
##
## Two modes:
##   • persistent_mode = false  (legacy scene-per-room, standalone)
##   • persistent_mode = true   (child of FloorHub, content only)

# --- Exported content-config ---
@export var enemy_spawn_positions: Array[Vector2] = []
@export var has_chest: bool = false
@export var has_shrine: bool = false
@export var persistent_mode: bool = false

# --- Persistent-mode state ---
var room_id: int = -1
var room_type: String = "combat"

# --- Runtime state ---
var _activated: bool = false
var _room_cleared: bool = false
var _enemies_alive: int = 0
var _guardian: CharacterBody2D = null
var _companion: Node2D = null

static var HEADLESS_RUN: bool = false  ## Set by AiRunEngine in headless mode to skip enemy damage

# --- Lazily-loaded scenes ---
var _scenes: Dictionary = {}

## Legacy aliases so room_template.gd and subclasses still work
func _get_shadow_walker_scene() -> PackedScene:
	return _scenes.shadow_walker
func _get_shadow_lurker_scene() -> PackedScene:
	return _scenes.shadow_lurker
func _get_swarmer_scene() -> PackedScene:
	var s: Variant = _scenes.swarmer
	if s is PackedScene: return s
	var fallback: Variant = _scenes.shadow_walker
	if fallback is PackedScene: return fallback
	return null
func _get_stalker_scene() -> PackedScene:
	var s: Variant = _scenes.stalker
	if s is PackedScene: return s
	var fallback: Variant = _scenes.shadow_lurker
	if fallback is PackedScene: return fallback
	return null
func _get_breakable_scene() -> PackedScene:
	return _scenes.breakable


func _ready() -> void:
	_load_scenes()
	if persistent_mode:
		_setup_persistent_mode()
	else:
		_setup_scene_mode()


func _load_scenes() -> void:
	_scenes.shadow_walker = _load("res://characters/enemies/shadow_walker.tscn")
	_scenes.shadow_lurker = _load("res://characters/enemies/shadow_lurker.tscn")
	var s: PackedScene = _load("res://characters/enemies/swarmer.tscn")
	_scenes.swarmer = s if s else _scenes.shadow_walker
	var t: PackedScene = _load("res://characters/enemies/stalker.tscn")
	_scenes.stalker = t if t else _scenes.shadow_lurker
	_scenes.breakable     = _load("res://scenes/interactables/breakable.tscn")


func _load(path: String) -> PackedScene:
	return load(path) if ResourceLoader.exists(path) else null


# =============================================================================
# Persistent Mode
# =============================================================================

func _setup_persistent_mode() -> void:
	## Remove the legacy ExitDoor — persistent floor has no interactable doors
	var door := get_node_or_null("Interactables/ExitDoor")
	if door:
		door.queue_free()
	## Setup content based on room_type
	_setup_room_content()
	## Exit room needs a trapdoor (placed now, checked on clear)
	if room_type == "exit":
		_place_exit_trapdoor()


func _setup_room_content() -> void:
	match room_type:
		"chest":
			has_chest = true
			_setup_chest()
		"shrine":
			has_shrine = true
			_setup_shrine()
		"start", "combat", "combat_elite", "exit":
			_setup_chest()  # hidden, enabled only if chest flag set
			_setup_breakables()


func activate() -> void:
	"""Called once: when player first enters this room."""
	if _activated:
		return
	_activated = true
	_spawn_enemies()
	if _enemies_alive == 0:
		call_deferred("_on_room_cleared")
	print("[ROOM] Activated %d (%s)" % [room_id, room_type])


# =============================================================================
# Scene-per-room mode (legacy, standalone)
# =============================================================================

func _setup_scene_mode() -> void:
	## Camera, pause menu, doors — self-contained room
	var cam := Camera2D.new()
	cam.position = Vector2(960, 540)
	cam.enabled = true
	add_child(cam)
	CameraShaker.register_camera(cam)
	
	add_child(load("res://scenes/ui/pause_menu.tscn").instantiate())
	_setup_doors()
	_spawn_player_characters()
	_spawn_enemies()
	if _enemies_alive == 0:
		call_deferred("_on_room_cleared")
	_setup_room_content()
	EventBus.room_entered.emit(GameManager.rooms_cleared_this_floor)
	print("[ROOM] Scene-mode room entered")


func _setup_doors() -> void:
	var connections: Array = FloorManager.get_connections(FloorManager.current_room_id)
	var template := get_node_or_null("Interactables/ExitDoor")
	if template:
		template.queue_free()
	for target_id in connections:
		_spawn_door(target_id, Vector2(960, 150))  # placeholder position


func _spawn_door(target_id: int, pos: Vector2) -> void:
	var door := Node2D.new()
	door.position = pos
	var vis := ColorRect.new()
	vis.size = Vector2(60, 80)
	vis.position = Vector2(-30, -40)
	vis.color = Color(0.2, 0.18, 0.3, 1)
	door.add_child(vis)
	door.set_meta("to_room_id", target_id)
	$Interactables.add_child(door)


func _spawn_player_characters() -> void:
	var g: Node = load("res://characters/guardian/guardian.tscn").instantiate()
	g.position = Vector2(960, 700)
	g.add_to_group("guardian")
	add_child(g)
	_guardian = g
	var c: Node = load("res://characters/companion/companion.tscn").instantiate()
	c.position = g.position + Vector2(-50, 30)
	c.add_to_group("companion")
	add_child(c)
	if c.has_method("initialize"):
		c.initialize(g)
	_companion = c


# =============================================================================
# Enemy Spawning
# =============================================================================

func _spawn_enemies() -> void:
	var floor_num: int = GameManager.current_floor
	match room_type:
		"chest", "shrine":
			return
		"exit":
			_spawn_enemy_pack(floor_num, true)
		"combat_elite":
			_spawn_enemy_pack(floor_num, true)
		_:  # "start", "combat"
			_spawn_enemy_pack(floor_num, false)


func _spawn_enemy_pack(floor_num: int, elite: bool) -> void:
	## Pick composition
	var count: int
	var pool: Array[ PackedScene ] = []
	
	if floor_num <= 2:
		count = randi_range(2, 3)
		pool = [_scenes.shadow_walker, _scenes.swarmer, _scenes.swarmer]
	elif floor_num <= 5:
		count = randi_range(3, 4)
		pool = [_scenes.shadow_walker, _scenes.swarmer, _scenes.stalker]
	else:
		count = randi_range(4, 6)
		pool = [_scenes.shadow_walker, _scenes.swarmer, _scenes.stalker, _scenes.shadow_lurker]
	
	if elite and _scenes.stalker:
		pool = [_scenes.stalker, _scenes.shadow_lurker, _scenes.stalker]
	
	## Spawn with minimum spacing
	var spawned: Array[Vector2] = []
	for i in range(count):
		var scene: PackedScene = pool[randi_range(0, pool.size() - 1)]
		var pos := _get_spawn_pos(spawned, 200.0)
		_spawn_enemy_at(scene, pos)
		spawned.append(pos)


func _get_spawn_pos(existing: Array[Vector2], min_dist: float) -> Vector2:
	var area_min := Vector2(300, 200)
	var area_max := Vector2(1620, 880)
	var safe_zone := Vector2(960, 700)
	for attempt in range(50):
		var pos := Vector2(
			randf_range(area_min.x, area_max.x),
			randf_range(area_min.y, area_max.y)
		)
		if pos.distance_to(safe_zone) < 300.0:
			continue
		var too_close := false
		for other in existing:
			if pos.distance_to(other) < min_dist:
				too_close = true
				break
		if not too_close:
			return pos
	return Vector2(randf_range(400, 1520), randf_range(300, 780))


func _spawn_enemy_at(scene: PackedScene, pos: Vector2) -> void:
	if not scene:
		return
	var enemy: Node = scene.instantiate()
	enemy.position = pos
	add_child(enemy)
	_enemies_alive += 1
	## Use tree_exited to count deaths, but check if it was alive first
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died)
	else:
		enemy.tree_exited.connect(_on_enemy_died)


func _on_enemy_died() -> void:
	if not is_inside_tree() or _room_cleared:
		return
	_enemies_alive -= 1
	if _enemies_alive <= 0:
		_on_room_cleared()


func _on_room_cleared() -> void:
	if _room_cleared:
		return
	_room_cleared = true
	EventBus.room_cleared.emit()
	FloorManager.on_room_cleared(room_id)
	print("[ROOM] Cleared %d" % room_id)


# =============================================================================
# Breakables / Pots
# =============================================================================

func _setup_breakables() -> void:
	if not _scenes.breakable:
		return
	
	var clusters := randi_range(1, 3)
	for c in range(clusters):
		var center := _get_cluster_center()
		var count := randi_range(2, 5)
		for b in range(count):
			var offset := Vector2(randf_range(-60, 60), randf_range(-60, 60))
			var pos := (center + offset).clamp(Vector2(200, 200), Vector2(1720, 880))
			var pot: Node2D = _scenes.breakable.instantiate()
			pot.position = pos
			add_child(pot)


func _get_cluster_center() -> Vector2:
	## Bias toward edges and walls
	var side := randi_range(0, 3)
	match side:
		0: return Vector2(randf_range(300, 1620), randf_range(200, 350))   # top
		1: return Vector2(randf_range(300, 1620), randf_range(730, 880))   # bottom
		2: return Vector2(randf_range(200, 400), randf_range(300, 780))    # left
		3: return Vector2(randf_range(1520, 1720), randf_range(300, 780))  # right
	return Vector2(960, 540)


# =============================================================================
# Chest / Shrine / Exit Trapdoor
# =============================================================================

func _setup_chest() -> void:
	var chest := get_node_or_null("Interactables/Chest")
	if not chest:
		return
	if has_chest:
		chest.visible = true
		chest.process_mode = Node.PROCESS_MODE_INHERIT
		chest.set_meta("object_type", "chest")
		if chest.has_method("enable"):
			chest.enable()
	else:
		chest.visible = false
		chest.process_mode = Node.PROCESS_MODE_DISABLED


func _setup_shrine() -> void:
	## Shrine nodes are not in the template yet — placeholder
	pass


func _place_exit_trapdoor() -> void:
	var area := Area2D.new()
	area.name = "ExitTrapdoor"
	area.position = Vector2(960, 540)
	
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(120, 120)
	shape.shape = rect
	area.add_child(shape)
	
	## Visual
	var vis := ColorRect.new()
	vis.size = Vector2(120, 120)
	vis.position = Vector2(-60, -60)
	vis.color = Color(0.1, 0.05, 0.15, 0.9)
	area.add_child(vis)
	
	var glow := ColorRect.new()
	glow.size = Vector2(100, 100)
	glow.position = Vector2(-50, -50)
	glow.color = Color(0.3, 0.1, 0.4, 0.5)
	area.add_child(glow)
	
	area.body_entered.connect(func(body: Node) -> void:
		if not body.is_in_group("guardian"):
			return
		if not _room_cleared:
			print("[ROOM] Trapdoor locked — clear room first")
			return
		print("[ROOM] Trapdoor activated — next floor")
		GameManager.exit_room()
	)
	# In persistent mode, Walls node is on the FloorHub, not this room.
	# Add the trapdoor directly to the room instead.
	if persistent_mode:
		add_child(area)
	else:
		$Walls.add_child(area)


# =============================================================================
# Tendrils (soft time pressure)
# =============================================================================

var _tendril_timer: float = 0.0
const TENDRIL_INTERVAL: float = 12.0

func _process(delta: float) -> void:
	if _room_cleared or not _activated:
		return
	_tendril_timer += delta
	if _tendril_timer >= TENDRIL_INTERVAL:
		_tendril_timer = 0.0
		_spawn_tendril()


func _spawn_tendril() -> void:
	if not _scenes.shadow_walker:
		return
	var angle := randf() * TAU
	var pos := Vector2(960, 540) + Vector2(cos(angle), sin(angle)) * 400
	var enemy: Node = _scenes.shadow_walker.instantiate()
	enemy.position = pos
	if enemy is EnemyBase:
		enemy.move_speed = 60
		enemy.damage_on_contact = 0.5
		enemy.max_hp = 0.5
		enemy.hp = 0.5
	add_child(enemy)
