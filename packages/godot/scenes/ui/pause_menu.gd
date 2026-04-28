extends CanvasLayer
## PauseMenu - In-game pause overlay.
## Added to the scene tree by RoomBase. Instances shared OptionsPanel.
## process_mode = PROCESS_MODE_WHEN_PAUSED keeps it live while tree is frozen.

@onready var _resume_btn: Button    = $Panel/ResumeButton
@onready var _options_btn: Button   = $Panel/OptionsButton
@onready var _quit_btn: Button      = $Panel/QuitToTitleButton
@onready var _options_panel: Control = $OptionsPanelRoot/OptionsPanel


func _ready() -> void:
	_resume_btn.pressed.connect(_on_resume)
	_options_btn.pressed.connect(_on_options)
	_quit_btn.pressed.connect(_on_quit_to_title)
	_options_panel.close_requested.connect(_on_options_closed)
	_options_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		if _options_panel.visible:
			# Close options first, stay paused
			_on_options_closed()
		elif visible:
			_on_resume()
		else:
			_open()


func _open() -> void:
	visible = true
	get_tree().paused = true
	_resume_btn.grab_focus()
	# Notify phone player
	if PhoneManager:
		PhoneManager.send_pause_state(true)


func _on_resume() -> void:
	_options_panel.visible = false
	visible = false
	get_tree().paused = false
	# Notify phone player
	if PhoneManager:
		PhoneManager.send_pause_state(false)


func _on_options() -> void:
	_options_panel.open()


func _on_options_closed() -> void:
	_options_panel.visible = false
	_resume_btn.grab_focus()


func _on_quit_to_title() -> void:
	get_tree().paused = false
	get_tree().call_deferred("change_scene_to_file", "res://scenes/menus/title_screen.tscn")
