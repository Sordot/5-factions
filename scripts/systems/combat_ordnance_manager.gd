class_name CombatOrdnanceManager
extends Node

## Deterministic physics-tick ordnance and radial AoE damage resolver (Milestone 4.5).
## Decouples mortar shells, siege blasts, and orbital strikes from pooled render-thread
## CombatVFX nodes, applies smooth radial falloff, and resets cleanly on rematch/retry.

var _pending: Array[Dictionary] = []
var _fog_cache: FogOfWarSystem = null


func _ready() -> void:
	add_to_group("combat_ordnance_manager")


func clear_all() -> void:
	_pending.clear()
	_fog_cache = null


func schedule_ground_detonation(spec: Dictionary) -> void:
	var delay: float = maxf(0.0, float(spec.get("delay", spec.get("remaining", 0.0))))
	var entry: Dictionary = {
		"remaining": delay,
		"attacker_ref": spec.get("attacker_ref", null),
		"attacker_team": int(spec.get("attacker_team", -1)),
		"center": spec.get("center", Vector2.ZERO) as Vector2,
		"radius": maxf(1.0, float(spec.get("radius", 48.0))),
		"inner_ratio": clampf(float(spec.get("inner_ratio", 0.35)), 0.0, 1.0),
		"edge_ratio": clampf(float(spec.get("edge_ratio", 0.45)), 0.05, 1.0),
		"base_dmg": maxf(0.0, float(spec.get("base_dmg", 0.0))),
		"bonus_armored": maxf(0.0, float(spec.get("bonus_armored", 0.0))),
		"armor_mult": maxf(1.0, float(spec.get("armor_mult", 1.0))),
		"shake_intensity": maxf(0.0, float(spec.get("shake_intensity", 0.0))),
		"shake_duration": maxf(0.0, float(spec.get("shake_duration", 0.0))),
		"impact_sfx": spec.get("impact_sfx", &"") as StringName,
		"scar_kind": spec.get("scar_kind", &"") as StringName,
		"vfx_color": spec.get("vfx_color", Color(1.0, 0.80, 0.30, 1.0)) as Color,
	}
	if delay <= 0.0:
		_detonate_entry(entry)
	else:
		_pending.append(entry)


func _physics_process(delta: float) -> void:
	if _pending.is_empty():
		return
	var i: int = _pending.size() - 1
	while i >= 0:
		var entry: Dictionary = _pending[i]
		var rem: float = float(entry.get("remaining", 0.0)) - delta
		entry["remaining"] = rem
		if rem <= 0.0:
			var last: int = _pending.size() - 1
			if i != last:
				_pending[i] = _pending[last]
			_pending.pop_back()
			_detonate_entry(entry)
		i -= 1


