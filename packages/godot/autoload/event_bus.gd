extends Node
## EventBus - Global signal hub for decoupled communication.
## Systems emit here, systems listen here. Nothing talks directly.

# --- Guardian signals ---
signal guardian_damaged(hearts_lost: float, source: String)
signal guardian_healed(hearts_restored: float)
signal guardian_died()
signal guardian_hearts_changed(current: float, maximum: float)

# --- Phone event signals ---
signal phone_event_triggered(event_type: String)
signal phone_event_completed(event_type: String, score: int, max_score: int)
signal phone_event_expired(event_type: String)

# --- Companion signals ---
signal companion_anchored(object_type: String)
signal companion_freed()
signal companion_damaged(hits_remaining: int)
signal companion_retreated()
signal companion_steering_target_set(world_pos: Vector2)
signal companion_steering_target_reached(world_pos: Vector2)
signal companion_gesture_at_door(door_id: int)

# --- Room signals ---
signal room_cleared()
signal room_entered(room_index: int)
signal floor_cleared(floor_number: int)

# --- Game flow signals ---
signal run_started()
signal run_ended(cause: String, floor_reached: int)
signal slow_mo_started(duration: float)
signal slow_mo_ended()

# --- Economy signals ---
signal dreamer_fragments_changed(new_total: int)

# --- Phone connection signals ---
signal phone_player_joined(peer_id: int)
signal phone_player_left(peer_id: int)
signal phone_input_received(peer_id: int, data: Dictionary)
signal phone_disconnected()
signal phone_reconnected()
