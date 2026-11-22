class_name Building
extends StaticBody2D

const HEALTH_BAR_WIDTH: float = 76.0
const DEPOSIT_PULSE_DURATION: float = 0.25

signal selection_changed(building: Building, selected: bool)
signal health_changed(building: Building, current_hp: float, max_hp: float)
signal destroyed(building: Building)

@export var team: Unit.Team = Unit.Team.PLAYER
@export var building_type_id: StringName = &"command_core"
@export var display_name: String = "Command Core"
@export var max_hp: float = 1500.0
@export var footprint_radius: float = 46.0
@export var selection_radius: float = 54.0
@export var is_resource_dropoff: bool = true
@export var accepted_resources: Array[StringName] = [&"biomass"]
@export var bandwidth_provided: int = 10
@export var always_show_health_bar: bool = false

@onready var selection_ring: Node2D = get_node_or_null("SelectionRing") as Node2D
@onready var body_visual: Node2D = get_node_or_null("BodyVisual") as Node2D
@onready var core_glow: Polygon2D = get_node_or_null("BodyVisual/CoreGlow") as Polygon2D
@onready var health_bar_root: Node2D = get_node_or_null("HealthBar") as Node2D
@onready var health_bar_fill: ColorRect = get_node_or_null("HealthBar/Fill") as ColorRect

var current_hp: float = 1500.0
var is_selected: bool = false
var is_destroyed: bool = false

var _deposit_pulse_timer: float = 0.0
var _base_core_color: Color = Color(0.22, 0.94, 0.88, 1.0)


func _ready() -> void:
	add_to_group("buildings")
	add_to_group("selectable_buildings")
	current_hp = max_hp
	if core_glow != null:
		_base_core_color = core_glow.color
	if selection_ring != null:
		selection_ring.visible = is_selected
	_update_health_bar()
	_register_with_economy()


func _exit_tree() -> void:
	_unregister_from_economy()


func _process(delta: float) -> void:
	if _deposit_pulse_timer > 0.0:
		_deposit_pulse_timer = maxf(0.0, _deposit_pulse_timer - delta)
		var t: float = _deposit_pulse_timer / DEPOSIT_PULSE_DURATION
		if core_glow != null:
			core_glow.color = _base_core_color.lerp(Color(0.45, 1.0, 0.62, 1.0), t)
		if _deposit_pulse_timer <= 0.0 and core_glow != null:
			core_glow.color = _base_core_color


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	if is_node_ready():
		if selection_ring != null:
			selection_ring.visible = is_selected
		_update_health_bar()
	selection_changed.emit(self, is_selected)


func contains_point(world_point: Vector2) -> bool:
	if is_destroyed:
		return false
	return global_position.distance_squared_to(world_point) <= selection_radius * selection_radius


func accepts_resource(resource_type: StringName) -> bool:
	if is_destroyed or not is_resource_dropoff:
		return false
	return accepted_resources.has(resource_type)


func pulse_deposit_feedback() -> void:
	_deposit_pulse_timer = DEPOSIT_PULSE_DURATION


func take_damage(amount: float) -> void:
	if is_destroyed or amount <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_update_health_bar()
	health_changed.emit(self, current_hp, max_hp)
	if current_hp <= 0.0:
		_destroy()


func _destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	set_selected(false)
	_unregister_from_economy()
	destroyed.emit(self)
	queue_free()


func _update_health_bar() -> void:
	if health_bar_root == null or health_bar_fill == null:
		return
	var max_val: float = maxf(1.0, max_hp)
	var ratio: float = clampf(current_hp / max_val, 0.0, 1.0)
	health_bar_fill.size.x = HEALTH_BAR_WIDTH * ratio
	health_bar_root.visible = always_show_health_bar or is_selected or ratio < 0.999


func _register_with_economy() -> void:
	if bandwidth_provided <= 0 or not is_inside_tree():
		return
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null:
		econ.register_bandwidth_provider(self, team, bandwidth_provided)


func _unregister_from_economy() -> void:
	if not is_inside_tree():
		return
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if econ != null:
		econ.unregister_bandwidth_provider(self)