func _detonate_entry(entry: Dictionary) -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	var center: Vector2 = entry.get("center", Vector2.ZERO) as Vector2
	var radius: float = float(entry.get("radius", 48.0))
	var atk_team: int = int(entry.get("attacker_team", -1))

	var attacker: Node = null
	var raw_ref: Variant = entry.get("attacker_ref", null)
	if raw_ref is WeakRef:
		var obj: Variant = (raw_ref as WeakRef).get_ref()
		if obj != null and is_instance_valid(obj) and obj is Node:
			var atk_node: Node = obj as Node
			if atk_node is Unit and not (atk_node as Unit).is_dead:
				attacker = atk_node
			elif atk_node is Building and not (atk_node as Building).is_destroyed:
				attacker = atk_node
			elif not (atk_node is Unit) and not (atk_node is Building):
				attacker = atk_node

	apply_aoe_damage(
		tree,
		attacker,
		atk_team,
		center,
		radius,
		float(entry.get("base_dmg", 0.0)),
		float(entry.get("bonus_armored", 0.0)),
		float(entry.get("armor_mult", 1.0)),
		float(entry.get("inner_ratio", 0.35)),
		float(entry.get("edge_ratio", 0.45))
	)

	var scar_kind: StringName = entry.get("scar_kind", &"") as StringName
	if scar_kind != &"":
		var scars: Node = tree.get_first_node_in_group("battle_scars")
		if scars != null and scars.has_method("add_scar"):
			var scar_col: Color = entry.get("vfx_color", Color(1.0, 0.80, 0.30, 1.0)) as Color
			scars.call("add_scar", scar_kind, center, clampf(radius * 0.62, 16.0, 58.0), scar_col)

	var vis_local: bool = _is_point_visible_local(center)
	var shake_i: float = float(entry.get("shake_intensity", 0.0))
	var shake_d: float = float(entry.get("shake_duration", 0.0))
	if vis_local and shake_i > 0.0 and shake_d > 0.0:
		var cam: Node = tree.get_first_node_in_group("rts_camera")
		if cam != null and cam.has_method("add_camera_shake"):
			cam.call("add_camera_shake", shake_i, shake_d, center)

	var sfx_id: StringName = entry.get("impact_sfx", &"") as StringName
	if sfx_id != &"" and AudioManager != null:
		var is_local_team: bool = TeamManager.is_team_controlled_by_local_human(atk_team) if TeamManager != null else (atk_team == int(Unit.Team.PLAYER))
		if vis_local or is_local_team:
			AudioManager.play_sfx(sfx_id, -3.5, 0.05, center, true)


func _is_point_visible_local(world_pos: Vector2) -> bool:
	if not is_inside_tree():
		return false
	if _fog_cache == null or not is_instance_valid(_fog_cache):
		_fog_cache = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if _fog_cache != null and _fog_cache.fog_enabled:
		return _fog_cache.is_world_pos_visible_strict(world_pos)
	return true


static func compute_radial_falloff(edge_dist: float, radius: float, inner_ratio: float, edge_ratio: float) -> float:
	if edge_dist > radius:
		return 0.0
	var inner_r: float = radius * clampf(inner_ratio, 0.0, 1.0)
	if edge_dist <= inner_r or inner_ratio >= 0.999 or edge_ratio >= 0.999:
		return 1.0
	var t: float = clampf((edge_dist - inner_r) / maxf(1.0, radius - inner_r), 0.0, 1.0)
	return lerpf(1.0, clampf(edge_ratio, 0.05, 1.0), t)


