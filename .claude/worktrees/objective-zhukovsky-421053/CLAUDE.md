# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Finding Colour is a co-op action roguelite. One player drives the Guardian in a Godot 4.6 client; a second player joins from a phone browser running a Phaser 3 mini-game. The two clients talk through Ably (pub/sub relay), and the message contract is a single source of truth in TypeScript that is **codegen'd into GDScript**.

## Repository layout

Bun + Turbo monorepo with three workspaces:

- `packages/shared/` — Zod schemas (`src/messages.ts`) defining every Ably message in both directions. **Source of truth**. Run `bun run gen` to regenerate `packages/godot/autoload/message_types.gd` from these schemas. Update both sides of the codegen if you change the wire format.
- `packages/phone/` — Phaser 3 + Vite + TS phone client. Connects to Ably with `VITE_ABLY_API_KEY`.
- `packages/godot/` — Godot 4.6 game project (this is the "server"). Has its own `addons/`, `autoload/`, `scenes/`, `characters/`, `shaders/`. Reads its Ably API key from `packages/godot/config.ini` (gitignored).

`tools/ai_run_engine.gd` mirrors `packages/godot/autoload/ai_run_engine.gd` (the canonical copy is the autoload).

## Commands

Root-level (Turbo orchestrates the workspaces):

```bash
bun install            # install everything
bun run dev            # turbo dev --filter=phone  (Vite at :5173)
bun run build          # build all workspaces (shared first, then phone)
bun run typecheck      # tsc --noEmit across workspaces
bun run gen            # regenerate Godot message types from Zod schemas
```

Phone in Docker (port-mapped to host :5174 → container :5173):

```bash
docker compose up phone
```

Godot — open `packages/godot/project.godot` in Godot 4.6.2. Main scene is `scenes/menus/title_screen.tscn`.

### Headless tests (Godot)

There are **no GDScript unit tests**. The end-to-end harness is `AiRunEngine` (autoload) which auto-runs when CLI flags are passed:

```bash
# Smoke test: run → floor 1 → clear → upgrade → floor 2 → verify upgrade persisted → exit 0
godot --headless --path packages/godot --ai-smoke

# Deterministic simulation across N floors
godot --headless --path packages/godot --ai-simulate --ai-floors 5 --ai-seed 42
```

CI (`.github/workflows/ci.yml`) runs the smoke test on every push/PR touching `packages/godot/**` or `packages/shared/**`, plus a parse-error scan over all `.gd` files. Simulation only runs on manual `workflow_dispatch`.

## Architecture

### Godot autoloads (registered in `project.godot`)

These run as singletons; treat them as global services:

- `EventBus` — purely a `signal` hub. Systems emit and listen here so nothing references siblings directly. Adding a new cross-system event? Declare the signal here.
- `GameManager` — run state, guardian HP, floor progression, time scale (slow-mo), upgrade application, debug keys 1–6.
- `FloorManager` — procedural floor map generation (grid random walk → connected room graph → assigns start/exit/combat/elite/chest/shrine), traversal state, fog-of-war, phone serialisation.
- `PhoneManager` — Ably bridge. Subscribes via WebSocket, publishes via REST POST, validates incoming client messages with `MessageTypes.validate_*`, owns active phone-event lifecycle (`trigger_event` / `_resolve_event` / `_expire_active_event`) and difficulty scaling.
- `MessageTypes` — **auto-generated**, do not edit. Holds enum constants, server-message builders (`make_state`, `make_event_start`, …), and client-message validators.
- `HitstopManager`, `CameraShaker`, `ScreenshotManager`, `CrackTextureGen`, `SettingsManager` — supporting services.
- `AiRunEngine` — the headless test harness. Inert during normal play; activated by `--ai-smoke`/`--ai-simulate`.

### End-to-end run lifecycle

`GameManager.start_run` → `FloorManager.generate_floor(1)` → `change_scene_to_file("res://scenes/floors/floor_hub.tscn")` → `FloorHub` reads the map, lays out rooms in world space, builds **global walls** for the whole floor (rooms never build their own walls), spawns the Guardian/Companion/Camera, activates the start room. Combat clears emit on `EventBus.room_cleared` → `FloorManager.on_room_cleared` → when all combat rooms cleared, `all_rooms_cleared` fires. `GameManager.exit_room` swaps to `upgrade_screen.tscn`; `advance_floor` regenerates and reloads `floor_hub.tscn`. Death or completion calls `end_run(cause)` → `end_screen.tscn`.

### Phone protocol

`packages/shared/src/messages.ts` defines two discriminated unions:
- `ServerMessage` (Godot → phone): `state`, `event_start`, `event_result`, `haptic`, `companion`, `paused`.
- `ClientMessage` (phone → Godot): `join`, `event_response`, `leave`. Note the GDScript validator additionally accepts `companion_steer`, `companion_gesture_door`, and `proactive_anchor` — if you formalise those, add them to the Zod schema and regen.

When you change the wire contract: edit `messages.ts`, update the mirrored constants in `packages/shared/scripts/gen-gdscript.ts`, run `bun run gen`, and verify both sides typecheck/parse.

### Floor-map specifics

- Rooms per floor: `FloorManager.ROOM_COUNTS = {early:4, mid:5, late:6}`, bracketed in `_get_room_count` as floors 1-3 / 4-6 / 7+. (Note: `GameManager.get_rooms_per_floor` has a different stale formula — `FloorManager` is authoritative for actual generation.)
- Elite chance: 25% on floors ≥3 in `FloorManager._build_grid_map`.
- Room dimensions: `FloorHub.ROOM_W = 1920`, `ROOM_H = 1080`; this is also assumed by `PhoneManager._on_companion_steer` when converting normalised phone coords to world space.

### `RoomBase.HEADLESS_RUN`

Set true by `AiRunEngine` to make rooms skip enemy-damage logic during simulation. Anything that should be inert in headless tests should check this flag.

## Conventions

- GDScript files: `class_name` only when the type is referenced from another script. Indented with **tabs** — the codegen script writes `\t` literals deliberately, do not "fix" them.
- Phone TS: imports go through `@finding-colour/shared` (the workspace package), not relative paths into `../shared`.
- Don't edit `packages/godot/autoload/message_types.gd` by hand; it's regenerated by `bun run gen`.
- Don't commit `packages/godot/config.ini` (it holds the Ably API key); `.gitignore` already excludes it.
- `ARCHITECTURE.md` and `TODO.md` at repo root track design intent and outstanding work — keep them in sync when you change tunables or finish items.
