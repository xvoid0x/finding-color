class_name ShadowGeyser
extends Node2D
## Shadow Geyser — Destructible floor hazard.
##
## Pulses a dark column upward every PULSE_INTERVAL seconds.
## The column blocks movement and deals contact damage.
## Destroyed after HITS_TO_DESTROY guardian hits.
##
## Telegraphed by a brief darkening below the vent before each pulse.
## Tests player positioning and makes open rooms more interesting.

signal destroyed()
signal pulsed()

enum GeyserState { IDLE, TELEGRAPH, ACTIVE, RECOVERING }

@export var pulse_interval: float = 4.0
@export var telegraph_duration: float = 0.6
@export var active_duration: float = 1.2
@export var recover_duration: float = 0.3
@export var hits_to_destroy: int = 3
@export var column_width: float = 64.0
@export var column_height: float = 160.0
@export var column_damage: float = 1.0
@export var damage_cooldown: float = 0.5

var _state: GeyserState = GeyserState.IDLE
var _state_timer: float = 0.0
var _hits_remaining: int
var _is_destroyed: bool = false
var _damage_timer: float = 0.0

## Visual nodes
var _vent_base: ColorRect
var _telegraph_glow: ColorRect
var _column: ColorRect
var _column_collision: Area2D
var _hitbox_area: Area2D

## Crack shader material (shared with enemies)
var _sprite_mat: ShaderMaterial = null


func _ready() -> void:
	_hits_remaining = hits_to_destroy
	add_to_group("hazards")
	
	_build_visuals()
	_build_collision()
	
	# Start cycle
	_state_timer = pulse_interval - telegraph_duration - active_duration - recover_duration
	_state = GeyserState.IDLE
	_update_visuals()


func _build_visuals() -> void:
	## Vent base — dark grate on the floor
	_vent_base = ColorRect.new()
	_vent_base.size = Vector2(48, 16)
	_vent_base.position = Vector2(-24, -8)
	_vent_base.color = Color(0.12, 0.08, 0.12, 1.0)
	_vent_base.z_index = 0
	add_child(_vent_base)
	
	## Telegraph glow — faint pulse that appears before the column
	_telegraph_glow = ColorRect.new()
	_telegraph_glow.size = Vector2(column_width + 16, column_height + 16)
	_telegraph_glow.position = Vector2(-(column_width + 16) / 2, -column_height - 16)
	_telegraph_glow.color = Color(0.15, 0.05, 0.2, 0.0)  # invisible until telegraph
	_telegraph_glow.z_index = 1
	add_child(_telegraph_glow)
	
	## Column — the hazard
	_column = ColorRect.new()
	_column.size = Vector2(column_width, column_height)
	_column.position = Vector2(-column_width / 2, -column_height)
	_column.color = Color(0.05, 0.02, 0.08, 0.85)
	_column.z_index = 2
	_column.visible = false
	add_child(_column)
	
	## Column glow overlay
	var glow := ColorRect.new()
	glow.name = "ColumnGlow"
	glow.size = Vector2(column_width + 12, column_height + 12)
	glow.position = Vector2(-(column_width + 12) / 2, -column_height - 6)
	glow.color = Color(0.2, 0.05, 0.3, 0.35)
	glow.z_index = 2
	glow.visible = false
	_column.add_child(glow)


func _build_collision() -> void:
	## Column collision — blocks guardian movement + deals damage
	_column_collision = Area2D.new()
	_column_collision.position = Vector2(0, -column_height / 2)
	
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(column_width, column_height)
	shape.shape = rect
	_column_collision.add_child(shape)
	
	_column_collision.body_entered.connect(_on_column_body_entered)
	_column_collision.area_entered.connect(_on_column_area_entered)
	
	_column_collision.monitoring = false
	_column_collision.monitorable = false
	add_child(_column_collision)
	
	## Hitbox — guardian hits this to destroy the geyser
	_hitbox_area = Area2D.new()
	_hitbox_area.position = Vector2(0, 0)
	
	var hit_shape := CollisionShape2D.new()
	var hit_rect := RectangleShape2D.new()
	hit_rect.size = Vector2(48, 16)
	hit_shape.shape = hit_rect
	_hitbox_area.add_child(hit_shape)
	
	_hitbox_area.area_entered.connect(_on_hitbox_area_entered)
	add_child(_hitbox_area)


# =============================================================================
# State Machine
# =============================================================================

func _process(delta: float) -> void:
	if _is_destroyed:
		return
	
	_damage_timer = maxf(0.0, _damage_timer - delta)
	_state_timer -= delta
	
	if _state_timer <= 0.0:
		_advance_state()


