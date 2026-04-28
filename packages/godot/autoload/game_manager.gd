extends Node
## GameManager - Run state, floor tracking, time scale control.

# --- Run State ---
var current_floor: int = 0
var run_active: bool = false
var rooms_cleared_this_floor: int = 0
var last_run_cause: String = "death"  # Persists across scene change for end_screen

# --- Upgrades (active this run) ---
# Each entry: upgrade_id -> true (flag) or numeric value (stack)
var upgrades: Dictionary = {}  # e.g. { "favourite_song": true, "someones_hand": true }

func has_upgrade(id: String) -> bool:
	return upgrades.get(id, false)

func apply_upgrade_to_state(id: String) -> void:
	"""Called by UpgradeScreen after card selection. Handles immediate stat changes."""
	match id:
		"warm_blanket":
			add_max_hearts(1.0)
		"steady_breathing":
			# Ghost heart: +1 temporary heart that absorbs one hit
			var guardian := get_tree().get_first_node_in_group("guardian")
			if guardian and guardian.has_method("add_ghost_heart"):
				guardian.add_ghost_heart()
		_:
			pass  # Flagged upgrades are checked at runtime by their systems
	upgrades[id] = true
	print("[UPGRADE] Applied: ", id, " | active: ", upgrades.keys())


func get_rooms_per_floor() -> int:
	"""Rooms per floor scales with depth. Deeper = longer floors."""
	if current_floor <= 3:
		return 3
	elif current_floor <= 6:
		return 4
	elif current_floor <= 10:
		return 5
	else:
		return 6

# --- Guardian State ---
var guardian_hearts: float = 5.0
var guardian_max_hearts: float = 5.0

# --- Dreamer (phone player) ---
var dreamer_fragments: int = 0

# --- Stats (tracked for end screen) ---
var stat_enemies_killed: int = 0
var stat_hearts_lost: float = 0.0
var stat_chests_opened: int = 0
var stat_pots_smashed: int = 0
var stat_phone_events_triggered: int = 0
var stat_phone_events_landed: int = 0
var stat_floors_reached: int = 0

# --- Time Scale ---
var _slow_mo_active: bool = false
var _slow_mo_timer: float = 0.0
const SLOW_MO_SCALE: float = 0.25
const REAL_TIME_SCALE: float = 1.0


var _state_push_timer: float = 0.0
const STATE_PUSH_INTERVAL: float = 2.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.guardian_damaged.connect(_on_guardian_damaged)
	EventBus.guardian_healed.connect(_on_guardian_healed)
	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.phone_event_triggered.connect(_on_phone_event_triggered)
	EventBus.phone_event_completed.connect(_on_phone_event_completed)


func _process(delta: float) -> void:
	# Slow-mo uses real delta (unscaled) so it times out correctly
	if _slow_mo_active:
		_slow_mo_timer -= delta
		if _slow_mo_timer <= 0.0:
			end_slow_mo()

	# Periodic state push to phone
	if run_active:
		_state_push_timer -= delta
		if _state_push_timer <= 0.0:
			_state_push_timer = STATE_PUSH_INTERVAL
			PhoneManager.push_game_state()


# --- Run Control ---

func start_run() -> void:
	current_floor = 1
	rooms_cleared_this_floor = 0
	run_active = true
	guardian_hearts = guardian_max_hearts
	guardian_max_hearts = 5.0  # Reset max hearts for new run
	guardian_hearts = guardian_max_hearts
	upgrades.clear()
	dreamer_fragments = 0
	_reset_stats()
	EventBus.run_started.emit()
	print("[GAME] Run started — floor 1")
	# Generate the first floor map
	FloorManager.generate_floor(current_floor)
	# Load floor hub (new multi-room floor scene)
	# Falls back to room_template if floor_hub doesn't exist yet
	var floor_scene := "res://scenes/floors/floor_hub.tscn"
	if not ResourceLoader.exists(floor_scene):
		floor_scene = "res://scenes/rooms/room_template.tscn"
	get_tree().call_deferred("change_scene_to_file", floor_scene)


func end_run(cause: String) -> void:
	run_active = false
	last_run_cause = cause
	stat_floors_reached = current_floor
	print("[GAME] Run ended — cause: ", cause, " | floor: ", current_floor)
	EventBus.run_ended.emit(cause, current_floor)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/end_screen.tscn")


# --- Guardian Health ---

func damage_guardian(amount: float, source: String = "enemy") -> void:
	if not run_active:
		return
	guardian_hearts = maxf(0.0, guardian_hearts - amount)
	stat_hearts_lost += amount
	EventBus.guardian_damaged.emit(amount, source)
	EventBus.guardian_hearts_changed.emit(guardian_hearts, guardian_max_hearts)
	if guardian_hearts <= 0.0:
		EventBus.guardian_died.emit()
		end_run("death")


func heal_guardian(amount: float) -> void:
	guardian_hearts = minf(guardian_max_hearts, guardian_hearts + amount)
	EventBus.guardian_healed.emit(amount)
	EventBus.guardian_hearts_changed.emit(guardian_hearts, guardian_max_hearts)


