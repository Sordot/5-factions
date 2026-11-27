class_name FogGhostOverlay
extends Node2D

## Renders authentic StarCraft II frozen building ghosts in explored Fog of War
## using the real faction procedural renderers under a subtle desaturation shader,
## and owns lightweight inspection/hover proxy handles for left-click read-only intel.

const GHOST_SHADER: Shader = preload("res://assets/shaders/ghost_desaturate.gdshader")
const GHOST_HANDLE_SCRIPT: GDScript = preload("res://scripts/world/fog_ghost_handle.gd")

var _fog_system: FogOfWarSystem = null
var _ghost_material: ShaderMaterial = null
var _inspect_handle: FogGhostInspectHandle = null
var _hover_handle: FogGhostInspectHandle = null


func _ready() -> void:
	z_index = 6
	add_to_group("fog_ghost_overlay")
	if GHOST_SHADER != null:
		_ghost_material = ShaderMaterial.new()
		_ghost_material.shader = GHOST_SHADER
		material = _ghost_material
	_inspect_handle = GHOST_HANDLE_SCRIPT.new() as FogGhostInspectHandle
	_inspect_handle.name = "GhostInspectHandle"
	add_child(_inspect_handle)
	_hover_handle = GHOST_HANDLE_SCRIPT.new() as FogGhostInspectHandle
	_hover_handle.name = "GhostHoverHandle"
	add_child(_hover_handle)
	call_deferred("_bind_fog_system")


func _bind_fog_system() -> void:
	if not is_inside_tree():
		return
	_fog_system = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if _fog_system != null:
		if not _fog_system.building_ghosts_changed.is_connected(_on_building_ghosts_changed):
			_fog_system.building_ghosts_changed.connect(_on_building_ghosts_changed)
	queue_redraw()


func _on_building_ghosts_changed() -> void:
	if _inspect_handle != null and is_instance_valid(_inspect_handle) and _inspect_handle.ghost_id >= 0:
		if not _inspect_handle.is_ghost_active():
			_inspect_handle.invalidate()
	if _hover_handle != null and is_instance_valid(_hover_handle) and _hover_handle.ghost_id >= 0:
		if not _hover_handle.is_ghost_active():
			_hover_handle.invalidate()
	queue_redraw()


func has_ghost_at_point(world_point: Vector2) -> bool:
	if _fog_system == null or not is_instance_valid(_fog_system):
		return false
	return not _fog_system.find_building_ghost_at_point(world_point).is_empty()


func get_ghost_handle_for_id(gid: int) -> FogGhostInspectHandle:
	if gid < 0 or _fog_system == null or not is_instance_valid(_fog_system) or _inspect_handle == null:
		return null
	if _fog_system.get_building_ghost_by_id(gid).is_empty():
		return null
	_inspect_handle.bind_ghost(gid, _fog_system, self)
	return _inspect_handle


func get_ghost_handle_at_point(world_point: Vector2) -> FogGhostInspectHandle:
	if _fog_system == null or not is_instance_valid(_fog_system) or _inspect_handle == null:
		return null
	var ghost: Dictionary = _fog_system.find_building_ghost_at_point(world_point)
	if ghost.is_empty():
		return null
	var gid: int = int(ghost.get("id", -1))
	if gid < 0:
		return null
	_inspect_handle.bind_ghost(gid, _fog_system, self)
	return _inspect_handle


func get_hover_handle_at_point(world_point: Vector2) -> FogGhostInspectHandle:
	if _fog_system == null or not is_instance_valid(_fog_system) or _hover_handle == null:
		return null
	var ghost: Dictionary = _fog_system.find_building_ghost_at_point(world_point)
	if ghost.is_empty():
		return null
	var gid: int = int(ghost.get("id", -1))
	if gid < 0:
		return null
	_hover_handle.bind_ghost(gid, _fog_system, self)
	return _hover_handle


func _draw() -> void:
	if _fog_system == null or not is_instance_valid(_fog_system):
		return
	if not _fog_system.fog_enabled or _fog_system.post_match_reveal:
		return
	var ghosts: Array[Dictionary] = _fog_system.get_active_building_ghosts()
	if ghosts.is_empty():
		return

	var selected_gid: int = _inspect_handle.ghost_id if (_inspect_handle != null and _inspect_handle.is_selected) else -1
	var hovered_gid: int = _hover_handle.ghost_id if (_hover_handle != null and _hover_handle.is_hovered) else -1

	for ghost: Dictionary in ghosts:
		var g_pos: Vector2 = ghost.get("pos", Vector2.ZERO) as Vector2
		var gid: int = int(ghost.get("id", -1))
		var sel_r: float = maxf(float(ghost.get("selection_radius", 32.0)), float(ghost.get("footprint_radius", 32.0)) + 6.0)
		draw_set_transform(g_pos)
		if gid == hovered_gid and gid != selected_gid:
			draw_arc(Vector2.ZERO, sel_r + 2.0, 0.0, TAU, 36, Color(0.86, 0.92, 0.96, 0.56), 1.6, true)
		if gid == selected_gid:
			draw_circle(Vector2.ZERO, sel_r + 3.0, Color(0.76, 0.86, 0.94, 0.12))
			draw_arc(Vector2.ZERO, sel_r + 3.0, 0.0, TAU, 36, Color(0.92, 0.96, 1.0, 0.84), 2.0, true)
		EntityVisuals.draw_frozen_building_ghost(self, ghost)

	draw_set_transform(Vector2.ZERO)
