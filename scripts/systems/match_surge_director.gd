class_name MatchSurgeDirector
extends RefCounted

const SURGE_FIRST_DELAY: float = 165.0
const SURGE_INTERVAL: float = 180.0
const SURGE_DURATION: float = 45.0
const SURGE_MULTIPLIER: float = 2.0

var _next_surge_time: float = SURGE_FIRST_DELAY
var _last_surged_vent: ResourceNode = null


func reset() -> void:
	_next_surge_time = SURGE_FIRST_DELAY
	_last_surged_vent = null


func tick(mm: MatchManager) -> void:
	if mm == null or mm.is_special_mode_active() or mm._is_sandbox_testbed_scene() or not mm.is_inside_tree():
		return
	if GameConfig != null and GameConfig.active_game_mode != GameConfig.GameMode.SKIRMISH:
		return
	if mm.match_elapsed < _next_surge_time:
		return
	_next_surge_time += SURGE_INTERVAL

	var anchor_positions: Array[Vector2] = []
	for raw_pos: Variant in mm._spawn_anchors.values():
		if raw_pos is Vector2:
			anchor_positions.append(raw_pos as Vector2)
	if anchor_positions.is_empty():
		for b_node: Node in mm.get_tree().get_nodes_in_group("buildings"):
			if b_node is Building and is_instance_valid(b_node):
				var b: Building = b_node as Building
				if not b.is_destroyed and b.is_command_hub():
					anchor_positions.append(b.global_position)

	var candidates: Array[ResourceNode] = []
	for node: Node in mm.get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node as ResourceNode
		if not rn.is_vent or rn.is_surging():
			continue
		var near_main_base: bool = false
		for anchor_pt: Vector2 in anchor_positions:
			if rn.global_position.distance_to(anchor_pt) <= 440.0:
				near_main_base = true
				break
		if not near_main_base:
			candidates.append(rn)

	if candidates.is_empty():
		return

	var pool: Array[ResourceNode] = []
	if candidates.size() >= 2 and _last_surged_vent != null and is_instance_valid(_last_surged_vent):
		for c: ResourceNode in candidates:
			if c != _last_surged_vent:
				pool.append(c)
	if pool.is_empty():
		pool = candidates

	var chosen_vent: ResourceNode = pool[randi() % pool.size()]
	_last_surged_vent = chosen_vent
	chosen_vent.start_overpressure_surge(SURGE_DURATION, SURGE_MULTIPLIER)
	mm.emit_tactical_event(
		&"surge",
		"Geothermal Compute Surge! Contested Vent 2x Output (%ds)" % int(round(SURGE_DURATION)),
		chosen_vent.global_position,
		Color(0.28, 0.94, 1.0, 1.0)
	)
	var minimap: Node = mm.get_tree().get_first_node_in_group("tactical_minimap")
	if minimap != null and minimap.has_method("flash_ping"):
		minimap.call("flash_ping", chosen_vent.global_position, Color(0.28, 0.96, 1.0, 1.0), 3.0)
	if AudioManager != null:
		AudioManager.play_sfx(&"alert_uplink", -6.5, 0.03)