static func apply_aoe_damage(
	tree: SceneTree,
	attacker: Node,
	attacker_team: int,
	center: Vector2,
	radius: float,
	base_dmg: float,
	bonus_vs_armored_flat: float = 0.0,
	armored_dmg_mult: float = 1.0,
	inner_ratio: float = 0.35,
	edge_ratio: float = 0.45
) -> void:
	if tree == null or radius <= 0.0 or (base_dmg <= 0.0 and bonus_vs_armored_flat <= 0.0):
		return

	var entities: Array = []
	if SpatialGrid != null:
		entities = SpatialGrid.query_entities_in_radius(center, radius, true, true)
	else:
		entities = tree.get_nodes_in_group("units") + tree.get_nodes_in_group("buildings") + tree.get_nodes_in_group("destructible_barricades")

	var hit_ov: Node = null
	var hit_ov_checked: bool = false

	for node: Variant in entities:
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var target_node: Node2D = node as Node2D
		if target_node is Unit:
			var u: Unit = target_node as Unit
			if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
				continue
			if not CombatTargeting.are_teams_hostile(attacker_team, int(u.team)):
				continue
			var u_r: float = u.data.collision_radius if u.data != null else 16.0
			var edge_d: float = maxf(0.0, u.global_position.distance_to(center) - u_r)
			if edge_d > radius:
				continue
			var falloff: float = compute_radial_falloff(edge_d, radius, inner_ratio, edge_ratio)
			var is_arm: bool = u.data != null and u.data.is_armored
			var raw_dmg: float = base_dmg
			var anti_arm: bool = false
			if is_arm and bonus_vs_armored_flat > 0.0:
				raw_dmg += bonus_vs_armored_flat
				anti_arm = true
			if is_arm and armored_dmg_mult > 1.0:
				raw_dmg *= armored_dmg_mult
				anti_arm = true
			var final_dmg: float = raw_dmg * falloff
			if final_dmg > 0.0:
				u.take_damage(final_dmg, attacker)
				if anti_arm and u.visible:
					if not hit_ov_checked:
						hit_ov = tree.get_first_node_in_group("hit_feedback_overlay")
						hit_ov_checked = true
					if hit_ov != null and hit_ov.has_method("push_hit_pip"):
						hit_ov.call("push_hit_pip", u.global_position, HitFeedbackOverlay.KIND_ANTI_ARMOR, 0, u.get_instance_id())
		elif target_node is Building:
			var b: Building = target_node as Building
			if b.is_destroyed or b.is_queued_for_deletion():
				continue
			if not CombatTargeting.are_teams_hostile(attacker_team, int(b.team)):
				continue
			var edge_db: float = maxf(0.0, b.global_position.distance_to(center) - b.footprint_radius)
			if edge_db > radius:
				continue
			var falloff_b: float = compute_radial_falloff(edge_db, radius, inner_ratio, edge_ratio)
			var raw_dmg_b: float = base_dmg
			var anti_arm_b: bool = false
			if bonus_vs_armored_flat > 0.0:
				raw_dmg_b += bonus_vs_armored_flat
				anti_arm_b = true
			if armored_dmg_mult > 1.0:
				raw_dmg_b *= armored_dmg_mult
				anti_arm_b = true
			var final_dmg_b: float = raw_dmg_b * falloff_b
			if final_dmg_b > 0.0:
				b.take_damage(final_dmg_b, attacker)
				if anti_arm_b and b.visible:
					if not hit_ov_checked:
						hit_ov = tree.get_first_node_in_group("hit_feedback_overlay")
						hit_ov_checked = true
					if hit_ov != null and hit_ov.has_method("push_hit_pip"):
						hit_ov.call("push_hit_pip", b.global_position, HitFeedbackOverlay.KIND_ANTI_ARMOR, 0, b.get_instance_id())
		elif target_node.is_in_group("destructible_barricades"):
			if bool(target_node.get("is_destroyed")) or target_node.is_queued_for_deletion():
				continue
			var bar_r: float = float(target_node.call("get_footprint_radius")) if target_node.has_method("get_footprint_radius") else 40.0
			var edge_dbar: float = maxf(0.0, target_node.global_position.distance_to(center) - bar_r)
			if edge_dbar > radius:
				continue
			var falloff_bar: float = compute_radial_falloff(edge_dbar, radius, inner_ratio, edge_ratio)
			var is_arm_bar: bool = bool(target_node.get("is_armored"))
			var raw_dmg_bar: float = base_dmg
			var anti_arm_bar: bool = false
			if is_arm_bar and bonus_vs_armored_flat > 0.0:
				raw_dmg_bar += bonus_vs_armored_flat
				anti_arm_bar = true
			if is_arm_bar and armored_dmg_mult > 1.0:
				raw_dmg_bar *= armored_dmg_mult
				anti_arm_bar = true
			var final_dmg_bar: float = raw_dmg_bar * falloff_bar
			if final_dmg_bar > 0.0:
				target_node.call("take_damage", final_dmg_bar, attacker)
				if anti_arm_bar and target_node.visible:
					if not hit_ov_checked:
						hit_ov = tree.get_first_node_in_group("hit_feedback_overlay")
						hit_ov_checked = true
					if hit_ov != null and hit_ov.has_method("push_hit_pip"):
						hit_ov.call("push_hit_pip", target_node.global_position, HitFeedbackOverlay.KIND_ANTI_ARMOR, 0, target_node.get_instance_id())
