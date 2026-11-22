class_name ResourceNode
extends StaticBody2D

const HARVEST_PULSE_DURATION: float = 0.22

signal amount_changed(node: ResourceNode, remaining: int, max_amount: int)
signal status_changed(node: ResourceNode)
signal depleted(node: ResourceNode)

@export var resource_type: StringName = &"biomass"
@export var display_name: String = "Biomass Cluster"
@export var max_amount: int = 1500
@export var remaining_amount: int = 1500
@export var collision_radius: float = 22.0
@export var interaction_radius: float = 28.0
@export var is_vent: bool = false

@onready var visual_root: Node2D = get_node_or_null("VisualRoot") as Node2D
@onready var highlight_ring: Line2D = get_node_or_null("HighlightRing") as Line2D
@onready var amount_label: Label = get_node_or_null("AmountLabel") as Label

var occupied_by_building: Building = null
var is_inspected: bool = false
var _pulse_timer: float = 0.0
var _is_highlighted: bool = false


func _ready() -> void:
	add_to_group("resource_nodes")
	remaining_amount = clampi(remaining_amount, 0, maxi(1, max_amount))
	_update_ring_visual()
	_update_visuals()


func _process(delta: float) -> void:
	if _pulse_timer > 0.0:
		_pulse_timer = maxf(0.0, _pulse_timer - delta)
		var t: float = _pulse_timer / HARVEST_PULSE_DURATION
		if visual_root != null:
			var boost: float = 1.0 + 0.35 * t
			visual_root.modulate = Color(boost, 1.0 + 0.55 * t, boost, 1.0)
		if _pulse_timer <= 0.0 and visual_root != null:
			visual_root.modulate = Color.WHITE


func is_depleted() -> bool:
	if is_vent:
		return false
	return remaining_amount <= 0


func is_occupied() -> bool:
	return occupied_by_building != null and is_instance_valid(occupied_by_building) and not occupied_by_building.is_destroyed


func claim_by_building(building: Building) -> void:
	occupied_by_building = building
	if amount_label != null and is_vent:
		amount_label.visible = false
	status_changed.emit(self)


func release_building(building: Building) -> void:
	if occupied_by_building == building:
		occupied_by_building = null
		if amount_label != null and is_vent:
			amount_label.visible = true
		status_changed.emit(self)


func contains_point(world_point: Vector2) -> bool:
	if is_depleted():
		return false
	return global_position.distance_squared_to(world_point) <= interaction_radius * interaction_radius


func set_highlighted(highlighted: bool) -> void:
	_is_highlighted = highlighted
	_update_ring_visual()


func set_inspected(inspected: bool) -> void:
	if is_inspected == inspected:
		return
	is_inspected = inspected
	_update_ring_visual()


func _update_ring_visual() -> void:
	if highlight_ring == null:
		return
	highlight_ring.visible = is_inspected or _is_highlighted
	if is_inspected:
		if is_vent:
			highlight_ring.default_color = Color(0.28, 0.92, 1.0, 0.96)
		else:
			highlight_ring.default_color = Color(1.0, 0.84, 0.28, 0.96)
		highlight_ring.width = 2.6
	else:
		highlight_ring.width = 2.0


func pulse_harvest_feedback() -> void:
	_pulse_timer = HARVEST_PULSE_DURATION


func extract(amount: int) -> int:
	if is_vent or amount <= 0 or remaining_amount <= 0:
		return 0
	var extracted: int = mini(amount, remaining_amount)
	remaining_amount -= extracted
	_update_visuals()
	amount_changed.emit(self, remaining_amount, max_amount)
	status_changed.emit(self)
	if remaining_amount <= 0:
		depleted.emit(self)
		queue_free()
	return extracted


func get_inspection_data() -> Dictionary:
	if is_vent:
		var status_text: String = "CAPPED — Compute Node" if is_occupied() else "UNOCCUPIED — Ready"
		var vent_stats: Array[Dictionary] = [
			{"label": "Status", "value": status_text},
			{"label": "Yield Rate", "value": "+5 Compute / 3.0s / Eng"},
			{"label": "Capacity", "value": "Infinite Geothermal"},
			{"label": "Structure", "value": "Compute Node [W]"},
		]
		return {
			"title": "Thermal Data Vent",
			"subtitle": "COMPUTE VENT",
			"affiliation": &"neutral",
			"accent_color": Color(0.32, 0.86, 1.0, 1.0),
			"ring_color": Color(0.28, 0.92, 1.0, 0.96),
			"show_hp_bar": false,
			"show_primary_bar": false,
			"stats": vent_stats,
			"is_commandable": false,
			"readonly_label": "READ-ONLY TELEMETRY  —  BUILD COMPUTE NODE [W]",
		}

	var is_silica: bool = (resource_type == &"silica")
	var accent: Color = Color(0.98, 0.78, 0.28, 1.0) if is_silica else Color(0.26, 0.94, 0.56, 1.0)
	var pct: int = int(round((float(remaining_amount) / float(maxi(1, max_amount))) * 100.0))
	var fmt_rem: String = InspectionHelper.format_number(remaining_amount)
	var fmt_max: String = InspectionHelper.format_number(max_amount)
	var active_gatherers: int = _count_active_gatherers()
	var deposit_stats: Array[Dictionary] = [
		{"label": "Resource", "value": "Silica" if is_silica else "Biomass"},
		{"label": "Remaining", "value": "%s / %s (%d%%)" % [fmt_rem, fmt_max, pct]},
		{"label": "Harvest", "value": "Automated Harvester" if is_silica else "Direct Worker Gather"},
		{"label": "Active", "value": "%d Harvester(s)" % active_gatherers},
	]
	return {
		"title": display_name,
		"subtitle": "SILICA VEIN" if is_silica else "BIOMASS DEPOSIT",
		"affiliation": &"neutral",
		"accent_color": accent,
		"ring_color": Color(1.0, 0.84, 0.28, 0.96),
		"show_hp_bar": false,
		"show_primary_bar": true,
		"primary_bar_label": "Remaining: %s / %s" % [fmt_rem, fmt_max],
		"primary_bar_value": float(remaining_amount),
		"primary_bar_max": float(maxi(1, max_amount)),
		"primary_bar_color": accent,
		"stats": deposit_stats,
		"is_commandable": false,
		"readonly_label": "READ-ONLY TELEMETRY",
	}


func _count_active_gatherers() -> int:
	if not is_inside_tree():
		return 0
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.gather_component == null:
			continue
		if unit.gather_component.is_active() and unit.gather_component.target_node == self:
			count += 1
	return count


func _update_visuals() -> void:
	if is_vent:
		if amount_label != null:
			amount_label.visible = not is_occupied()
		return
	var ratio: float = clampf(float(remaining_amount) / float(maxi(1, max_amount)), 0.0, 1.0)
	if visual_root != null:
		var scale_factor: float = lerpf(0.65, 1.0, ratio)
		visual_root.scale = Vector2(scale_factor, scale_factor)
	if amount_label != null:
		amount_label.text = str(remaining_amount)
