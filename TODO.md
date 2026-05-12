# TODO — Finding Colour

## Now
- [ ] Make smoke/sim thresholds configurable (room counts, enemy counts, breakable counts)
- [ ] Wire FloorManager seed to global seed for deterministic CI runs
- [ ] Boss prototype: The Mirror
- [ ] Generate enemy sprites via Pixellab (6 types: shadow_walker, shadow_lurker, swarmer, stalker, crawler, sploder)

## Soon
- [ ] 5-7 room floors as design evolves (tune ROOM_COUNTS)
- [ ] More enemy spawn diversity per room type (tune room_template.gd)
- [ ] More breakable clusters, chests, shrines (tune room_base.gd)
- [ ] Greyscale desaturation shader + PointLight2D colour bloom in real rooms
- [ ] Companion more animations (walk, take_hit, retreat)

## Later
- [ ] Meta-progression: Dream Fragments, Deep Shards
- [ ] Boss system: BossBase class, phase transitions
- [ ] Story vignettes between floors
- [ ] Companion visual evolution across runs
- [ ] Audio: SFX, music, bus design
- [ ] Secret rooms / hidden interactables

---

## Done
- [x] ai_run_engine.gd — autoload headless test harness (smoke + simulate)
- [x] CI: GitHub Actions workflow (.github/workflows/ci.yml)
- [x] Floor map system: grid random walk, global walls, room activation
- [x] 4 enemy archetypes: Shadow Walker, Shadow Lurker, Swarmer, Stalker
- [x] Companion steering + proactive anchor
- [x] Upgrade screen with 6 upgrade types
- [x] Phone event lifecycle (heal, chest_unlock, power_attack, boss_phase skeleton)
- [x] All debug keys (1-6)
- [x] Art pass — object sprites wired (breakable pot, chest, shrine, health/fragment pickups)
- [x] Companion sprites downloaded and wired (8-dir breathing-idle + rotation)
- [x] Guardian spritesheets confirmed working (6 animations, 8 directions)
- [x] Floor/wall tileset applied (flagstone + void tendril Wang tileset)
