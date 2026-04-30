extends Node
## AiRunEngine — Headless end-to-end run harness + simulation engine.
##
## Coroutine-driven: each phase is an awaitable function. No _process polling.
##
## Modes:
##   • Smoke test: title → start_run → floor 1 → clear → exit →
##     upgrade → floor 2 → verify → exit 0
##   • Simulation: run N floors with deterministic seed, track stats
##
## Usage (headless CI):
##   godot --headless --path packages/godot tools/ai_run_engine.tscn
## Usage (headless simulation):
##   godot --headless --path packages/godot tools/ai_run_engine.tscn \
##     --ai-mode simulate --ai-floors 5 --ai-seed 42
##
## Exit codes: 0=pass, 1=fail, 2=crash

enum RunMode { SMOKE, SIMULATE }

# --- Configuration ---
var mode: RunMode = RunMode.SMOKE
var sim_floors: int = 3
var sim_seed: int = 0

# --- State ---
var _step_log: Array[String] = []
var _errors: Array[String] = []
var _warnings: Array[String] = []
var _floor_history: Array[Dictionary] = []
var _sim_stats: Dictionary = {}

# --- Track which floor we're on (for simulation loop) ---
var _current_sim_floor: int = 0


## Cached reference to SceneTree (persists through scene changes)
var _engine_tree: SceneTree


func _ready() -> void:
	_engine_tree = get_tree()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_cli_args()
	_log("=== AI Run Engine v2 ===")
	_log("Mode: %s" % ("SMOKE" if mode == RunMode.SMOKE else "SIMULATE (%d floors, seed %d)" % [sim_floors, sim_seed]))
	_log("")

	# Set headless flag so enemies don't damage the guardian during runs
	RoomBase.HEADLESS_RUN = true

	if sim_seed > 0:
		seed(sim_seed)
		_log("  Seed: %d" % sim_seed)

	# Start the coroutine
	_run_engine()


func _parse_cli_args() -> void:
	var args := OS.get_cmdline_args()
	for i in args.size():
		match args[i]:
			"--ai-mode":
				if i + 1 < args.size():
					match args[i + 1]:
						"simulate": mode = RunMode.SIMULATE
			"--ai-floors":
				if i + 1 < args.size():
					sim_floors = maxi(1, int(args[i + 1]))
			"--ai-seed":
				if i + 1 < args.size():
					sim_seed = int(args[i + 1])


# =============================================================================
# Main Coroutine — linear, readable, no _process state machine
# =============================================================================

func _run_engine() -> void:
	# Phase: START_RUN
	var ok := await _phase_start_run()
	if not ok: return

	# Phase: VERIFY FLOOR (repeats for simulation)
	while true:
		ok = await _phase_verify_floor()
		if not ok: return

		ok = await _phase_clear_all_rooms()
		if not ok: return

		# TRIGGER EXIT → UPGRADE
		ok = await _phase_exit_and_upgrade()
		if not ok: return

		# CHECK DONE
		if mode == RunMode.SMOKE:
			ok = await _phase_verify_floor_2()
			return  # _phase_verify_floor_2 exits the process

		if mode == RunMode.SIMULATE and _current_sim_floor >= sim_floors:
			_sim_stats = GameManager.get_stats()
			_sim_stats["floors_completed"] = sim_floors
			_sim_stats["upgrades_collected"] = GameManager.upgrades.keys()
			_sim_stats["final_hp"] = GameManager.guardian_hearts
			_sim_stats["max_hp"] = GameManager.guardian_max_hearts
			GameManager.end_run("complete")
			await _engine_tree.process_frame
			_print_sim_summary()
			_print_summary(true)
			_engine_tree.quit(0)
			return

		# ADVANCE FLOOR
		ok = await _phase_advance_floor()
		if not ok: return

		_current_sim_floor = GameManager.current_floor


# =============================================================================
# Phase: START_RUN
# =============================================================================

func _phase_start_run() -> bool:
	_log("→ START_RUN")
	_log("  Calling GameManager.start_run()")
	GameManager.start_run()

	_log("  current_floor = %d" % GameManager.current_floor)
	_log("  run_active = %s" % GameManager.run_active)

	if not GameManager.run_active:
		return _fail("run_active is false")
	if GameManager.current_floor != 1:
		return _fail("current_floor should be 1, got %d" % GameManager.current_floor)

	_log("  ✓ Run started — waiting for FloorHub scene...")

	# Wait for scene to actually change (call_deferred means it hasn't happened yet)
	await _wait_for_scene("floor_hub")

	_log("  ✓ FloorHub loaded")

	# Wait one more frame for FloorHub._ready() to finish spawning enemies
	await _engine_tree.process_frame
	await _engine_tree.process_frame

	# Kill all enemies now before they get a physics tick
	_kill_all_enemies()
	_log("  ✓ Enemies cleared from start room")

	_current_sim_floor = 1
	return true


