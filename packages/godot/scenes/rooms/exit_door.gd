extends Node2D
## ExitDoor - Door between rooms (or floor exit).
## Locked until all enemies are cleared.
## Unlocks when RoomBase calls unlock(). Guardian walks through to transition.

@export var to_room_id: int = -1

var _locked: bool = true

@onready var _visual: ColorRect = $DoorVisual
@onready var _player_detector: Area2D = $PlayerDetector


func _ready() -> void:
	_player_detector.monitoring = false
	_player_detector.body_entered.connect(_on_body_entered)


func unlock() -> void:
	if not _locked:
		return
	_locked = false
	_player_detector.monitoring = true
	# Brighten to show it's passable
	var tween := create_tween()
	tween.tween_property(_visual, "color", Color(0.2, 0.7, 0.4, 1.0), 0.4)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("guardian"):
		return

	# Determine if this door leads to the floor exit
	var is_exit: bool = false
	if to_room_id == -1:
		is_exit = true
	elif FloorManager.current_map.has("room_types"):
		var room_type: String = FloorManager.current_map.room_types.get(to_room_id, "combat")
		is_exit = (room_type == "exit")

	if is_exit:
		# Floor complete — go to upgrade screen
		GameManager.exit_room()
	else:
		# Move to next room in the floor
		FloorManager.enter_room(to_room_id)
		# Reload room scene
		get_tree().call_deferred("change_scene_to_file", "res://scenes/rooms/room_template.tscn")
