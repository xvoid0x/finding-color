extends Node
## GuardianAnimator - Drives the guardian's AnimatedSprite2D based on state + facing.
##
## Directions: 8-way (south, south-west, west, north-west, north, north-east, east, south-east)
## Animations: idle, breathing_idle, fight_idle, walk, attack, taking_punch
##
## Usage: attach as child of guardian. Call set_state() each frame from guardian.gd.

## Animation FPS per type
const FPS := {
	"idle":           8,
	"breathing_idle": 6,
	"fight_idle":     8,
	"walk":           10,
	"attack":         14,
	"taking_punch":   12,
}

## Direction names matching spritesheet filenames
const DIRECTIONS := [
	"south", "south-west", "west", "north-west",
	"north", "north-east", "east", "south-east"
]

## Frame counts per animation (must match spritesheets)
const FRAME_COUNTS := {
	"idle":           8,
	"breathing_idle": 4,
	"fight_idle":     8,
	"walk":           8,
	"attack":         6,
	"taking_punch":   6,
}

const SPRITE_BASE := "res://assets/characters/guardian/spritesheets/"
const FRAME_SIZE := Vector2(176, 176)

@onready var _sprite: AnimatedSprite2D = $"../Sprite/AnimatedSprite2D"

var _current_anim: String = ""
var _current_dir: String = "south"
var _enemies_nearby: bool = false


func _ready() -> void:
	if not _sprite:
		push_error("[GUARDIAN_ANIM] AnimatedSprite2D not found — check node path")
		return
	_build_sprite_frames()
	play("breathing_idle", "south")


func _build_sprite_frames() -> void:
	"""Load all spritesheets into a SpriteFrames resource."""
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for anim_name in FRAME_COUNTS:
		for direction in DIRECTIONS:
			var anim_key := "%s_%s" % [anim_name, direction]
			var fps: int = FPS.get(anim_name, 8)
			var frame_count: int = FRAME_COUNTS[anim_name]
			var sheet_path := "%s%s_%s.png" % [SPRITE_BASE, anim_name, direction]

			if not ResourceLoader.exists(sheet_path):
				push_warning("[GUARDIAN_ANIM] Missing spritesheet: %s" % sheet_path)
				continue

			var texture := load(sheet_path) as Texture2D
			if not texture:
				push_warning("[GUARDIAN_ANIM] Failed to load: %s" % sheet_path)
				continue

			frames.add_animation(anim_key)
			frames.set_animation_speed(anim_key, fps)
			frames.set_animation_loop(anim_key, _should_loop(anim_name))

			# Slice spritesheet into individual frames
			var atlas_w: int = texture.get_width()
			var frame_w: int = atlas_w / frame_count
			var frame_h: int = int(FRAME_SIZE.y)

			for i in frame_count:
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
				frames.add_frame(anim_key, atlas)

	_sprite.sprite_frames = frames
	print("[GUARDIAN_ANIM] SpriteFrames built: %d animations" % frames.get_animation_names().size())


func _should_loop(anim_name: String) -> bool:
	match anim_name:
		"attack", "taking_punch":
			return false
		_:
			return true


# =============================================================================
# Public API — called from guardian.gd each frame
# =============================================================================

func update_from_state(
	guardian_state: int,   # Guardian.State enum value
	aim_dir: Vector2,
	move_dir: Vector2,
	enemies_nearby: bool
) -> void:
	if not _sprite:
		return
	_enemies_nearby = enemies_nearby
	var dir := _vector_to_direction(aim_dir if aim_dir.length() > 0.1 else move_dir)
	_current_dir = dir

	# Map guardian state to animation name
	var anim := _state_to_anim(guardian_state, move_dir, enemies_nearby)
	play(anim, dir)


func play(anim_name: String, direction: String) -> void:
	if not _sprite:
		return
	var anim_key := "%s_%s" % [anim_name, direction]
	if _sprite.animation == anim_key and _sprite.is_playing():
		return  # Already playing — don't restart

	if not _sprite.sprite_frames or not _sprite.sprite_frames.has_animation(anim_key):
		return

	_current_anim = anim_name
	_sprite.play(anim_key)


func play_once(anim_name: String, direction: String, on_finish: Callable = Callable()) -> void:
	"""Play a one-shot animation then call on_finish."""
	var anim_key := "%s_%s" % [anim_name, direction]
	if not _sprite.sprite_frames or not _sprite.sprite_frames.has_animation(anim_key):
		if on_finish.is_valid():
			on_finish.call()
		return

	_current_anim = anim_name
	_sprite.play(anim_key)

	# Wait for animation to finish
	if not _sprite.animation_finished.is_connected(_on_oneshot_finished):
		_sprite.animation_finished.connect(_on_oneshot_finished.bind(on_finish), CONNECT_ONE_SHOT)


func _on_oneshot_finished(on_finish: Callable) -> void:
	if on_finish.is_valid():
		on_finish.call()


# =============================================================================
# State → Animation mapping
# =============================================================================

func _state_to_anim(state: int, move_dir: Vector2, enemies_nearby: bool) -> String:
	# Guardian.State enum: IDLE=0, MOVING=1, ATTACKING=2, DODGING=3, KNOCKBACK=4, DEAD=5
	match state:
		0:  # IDLE
			return "fight_idle" if enemies_nearby else "breathing_idle"
		1:  # MOVING
			return "walk"
		2:  # ATTACKING
			return "attack"
		3:  # DODGING
			return "walk"  # dodge uses walk frames at higher speed
		4:  # KNOCKBACK
			return "taking_punch"
		5:  # DEAD
			return "taking_punch"
		_:
			return "idle"


# =============================================================================
# Direction from vector
# =============================================================================

func _vector_to_direction(vec: Vector2) -> String:
	if vec.length() < 0.1:
		return _current_dir  # Keep last direction

	var angle := vec.angle()  # Radians, 0 = right (east)
	# Convert to degrees, normalise to 0-360
	var deg := fmod(rad_to_deg(angle) + 360.0, 360.0)

	# 8 directions, each 45° wide, offset by 22.5°
	# East=0°, South-East=45°, South=90°, South-West=135°
	# West=180°, North-West=225°, North=270°, North-East=315°
	if deg < 22.5 or deg >= 337.5:
		return "east"
	elif deg < 67.5:
		return "south-east"
	elif deg < 112.5:
		return "south"
	elif deg < 157.5:
		return "south-west"
	elif deg < 202.5:
		return "west"
	elif deg < 247.5:
		return "north-west"
	elif deg < 292.5:
		return "north"
	else:
		return "north-east"
