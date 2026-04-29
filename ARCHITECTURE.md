Finding Colour — Architecture Overview
====================================

Scope
- A co-op action roguelite built on Godot 4.6+ with a browser-based phone partner connected via Ably. The architecture balances a persistent floor/hub pattern with per-floor room content, shared systems, and a robust end-to-end loop.

System overview
- Godot runtime (game client) orchestrates floors, rooms, agents, UI, and visuals.
- Ably bridge (PhoneManager) communicates game state and events to a browser/mobile client.
- Autoload singletons provide global services and event channels.
- AiRunEngine (autoload) provides headless end-to-end testing and simulation.

Lifecycle: end-to-end
1) Start Run — GameManager.start_run → FloorManager.generate_floor(1) → FloorHub
2) Floor navigation — Guardian moves between rooms; rooms activate on entry
3) Combat & events — Attack/dodge with Hitstop + CameraShaker; phone events trigger slow-mo
4) Floor completion — All combat rooms cleared → exit trapdoor → upgrade screen
5) Next floor or end — advance_floor generates new map; end_run on death or completion

Key Configurables
- Rooms per floor: FloorManager.ROOM_COUNTS — {early:4, mid:5, late:6}
- Floor depth brackets: early(1-3), mid(4-6), late(7+) in FloorManager._get_room_count()
- Room sizes: FloorHub ROOM_W (1920) and ROOM_H (1080)
- Enemy spawning: room_template.gd._spawn_enemies() — per floor_num bracket, per room_type
- Breakables: room_base.gd._setup_breakables() — cluster count (1-3) and count per cluster (2-5)
- Elite chance: 25% at floor ≥ 3 in FloorManager._build_grid_map()
- Smoke test: ai_run_engine.gd — upgrade pool, min rooms, max scene frames

Testing
- Smoke test: godot --headless --path packages/godot --ai-smoke
  - Runs floor 1 → upgrade → floor 2 → verifies upgrade persisted → exit 0
- Simulation: godot --headless --path packages/godot --ai-simulate --ai-floors 5 --ai-seed 42
  - Runs N floors with deterministic seed, cycles upgrades, tracks stats → exit 0
- GitHub Actions: .github/workflows/ci.yml — smoke test on push/PR, simulation on manual dispatch