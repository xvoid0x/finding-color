/**
 * gen-gdscript.ts
 * Generates GDScript message types + validators from Zod schemas.
 * Run: bun run gen (from packages/shared or root)
 * Output: packages/godot/autoload/message_types.gd
 */

import { resolve } from 'path'
import { writeFileSync } from 'fs'

const OUTPUT_PATH = resolve(__dirname, '../../godot/autoload/message_types.gd')

// ---------------------------------------------------------------------------
// These mirror the Zod schemas in messages.ts
// Update both together when the contract changes
// ---------------------------------------------------------------------------

const EVENT_TYPES = ['heal', 'chest_unlock', 'power_attack', 'boss_phase']
const HAPTIC_PATTERNS = ['short_triple', 'long_double', 'long_single', 'escalating']
const COMPANION_STATES = ['following', 'anchored', 'retreating', 'celebrating', 'hurt', 'idle']

// ---------------------------------------------------------------------------

function gdArray(values: string[]): string {
  return '[' + values.map(v => `"${v}"`).join(', ') + ']'
}

const output = `## message_types.gd
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

const EVENT_TYPES: Array[String] = ${gdArray(EVENT_TYPES)}
const HAPTIC_PATTERNS: Array[String] = ${gdArray(HAPTIC_PATTERNS)}
const COMPANION_STATES: Array[String] = ${gdArray(COMPANION_STATES)}

# Ably channel topics
const TOPIC_SERVER := "server"  # Godot publishes here
const TOPIC_CLIENT := "client"  # Phone publishes here

# ---------------------------------------------------------------------------
# Server message builders (Godot -> Phone)
# ---------------------------------------------------------------------------

static func make_state(
\tfloor: int,
\tguardian_hp: float,
\tguardian_max_hp: float,
\tevent_active: bool,
\tevent_type: String,
\tenemies_alive: int,
\tcompanion_anchored: bool
) -> Dictionary:
\treturn {
\t\t"type": "state",
\t\t"floor": floor,
\t\t"guardian_hp": guardian_hp,
\t\t"guardian_max_hp": guardian_max_hp,
\t\t"event_active": event_active,
\t\t"event_type": event_type if event_type != "" else null,
\t\t"enemies_alive": enemies_alive,
\t\t"companion_anchored": companion_anchored,
\t}


static func make_event_start(
\tevent: String,
\twindow: float,
\tfloor: int,
\tguardian_hp: float,
\tguardian_max_hp: float
) -> Dictionary:
\treturn {
\t\t"type": "event_start",
\t\t"event": event,
\t\t"window": window,
\t\t"floor": floor,
\t\t"guardian_hp": guardian_hp,
\t\t"guardian_max_hp": guardian_max_hp,
\t}


static func make_event_result(
\tevent: String,
\tscore: int,
\tmax_score: int,
\teffect_applied: String
) -> Dictionary:
\treturn {
\t\t"type": "event_result",
\t\t"event": event,
\t\t"score": score,
\t\t"max_score": max_score,
\t\t"effect_applied": effect_applied,
\t}


static func make_haptic(pattern: String) -> Dictionary:
\treturn {
\t\t"type": "haptic",
\t\t"pattern": pattern,
\t}


static func make_companion(state: String, hp_buffer: int = -1) -> Dictionary:
\tvar msg := {
\t\t"type": "companion",
\t\t"state": state,
\t}
\tif hp_buffer >= 0:
\t\tmsg["hp_buffer"] = hp_buffer
\treturn msg


# ---------------------------------------------------------------------------
# Client message validators (Phone -> Godot)
# ---------------------------------------------------------------------------

static func validate_join(data: Dictionary) -> bool:
\treturn (
\t\tdata.has("type") and data["type"] == "join" and
\t\tdata.has("name") and data["name"] is String and
\t\tdata["name"].length() >= 1 and data["name"].length() <= 20 and
\t\tdata.has("peer_id") and data["peer_id"] is String
\t)


static func validate_event_response(data: Dictionary) -> bool:
\treturn (
\t\tdata.has("type") and data["type"] == "event_response" and
\t\tdata.has("event") and data["event"] in EVENT_TYPES and
\t\tdata.has("score") and data["score"] is int and data["score"] >= 0 and
\t\tdata.has("max_score") and data["max_score"] is int and data["max_score"] > 0
\t)


static func validate_leave(data: Dictionary) -> bool:
\treturn (
\t\tdata.has("type") and data["type"] == "leave" and
\t\tdata.has("peer_id") and data["peer_id"] is String
\t)


static func validate_client_message(data: Dictionary) -> bool:
\t"""Validate any incoming client message."""
\tif not data.has("type"):
\t\treturn false
\tmatch data["type"]:
\t\t"join":           return validate_join(data)
\t\t"event_response": return validate_event_response(data)
\t\t"leave":          return validate_leave(data)
\t\t_:                return false
`

writeFileSync(OUTPUT_PATH, output, 'utf-8')
console.log(`Generated: ${OUTPUT_PATH}`)
