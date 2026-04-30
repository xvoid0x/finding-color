extends Control
## OptionsPanel — shared options UI instanced by both title screen and pause menu.
## Reads initial state from SettingsManager, writes back via SettingsManager setters.
## Emit close_requested to tell the parent to hide this panel.

signal close_requested

@onready var _fullscreen_toggle: CheckButton  = $MarginContainer/ScrollContainer/ContentVBox/FullscreenRow/FullscreenToggle
@onready var _master_slider: HSlider          = $MarginContainer/ScrollContainer/ContentVBox/MasterVolumeRow/MasterSlider
@onready var _master_value: Label             = $MarginContainer/ScrollContainer/ContentVBox/MasterVolumeRow/MasterValueLabel
@onready var _sfx_slider: HSlider             = $MarginContainer/ScrollContainer/ContentVBox/SFXVolumeRow/SFXSlider
@onready var _sfx_value: Label                = $MarginContainer/ScrollContainer/ContentVBox/SFXVolumeRow/SFXValueLabel
@onready var _music_slider: HSlider           = $MarginContainer/ScrollContainer/ContentVBox/MusicVolumeRow/MusicSlider
@onready var _music_value: Label              = $MarginContainer/ScrollContainer/ContentVBox/MusicVolumeRow/MusicValueLabel
@onready var _shake_option: OptionButton      = $MarginContainer/ScrollContainer/ContentVBox/ScreenShakeRow/ShakeOptionButton
@onready var _rumble_toggle: CheckButton      = $MarginContainer/ScrollContainer/ContentVBox/RumbleRow/RumbleToggle
@onready var _flash_toggle: CheckButton       = $MarginContainer/ScrollContainer/ContentVBox/FlashRow/FlashToggle
@onready var _room_code_value: Label          = $MarginContainer/ScrollContainer/ContentVBox/RoomCodeRow/RoomCodeValue
@onready var _reconnect_btn: Button           = $MarginContainer/ScrollContainer/ContentVBox/ReconnectRow/ReconnectButton
@onready var _close_btn: Button               = $CloseButton


func _ready() -> void:
	# Populate screen shake options
	_shake_option.clear()
	_shake_option.add_item("Off",  0)
	_shake_option.add_item("Low",  1)
	_shake_option.add_item("High", 2)

	# Load current settings into controls
	_fullscreen_toggle.button_pressed = SettingsManager.fullscreen
	_master_slider.value  = SettingsManager.volume_master
	_sfx_slider.value     = SettingsManager.volume_sfx
	_music_slider.value   = SettingsManager.volume_music
	_shake_option.selected = SettingsManager.screen_shake
	_rumble_toggle.button_pressed  = SettingsManager.controller_rumble
	_flash_toggle.button_pressed   = SettingsManager.reduce_flashing

	_update_value_labels()
	_update_room_code()

	# Connect controls
	_fullscreen_toggle.toggled.connect(func(v: bool): SettingsManager.set_fullscreen(v))
	_master_slider.value_changed.connect(_on_master_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_shake_option.item_selected.connect(func(i: int): SettingsManager.set_screen_shake(i))
	_rumble_toggle.toggled.connect(func(v: bool): SettingsManager.set_controller_rumble(v))
	_flash_toggle.toggled.connect(func(v: bool): SettingsManager.set_reduce_flashing(v))
	_reconnect_btn.pressed.connect(_on_reconnect)
	_close_btn.pressed.connect(func(): close_requested.emit())


func open() -> void:
	_update_room_code()
	visible = true
	_close_btn.grab_focus()


func _on_master_changed(value: float) -> void:
	SettingsManager.set_volume_master(value)
	_master_value.text = str(int(value * 100))


func _on_sfx_changed(value: float) -> void:
	SettingsManager.set_volume_sfx(value)
	_sfx_value.text = str(int(value * 100))


func _on_music_changed(value: float) -> void:
	SettingsManager.set_volume_music(value)
	_music_value.text = str(int(value * 100))


func _on_reconnect() -> void:
	if PhoneManager:
		_reconnect_btn.text = "Reconnecting..."
		_reconnect_btn.disabled = true
		PhoneManager.connect_ably()
		# Re-enable after a moment regardless of result
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(_reconnect_btn):
				_reconnect_btn.text = "Reconnect Phone"
				_reconnect_btn.disabled = false
		)


func _update_value_labels() -> void:
	_master_value.text = str(int(SettingsManager.volume_master * 100))
	_sfx_value.text    = str(int(SettingsManager.volume_sfx * 100))
	_music_value.text  = str(int(SettingsManager.volume_music * 100))


func _update_room_code() -> void:
	var code := SettingsManager.room_code
	_room_code_value.text = code if code != "" else "----"
