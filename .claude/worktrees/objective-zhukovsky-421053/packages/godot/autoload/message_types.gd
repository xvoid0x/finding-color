## message_types.gd
## AUTO-GENERATED -- DO NOT EDIT MANUALLY
## Source: packages/shared/src/messages.ts
## Regenerate: bun run gen (from monorepo root)
##
## Provides constants and validators for Ably messages
## between Godot (server) and phone (client).

extends Node

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const EVENT_TYPES: Array[String] = ["heal", "chest_unlock", "power_attack", "boss_phase"]
const HAPTIC_PATTERNS: Array[String] = ["short_triple", "long_double", "long_single", "escalating"]
const COMPANION_STATES: Array[String] = ["following", "anchored", "retreating", "celebrating", "hurt", "idle"]

# Ably channel topics
const TOPIC_SERVER := "server"  # Godot publishes here
const TOPIC_CLIENT := "client"  # Phone publishes here

# ---------------------------------------------------------------------------
# Server message builders (Godot -> Phone)
# ---------------------------------------------------------------------------

static func make_state(
	floor: int,
	guardian_hp: float,
	guardian_max_hp: float,
	event_active: bool,
	event_type: String,
	enemies_alive: int,
	companion_anchored: bool,
	dreamer_fragments: int = 0
) -> Dictionary:
	return {
		"type": "state",
		"floor": floor,
		"guardian_hp": guardian_hp,
		"guardian_max_hp": guardian_max_hp,
		"event_active": event_active,
		"event_type": event_type if event_type != "" else null,
		"enemies_alive": enemies_alive,
		"companion_anchored": companion_anchored,
		"dreamer_fragments": dreamer_fragments,
	}


static func make_event_start(
	event: String,
	window: float,
	floor: int,
	guardian_hp: float,
	guardian_max_hp: float
) -> Dictionary:
	return {
		"type": "event_start",
		"event": event,
		"window": window,
		"floor": floor,
		"guardian_hp": guardian_hp,
		"guardian_max_hp": guardian_max_hp,
	}


static func make_event_result(
	event: String,
	score: int,
	max_score: int,
	effect_applied: String
) -> Dictionary:
	return {
		"type": "event_result",
		"event": event,
		"score": score,
		"max_score": max_score,
		"effect_applied": effect_applied,
	}


static func make_haptic(pattern: String) -> Dictionary:
	return {
		"type": "haptic",
		"pattern": pattern,
	}


static func make_companion(state: String, hp_buffer: int = -1) -> Dictionary:
	var msg := {
		"type": "companion",
		"state": state,
	}
	if hp_buffer >= 0:
		msg["hp_buffer"] = hp_buffer
	return msg


# ---------------------------------------------------------------------------
# Client message validators (Phone -> Godot)
# ---------------------------------------------------------------------------

static func validate_join(data: Dictionary) -> bool:
	return (
		data.has("type") and data["type"] == "join" and
		data.has("name") and data["name"] is String and
		data["name"].length() >= 1 and data["name"].length() <= 20 and
		data.has("peer_id") and data["peer_id"] is String
	)


static func validate_event_response(data: Dictionary) -> bool:
	return (
		data.has("type") and data["type"] == "event_response" and
		data.has("event") and data["event"] in EVENT_TYPES and
		data.has("score") and data["score"] is int and data["score"] >= 0 and
		data.has("max_score") and data["max_score"] is int and data["max_score"] > 0
	)


static func validate_leave(data: Dictionary) -> bool:
	return (
		data.has("type") and data["type"] == "leave" and
		data.has("peer_id") and data["peer_id"] is String
	)


static func validate_client_message(data: Dictionary) -> bool:
	"""Validate any incoming client message."""
	if not data.has("type"):
		return false
	match data["type"]:
		"join":           return validate_join(data)
		"event_response": return validate_event_response(data)
		"leave":          return validate_leave(data)
		_:                return false
