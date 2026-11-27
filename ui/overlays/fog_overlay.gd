class_name FogOverlay
extends Node2D

const FOG_SHADER: Shader = preload("res://assets/shaders/fog_of_war.gdshader")

@export var fog_system_path: NodePath

var _fog_system: FogOfWarSystem = null
var _fog_material: ShaderMaterial = null


func _ready() -> void:
	z_index = 35
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	if FOG_SHADER != null:
		_fog_material = ShaderMaterial.new()
		_fog_material.shader = FOG_SHADER
		material = _fog_material
	call_deferred("_bind_fog_system")


func _bind_fog_system() -> void:
	if not fog_system_path.is_empty():
		_fog_system = get_node_or_null(fog_system_path) as FogOfWarSystem
	if _fog_system == null and is_inside_tree():
		_fog_system = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if _fog_system != null:
		if not _fog_system.visibility_updated.is_connected(_on_visibility_updated):
			_fog_system.visibility_updated.connect(_on_visibility_updated)
		if _fog_system.has_signal("world_fog_visual_updated") and not _fog_system.world_fog_visual_updated.is_connected(_on_world_fog_visual_updated):
			_fog_system.world_fog_visual_updated.connect(_on_world_fog_visual_updated)
	_sync_shader_uniforms()
	queue_redraw()


func _sync_shader_uniforms() -> void:
	if _fog_material == null or _fog_system == null:
		return
	_fog_material.set_shader_parameter("grid_size", Vector2(float(_fog_system.grid_width), float(_fog_system.grid_height)))
	_fog_material.set_shader_parameter("arena_size", _fog_system.arena_bounds.size)


func _on_visibility_updated() -> void:
	_sync_shader_uniforms()
	queue_redraw()


func _on_world_fog_visual_updated() -> void:
	if _fog_system == null or not _fog_system.fog_enabled or _fog_system.post_match_reveal:
		queue_redraw()
		return
	queue_redraw()


func _draw() -> void:
	if _fog_system == null:
		return
	if not _fog_system.fog_enabled or _fog_system.post_match_reveal:
		return
	var tex: Texture2D = _fog_system.world_fog_texture
	if tex == null:
		tex = _fog_system.fog_texture
		if tex == null:
			return
		material = null
	else:
		if _fog_material != null and material != _fog_material:
			material = _fog_material
	draw_texture_rect(tex, _fog_system.arena_bounds, false)
