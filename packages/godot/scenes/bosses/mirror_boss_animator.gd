extends Node
## MirrorBossAnimator — Drives the mirror boss AnimatedSprite2D based on movement direction.
## Uses the 8-direction rotation sprites from Pixellab character generation.

const DIRECTIONS := ["south", "south-west", "west", "north-west", "north", "north-east", "east", "south-east"]
const SPRITE_BASE := "res://assets/characters/mirror_boss/rotations/"

@onready var _sprite: AnimatedSprite2D = $"../AnimatedSprite2D"

var _current_dir: String = "south"


func _ready() -> void:
	if not _sprite:
		push_error("[MIRROR_ANIM] AnimatedSprite2D not found")
		return
	_build_sprite_frames()
	play("south")


func _build_sprite_frames() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for direction in DIRECTIONS:
		var anim_key := "idle_%s" % direction
		var path := "%s%s.png" % [SPRITE_BASE, direction]

		if not ResourceLoader.exists(path):
			push_warning("[MIRROR_ANIM] Missing sprite: %s" % path)
			continue

		var texture := load(path) as Texture2D
		if not texture:
			continue

		frames.add_animation(anim_key)
		frames.set_animation_speed(anim_key, 1)
		frames.set_animation_loop(anim_key, true)
		frames.add_frame(anim_key, texture)

	_sprite.sprite_frames = frames
	_sprite.scale = Vector2(0.6, 0.6)
	print("[MIRROR_ANIM] SpriteFrames built: %d directions" % frames.get_animation_names().size())


func set_direction(direction: String) -> void:
	if direction == _current_dir:
		return
	_current_dir = direction
	play(direction)


func play(direction: String) -> void:
	if not _sprite or not _sprite.sprite_frames:
		return
	var anim_key := "idle_%s" % direction
	if not _sprite.sprite_frames.has_animation(anim_key):
		return
	if _sprite.animation == anim_key:
		return
	_sprite.play(anim_key)


func get_dir_from_vector(vec: Vector2) -> String:
	return DirectionUtils.vector_to_direction(vec, _current_dir)
