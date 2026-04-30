import { z } from 'zod'

// =============================================================================
// FINDING COLOUR -- Ably Message Contract
// Source of truth for all messages between Godot (server) and Phaser (client)
// GDScript types are auto-generated from these schemas via: bun run gen
// =============================================================================

// --- Enums (used in both directions) ---

export const EventType = z.enum([
  'heal',
  'chest_unlock',
  'power_attack',
  'boss_phase',
])
export type TEventType = z.infer<typeof EventType>

export const HapticPattern = z.enum([
  'short_triple',   // heal
  'long_double',    // power attack
  'long_single',    // chest unlock / floor exit
  'escalating',     // boss phase
])
export type THapticPattern = z.infer<typeof HapticPattern>

// =============================================================================
// SERVER MESSAGES (Godot -> Phone)
// =============================================================================

/**
 * Sent periodically to keep phone UI in sync with game state.
 * Phone uses this to update HP display, floor number, etc.
 */
export const GameStateMessage = z.object({
  type: z.literal('state'),
  floor: z.number().int().positive(),
  guardian_hp: z.number().min(0),
  guardian_max_hp: z.number().positive(),
  event_active: z.boolean(),
  event_type: EventType.nullable(),
  enemies_alive: z.number().int().min(0),
  companion_anchored: z.boolean(),
  dreamer_fragments: z.number().int().min(0),
})
export type TGameStateMessage = z.infer<typeof GameStateMessage>

/**
 * Fired when a phone event begins. Phone should launch the minigame scene.
 * slow-mo starts on Godot side simultaneously.
 */
export const EventStartMessage = z.object({
  type: z.literal('event_start'),
  event: EventType,
  window: z.number().positive(),     // seconds phone player has to respond
  floor: z.number().int().positive(),
  guardian_hp: z.number().min(0),
  guardian_max_hp: z.number().positive(),
})
export type TEventStartMessage = z.infer<typeof EventStartMessage>

/**
 * Sent after Godot resolves an event (phone responded or window expired).
 * Phone uses this to show result feedback.
 */
export const EventResultMessage = z.object({
  type: z.literal('event_result'),
  event: EventType,
  score: z.number().int().min(0),
  max_score: z.number().int().positive(),
  effect_applied: z.string(),        // human-readable: "Healed 1 heart", "No effect"
})
export type TEventResultMessage = z.infer<typeof EventResultMessage>

/**
 * Triggers phone haptic feedback.
 * Sent just before event_start so phone player feels it before looking down.
 */
export const HapticMessage = z.object({
  type: z.literal('haptic'),
  pattern: HapticPattern,
})
export type THapticMessage = z.infer<typeof HapticMessage>

/**
 * Companion state update -- drives companion animations on phone.
 */
export const CompanionStateMessage = z.object({
  type: z.literal('companion'),
  state: z.enum([
    'following',
    'anchored',
    'retreating',
    'celebrating',
    'hurt',
    'idle',
  ]),
  hp_buffer: z.number().int().min(0).optional(),
})
export type TCompanionStateMessage = z.infer<typeof CompanionStateMessage>

// Pause state message
export const PausedMessage = z.object({
  type: z.literal('paused'),
  paused: z.boolean(),
})
export type TPausedMessage = z.infer<typeof PausedMessage>

// Discriminated union of all server messages
export const ServerMessage = z.discriminatedUnion('type', [
  GameStateMessage,
  EventStartMessage,
  EventResultMessage,
  HapticMessage,
  CompanionStateMessage,
  PausedMessage,
])
export type TServerMessage = z.infer<typeof ServerMessage>

// =============================================================================
// CLIENT MESSAGES (Phone -> Godot)
// =============================================================================

/**
 * Phone player joins the session.
 */
export const JoinMessage = z.object({
  type: z.literal('join'),
  name: z.string().min(1).max(20),
  peer_id: z.string().uuid(),
})
export type TJoinMessage = z.infer<typeof JoinMessage>

/**
 * Phone player completed a minigame -- sends their score back.
 */
export const EventResponseMessage = z.object({
  type: z.literal('event_response'),
  event: EventType,
  score: z.number().int().min(0),
  max_score: z.number().int().positive(),
})
export type TEventResponseMessage = z.infer<typeof EventResponseMessage>

/**
 * Phone player left or disconnected.
 */
export const LeaveMessage = z.object({
  type: z.literal('leave'),
  peer_id: z.string(),
})
export type TLeaveMessage = z.infer<typeof LeaveMessage>

// Discriminated union of all client messages
export const ClientMessage = z.discriminatedUnion('type', [
  JoinMessage,
  EventResponseMessage,
  LeaveMessage,
])
export type TClientMessage = z.infer<typeof ClientMessage>
