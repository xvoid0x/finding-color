extends Control
## EndScreen - Post-run stats. Death or victory.

@onready var _title_label: Label = $TitleLabel
@onready var _subtitle_label: Label = $SubtitleLabel
@onready var _guardian_stats: VBoxContainer = $StatsContainer/GuardianStats
@onready var _phone_stats: VBoxContainer = $StatsContainer/PhoneStats
@onready var _fragments_label: Label = $RewardsContainer/FragmentsLabel
@onready var _continue_btn: Button = $ContinueButton


func _ready() -> void:
	var stats: Dictionary = GameManager.get_stats()
	var cause: String = GameManager.last_run_cause

	_setup_title(cause)
	_populate_guardian_stats(stats)
	_populate_phone_stats(stats)
	_populate_rewards(stats)

	_continue_btn.pressed.connect(_on_continue)

	# On victory, bleed colour into the UI
	if cause == "victory":
		_play_victory_colour_effect()


func _setup_title(cause: String) -> void:
	match cause:
		"death":
			_title_label.text = "The nightmare recedes..."
			_subtitle_label.text = "...for now."
			_title_label.modulate = Color(0.7, 0.7, 0.8)
		"victory":
			_title_label.text = "The child stirs..."
			_subtitle_label.text = "Light finds its way back."
			_title_label.modulate = Color(1.0, 0.9, 0.5)


func _populate_guardian_stats(stats: Dictionary) -> void:
	_add_stat_row(_guardian_stats, "Floor reached", str(stats.get("floor_reached", 0)))
	_add_stat_row(_guardian_stats, "Enemies defeated", str(stats.get("enemies_killed", 0)))
	_add_stat_row(_guardian_stats, "Hearts lost", "%.1f" % stats.get("hearts_lost", 0.0))
	_add_stat_row(_guardian_stats, "Chests opened", str(stats.get("chests_opened", 0)))
	_add_stat_row(_guardian_stats, "Pots smashed", str(stats.get("pots_smashed", 0)))


func _populate_phone_stats(stats: Dictionary) -> void:
	var triggered: int = stats.get("phone_events_triggered", 0)
	var landed: int = stats.get("phone_events_landed", 0)
	var accuracy: String = "N/A"
	if triggered > 0:
		accuracy = "%d%%" % int(float(landed) / float(triggered) * 100.0)

	_add_stat_row(_phone_stats, "Events triggered", str(triggered))
	_add_stat_row(_phone_stats, "Events landed", str(landed))
	_add_stat_row(_phone_stats, "Accuracy", accuracy)


func _populate_rewards(stats: Dictionary) -> void:
	# Base fragments earned: 2 per floor + 1 per 10 enemies
	var fragments: int = stats.get("floor_reached", 0) * 2
	fragments += stats.get("enemies_killed", 0) / 10
	_fragments_label.text = "+%d Dream Fragments" % fragments


func _add_stat_row(container: VBoxContainer, label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 22)
	label.modulate = Color(0.7, 0.7, 0.8)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 22)

	row.add_child(label)
	row.add_child(value)
	container.add_child(row)


func _play_victory_colour_effect() -> void:
	# Gradually tint the background warmer on victory
	var bg := get_node_or_null("Background")
	if bg:
		var tween := create_tween()
		tween.tween_property(bg, "modulate", Color(1.0, 0.9, 0.7), 3.0)


func _on_continue() -> void:
	get_tree().call_deferred("change_scene_to_file", "res://scenes/menus/title_screen.tscn")
