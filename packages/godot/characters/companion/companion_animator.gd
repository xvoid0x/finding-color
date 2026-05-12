extends Node
## CompanionAnimator — Drives the companion's AnimatedSprite2D with breathing-idle animation.
## Companion only has one animation (breathing-idle) across 8 directions.
## Direction is set by companion.gd based on position relative to guardian.

const DIRECTIONS := [
	"south", "south-west", "west", "north-west",
	"north", "north-east", "east", "south-east"
]

const ANIM_BASE := "res://assets/characters/companion/animations/animating-1b4875a4/"
const FRAME_COUNT := 4
const FPS := 6

@onready var _sprite: AnimatedSprite2D = $"../AnimatedSprite2D"

var _current_dir: String = "south"


func _ready() -> void:
	if not _sprite:
		push_error("[COMP_ANIM] AnimatedSprite2D not found")
		return
	_build_sprite_frames()
	play("south")


func _build_sprite_frames() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for direction in DIRECTIONS:
		var anim_key := "breathing_idle_%s" % direction

		frames.add_animation(anim_key)
		frames.set_animation_speed(anim_key, FPS)
		frames.set_animation_loop(anim_key, true)

		for i in FRAME_COUNT:
			var frame_path := "%s%s/frame_%s.png" % [ANIM_BASE, direction, "%03d" % i]
			if not ResourceLoader.exists(frame_path):
				push_warning("[COMP_ANIM] Missing frame: %s" % frame_path)
				continue
			var texture := load(frame_path) as Texture2D
			if not texture:
				continue
			frames.add_frame(anim_key, texture)

	_sprite.sprite_frames = frames
	print("[COMP_ANIM] SpriteFrames built: %d animations" % frames.get_animation_names().size())


func set_direction(direction: String) -> void:
	if direction == _current_dir:
		return
	_current_dir = direction
	play(direction)


func play(direction: String) -> void:
	if not _sprite or not _sprite.sprite_frames:
		return
	var anim_key := "breathing_idle_%s" % direction
	if not _sprite.sprite_frames.has_animation(anim_key):
		return
	if _sprite.animation == anim_key and _sprite.is_playing():
		return
	_sprite.play(anim_key)