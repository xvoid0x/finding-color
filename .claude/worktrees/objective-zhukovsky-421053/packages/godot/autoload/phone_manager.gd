extends Node
## PhoneManager - Ably pub/sub bridge between Godot and phone browser.
##
## Architecture:
##   Godot publishes  → REST POST  → Ably → "server" topic → Phone subscribes
##   Phone publishes  → Ably       → "client" topic → WebSocket → Godot receives
##
## Channel: game-{ROOM_CODE}
## Config:  res://config.ini  [ably] api_key = "..."

signal event_response_received(event_type: String, score: int, max_score: int)

# --- Connection State ---
var room_code: String = ""
var connected_peers: Dictionary = {}  # peer_id -> { "name": String }
var phone_player_count: int = 0

# --- Ably Config ---
var _api_key: String = ""
var _channel_name: String = ""

# --- WebSocket (subscribing: Phone -> Godot) ---
var _ws: WebSocketPeer = WebSocketPeer.new()
var _ws_state: int = -1  # -1 = idle

# --- REST HTTP (publishing: Godot -> Phone) ---
var _http: HTTPRequest
var _publish_queue: Array[Dictionary] = []
var _http_busy: bool = false

# --- Active Event State ---
var _active_event: String = ""
var _event_window_timer: float = 0.0
var _event_window_duration: float = 0.0
var _event_active: bool = false

# --- Difficulty ---
var _performance_score: float = 1.0
const PERF_ADJUST_AMOUNT: float = 0.05


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.companion_anchored.connect(_on_companion_anchored)

	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)

	_load_config()


func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load("res://config.ini") == OK:
		_api_key = config.get_value("ably", "api_key", "")
		if _api_key == "YOUR_ABLY_API_KEY_HERE" or _api_key.is_empty():
			push_warning("[PHONE] Paste your Ably API key into packages/godot/config.ini")
			_api_key = ""
		else:
			print("[PHONE] Ably API key loaded")
	else:
		push_warning("[PHONE] config.ini not found — create packages/godot/config.ini")


func _process(delta: float) -> void:
	# Event timer runs on real time (unaffected by slow-mo)
	if _event_active:
		_event_window_timer -= delta
		if _event_window_timer <= 0.0:
			_expire_active_event()

	# Poll WebSocket every frame
	_poll_ws()

	# Drain publish queue
	if not _http_busy and not _publish_queue.is_empty():
		_flush_publish_queue()


# =============================================================================
# Room Code & Connection
# =============================================================================

func generate_room_code() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ"
	var code := ""
	for i in 4:
		code += CHARS[randi() % CHARS.length()]
	room_code = code
	SettingsManager.room_code = code
	_channel_name = "game-%s" % code
	return code


func connect_ably() -> void:
	if _api_key.is_empty():
		print("[PHONE] No API key — running without phone connection")
		return

	print("[PHONE] Connecting to Ably | channel: ", _channel_name)

	var url := "wss://realtime.ably.io/?key=%s&v=2&format=json&heartbeats=true" % _api_key
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_error("[PHONE] WebSocket connect error: %d" % err)


# =============================================================================
# WebSocket — Subscribing (Phone -> Godot)
# =============================================================================

func _poll_ws() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == _ws_state:
		# State unchanged — just read packets
		if state == WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count() > 0:
				var raw := _ws.get_packet().get_string_from_utf8()
				_on_ws_message(raw)
		return

	# State changed
	_ws_state = state
	match state:
		WebSocketPeer.STATE_OPEN:
			print("[PHONE] WebSocket connected")
		WebSocketPeer.STATE_CLOSED:
			print("[PHONE] WebSocket closed (code %d)" % _ws.get_close_code())
			# Clear all connected peers — they all disconnected with the socket
			for peer_id in connected_peers.keys():
				EventBus.phone_player_left.emit(0)
			connected_peers.clear()
			phone_player_count = 0
			EventBus.phone_disconnected.emit()
		_:
			# Read any pending packets regardless
			while _ws.get_available_packet_count() > 0:
				var raw := _ws.get_packet().get_string_from_utf8()
				_on_ws_message(raw)


