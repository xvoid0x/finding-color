extends Node
## AiRunEngine — Headless end-to-end run harness + simulation engine.
##
## **This is an autoload.** Registered in project.godot.
## Auto-starts when headless flag is detected, or triggered via MCP.
##
## Modes:
##   Smoke test:  title → start_run → floor 1 → clear → exit →
##                upgrade → floor 2 → verify → exit 0
##   Simulation:  run N floors with deterministic seed, track stats
##
## Usage (headless CI):
##   godot --headless --path packages/godot --ai-smoke
## Usage (headless simulation):
##   godot --headless --path packages/godot --ai-simulate --ai-floors 5 --ai-seed 42
##
## Exit codes: 0=pass, 1=fail

enum RunMode { NONE, SMOKE, SIMULATE }

var mode: RunMode = RunMode.NONE
var sim_floors: int = 3
var sim_seed: int = 0

var _started: bool = false
var _step_log: Array[String] = []
var _errors: Array[String] = []
var _floor_history: Array[Dictionary] = []
var _sim_stats: Dictionary = {}
var _current_sim_floor: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_cli_args()
	if mode == RunMode.NONE:
		return  # Normal gameplay, no AI engine needed

	_started = true

	_log("=== AI Run Engine v2 (autoload) ===")
	_log("Mode: %s" % ("SMOKE" if mode == RunMode.SMOKE else "SIMULATE (%d floors, seed %d)" % [sim_floors, sim_seed]))
	_log("")

	RoomBase.HEADLESS_RUN = true
	if sim_seed > 0:
		seed(sim_seed)
		_log("  Seed: %d" % sim_seed)

	# Start one frame later to let all autoloads initialize
	await get_tree().process_frame
	_run_engine()


func _parse_cli_args() -> void:
	var args := OS.get_cmdline_args()
	for i in args.size():
		match args[i]:
			"--ai-smoke":    mode = RunMode.SMOKE
			"--ai-simulate": mode = RunMode.SIMULATE
			"--ai-floors":
				if i + 1 < args.size():
					sim_floors = maxi(1, int(args[i + 1]))
			"--ai-seed":
				if i + 1 < args.size():
					sim_seed = int(args[i + 1])


# =============================================================================
# Main Coroutine
# =============================================================================

func _run_engine() -> void:
	# START_RUN
	var ok := await _phase_start_run()
	if not ok: return

	while true:
		ok = await _phase_verify_floor()
		if not ok: return

		ok = await _phase_clear_all_rooms()
		if not ok: return

		ok = await _phase_exit_and_upgrade()
		if not ok: return

		if mode == RunMode.SMOKE:
			# Advance to floor 2 before verifying
			ok = await _phase_advance_floor()
			if not ok: return
			_current_sim_floor = GameManager.current_floor
			await _phase_verify_floor_2()
			return

		if _current_sim_floor >= sim_floors:
			_sim_stats = GameManager.get_stats()
			_sim_stats["floors_completed"] = sim_floors
			_sim_stats["upgrades_collected"] = GameManager.upgrades.keys()
			_sim_stats["final_hp"] = GameManager.guardian_hearts
			_sim_stats["max_hp"] = GameManager.guardian_max_hearts
			GameManager.end_run("complete")
			await get_tree().process_frame
			_print_sim_summary()
			_print_summary(true)
			get_tree().quit(0)
			return

		ok = await _phase_advance_floor()
		if not ok: return

		_current_sim_floor = GameManager.current_floor


# =============================================================================
# Phases
# =============================================================================

func _phase_start_run() -> bool:
	_log("→ START_RUN")
	GameManager.start_run()
	_log("  current_floor = %d, run_active = %s" % [GameManager.current_floor, GameManager.run_active])
	assert_that(GameManager.run_active, "run_active false")
	assert_that(GameManager.current_floor == 1, "not floor 1")

	await _wait_for_group("floor_hub")
	await get_tree().process_frame
	await get_tree().process_frame
	_kill_all_enemies()
	_log("  ✓ FloorHub loaded, enemies cleared")
	_current_sim_floor = 1
	return true


func _phase_verify_floor() -> bool:
	_log("→ VERIFY FLOOR %d" % GameManager.current_floor)
	var map := FloorManager.current_map
	assert_that(not map.is_empty(), "map empty")

	var rc: int = map.get("room_count", 0)
	var sr: int = map.get("start_room", -1)
	var er: int = map.get("exit_room", -1)
	var cxns: Dictionary = map.get("connections", {})

	_log("  rooms=%d start=%d exit=%d" % [rc, sr, er])
	assert_that(rc >= 3, "too few rooms: %d" % rc)
	assert_that(sr != er, "start=exit")
	assert_that(_is_connected(cxns, rc), "rooms disconnected")
	assert_that(get_tree().get_first_node_in_group("guardian") != null, "guardian missing")

	if mode == RunMode.SIMULATE:
		_floor_history.append({"floor": GameManager.current_floor, "rooms": rc,
			"hp": GameManager.guardian_hearts, "max_hp": GameManager.guardian_max_hearts,
			"upgrades": GameManager.upgrades.keys()})
	return true


