extends Control
## UpgradeScreen - Choose 1 of 3 memory upgrade cards between floors.
## Both players see this simultaneously. Each makes their own choice.

# Hardcoded cards for prototype -- expand into a proper pool later
const UPGRADE_POOL: Array[Dictionary] = [
	{
		"id": "birthday_candle",
		"name": "A Birthday Candle",
		"description": "Your attacks leave a trail of light for 1.8 seconds.\nEnemies walking through it take 0.75 damage.",
		"category": "combat",
	},
	{
		"id": "smell_of_rain",
		"name": "The Smell of Rain",
		"description": "Your dodge roll blooms colour on the floor.\nEnemies inside are slowed for 2.5 seconds.",
		"category": "survival",
	},
	{
		"id": "someones_hand",
		"name": "Someone's Hand",
		"description": "Healing events restore 20% more HP.\nClearing a room restores a sliver of health.",
		"category": "dream",
	},
	{
		"id": "warm_blanket",
		"name": "A Warm Blanket",
		"description": "+1 maximum heart.\nSomething safe wraps around you.",
		"category": "survival",
	},
	{
		"id": "favourite_song",
		"name": "A Favourite Song",
		"description": "Your attack arc is 40% wider and your reach extends further.\nThe melody guides your reach.",
		"category": "combat",
	},
	{
		"id": "steady_breathing",
		"name": "Steady Breathing",
		"description": "Gain a ghost heart. Absorbs one hit,\nthen fades. Does not regenerate.",
		"category": "survival",
	},
]

var _offered_upgrades: Array[Dictionary] = []
var _selected: bool = false

@onready var _card_container: HBoxContainer = $CardContainer
@onready var _floor_label: Label = $FloorLabel
@warning_ignore("unused_private_class_variable")
@onready var _skip_label: Label = $SkipLabel  # Reserved for "press X to skip" hint


func _ready() -> void:
	add_to_group("upgrade_screen")
	_floor_label.text = "Floor %d cleared" % GameManager.current_floor
	_offered_upgrades = _pick_three_upgrades()

	# Brief darkness before cards appear (Pillar 5 — breath moment)
	modulate.a = 0.0
	var intro := create_tween()
	intro.tween_property(self, "modulate:a", 1.0, 0.35)
	intro.tween_callback(_build_cards)


func _pick_three_upgrades() -> Array[Dictionary]:
	var pool := UPGRADE_POOL.duplicate()
	pool.shuffle()
	return pool.slice(0, 3)


func _build_cards() -> void:
	for child in _card_container.get_children():
		child.queue_free()

	for i in _offered_upgrades.size():
		var upgrade: Dictionary = _offered_upgrades[i]
		var card := _create_card(upgrade, i)
		card.modulate.a = 0.0
		# Start off-screen below, slide up staggered (Pillar 5)
		card.position.y += 60.0
		_card_container.add_child(card)

		var delay: float = 0.08 * i
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_property(card, "modulate:a", 1.0, 0.22)
		tween.parallel().tween_property(card, "position:y", card.position.y - 60.0, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)


func _create_card(upgrade: Dictionary, _index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 300)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.14, 0.95)
	style.border_color = Color(0.3, 0.25, 0.5, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	# Category tag
	var category_label := Label.new()
	match upgrade.get("category", ""):
		"combat":   category_label.text = "COMBAT"
		"survival": category_label.text = "SURVIVAL"
		"dream":    category_label.text = "DREAM POWER"
	category_label.add_theme_font_size_override("font_size", 16)
	category_label.modulate = Color(0.5, 0.4, 0.8, 0.8)
	vbox.add_child(category_label)

	# Name
	var name_label := Label.new()
	name_label.text = upgrade.get("name", "")
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_label)

	# Description
	var desc_label := Label.new()
	desc_label.text = upgrade.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 20)
	desc_label.modulate = Color(0.8, 0.8, 0.85)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Select button
	var btn := Button.new()
	btn.text = "Remember this"
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(_on_card_selected.bind(upgrade, panel))
	vbox.add_child(btn)

	panel.add_child(vbox)
	return panel


func _on_card_selected(upgrade: Dictionary, card: PanelContainer) -> void:
	if _selected:
		return
	_selected = true

	# Flash selected card white, fade out others, then advance (Pillar 6)
	var tween := create_tween()
	tween.tween_property(card, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.1)
	tween.tween_property(card, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)
	for child in _card_container.get_children():
		if child != card:
			tween.parallel().tween_property(child, "modulate:a", 0.0, 0.2)
	tween.tween_interval(0.25)
	tween.tween_callback(func():
		_apply_upgrade(upgrade)
		GameManager.advance_floor()
	)


func _apply_upgrade(upgrade: Dictionary) -> void:
	GameManager.apply_upgrade_to_state(upgrade.get("id", ""))


func _input(event: InputEvent) -> void:
	# Allow skipping with Escape (no upgrade)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _selected:
			_selected = true
			GameManager.advance_floor()