func _advance_state() -> void:
	match _state:
		GeyserState.IDLE:
			_state = GeyserState.TELEGRAPH
			_state_timer = telegraph_duration
			_on_telegraph_start()
		
		GeyserState.TELEGRAPH:
			_state = GeyserState.ACTIVE
			_state_timer = active_duration
			_on_column_rise()
		
		GeyserState.ACTIVE:
			_state = GeyserState.RECOVERING
			_state_timer = recover_duration
			_on_column_retract()
		
		GeyserState.RECOVERING:
			_state = GeyserState.IDLE
			_state_timer = pulse_interval
			_on_idle()
	
	_update_visuals()


func _on_telegraph_start() -> void:
	# Brief darkening / glow before column erupts
	var tween := create_tween()
	tween.tween_property(_telegraph_glow, "color:a", 0.4, telegraph_duration * 0.5)
	tween.tween_property(_telegraph_glow, "color:a", 0.0, telegraph_duration * 0.5)
	print("[GEYSER] Telegraph")


func _on_column_rise() -> void:
	_column.visible = true
	_column_collision.monitoring = true
	_column_collision.monitorable = true
	# Column rises with a brief tween
	var tween := create_tween()
	tween.tween_method(_animate_rise, 0.0, 1.0, 0.15)
	pulsed.emit()
	print("[GEYSER] Pulse")


func _animate_rise(progress: float) -> void:
	var h: float = column_height * progress
	var w: float = column_width * (0.6 + 0.4 * (1.0 - progress))  # narrows as it rises
	_column.size = Vector2(w, h)
	_column.position = Vector2(-w / 2, -h)
	# Also nudge collision shape
	if _column_collision:
		var cs := _column_collision.get_child(0) as CollisionShape2D
		if cs and cs.shape is RectangleShape2D:
			(cs.shape as RectangleShape2D).size = Vector2(w, h)
		_column_collision.position = Vector2(0, -h / 2)


func _on_column_retract() -> void:
	var tween := create_tween()
	tween.tween_method(_animate_retract, 1.0, 0.0, recover_duration)
	tween.tween_callback(func():
		_column.visible = false
		_column_collision.monitoring = false
		_column_collision.monitorable = false
	)


func _animate_retract(progress: float) -> void:
	var h: float = column_height * progress
	var w: float = column_width
	_column.size = Vector2(w, h)
	_column.position = Vector2(-w / 2, -h)


func _on_idle() -> void:
	pass


func _update_visuals() -> void:
	match _state:
		GeyserState.IDLE:
			_vent_base.color = Color(0.12, 0.08, 0.12, 1.0)
		GeyserState.TELEGRAPH:
			_vent_base.color = Color(0.08, 0.04, 0.1, 1.0)
		GeyserState.ACTIVE:
			_vent_base.color = Color(0.04, 0.02, 0.06, 1.0)
		GeyserState.RECOVERING:
			_vent_base.color = Color(0.1, 0.06, 0.12, 1.0)


# =============================================================================
# Damage & Destruction
# =============================================================================

func _on_column_body_entered(body: Node) -> void:
	if _damage_timer > 0.0:
		return
	if body.is_in_group("guardian") and body.has_method("take_hit"):
		body.take_hit(column_damage, global_position)
		_damage_timer = damage_cooldown


func _on_column_area_entered(area: Node) -> void:
	# Companion also takes damage if anchored
	if _damage_timer > 0.0:
		return
	var parent := area.get_parent()
	if parent and parent.is_in_group("companion") and parent.has_method("take_hit"):
		parent.take_hit(column_damage)
		_damage_timer = damage_cooldown


func _on_hitbox_area_entered(area: Area2D) -> void:
	if _is_destroyed:
		return
	# Only the guardian's attack area damages geysers
	var parent := area.get_parent()
	if not parent or not parent.is_in_group("guardian"):
		return
	# Debounce so rapid hits don't double-count
	if _damage_timer > 0.0:
		return
	_damage_timer = damage_cooldown * 0.5  # shorter cooldown for hits than damage
	
	_hits_remaining -= 1
	_hit_flash()
	
	if _hits_remaining <= 0:
		_destroy()


func _hit_flash() -> void:
	_vent_base.color = Color(0.4, 0.4, 0.4, 1.0)
	var tween := create_tween()
	tween.tween_interval(0.1)
	tween.tween_callback(func():
		if is_instance_valid(self):
			_update_visuals()
	)


func _destroy() -> void:
	_is_destroyed = true
	_column.visible = false
	_column_collision.monitoring = false
	_column_collision.monitorable = false
	_hitbox_area.monitoring = false
	_hitbox_area.monitorable = false
	
	# Shatter effect
	_vent_base.color = Color(0.3, 0.3, 0.3, 1.0)
	var tween := create_tween()
	tween.tween_property(_vent_base, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
	
	print("[GEYSER] Destroyed")
	destroyed.emit()
