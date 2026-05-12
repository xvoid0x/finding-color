extends Node2D
## Chest - Interactable. Guardian gets nearby, presses E, companion anchors.
## Phone event (chest_unlock) is triggered automatically via companion_anchored signal.
## On success: companion is freed and chest opens (drops loot).

var _guardian_nearby: bool = false
var _opened: bool = false
var _enabled: bool = false

@onready var _visual: Sprite2D = $ChestVisual
@onready var _interact_area: Area2D = $InteractArea


func _ready() -> void:
	add_to_group("chests")
	_interact_area.monitoring = false  # Disabled until room enables this chest
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)
	EventBus.companion_freed.connect(_on_companion_freed)


func enable() -> void:
	"""Called by RoomBase when has_chest = true."""
	_enabled = true
	_interact_area.monitoring = true


func _process(_delta: float) -> void:
	if not _enabled or _opened or not _guardian_nearby:
		return
	if Input.is_action_just_pressed("interact"):
		_trigger_unlock()


func _trigger_unlock() -> void:
	var companion := get_tree().get_first_node_in_group("companion")
	if companion and companion.has_method("anchor_to"):
		companion.anchor_to(self)
		# Brief visual pulse
		var tween := create_tween()
		tween.tween_property(_visual, "modulate", Color(1.6, 1.4, 0.8, 1.0), 0.15)
		tween.tween_property(_visual, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)


func _on_companion_freed() -> void:
	if not _enabled or _opened:
		return
	_opened = true
	GameManager.stat_chests_opened += 1
	# Open visual: gold flash
	var tween := create_tween()
	tween.tween_property(_visual, "modulate", Color(2.0, 1.8, 0.5, 1.0), 0.1)
	tween.tween_property(_visual, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.3)
	# TODO: Spawn loot drops at position


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("guardian"):
		_guardian_nearby = true


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("guardian"):
		_guardian_nearby = false
