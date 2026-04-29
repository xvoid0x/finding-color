# TODO — Finding Colour

## Now
- [ ] Make smoke/sim thresholds configurable (room counts, enemy counts, breakable counts)
- [ ] Wire FloorManager seed to global seed for deterministic CI runs
- [ ] Art pass — replace ColorRect placeholders with real sprites
- [ ] Boss prototype: The Mirror

## Soon
- [ ] 5-7 room floors as design evolves (tune ROOM_COUNTS)
- [ ] More enemy spawn diversity per room type (tune room_template.gd)
- [ ] More breakable clusters, chests, shrines (tune room_base.gd)
- [ ] Companion breathing-idle animation from Pixellab
- [ ] Guardian walk/idle/attack animations from Pixellab
- [ ] Greyscale desaturation shader + PointLight2D colour bloom in real rooms

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