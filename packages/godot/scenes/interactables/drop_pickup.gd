class_name DropPickup
extends Area2D
## DropPickup — A collectible that spawns on the floor after a breakable is smashed.
## Floats slightly (tween) then waits for guardian body overlap to collect.
## Auto-collects after LIFETIME seconds if uncollected.
##
## pickup_type: "fragment" | "heart"
## amount: how much to award (fragments = count, heart = 0.5 per unit)

@export var pickup_type: String = "fragment"
@export var amount: int = 1

const LIFETIME: float = 12.0          # Auto-award after this many seconds
const FLOAT_HEIGHT: float = 14.0       # How far it bobs upward on spawn
const COLLECT_FLASH_DURATION: float = 0.08

var _collected: bool = false
var _lifetime_timer: float = 0.0

@onready var _visual: ColorRect = $Visual
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Colour by type
	if pickup_type == "fragment":
		_visual.color = Color(0.35, 0.65, 1.0)   # cool blue — dream fragment
	else:
		_visual.color = Color(0.9, 0.2, 0.3)      # red — heart

	# Float up from spawn point
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", position.y - FLOAT_HEIGHT, 0.18)

	# Gentle idle bob after landing
	var bob := create_tween().set_loops()
	bob.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(self, "position:y", position.y - FLOAT_HEIGHT - 3.0, 0.55)
	bob.tween_property(self, "position:y", position.y - FLOAT_HEIGHT + 3.0, 0.55)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _collected:
		return
	_lifetime_timer += delta
	if _lifetime_timer >= LIFETIME:
		_collect()  # Award and disappear even if not touched


func _on_body_entered(body: Node) -> void:
	if _collected:
		return
	if body.is_in_group("guardian"):
		_collect()


func _collect() -> void:
	if _collected:
		return
	_collected = true
	_collision.set_deferred("disabled", true)

	# Flash and disappear
	var tween := create_tween()
	tween.tween_property(_visual, "color", Color(1.0, 1.0, 1.0, 1.0), COLLECT_FLASH_DURATION)
	tween.tween_property(_visual, "self_modulate:a", 0.0, 0.1)
	tween.tween_callback(queue_free)

	# Award
	match pickup_type:
		"fragment":
			GameManager.award_dreamer_fragments(amount)
			print("[PICKUP] Fragment x", amount, " collected")
		"heart":
			# Each 'amount' unit = 0.5 hearts
			GameManager.heal_guardian(0.5 * amount)
			print("[PICKUP] Heart fragment collected (+", 0.5 * amount, " HP)")