# =============================================================================
# Phase: VERIFY FLOOR
# =============================================================================

func _phase_verify_floor() -> bool:
	_log("→ VERIFY FLOOR %d" % GameManager.current_floor)

	var map: Dictionary = FloorManager.current_map
	if map.is_empty():
		return _fail("FloorManager.current_map is empty")

	var room_count: int = map.get("room_count", 0)
	var start_room: int = map.get("start_room", -1)
	var exit_room: int = map.get("exit_room", -1)
	var connections: Dictionary = map.get("connections", {})
	var room_types: Dictionary = map.get("room_types", {})

	_log("  room_count = %d, start=%d, exit=%d" % [room_count, start_room, exit_room])
	_log("  room_types = %s" % str(room_types))

	var min_rooms := 4 if mode == RunMode.SIMULATE and GameManager.current_floor <= 3 else 3
	if room_count < min_rooms:
		return _fail("room_count too low: %d (min %d)" % [room_count, min_rooms])
	if start_room < 0 or exit_room < 0:
		return _fail("invalid start/exit room IDs")
	if start_room == exit_room:
		return _fail("start and exit room are the same")

	# BFS: all rooms connected
	var visited: Dictionary = {}
	var queue: Array[int] = [start_room]
	visited[start_room] = true
	while not queue.is_empty():
		var rid: int = queue.pop_front()
		for nb in connections.get(rid, []):
			if not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	if visited.size() != room_count:
		return _fail("Not all rooms connected: %d / %d" % [visited.size(), room_count])

	_log("  ✓ All %d rooms connected" % room_count)

	# Verify entities exist
	if not _engine_tree.get_first_node_in_group("guardian"):
		return _fail("Guardian missing")
	if not _engine_tree.get_first_node_in_group("companion"):
		return _fail("Companion missing")
	_log("  ✓ Guardian + Companion present")

	# Record for simulation
	if mode == RunMode.SIMULATE:
		_floor_history.append({
			"floor": GameManager.current_floor,
			"rooms": room_count,
			"room_types": room_types.duplicate(true),
			"hp": GameManager.guardian_hearts,
			"max_hp": GameManager.guardian_max_hearts,
			"upgrades": GameManager.upgrades.keys(),
		})

	return true


# =============================================================================
# Phase: CLEAR ALL ROOMS
# =============================================================================

func _phase_clear_all_rooms() -> bool:
	_log("→ CLEAR ROOMS")

	# Force-kill any remaining enemies
	_kill_all_enemies()
	await _engine_tree.process_frame
	await _engine_tree.process_frame

	var map: Dictionary = FloorManager.current_map
	for rid in map.room_types:
		var rtype: String = map.room_types[rid]
		if rtype in ["combat", "combat_elite", "exit", "start"]:
			if not FloorManager.is_room_cleared(rid):
				FloorManager.on_room_cleared(rid)

	_log("  Cleared rooms: %s" % str(FloorManager.cleared_rooms))
	_log("  ✓ All combat rooms cleared")
	return true


# =============================================================================
# Phase: EXIT & UPGRADE
# =============================================================================

func _phase_exit_and_upgrade() -> bool:
	_log("→ EXIT ROOM")
	GameManager.exit_room()

	_log("  Waiting for upgrade screen...")
	await _wait_for_scene("upgrade_screen")
	_log("  ✓ Upgrade screen loaded")

	# Give the upgrade screen a frame to build cards
	await _engine_tree.process_frame
	await _engine_tree.process_frame

	# Pick upgrade (cycle through pool in simulation, use warm_blanket in smoke)
	var pool := ["warm_blanket", "favourite_song", "steady_breathing",
		"birthday_candle", "smell_of_rain", "someones_hand"]
	var idx: int = (_current_sim_floor - 1) % pool.size() if mode == RunMode.SIMULATE else 0
	var uid: String = pool[idx]
	_log("  Applying upgrade: %s" % uid)
	GameManager.apply_upgrade_to_state(uid)

	if not GameManager.has_upgrade(uid):
		return _fail("Upgrade '%s' not applied" % uid)

	_log("  ✓ Upgrade applied")
	return true


# =============================================================================
# Phase: ADVANCE FLOOR
# =============================================================================

