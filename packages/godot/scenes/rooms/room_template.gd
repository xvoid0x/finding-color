extends RoomBase
## RoomTemplate - The single prototype room.
## Spawns enemies based on current floor depth using an Isaac-inspired pool system.
##
## Each floor has a difficulty range that determines which enemy configurations
## can appear. Higher floors unlock harder enemy types and denser layouts.
## The three arches are: chaser (Swarmer), ranged (Lurker), tactical (Stalker/Crawler),
## with Sploder as a chaos element introduced at floor 3.

# ---- Enemy pool definitions ----
# Each pool entry: [scene_getter_func_name, weight, min_count, max_count]
# Higher weight = more likely to be picked for a slot

const POOL_F1_EASY := [
	["_get_swarmer_scene", 3, 1, 2],
	["_get_lurker_scene", 2, 1, 2],
]

const POOL_F2_MEDIUM := [
	["_get_swarmer_scene", 3, 2, 3],
	["_get_lurker_scene", 2, 1, 2],
	["_get_stalker_scene", 1, 1, 1],
]

const POOL_F3_HARD := [
	["_get_swarmer_scene", 2, 2, 3],
	["_get_lurker_scene", 2, 1, 2],
	["_get_stalker_scene", 2, 1, 2],
	["_get_crawler_scene", 1, 1, 1],
	["_get_sploder_scene", 1, 1, 1],
]

const POOL_F4_HARDER := [
	["_get_swarmer_scene", 2, 2, 4],
	["_get_lurker_scene", 2, 1, 3],
	["_get_stalker_scene", 2, 1, 2],
	["_get_crawler_scene", 2, 1, 2],
	["_get_sploder_scene", 2, 1, 2],
]

const POOL_F5_ELITE := [
	["_get_swarmer_scene", 2, 2, 4],
	["_get_lurker_scene", 2, 2, 3],
	["_get_stalker_scene", 2, 1, 2],
	["_get_crawler_scene", 2, 1, 2],
	["_get_sploder_scene", 2, 1, 2],
	["_get_shadow_lurker_scene", 1, 1, 1],
]

# Spawn positions for different room configurations
const ROOM_CENTER := Vector2(960, 540)
const SPAWN_GRID := [
	Vector2(400, 300), Vector2(1520, 300),
	Vector2(400, 780), Vector2(1520, 780),
	Vector2(600, 540), Vector2(1320, 540),
	Vector2(960, 300), Vector2(960, 780),
]

# Geyser spawn positions — distinct from enemy spawns, biased toward room edges
const GEYSER_SPAWNS := [
	Vector2(400, 300), Vector2(1520, 300),
	Vector2(400, 780), Vector2(1520, 780),
	Vector2(960, 200), Vector2(960, 880),
]

var _rng: RandomNumberGenerator


func _spawn_enemies() -> void:
	var floor_num: int = GameManager.current_floor
	var rtype: String = room_type

	# Chest / shrine have no enemies
	if rtype == "chest" or rtype == "shrine":
		return

	_rng = RandomNumberGenerator.new()
	_rng.randomize()

	_spawn_hazards(rtype, floor_num)
	_spawn_pools(rtype, floor_num)
	_spawn_cracked_floors(rtype, floor_num)

	if rtype == "exit":
		_spawn_exit_room(floor_num)
		return

	var is_elite: bool = (rtype == "combat_elite")

	# Pick pool based on floor and elite status
	var pool: Array = _get_pool(floor_num, is_elite)
	if pool.is_empty():
		# Fallback: easy pool
		pool = POOL_F1_EASY

	# Build enemy list from weighted pool
	var enemies_to_spawn: Array[PackedScene] = []
	var total_enemies: int = _pick_enemy_count(floor_num, is_elite)

	for i in total_enemies:
		var entry: Array = _weighted_pick(pool)
		if entry.is_empty():
			continue
		var getter_name: String = entry[0]
		var scene: PackedScene = call(getter_name)
		if scene:
			enemies_to_spawn.append(scene)

	# Shuffle spawn positions
	var positions: Array = SPAWN_GRID.duplicate()
	positions.shuffle()

	# Spawn enemies at shuffled positions
	for i in enemies_to_spawn.size():
		var pos: Vector2 = positions[i % positions.size()]
		# Add some jitter
		pos += Vector2(_rng.randf_range(-80, 80), _rng.randf_range(-80, 80))
		_spawn_enemy_at(enemies_to_spawn[i], pos)

	# Scale HP for deeper floors (compressed version of old system)
	if floor_num > 3:
		var hp_bonus: float = (floor_num - 3) * 0.15
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.has_method("set_max_hp") or "max_hp" in enemy:
				enemy.max_hp = maxf(enemy.max_hp, enemy.max_hp + hp_bonus)
				enemy.hp = enemy.max_hp


