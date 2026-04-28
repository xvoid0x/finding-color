class_name Breakable
extends StaticBody2D
## Breakable — Pot/debris that can be smashed by attack arc or dodge roll.
## Drops Dream Fragments or Heart Fragments at configurable rates.
##
## Break triggers:
##   - Guardian attack arc overlaps this body (add_to_group("breakable"))
##   - Guardian dodge roll body overlaps this (checked in guardian.gd)
##
## Drop rates (default, tunable via @export):
##   - fragment_chance: 0.65  →  65% to drop 1-2 Dream Fragments
##   - heart_chance:    0.20  →  20% to drop a half-heart pickup
##   - nothing:         0.15  →  15% empty

@export var fragment_chance: float = 0.65
@export var heart_chance:    float = 0.20
# nothing_chance = 1.0 - fragment_chance - heart_chance (implicit)

@export var fragment_amount_min: int = 1
@export var fragment_amount_max: int = 2

var _broken: bool = false

# Preload the pickup scene — set in _ready so we don't hard-fail on missing asset
var _pickup_scene: PackedScene = null

@onready var _visual: ColorRect = $Visual  # placeholder — swap for Sprite2D when art exists
@onready var _collision: CollisionShape2D  = $CollisionShape2D


func _ready() -> void:
	add_to_group("breakable")
	_pickup_scene = load("res://scenes/interactables/drop_pickup.tscn") if \
		ResourceLoader.exists("res://scenes/interactables/drop_pickup.tscn") else null


func smash(source: String = "attack") -> void:
	"""Break this pot. source = "attack" | "dodge" """
	if _broken:
		return
	_broken = true

	GameManager.stat_pots_smashed += 1

	# Disable collision immediately
	_collision.set_deferred("disabled", true)

	# Visual break: flash white then vanish
	var tween := create_tween()
	tween.tween_property(_visual, "color", Color(1.0, 1.0, 1.0, 1.0), 0.05)
	tween.tween_property(_visual, "self_modulate:a", 0.0, 0.12)
	tween.tween_callback(queue_free)

	# Juice: light hitstop + small shake
	HitstopManager.hit()
	CameraShaker.shake(3.0, 0.08)

	# Drop
	_roll_drop()


func _roll_drop() -> void:
	var roll := randf()

	if roll < fragment_chance:
		# Drop Dream Fragments
		var amount := randi_range(fragment_amount_min, fragment_amount_max)
		_spawn_pickup("fragment", amount)
	elif roll < fragment_chance + heart_chance:
		# Drop a half-heart
		_spawn_pickup("heart", 1)
	# else: nothing drops — ~15% of the time


func _spawn_pickup(pickup_type: String, amount: int) -> void:
	if _pickup_scene == null:
		# Fallback: award directly with no animation
		_award_direct(pickup_type, amount)
		return

	var pickup: DropPickup = _pickup_scene.instantiate()
	pickup.pickup_type = pickup_type
	pickup.amount = amount
	pickup.position = global_position
	# Deferred — can't add children during physics query flush
	get_parent().call_deferred("add_child", pickup)


func _award_direct(pickup_type: String, amount: int) -> void:
	"""Fallback when pickup scene isn't available yet (early dev)."""
	match pickup_type:
		"fragment":
			GameManager.award_dreamer_fragments(amount)
		"heart":
			GameManager.heal_guardian(0.5)