func _on_ws_message(raw: String) -> void:
	var msg = JSON.parse_string(raw)
	if not msg is Dictionary:
		return

	var action: int = msg.get("action", -1)
	match action:
		0:  # HEARTBEAT — must respond
			_ws.send_text(JSON.stringify({"action": 0}))

		4:  # CONNECTED — attach to channel
			print("[PHONE] Ably connected — attaching to: ", _channel_name)
			_ws.send_text(JSON.stringify({
				"action": 10,
				"channel": _channel_name,
			}))

		11: # ATTACHED
			print("[PHONE] Subscribed to channel: ", msg.get("channel", "?"))

		15: # MESSAGE — incoming from phone
			var messages = msg.get("messages", [])
			for m in messages:
				if m.get("name", "") == "client":
					_dispatch_client_message(m)

		9:  # ERROR
			push_error("[PHONE] Ably error: %s" % JSON.stringify(msg.get("error", {})))


func _dispatch_client_message(envelope: Dictionary) -> void:
	var raw = envelope.get("data", "")
	var data: Dictionary
	if raw is String:
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			data = parsed
		else:
			return
	elif raw is Dictionary:
		data = raw
	else:
		return

	if not MessageTypes.validate_client_message(data):
		push_warning("[PHONE] Invalid client message: %s" % JSON.stringify(data))
		return

	var msg_type: String = data.get("type", "")
	print("[PHONE] Received: ", msg_type)

	match msg_type:
		"join":
			_on_peer_joined(data)
		"event_response":
			receive_event_response(
				0,
				data.get("event", ""),
				data.get("score", 0),
				data.get("max_score", 3)
			)
		"companion_steer":
			_on_companion_steer(data)
		"companion_gesture_door":
			_on_companion_gesture_door(data)
		"proactive_anchor":
			_on_proactive_anchor(data)
		"leave":
			_on_peer_left(data)


func _on_peer_joined(data: Dictionary) -> void:
	var peer_id: String = data.get("peer_id", "unknown")
	var name: String = data.get("name", "Player")
	var was_empty := connected_peers.is_empty()
	connected_peers[peer_id] = {"name": name}
	phone_player_count = connected_peers.size()
	print("[PHONE] Player joined: %s | total: %d" % [name, phone_player_count])
	EventBus.phone_player_joined.emit(0)
	if was_empty:
		EventBus.phone_reconnected.emit()
	# Push current state immediately so phone is in sync
	push_game_state()


func _on_peer_left(data: Dictionary) -> void:
	var peer_id: String = data.get("peer_id", "")
	connected_peers.erase(peer_id)
	phone_player_count = connected_peers.size()
	print("[PHONE] Player left | remaining: %d" % phone_player_count)
	EventBus.phone_player_left.emit(0)


# =============================================================================
# REST — Publishing (Godot -> Phone)
# =============================================================================

func _send_to_all(data: Dictionary) -> void:
	if _api_key.is_empty() or _channel_name.is_empty():
		return
	_publish_queue.append(data)


func _flush_publish_queue() -> void:
	if _publish_queue.is_empty() or _http_busy:
		return

	# Batch into one request if possible (Ably supports array of messages)
	var batch: Array = []
	while not _publish_queue.is_empty() and batch.size() < 10:
		batch.append({
			"name": "server",
			"data": JSON.stringify(_publish_queue.pop_front()),
		})

	var url := "https://rest.ably.io/channels/%s/messages" % _channel_name
	var auth := Marshalls.utf8_to_base64(_api_key)
	var headers := [
		"Content-Type: application/json",
		"Authorization: Basic %s" % auth,
	]
	var body := JSON.stringify(batch)
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err == OK:
		_http_busy = true
	else:
		push_warning("[PHONE] HTTP request error: %d" % err)


func _on_http_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_http_busy = false
	if code != 201:
		push_warning("[PHONE] Ably publish failed — HTTP %d" % code)


