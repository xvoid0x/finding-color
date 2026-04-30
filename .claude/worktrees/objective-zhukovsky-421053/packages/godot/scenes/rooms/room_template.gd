extends RoomBase
## RoomTemplate - The single prototype room.
## Spawns enemies based on current floor depth.

func _spawn_enemies() -> void:
	var floor_num: int = GameManager.current_floor
	var rtype: String = room_type

	# Chest / shrine / exit have no enemies
	if rtype == "chest" or rtype == "shrine":
		return
	if rtype == "exit":
		# Exit room: light guard
		_spawn_enemy_at(_get_shadow_walker_scene(), Vector2(700, 400))
		_spawn_enemy_at(_get_shadow_walker_scene(), Vector2(1200, 400))
		return

	var is_elite: bool = (rtype == "combat_elite")
	var progress: float = clampf(float(floor_num - 1) / 10.0, 0.0, 1.0)

	if floor_num == 1:
		_spawn_enemy_at(_get_swarmer_scene(), Vector2(700, 350))
		_spawn_enemy_at(_get_swarmer_scene(), Vector2(1200, 700))

	elif floor_num <= 3:
		_spawn_enemy_at(_get_swarmer_scene(), Vector2(700, 350))
		_spawn_enemy_at(_get_swarmer_scene(), Vector2(1200, 700))
		if is_elite or floor_num == 3:
			_spawn_enemy_at(_get_stalker_scene(), Vector2(960, 300))

	elif floor_num <= 6:
		_spawn_enemy_at(_get_swarmer_scene(), Vector2(600, 400))
		_spawn_enemy_at(_get_swarmer_scene(), Vector2(1300, 400))
		_spawn_enemy_at(_get_stalker_scene(), Vector2(960, 700))
		if is_elite:
			_spawn_enemy_at(_get_swarmer_scene(), Vector2(960, 300))
			_spawn_enemy_at(_get_shadow_lurker_scene(), Vector2(750, 600))

	else:
		_spawn_enemy_at(_get_swarmer_scene(), Vector2(600, 350))
		_spawn_enemy_at(_get_swarmer_scene(), Vector2(1300, 350))
		_spawn_enemy_at(_get_swarmer_scene(), Vector2(960, 300))
		_spawn_enemy_at(_get_stalker_scene(), Vector2(700, 650))
		_spawn_enemy_at(_get_stalker_scene(), Vector2(1200, 650))
		if is_elite:
			_spawn_enemy_at(_get_shadow_lurker_scene(), Vector2(960, 500))

	# Scale HP with depth
	var hp_bonus: float = (floor_num - 1) * 0.3
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("set_max_hp"):
			enemy.max_hp = maxf(enemy.max_hp, enemy.max_hp + hp_bonus)
			enemy.hp = enemy.max_hp
