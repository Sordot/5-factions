extends Node

## Reusable object pool for high-frequency ephemeral 2D VFX nodes
## (AttackTracer, CombatVFX, MoveMarker, AbilityEffect) with safe scene-change teardown.

const ATTACK_TRACER_SCRIPT: GDScript = preload("res://ui/overlays/attack_tracer.gd")
const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")
const MOVE_MARKER_SCRIPT: GDScript = preload("res://ui/overlays/move_marker.gd")
const ABILITY_EFFECT_SCRIPT: GDScript = preload("res://ui/overlays/ability_effect.gd")

const CAP_TRACER: int = 96
const CAP_COMBAT_VFX: int = 64
const CAP_MOVE_MARKER: int = 24
const CAP_ABILITY_EFFECT: int = 24
const HIGH_VFX_LOAD_THRESHOLD: int = 96

var _vfx_layer: Node2D = null
var _bound_scene_id: int = 0

var _free_tracers: Array[Node2D] = []
var _active_tracers: Array[Node2D] = []

var _free_combat_vfx: Array[Node2D] = []
var _active_combat_vfx: Array[Node2D] = []

var _free_markers: Array[Node2D] = []
var _active_markers: Array[Node2D] = []

var _free_abilities: Array[Node2D] = []
var _active_abilities: Array[Node2D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_high_vfx_load() -> bool:
	return (_active_combat_vfx.size() + _active_tracers.size()) > HIGH_VFX_LOAD_THRESHOLD


func _ensure_vfx_layer() -> Node2D:
	if not is_inside_tree():
		return null
	var cur_scene: Node = get_tree().current_scene
	if cur_scene == null or not is_instance_valid(cur_scene):
		return null
	var scene_id: int = cur_scene.get_instance_id()
	if scene_id != _bound_scene_id or _vfx_layer == null or not is_instance_valid(_vfx_layer) or not _vfx_layer.is_inside_tree():
		clear_pool()
		_bound_scene_id = scene_id
		var existing: Node2D = cur_scene.get_node_or_null("VFXLayer") as Node2D
		if existing != null and is_instance_valid(existing):
			_vfx_layer = existing
		else:
			_vfx_layer = Node2D.new()
			_vfx_layer.name = "VFXLayer"
			_vfx_layer.z_index = 0
			cur_scene.add_child(_vfx_layer)
	return _vfx_layer


func acquire_attack_tracer(z_idx: int = 50) -> AttackTracer:
	var layer: Node2D = _ensure_vfx_layer()
	if layer == null:
		return null
	var node: AttackTracer = _acquire_from_lists(_free_tracers, _active_tracers, CAP_TRACER, ATTACK_TRACER_SCRIPT, layer, false) as AttackTracer
	if node != null:
		node.z_index = z_idx
		node.reset_for_pool()
		node.visible = true
		node.set_process(true)
	return node


func acquire_combat_vfx(z_idx: int = 52) -> CombatVFX:
	var layer: Node2D = _ensure_vfx_layer()
	if layer == null:
		return null
	var node: CombatVFX = _acquire_from_lists(_free_combat_vfx, _active_combat_vfx, CAP_COMBAT_VFX, COMBAT_VFX_SCRIPT, layer, true) as CombatVFX
	if node != null:
		node.z_index = z_idx
		node.reset_for_pool()
		node.visible = true
		node.set_process(true)
	return node


func acquire_move_marker(z_idx: int = 60) -> MoveMarker:
	var layer: Node2D = _ensure_vfx_layer()
	if layer == null:
		return null
	var node: MoveMarker = _acquire_from_lists(_free_markers, _active_markers, CAP_MOVE_MARKER, MOVE_MARKER_SCRIPT, layer, false) as MoveMarker
	if node != null:
		node.z_index = z_idx
		node.reset_for_pool()
		node.visible = true
		node.set_process(true)
	return node


func acquire_ability_effect(z_idx: int = 55) -> AbilityEffect:
	var layer: Node2D = _ensure_vfx_layer()
	if layer == null:
		return null
	var node: AbilityEffect = _acquire_from_lists(_free_abilities, _active_abilities, CAP_ABILITY_EFFECT, ABILITY_EFFECT_SCRIPT, layer, false) as AbilityEffect
	if node != null:
		node.z_index = z_idx
		node.reset_for_pool()
		node.visible = true
		node.set_process(true)
	return node


func recycle_node(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.visible = false
	node.set_process(false)
	if node is AttackTracer:
		_active_tracers.erase(node)
		if _free_tracers.size() < CAP_TRACER and not _free_tracers.has(node):
			_free_tracers.append(node)
		elif not _free_tracers.has(node):
			node.queue_free()
	elif node is CombatVFX:
		_active_combat_vfx.erase(node)
		if _free_combat_vfx.size() < CAP_COMBAT_VFX and not _free_combat_vfx.has(node):
			_free_combat_vfx.append(node)
		elif not _free_combat_vfx.has(node):
			node.queue_free()
	elif node is MoveMarker:
		_active_markers.erase(node)
		if _free_markers.size() < CAP_MOVE_MARKER and not _free_markers.has(node):
			_free_markers.append(node)
		elif not _free_markers.has(node):
			node.queue_free()
	elif node is AbilityEffect:
		_active_abilities.erase(node)
		if _free_abilities.size() < CAP_ABILITY_EFFECT and not _free_abilities.has(node):
			_free_abilities.append(node)
		elif not _free_abilities.has(node):
			node.queue_free()


func clear_pool() -> void:
	_free_list(_free_tracers)
	_free_list(_active_tracers)
	_free_list(_free_combat_vfx)
	_free_list(_active_combat_vfx)
	_free_list(_free_markers)
	_free_list(_active_markers)
	_free_list(_free_abilities)
	_free_list(_active_abilities)
	_vfx_layer = null
	_bound_scene_id = 0


func _free_list(list: Array[Node2D]) -> void:
	for n: Node2D in list:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			n.set_process(false)
			n.visible = false
			n.queue_free()
	list.clear()


func _acquire_from_lists(
	free_list: Array[Node2D],
	active_list: Array[Node2D],
	cap: int,
	script_res: GDScript,
	layer: Node2D,
	protect_mortar: bool
) -> Node2D:
	# 1. Reuse an idle pooled instance
	while not free_list.is_empty():
		var reused: Node2D = free_list.pop_back()
		if is_instance_valid(reused) and not reused.is_queued_for_deletion():
			if reused.get_parent() != layer:
				if reused.get_parent() != null:
					reused.get_parent().remove_child(reused)
				layer.add_child(reused)
			active_list.append(reused)
			return reused

	# Prune any externally freed active nodes before checking cap
	var clean_active: Array[Node2D] = []
	for a: Node2D in active_list:
		if is_instance_valid(a) and not a.is_queued_for_deletion():
			clean_active.append(a)
	if clean_active.size() != active_list.size():
		active_list.clear()
		for ca: Node2D in clean_active:
			active_list.append(ca)

	# 2. Allocate fresh instance up to cap
	if active_list.size() < cap:
		var created: Node2D = script_res.new() as Node2D
		if created == null:
			return null
		created.set("is_pooled", true)
		layer.add_child(created)
		active_list.append(created)
		return created

	# 3. Cap saturated: steal the oldest non-critical active node
	var steal_idx: int = -1
	for i: int in range(active_list.size()):
		var cand: Node2D = active_list[i]
		if protect_mortar and cand.has_method("is_critical_flight") and bool(cand.call("is_critical_flight")):
			continue
		steal_idx = i
		break

	if steal_idx >= 0:
		var stolen: Node2D = active_list[steal_idx]
		active_list.remove_at(steal_idx)
		active_list.append(stolen)
		return stolen

	# Fallback overflow (e.g., all 64 slots are live mortar shells awaiting impact)
	var overflow: Node2D = script_res.new() as Node2D
	if overflow != null:
		overflow.set("is_pooled", false)
		layer.add_child(overflow)
	return overflow
