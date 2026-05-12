class_name MirrorReflection
extends CharacterBody2D
## MirrorReflection — The distorted copy of the guardian spawned by The Mirror boss.
##
## Chases the guardian. Uses the guardian sprite with a desaturated, darkened tint.
## Emits `died` when destroyed. The Mirror listens for this.

signal died()

@export var move_speed: float = 200.0
@export var hp: float = 1.0
@export var damage_on_contact: float = 1.0
@export var contact_cooldown: float = 0.8

const SPRITESHEETS_BASE := "res://assets/characters/guardian/spritesheets/"
const DIRECTIONS := ["south", "south-west", "west", "north-west", "north", "north-east", "east", "south-east"]
const ANIM_WALK_FPS := 10
const ANIM_WALK_FRAMES := 8
const FRAME_SIZE := Vector2(176, 176)

var _is_dead: bool = false
var _contact_timer: float = 0.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("enemies")
	_build_sprite_frames()


func _build_sprite_frames() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for direction in DIRECTIONS:
		var anim_key := "walk_%s" % direction
		var sheet_path := "%swalk_%s.png" % [SPRITESHEETS_BASE, direction]

		if not ResourceLoader.exists(sheet_path):
			continue

		var texture := load(sheet_path) as Texture2D
		if not texture:
			continue

		frames.add_animation(anim_key)
		frames.set_animation_speed(anim_key, ANIM_WALK_FPS)
		frames.set_animation_loop(anim_key, true)

		# Slice spritesheet into individual frames
		var atlas_w: int = texture.get_width()
		var frame_w: int = atlas_w / ANIM_WALK_FRAMES
		var frame_h: int = int(FRAME_SIZE.y)

		for i in ANIM_WALK_FRAMES:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
			frames.add_frame(anim_key, atlas)

	_sprite.sprite_frames = frames
	# Darken and desaturate the reflection
	_sprite.modulate = Color(0.4, 0.35, 0.45, 0.85)
	play("walk", "south")


func play(anim_name: String, direction: String) -> void:
	var anim_key := "%s_%s" % [anim_name, direction]
	if not _sprite.sprite_frames or not _sprite.sprite_frames.has_animation(anim_key):
		return
	_sprite.play(anim_key)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	var guardian := get_tree().get_first_node_in_group("guardian") as Node2D
	if not guardian:
		return

	_contact_timer = max(_contact_timer - delta, 0.0)

	# Chase the guardian
	var dir: Vector2 = (guardian.global_position - global_position)
	var dist: float = dir.length()
	if dist > 30.0:
		var move_dir := dir.normalized()
		velocity = move_dir * move_speed
		move_and_slide()
		# Update facing direction
		var deg := fmod(rad_to_deg(move_dir.angle()) + 360.0, 360.0)
		var dir_name := _angle_to_dir(deg)
		play("walk", dir_name)
	else:
		velocity = Vector2.ZERO

	# Contact damage
	if dist < 50.0 and _contact_timer <= 0.0:
		GameManager.damage_guardian(damage_on_contact)
		_contact_timer = contact_cooldown


func _angle_to_dir(deg: float) -> String:
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


func take_damage(amount: float, _aim_dir: Vector2 = Vector2.ZERO) -> void:
	if _is_dead:
		return
	hp -= amount
	# Flash
	_sprite.modulate = Color(1.0, 0.5, 0.5, 0.95)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", Color(0.4, 0.35, 0.45, 0.85), 0.1)

	if hp <= 0.0:
		_die()


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_collision.set_deferred("disabled", true)
	velocity = Vector2.ZERO
	died.emit()

	# Shatter visual
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)
