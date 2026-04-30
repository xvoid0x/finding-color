# Finding Colour

Co-op action roguelite. One player fights. One player supports from a phone.

## Setup

1. Open project in Godot 4.6.2
2. Let it import all files
3. Open `scenes/menus/title_screen.tscn` -- set as main scene (already set in project.godot)
4. Hit Play

## Project Structure

```
autoload/
  event_bus.gd        -- Global signal hub
  game_manager.gd     -- Run state, health, floor progression, time scale
  phone_manager.gd    -- Phone event lifecycle, Ably transport (placeholder)

characters/
  guardian/           -- Controller player character
  companion/          -- Phone player's physical presence in the world
  enemies/
    enemy_base.gd     -- Base class (health, crack shader, death)
    shadow_walker.gd  -- Enemy type 1: moves toward guardian
    shadow_lurker.gd  -- Enemy type 2: circles then dashes

scenes/
  menus/
    title_screen.gd   -- Start screen, room code display
  rooms/
    room_base.gd      -- Base room class, enemy spawning, tendril pressure
  ui/
    hud.gd            -- Hearts, floor number, companion HP bar, event indicator
    upgrade_screen.gd -- Post-floor memory card selection
    end_screen.gd     -- Post-run stats (death or victory)

shaders/
  enemy_crack.gdshader    -- Progressive white cracks on enemies
  world_desaturate.gdshader -- Greyscale world layer

assets/
  sprites/            -- Art goes here
  audio/              -- Audio goes here
```

## What Needs Building in Godot Editor

These scripts are written but need .tscn scene files created in the editor:

- [ ] guardian.tscn -- CharacterBody2D + Sprite2D + CollisionShape2D + AttackArea + PointLight2D
- [ ] companion.tscn -- Node2D + Sprite2D + PointLight2D + HPBar
- [ ] shadow_walker.tscn -- CharacterBody2D + Sprite2D + CollisionShape2D + ContactArea
- [ ] shadow_lurker.tscn -- CharacterBody2D + Sprite2D + CollisionShape2D + ContactArea
- [ ] room_template.tscn -- Node2D room with walls, floor, exits
- [ ] title_screen.tscn -- Control with labels and room code display
- [ ] hud.tscn -- CanvasLayer with heart container, labels
- [ ] upgrade_screen.tscn -- Control with card container
- [ ] end_screen.tscn -- Control with stat containers

## Prototype Goals

1. Guardian moves + attacks + dodges
2. Enemies spawn and die with crack/shatter effect
3. HEAL event fires, phone player gets minigame, result heals guardian
4. CHEST UNLOCK fires, companion anchors, phone player unlocks it
5. Slow-mo at 25% during both events
6. Floor clears, upgrade screen appears, advance to next floor