func add_max_hearts(amount: float) -> void:
	guardian_max_hearts += amount
	guardian_hearts = minf(guardian_hearts + amount, guardian_max_hearts)
	EventBus.guardian_hearts_changed.emit(guardian_hearts, guardian_max_hearts)


# --- Floor / Room Progression ---

func _on_room_cleared() -> void:
	rooms_cleared_this_floor += 1
	# Someone's Hand upgrade: passive +0.1 heart regen on room clear (solo feel)
	if has_upgrade("someones_hand"):
		heal_guardian(0.1)


func exit_room() -> void:
	"""Called when guardian walks through the exit door (exit room type).
	This now means the whole floor is done — go to upgrade screen."""
	print("[GAME] Floor ", current_floor, " exit reached — going to upgrade screen")
	EventBus.floor_cleared.emit(current_floor)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/upgrade_screen.tscn")


func advance_floor() -> void:
	current_floor += 1
	rooms_cleared_this_floor = 0
	print("[GAME] Advancing to floor ", current_floor)
	# Generate a new floor map for the next floor
	FloorManager.generate_floor(current_floor)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/floors/floor_hub.tscn")


# --- Slow Mo ---

func trigger_slow_mo(duration: float) -> void:
	if _slow_mo_active:
		_slow_mo_timer = maxf(_slow_mo_timer, duration)
		return
	_slow_mo_active = true
	_slow_mo_timer = duration
	# If hitstop is active, update its restore target — don't fight it
	if HitstopManager._active:
		HitstopManager._restore_scale = SLOW_MO_SCALE
	else:
		Engine.time_scale = SLOW_MO_SCALE
	EventBus.slow_mo_started.emit(duration)


func end_slow_mo() -> void:
	_slow_mo_active = false
	_slow_mo_timer = 0.0
	# If hitstop is mid-freeze, update its restore target to 1.0
	# so when it finishes it restores to normal speed, not slow-mo.
	if HitstopManager._active:
		HitstopManager._restore_scale = REAL_TIME_SCALE
	else:
		Engine.time_scale = REAL_TIME_SCALE
	EventBus.slow_mo_ended.emit()


# --- Stats ---

func _reset_stats() -> void:
	stat_enemies_killed = 0
	stat_hearts_lost = 0.0
	stat_chests_opened = 0
	stat_pots_smashed = 0
	stat_phone_events_triggered = 0
	stat_phone_events_landed = 0
	stat_floors_reached = 0


# --- Debug (debug builds only) ---

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			# Force trigger heal event (bypasses phone_player_count check)
			if not PhoneManager._event_active:
				PhoneManager.trigger_event("heal", 5.0)
				print("[DEBUG] Heal event triggered")
			else:
				print("[DEBUG] Event already active: ", PhoneManager._active_event)
		KEY_2:
			# Simulate perfect phone response to active event (3/3)
			if PhoneManager._event_active:
				print("[DEBUG] Resolving event: ", PhoneManager._active_event, " with perfect score")
				PhoneManager.receive_event_response(0, PhoneManager._active_event, 3, 3)
			else:
				print("[DEBUG] No active event to resolve")
		KEY_3:
			# Trigger chest: anchor companion to nearest chest
			var companion := get_tree().get_first_node_in_group("companion")
			var chest := get_tree().get_first_node_in_group("chests")
			if companion and chest and companion.has_method("anchor_to"):
				companion.anchor_to(chest)
				print("[DEBUG] Chest unlock event triggered")
			else:
				print("[DEBUG] No companion or chest found in scene")
		KEY_4:
			# Force-clear current room (kill all enemies, unlock door)
			print("[DEBUG] Force-clearing room")
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if enemy.has_method("take_damage"):
					enemy.take_damage(9999.0)
		KEY_5:
			# Force exit room (as if walking through door)
			print("[DEBUG] Force exiting room")
			exit_room()
		KEY_6:
			# Print current floor map to console
			print("[DEBUG] Floor map: ", JSON.stringify(FloorManager.current_map, "  "))
			print("[DEBUG] Current room: ", FloorManager.current_room_id)
			print("[DEBUG] Discovered: ", FloorManager.discovered_rooms)
			print("[DEBUG] Cleared: ", FloorManager.cleared_rooms)


func _on_guardian_damaged(_amount: float, _source: String) -> void:
	pass  # Hearts lost tracked in damage_guardian directly


func _on_guardian_healed(_amount: float) -> void:
	pass


func _on_phone_event_triggered(_event_type: String) -> void:
	stat_phone_events_triggered += 1


func _on_phone_event_completed(_event_type: String, score: int, max_score: int) -> void:
	if score > 0:
		stat_phone_events_landed += 1


func award_dreamer_fragments(amount: int) -> void:
	dreamer_fragments += amount
	EventBus.dreamer_fragments_changed.emit(dreamer_fragments)
	print("[DREAMER] Fragments: ", dreamer_fragments, " (+", amount, ")")


func get_stats() -> Dictionary:
	return {
		"floor_reached": stat_floors_reached,
		"enemies_killed": stat_enemies_killed,
		"hearts_lost": stat_hearts_lost,
		"chests_opened": stat_chests_opened,
		"pots_smashed": stat_pots_smashed,
		"phone_events_triggered": stat_phone_events_triggered,
		"phone_events_landed": stat_phone_events_landed,
	}