# =============================================================================
# Phone Events
# =============================================================================

func trigger_event(event_type: String, window_duration: float) -> void:
	if _event_active:
		print("[EVENT] Blocked — already active: ", _active_event)
		return

	_active_event = event_type
	_event_window_duration = window_duration
	_event_window_timer = window_duration
	_event_active = true

	# Slow-mo only for combat events
	if event_type != "chest_unlock":
		GameManager.trigger_slow_mo(window_duration * 1.2)

	EventBus.phone_event_triggered.emit(event_type)
	print("[EVENT] Triggered: %s | window: %.1fs" % [event_type, window_duration])

	_send_to_all(MessageTypes.make_event_start(
		event_type,
		window_duration,
		GameManager.current_floor,
		GameManager.guardian_hearts,
		GameManager.guardian_max_hearts
	))
	_send_to_all(MessageTypes.make_haptic(_get_haptic_pattern(event_type)))


func receive_event_response(peer_id: int, event_type: String, score: int, max_score: int) -> void:
	if not _event_active or _active_event != event_type:
		return
	_resolve_event(event_type, score, max_score)


func _expire_active_event() -> void:
	print("[EVENT] Expired: %s — no response" % _active_event)
	_resolve_event(_active_event, 0, 3)


func _resolve_event(event_type: String, score: int, max_score: int) -> void:
	print("[EVENT] Resolved: %s | score: %d/%d" % [event_type, score, max_score])
	_event_active = false
	_event_window_timer = 0.0
	GameManager.end_slow_mo()

	var hit_rate: float = float(score) / float(max_score) if max_score > 0 else 0.0
	if hit_rate >= 0.8:
		_performance_score = minf(1.3, _performance_score + PERF_ADJUST_AMOUNT)
	elif hit_rate <= 0.3:
		_performance_score = maxf(0.7, _performance_score - PERF_ADJUST_AMOUNT)

	EventBus.phone_event_completed.emit(event_type, score, max_score)
	event_response_received.emit(event_type, score, max_score)
	_apply_event_effect(event_type, score, max_score)

	var effect_label := _describe_effect(event_type, score, max_score)
	_send_to_all(MessageTypes.make_event_result(event_type, score, max_score, effect_label))


func _apply_event_effect(event_type: String, score: int, max_score: int) -> void:
	match event_type:
		"heal":
			var heal_amount: float = 0.0
			match score:
				3: heal_amount = 1.0
				2: heal_amount = 0.6
				1: heal_amount = 0.25
			# Someone's Hand upgrade: +20% heal amount
			if GameManager.has_upgrade("someones_hand"):
				heal_amount *= 1.2
			if heal_amount > 0.0:
				GameManager.heal_guardian(heal_amount)
		"chest_unlock":
			# EventBus.phone_event_completed handles this via companion listener.
			# Direct call here as a guaranteed fallback in case signal chain breaks.
			var companion := get_tree().get_first_node_in_group("companion")
			if companion:
				if score > 0 and companion.has_method("free_from_anchor"):
					print("[PHONE] Direct: freeing companion from anchor")
					companion.free_from_anchor()
				elif score == 0 and companion.has_method("retreat"):
					companion.retreat()


func _describe_effect(event_type: String, score: int, _max_score: int) -> String:
	match event_type:
		"heal":
			match score:
				3: return "Healed 1 heart"
				2: return "Healed 0.6 hearts"
				1: return "Healed 0.25 hearts"
				_: return "No effect"
		"chest_unlock":
			return "Chest opened" if score > 0 else "Chest failed"
		_:
			return "Effect applied"


# =============================================================================
# Game State Push
# =============================================================================

func send_pause_state(paused: bool) -> void:
	_send_to_all(MessageTypes.make_pause(paused))


