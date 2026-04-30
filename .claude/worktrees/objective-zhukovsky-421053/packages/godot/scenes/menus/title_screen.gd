extends Control
## TitleScreen - Main menu. New Run, Options, Quit.

@onready var _title_label: Label       = $TitleLabel
@onready var _room_code_label: Label   = $RoomCodeLabel
@onready var _phone_status_label: Label = $PhoneStatusLabel
@onready var _new_run_btn: Button      = $MenuContainer/NewRunButton
@onready var _options_btn: Button      = $MenuContainer/OptionsButton
@onready var _quit_btn: Button         = $MenuContainer/QuitButton
@onready var _options_panel: Control   = $OptionsPanel

var _blink_timer: float = 0.0
var _room_code: String = ""


func _ready() -> void:
	_room_code = PhoneManager.generate_room_code()
	_room_code_label.text = "Room code: %s  •  findingcolour.app" % _room_code

	_new_run_btn.pressed.connect(_on_new_run)
	_options_btn.pressed.connect(_on_options)
	_quit_btn.pressed.connect(_on_quit)
	_options_panel.close_requested.connect(_on_options_closed)

	_options_panel.visible = false

	EventBus.phone_player_joined.connect(_on_phone_joined)
	PhoneManager.connect_ably()

	_new_run_btn.grab_focus()


func _process(delta: float) -> void:
	_blink_timer += delta * 1.8
	_title_label.modulate.a = 0.9 + sin(_blink_timer * 0.4) * 0.1


func _on_new_run() -> void:
	GameManager.start_run()


func _on_options() -> void:
	_options_panel.open()


func _on_options_closed() -> void:
	_options_panel.visible = false
	_new_run_btn.grab_focus()


func _on_quit() -> void:
	get_tree().quit()


func _on_phone_joined(_peer_id: int) -> void:
	_phone_status_label.text = "● Phone player connected"
	_phone_status_label.modulate = Color(0.3, 1.0, 0.5)