func _spawn_exit_room(floor_num: int) -> void:
	"""Exit room has a guard — light on early floors, tougher later."""
	var pool: Array
	var count: int

	if floor_num <= 2:
		pool = [["_get_swarmer_scene", 3, 2, 3]]
		count = 2
	elif floor_num <= 4:
		pool = POOL_F2_MEDIUM
		count = 3
	elif floor_num <= 6:
		pool = POOL_F4_HARDER
		count = 4
	else:
		pool = POOL_F5_ELITE
		count = 5

	# Boss floors (3, 6, 9) — exit room is the boss fight
	# TODO: spawn boss scene here
	if floor_num % 3 == 0:
		# For now, heavier guard
		count += 2

	var positions: Array[Vector2] = [
		Vector2(700, 400), Vector2(1200, 400),
		Vector2(960, 300), Vector2(700, 700), Vector2(1200, 700),
	]

	for i in count:
		var entry: Array = _weighted_pick(pool)
		var scene: PackedScene = call(entry[0])
		if scene:
			_spawn_enemy_at(scene, positions[i % positions.size()])


func _get_pool(floor_num: int, is_elite: bool) -> Array:
	"""Return the enemy pool for the given floor and difficulty."""

	# Elite rooms on any floor use the next tier
	if is_elite:
		floor_num += 1

	if floor_num <= 1:
		return POOL_F1_EASY
	elif floor_num <= 2:
		return POOL_F2_MEDIUM
	elif floor_num <= 3:
		return POOL_F3_HARD
	elif floor_num <= 5:
		return POOL_F4_HARDER

	return POOL_F5_ELITE


func _pick_enemy_count(floor_num: int, is_elite: bool) -> int:
	var base: int

	if floor_num <= 1:
		base = _rng.randi_range(2, 3)
	elif floor_num <= 2:
		base = _rng.randi_range(2, 4)
	elif floor_num <= 3:
		base = _rng.randi_range(3, 4)
	elif floor_num <= 5:
		base = _rng.randi_range(3, 5)
	else:
		base = _rng.randi_range(4, 6)

	if is_elite:
		base += _rng.randi_range(0, 2)

	return base


func _weighted_pick(pool: Array) -> Array:
	"""Pick an entry from the weighted pool."""
	var total_weight: float = 0.0
	for entry in pool:
		total_weight += entry[1]

	var roll: float = _rng.randf_range(0.0, total_weight)
	var cumulative: float = 0.0
	for entry in pool:
		cumulative += entry[1]
		if roll <= cumulative:
			return entry

	return pool.back() if pool else []


# =============================================================================
# In-Room Hazards
# =============================================================================

const GeyserScene: PackedScene = preload("res://scenes/hazards/shadow_geyser.tscn")
const PoolScene: PackedScene = preload("res://scenes/hazards/shadow_pool.tscn")
const CrackedFloorScene: PackedScene = preload("res://scenes/hazards/cracked_floor.tscn")


func _spawn_hazards(rtype: String, floor_num: int) -> void:
	"""Spawn in-room hazards based on room type and floor depth.
	
	Start introducing geysers at floor 2 to ease players in.
	By floor 4, most combat rooms have at least one.
	"""
	if rtype == "chest" or rtype == "shrine":
		return
	
	if not GeyserScene:
		return
	
	var geyser_count: int = _pick_geyser_count(rtype, floor_num)
	if geyser_count <= 0:
		return
	
	var positions: Array = GEYSER_SPAWNS.duplicate()
	positions.shuffle()
	
	for i in range(mini(geyser_count, positions.size())):
		var pos: Vector2 = positions[i]
		# Add slight offset so geysers don't look grid-aligned
		pos += Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30))
		_spawn_geyser_at(pos)
	
	print("[ROOM] Spawned %d geyser(s) in %s room" % [geyser_count, rtype])


func _pick_geyser_count(rtype: String, floor_num: int) -> int:
	"""How many geysers to place in this room.
	
	- No geysers on floor 1 (learning)
	- 0-1 on floor 2, 3
	- 1-2 on floor 4+
	- Exit rooms get +1
	"""
	if floor_num <= 1:
		return 0
	
	var base: int
	if floor_num <= 3:
		base = _rng.randi_range(0, 1)
	elif floor_num <= 5:
		base = _rng.randi_range(1, 2)
	else:
		base = _rng.randi_range(1, 3)
	
	# Elite rooms and exit rooms have more hazards
	if rtype == "combat_elite" or rtype == "exit":
		base += 1
	
	return mini(base, GEYSER_SPAWNS.size())


