extends RoomBase
## RoomTemplate - The single prototype room.
## Spawns enemies based on current floor depth using the new archetype system.
##
## Enemy composition:
##   Early rooms:  Swarmers only — learn the basic threat
##   Mid rooms:    Swarmers + 1 Stalker — introduces the companion threat
##   Late rooms:   More swarmers + more stalkers + old lurker as elite stand-in
##   Deep floors:  Volume scales up

func _spawn_enemies() -> void:
	var floor_num: int = GameManager.current_floor
	var room_type: String = FloorManager.get_current_room_type()

	# Chest and shrine rooms have no enemies
	if room_type == "chest" or room_type == "shrine" or room_type == "exit":
		has_chest = (room_type == "chest")
		has_shrine = (room_type == "shrine")
		return

	# Enemy count + composition based on floor depth
	var is_elite_room: bool = (room_type == "combat_elite")
	var progress: float = clampf(float(floor_num - 1) / 10.0, 0.0, 1.0)

	if floor_num == 1:
		# Floor 1: two swarmers, no stalkers — onboarding
		_spawn_enemy_at(_swarmer_scene, Vector2(700, 350))
		_spawn_enemy_at(_swarmer_scene, Vector2(1200, 700))

	elif floor_num <= 3:
		# Early floors: swarmers + first stalker introduction
		_spawn_enemy_at(_swarmer_scene, Vector2(700, 350))
		_spawn_enemy_at(_swarmer_scene, Vector2(1200, 700))
		if is_elite_room or floor_num == 3:
			_spawn_enemy_at(_stalker_scene, Vector2(960, 300))

	elif floor_num <= 6:
		# Mid floors: swarmers + stalker combo
		_spawn_enemy_at(_swarmer_scene, Vector2(600, 400))
		_spawn_enemy_at(_swarmer_scene, Vector2(1300, 400))
		_spawn_enemy_at(_stalker_scene, Vector2(960, 700))
		if is_elite_room:
			_spawn_enemy_at(_swarmer_scene, Vector2(960, 300))
			_spawn_enemy_at(_shadow_lurker_scene, Vector2(750, 600))  # Lurker as elite

	else:
		# Late floors: high pressure
		_spawn_enemy_at(_swarmer_scene, Vector2(600, 350))
		_spawn_enemy_at(_swarmer_scene, Vector2(1300, 350))
		_spawn_enemy_at(_swarmer_scene, Vector2(960, 300))
		_spawn_enemy_at(_stalker_scene, Vector2(700, 650))
		_spawn_enemy_at(_stalker_scene, Vector2(1200, 650))
		if is_elite_room:
			_spawn_enemy_at(_shadow_lurker_scene, Vector2(960, 500))

	# Scale HP slightly with floor depth (behaviour stays primary threat)
	var hp_bonus: float = (floor_num - 1) * 0.3
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.max_hp = maxf(enemy.max_hp, enemy.max_hp + hp_bonus)
		enemy.hp = enemy.max_hp