func _phase_advance_floor() -> bool:
	var next := GameManager.current_floor + 1
	_log("→ ADVANCE to floor %d" % next)
	GameManager.advance_floor()

	await _wait_for_scene("floor_hub")
	await _engine_tree.process_frame
	await _engine_tree.process_frame

	# Kill enemies that spawned in the new floor's start room
	_kill_all_enemies()

	if GameManager.current_floor != next:
		return _fail("Expected floor %d, got %d" % [next, GameManager.current_floor])

	_log("  ✓ Floor %d loaded" % next)
	return true


# =============================================================================
# Phase: SMOKE TEST — VERIFY FLOOR 2
# =============================================================================

func _phase_verify_floor_2() -> bool:
	_log("→ SMOKE: VERIFY FLOOR 2")

	if GameManager.current_floor != 2:
		return _fail("Expected floor 2, got %d" % GameManager.current_floor)

	var map: Dictionary = FloorManager.current_map
	if map.is_empty():
		return _fail("Floor 2 map is empty")

	_log("  room_count = %d" % map.get("room_count", 0))
	_log("  HP: %.1f / %.1f" % [GameManager.guardian_hearts, GameManager.guardian_max_hearts])
	_log("  upgrades: %s" % str(GameManager.upgrades.keys()))

	if not GameManager.has_upgrade("warm_blanket"):
		return _fail("warm_blanket not persisted")
	if GameManager.guardian_max_hearts < 6.0:
		return _fail("Max hearts too low: %.1f" % GameManager.guardian_max_hearts)
	if not _engine_tree.get_first_node_in_group("guardian"):
		return _fail("Guardian missing on floor 2")

	_log("  ✓ Floor 2 verified — PASS")
	_print_summary(true)
	_engine_tree.quit(0)
	return true


# =============================================================================
# Helpers
# =============================================================================

func _wait_for_scene(hint: String) -> void:
	"""Wait until the expected scene type appears in the tree."""
	# Group check is the most reliable cross-scene detection
	var group_name: String
	match hint:
		"floor_hub":       group_name = "floor_hub"
		"upgrade_screen":  group_name = "upgrade_screen"
		_:                 group_name = hint
	
	for _i in 300:
		# Check if a node with this script hint exists in the tree
		var cs := _engine_tree.current_scene
		if cs and _tree_contains(cs, hint):
			return
		# Also check the group
		var nodes := _engine_tree.get_nodes_in_group(group_name)
		if not nodes.is_empty():
			return
		await _engine_tree.process_frame
	
	_fail("Timeout waiting for scene '%s'" % hint)


func _scene_contains(hint: String) -> bool:
	var root := _engine_tree.current_scene
	if not root:
		return false
	return _tree_contains(root, hint)


func _tree_contains(node: Node, hint: String) -> bool:
	var script: Script = node.get_script()
	if script and script.resource_path.contains(hint):
		return true
	for child in node.get_children():
		if _tree_contains(child, hint):
			return true
	return false


func _kill_all_enemies() -> void:
	for enemy in _engine_tree.get_nodes_in_group("enemies"):
		if enemy.has_method("take_damage"):
			enemy.take_damage(9999.0)
			GameManager.stat_enemies_killed += 1


# =============================================================================
# Logging & Results
# =============================================================================

func _fail(reason: String) -> bool:
	_log("❌ FAIL: %s" % reason)
	_errors.append(reason)
	_print_summary(false)
	_engine_tree.quit(1)
	return false


func _log(msg: String) -> void:
	var entry := "[AIRun] %s" % msg
	_step_log.append(entry)
	print(entry)


func _print_summary(passed: bool) -> void:
	_log("")
	_log("═══════════════════════════════════════")
	if passed:
		_log("  ✅ RUN PASSED")
	else:
		_log("  ❌ RUN FAILED")
		for err in _errors:
			_log("    • %s" % err)
	if not _warnings.is_empty():
		for w in _warnings:
			_log("  ⚠️  %s" % w)
	_log("  Steps: %d | Errors: %d" % [_step_log.size(), _errors.size()])
	_log("═══════════════════════════════════════")


func _print_sim_summary() -> void:
	_log("")
	_log("─── Simulation Results ───")
	_log("  Floors: %d" % _sim_stats.get("floors_completed", 0))
	_log("  Final HP: %.1f / %.1f" % [_sim_stats.get("final_hp", 0.0), _sim_stats.get("max_hp", 5.0)])
	_log("  Upgrades: %s" % str(_sim_stats.get("upgrades_collected", [])))
	_log("  Enemies killed: %d" % _sim_stats.get("enemies_killed", 0))
	_log("  Floor history:")
	for fh in _floor_history:
		_log("    Floor %d: %d rooms, HP %.1f/%.1f, upgrades=%s" % [
			fh.floor, fh.rooms, fh.hp, fh.max_hp, str(fh.upgrades)
		])