func _spawn_geyser_at(pos: Vector2) -> void:
	if not GeyserScene:
		return
	var geyser: Node2D = GeyserScene.instantiate()
	geyser.position = pos
	add_child(geyser)
	print("[ROOM] Placed geyser at %v" % [pos])


# =============================================================================
# Shadow Pools
# =============================================================================

const POOL_SPAWNS := [
	Vector2(500, 350), Vector2(1420, 350),
	Vector2(500, 730), Vector2(1420, 730),
	Vector2(960, 540),
]


func _spawn_pools(rtype: String, floor_num: int) -> void:
	"""Spawn shadow pools in the room.
	
	Pools are permanent area hazards — always present from room activation.
	They don't telegraph, don't get destroyed. Navigate or dodge through.
	Introduced later than geysers since they're always-on pressure.
	"""
	if rtype == "chest" or rtype == "shrine":
		return
	if not PoolScene:
		return
	
	var pool_count: int = _pick_pool_count(rtype, floor_num)
	if pool_count <= 0:
		return
	
	var positions: Array = POOL_SPAWNS.duplicate()
	positions.shuffle()
	
	for i in range(mini(pool_count, positions.size())):
		var pos: Vector2 = positions[i]
		pos += Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40))
		_spawn_pool_at(pos)
	
	print("[ROOM] Spawned %d pool(s) in %s room" % [pool_count, rtype])


func _pick_pool_count(rtype: String, floor_num: int) -> int:
	"""How many pools to place.
	
	Pools are always-on pressure (no telegraph, no destroy), so they
	arrive later than geysers:
	- Floor 1: 0 (pure combat learning)
	- Floors 2-3: 0 (geysers only, pools introduced later)
	- Floors 4-5: 0-1
	- Floors 6+: 1-2
	- Elite/exit: +1
	"""
	if floor_num <= 3:
		return 0
	
	var base: int
	if floor_num <= 5:
		base = _rng.randi_range(0, 1)
	else:
		base = _rng.randi_range(1, 2)
	
	if rtype == "combat_elite" or rtype == "exit":
		base += 1
	
	return mini(base, POOL_SPAWNS.size())


func _spawn_pool_at(pos: Vector2) -> void:
	if not PoolScene:
		return
	var pool: Area2D = PoolScene.instantiate()
	pool.position = pos
	add_child(pool)
	print("[ROOM] Placed pool at %v" % [pos])


# =============================================================================
# Cracked Floor
# =============================================================================

func _spawn_cracked_floors(rtype: String, floor_num: int) -> void:
	"""Spawn cracked floor tiles in the room.
	
	Clusters of cracked tiles in passage areas. Guardians learn to keep moving.
	Cracked floors appear from floor 1 — they're a teaching hazard, not a
	late-game punishment. Low step count, low damage.

	Clusters: each cluster = 1-3 adjacent cracked tiles.
	"""
	if rtype == "chest" or rtype == "shrine":
		return
	if not CrackedFloorScene:
		return
	
	var cluster_count: int = _pick_cracked_cluster_count(rtype, floor_num)
	if cluster_count <= 0:
		return
	
	# Cluster centers — mid-room and narrow passage areas
	var centers := [
		Vector2(960, 600),  # center-ish
		Vector2(600, 540),
		Vector2(1320, 540),
	]
	centers.shuffle()
	
	for c in range(mini(cluster_count, centers.size())):
		var center: Vector2 = centers[c]
		var tiles_in_cluster: int = _rng.randi_range(1, 3)
		for t in range(tiles_in_cluster):
			var offset := Vector2(
				_rng.randf_range(-80, 80),
				_rng.randf_range(-80, 80)
			)
			var pos := center + offset
			pos.x = clampf(pos.x, 300, 1620)
			pos.y = clampf(pos.y, 300, 780)
			_spawn_cracked_floor_at(pos)
	
	print("[ROOM] Spawned %d cracked floor tile(s) in %s room" % [cluster_count, rtype])


func _pick_cracked_cluster_count(rtype: String, floor_num: int) -> int:
	"""How many cracked tile clusters to place.
	
	Cracked floors are a teaching hazard — they're everywhere but forgiving:
	- All floors: 0-1 clusters in combat rooms
	- Elite/exit: 1-2
	"""
	var base: int = _rng.randi_range(0, 1)
	
	if rtype == "combat_elite" or rtype == "exit":
		base += _rng.randi_range(0, 1)
	
	# Floors 5+: slightly more
	if floor_num >= 5:
		base += _rng.randi_range(0, 1)
	
	return mini(base, 3)


func _spawn_cracked_floor_at(pos: Vector2) -> void:
	if not CrackedFloorScene:
		return
	var cracked: Area2D = CrackedFloorScene.instantiate()
	cracked.position = pos
	add_child(cracked)
	print("[ROOM] Placed cracked floor at %v" % [pos])