func _phase_clear_all_rooms() -> bool:
	_log("→ CLEAR ROOMS")
	_kill_all_enemies()
	await get_tree().process_frame
	await get_tree().process_frame
	for rid in FloorManager.current_map.room_types:
		if str(FloorManager.current_map.room_types[rid]) in ["combat", "combat_elite", "exit", "start"]:
			if not FloorManager.is_room_cleared(rid):
				FloorManager.on_room_cleared(rid)
	_log("  cleared=%s" % str(FloorManager.cleared_rooms))
	return true


func _phase_exit_and_upgrade() -> bool:
	_log("→ EXIT + UPGRADE")
	GameManager.exit_room()
	await _wait_for_group("upgrade_screen")
	await get_tree().process_frame
	await get_tree().process_frame

	var pool := ["warm_blanket", "favourite_song", "steady_breathing",
		"birthday_candle", "smell_of_rain", "someones_hand"]
	var idx := (_current_sim_floor - 1) % pool.size() if mode == RunMode.SIMULATE else 0
	var uid: String = pool[idx]
	_log("  upgrade: %s" % uid)
	GameManager.apply_upgrade_to_state(uid)
	assert_that(GameManager.has_upgrade(uid), "upgrade not applied: %s" % uid)
	return true


func _phase_advance_floor() -> bool:
	var nxt := GameManager.current_floor + 1
	_log("→ ADVANCE to floor %d" % nxt)
	GameManager.advance_floor()
	await _wait_for_group("floor_hub")
	await get_tree().process_frame
	await get_tree().process_frame
	_kill_all_enemies()
	assert_that(GameManager.current_floor == nxt, "floor mismatch: %d != %d" % [GameManager.current_floor, nxt])
	return true


func _phase_verify_floor_2() -> bool:
	_log("→ SMOKE: VERIFY FLOOR 2")
	assert_that(GameManager.current_floor == 2, "not floor 2")
	assert_that(not FloorManager.current_map.is_empty(), "map empty")
	assert_that(GameManager.has_upgrade("warm_blanket"), "warm_blanket missing")
	assert_that(GameManager.guardian_max_hearts >= 6.0, "max HP too low")
	_log("  ✓ PASS")
	_print_summary(true)
	get_tree().quit(0)
	return true


# =============================================================================
# Helpers
# =============================================================================

func _wait_for_group(group_name: String) -> void:
	for _i in 300:
		if not get_tree().get_nodes_in_group(group_name).is_empty():
			return
		await get_tree().process_frame
	_fail("timeout waiting for group '%s'" % group_name)


func _kill_all_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("take_damage"):
			e.take_damage(9999.0)
			GameManager.stat_enemies_killed += 1


func _is_connected(cxns: Dictionary, total: int) -> bool:
	var v: Dictionary = {}
	var q: Array[int] = [0]
	v[0] = true
	while not q.is_empty():
		for nb in cxns.get(q.pop_front(), []):
			if not v.has(nb):
				v[nb] = true
				q.append(nb)
	return v.size() == total


func assert_that(cond: bool, msg: String) -> void:
	if not cond: _fail(msg)


func _fail(reason: String) -> bool:
	_log("❌ FAIL: %s" % reason)
	_errors.append(reason)
	_print_summary(false)
	get_tree().quit(1)
	return false


# =============================================================================
# Logging
# =============================================================================

func _log(msg: String) -> void:
	var e := "[AIRun] %s" % msg
	_step_log.append(e)
	print(e)


func _print_summary(passed: bool) -> void:
	_log("")
	_log("══════════════════════════")
	if passed: _log("  ✅ RUN PASSED")
	else: _log("  ❌ RUN FAILED")
	for err in _errors: _log("    • %s" % err)
	_log("  Steps: %d | Errors: %d" % [_step_log.size(), _errors.size()])
	_log("══════════════════════════")


func _print_sim_summary() -> void:
	_log("")
	_log("─── Simulation Results ───")
	_log("  Floors: %d" % _sim_stats.get("floors_completed", 0))
	_log("  HP: %.1f/%.1f" % [_sim_stats.get("final_hp", 0.0), _sim_stats.get("max_hp", 5.0)])
	_log("  Upgrades: %s" % str(_sim_stats.get("upgrades_collected", [])))
	for fh in _floor_history:
		_log("    Floor %d: %d rooms, HP %.1f/%.1f, upgrades=%s" % [
			fh.floor, fh.rooms, fh.hp, fh.max_hp, str(fh.upgrades)])