class_name FogOverlay
extends Node2D

@export var fog_system_path: NodePath

var _fog_system: FogOfWarSystem = null


func _ready() -> void:
	z_index = 35
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	call_deferred("_bind_fog_system")


func _bind_fog_system() -> void:
	if not fog_system_path.is_empty():
		_fog_system = get_node_or_null(fog_system_path) as FogOfWarSystem
	if _fog_system == null and is_inside_tree():
		_fog_system = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if _fog_system != null and not _fog_system.visibility_updated.is_connected(_on_visibility_updated):
		_fog_system.visibility_updated.connect(_on_visibility_updated)
	queue_redraw()


func _on_visibility_updated() -> void:
	queue_redraw()


func _draw() -> void:
	if _fog_system == null or _fog_system.fog_texture == null:
		return
	if not _fog_system.fog_enabled:
		return
	draw_texture_rect(_fog_system.fog_texture, _fog_system.arena_bounds, false)
