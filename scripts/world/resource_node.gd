class_name ResourceNode
extends StaticBody2D

const HARVEST_PULSE_DURATION: float = 0.22

signal amount_changed(node: ResourceNode, remaining: int, max_amount: int)
signal depleted(node: ResourceNode)

@export var resource_type: StringName = &"biomass"
@export var display_name: String = "Biomass Cluster"
@export var max_amount: int = 1500
@export var remaining_amount: int = 1500
@export var collision_radius: float = 22.0
@export var interaction_radius: float = 28.0

@onready var visual_root: Node2D = get_node_or_null("VisualRoot") as Node2D
@onready var highlight_ring: Line2D = get_node_or_null("HighlightRing") as Line2D
@onready var amount_label: Label = get_node_or_null("AmountLabel") as Label

var _pulse_timer: float = 0.0
var _is_highlighted: bool = false


func _ready() -> void:
	add_to_group("resource_nodes")
	remaining_amount = clampi(remaining_amount, 0, maxi(1, max_amount))
	if highlight_ring != null:
		highlight_ring.visible = _is_highlighted
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
	return remaining_amount <= 0


func contains_point(world_point: Vector2) -> bool:
	if is_depleted():
		return false
	return global_position.distance_squared_to(world_point) <= interaction_radius * interaction_radius


func set_highlighted(highlighted: bool) -> void:
	_is_highlighted = highlighted
	if highlight_ring != null:
		highlight_ring.visible = highlighted


func pulse_harvest_feedback() -> void:
	_pulse_timer = HARVEST_PULSE_DURATION


func extract(amount: int) -> int:
	if amount <= 0 or remaining_amount <= 0:
		return 0
	var extracted: int = mini(amount, remaining_amount)
	remaining_amount -= extracted
	_update_visuals()
	amount_changed.emit(self, remaining_amount, max_amount)
	if remaining_amount <= 0:
		depleted.emit(self)
		queue_free()
	return extracted


func _update_visuals() -> void:
	var ratio: float = clampf(float(remaining_amount) / float(maxi(1, max_amount)), 0.0, 1.0)
	if visual_root != null:
		var scale_factor: float = lerpf(0.65, 1.0, ratio)
		visual_root.scale = Vector2(scale_factor, scale_factor)
	if amount_label != null:
		amount_label.text = str(remaining_amount)