func push_game_state() -> void:
	var enemies_alive := get_tree().get_nodes_in_group("enemies").size()
	var companion_anchored := false
	var companion := get_tree().get_first_node_in_group("companion")
	if companion and companion.has_method("is_anchored"):
		companion_anchored = companion.is_anchored()

	_send_to_all(MessageTypes.make_state(
		GameManager.current_floor,
		GameManager.guardian_hearts,
		GameManager.guardian_max_hearts,
		_event_active,
		_active_event,
		enemies_alive,
		companion_anchored,
		GameManager.dreamer_fragments
	))


func push_floor_map_state() -> void:
	"""Push current floor map to phone (fog of war, cleared rooms, current room)."""
	var map_state := FloorManager.get_map_state_for_phone()
	if map_state.is_empty():
		return
	_send_to_all({
		"type": "floor_map",
		"map": map_state,
	})


# =============================================================================
# Companion Steering & Proactive Anchor
# =============================================================================

func _on_companion_steer(data: Dictionary) -> void:
	## Phone player tapped/dragged on screen — steer companion to world position.
	## Phone sends normalised screen coords (0.0-1.0); we convert to world space.
	var companion := get_tree().get_first_node_in_group("companion")
	if not companion or not companion.has_method("set_steering_target"):
		return

	# Phone sends x/y as normalised 0..1 screen fractions
	# Convert to Godot world coords (room is 1920x1080)
	var nx: float = data.get("x", 0.5)
	var ny: float = data.get("y", 0.5)
	var world_pos := Vector2(nx * 1920.0, ny * 1080.0)
	companion.set_steering_target(world_pos)


func _on_companion_gesture_door(data: Dictionary) -> void:
	## Phone player gestured toward a specific door on their map.
	var companion := get_tree().get_first_node_in_group("companion")
	if not companion or not companion.has_method("gesture_at_door"):
		return
	var door_id: int = data.get("door_id", 0)
	companion.gesture_at_door(door_id)


func _on_proactive_anchor(data: Dictionary) -> void:
	## Phone player tapped an interactable on their map — anchor companion to it.
	if _event_active:
		return  # Don't interrupt an active event

	var companion := get_tree().get_first_node_in_group("companion")
	if not companion or not companion.has_method("anchor_to"):
		return

	var target_type: String = data.get("target_type", "")
	var target := _find_nearest_interactable(target_type)
	if target:
		print("[PHONE] Proactive anchor: ", target_type, " at ", target.global_position)
		companion.anchor_to(target)


func _find_nearest_interactable(target_type: String) -> Node2D:
	## Find the nearest interactable of the given type in the current scene.
	var candidates: Array = []
	match target_type:
		"chest":
			candidates = get_tree().get_nodes_in_group("chests")
		"shrine":
			candidates = get_tree().get_nodes_in_group("shrines")
		_:
			return null

	if candidates.is_empty():
		return null

	var companion := get_tree().get_first_node_in_group("companion") as Node2D
	if not companion:
		return null

	var nearest: Node2D = null
	var nearest_dist := INF
	for c in candidates:
		if c is Node2D:
			var d := companion.global_position.distance_squared_to((c as Node2D).global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = c
	return nearest


# =============================================================================
# Helpers
# =============================================================================

func get_event_difficulty(base_window: float) -> float:
	var floor_scale: float = maxf(0.4, 1.0 - (GameManager.current_floor - 1) * 0.06)
	return base_window * floor_scale * (2.0 - _performance_score)


func _on_companion_anchored(object_type: String) -> void:
	print("[EVENT] Companion anchored to: ", object_type)
	_send_to_all(MessageTypes.make_companion("anchored"))
	match object_type:
		"chest":
			var window := get_event_difficulty(8.0)
			print("[EVENT] Triggering chest_unlock | window: %.1fs" % window)
			trigger_event("chest_unlock", window)
		"unknown":
			push_error("[EVENT] Companion anchored to object with no 'object_type' meta set! Check RoomBase._setup_chest_node()")


func _get_haptic_pattern(event_type: String) -> String:
	match event_type:
		"heal":         return "short_triple"
		"power_attack": return "long_double"
		"chest_unlock": return "long_single"
		"boss_phase":   return "escalating"
		_:              return "short_triple"
