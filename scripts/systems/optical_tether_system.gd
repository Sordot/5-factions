class_name OpticalTetherSystem
extends Node

## Manages Optical Tether ("Harmonic Communion") links from friendly emitter units
## and powered emitter structures to nearby allied combat units (Milestone 3.9).
## Strictly deterministic, 0.20s interval, capped at MAX_TETHER_STACKS = 2, and
## zero overhead when no emitters exist on the battlefield.

const UPDATE_INTERVAL: float = 0.20
const MAX_TETHER_STACKS: int = 2
const TETHER_TTL: float = 0.45

var active_links: Array[Dictionary] = []
var _update_acc: float = 0.0


func _ready() -> void:
	add_to_group("optical_tether_system")


func _physics_process(delta: float) -> void:
	_update_acc += delta
	if _update_acc < UPDATE_INTERVAL:
		return
	_update_acc = fmod(_update_acc, UPDATE_INTERVAL)
	_recompute_tethers()


func _recompute_tethers() -> void:
	if not is_inside_tree():
		active_links.clear()
		return

	var emitters: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(node) or not (node is Unit):
			continue
		var u: Unit = node as Unit
		if u.is_dead or u.is_staffed or u.is_queued_for_deletion() or u.data == null:
			continue
		if u.data.tether_emit_radius > 0.0 and u.data.tether_max_links > 0:
			emitters.append({
				"node": u,
				"id": u.get_instance_id(),
				"pos": u.global_position,
				"team": int(u.team),
				"radius": u.data.tether_emit_radius,
				"max_links": u.data.tether_max_links,
				"fire_rate_bonus": maxf(0.0, u.data.tether_fire_rate_bonus),
				"range_bonus": maxf(0.0, u.data.tether_range_bonus),
				"beam_ramp_bonus": maxf(0.0, u.data.tether_beam_ramp_bonus),
			})

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(node) or not (node is Building):
			continue
		var b: Building = node as Building
		if b.is_destroyed or not b.is_constructed or b.is_salvaging or not b.is_powered or b.is_queued_for_deletion():
			continue
		if b.tether_emit_radius > 0.0 and b.tether_max_links > 0:
			emitters.append({
				"node": b,
				"id": b.get_instance_id(),
				"pos": b.global_position,
				"team": int(b.team),
				"radius": b.tether_emit_radius,
				"max_links": b.tether_max_links,
				"fire_rate_bonus": maxf(0.0, b.tether_fire_rate_bonus),
				"range_bonus": maxf(0.0, b.tether_range_bonus),
				"beam_ramp_bonus": maxf(0.0, b.tether_beam_ramp_bonus),
			})

	# Fast-exit when zero emitters exist (zero overhead for GENESIS_V2 & MONOLITH_OS)
	if emitters.is_empty():
		if not active_links.is_empty():
			active_links.clear()
		return

	emitters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["id"]) < int(b["id"])
	)

	var new_links: Array[Dictionary] = []
	var unit_accum: Dictionary = {} # unit_instance_id -> Dictionary
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager

	for em: Dictionary in emitters:
		var em_node: Node2D = em["node"] as Node2D
		var em_pos: Vector2 = em["pos"] as Vector2
		var em_team: int = int(em["team"])
		var emit_r: float = float(em["radius"]) + (econ.get_bonus_tether_radius(em_team) if econ != null else 0.0)
		var emit_r_sq: float = emit_r * emit_r
		var max_links: int = int(em["max_links"]) + (econ.get_bonus_tether_links(em_team) if econ != null else 0)
		var fr_bonus: float = float(em["fire_rate_bonus"])
		var rng_bonus: float = float(em["range_bonus"])
		var ramp_bonus: float = float(em["beam_ramp_bonus"])

		var nearby: Array = SpatialGrid.query_units_in_radius(em_pos, emit_r + 24.0) if SpatialGrid != null else get_tree().get_nodes_in_group("units")
		var candidates: Array[Dictionary] = []
		for item: Variant in nearby:
			if not is_instance_valid(item) or not (item is Unit):
				continue
			var cand: Unit = item as Unit
			if cand == em_node or cand.is_dead or cand.is_staffed or cand.is_queued_for_deletion():
				continue
			if int(cand.team) != em_team:
				continue
			if cand.data == null or not cand.data.is_combat_unit():
				continue
			var d_sq: float = em_pos.distance_squared_to(cand.global_position)
			if d_sq > emit_r_sq:
				continue
			var cid: int = cand.get_instance_id()
			var cur_stacks: int = int((unit_accum[cid] as Dictionary)["stacks"]) if unit_accum.has(cid) else 0
			if cur_stacks >= MAX_TETHER_STACKS:
				continue
			candidates.append({
				"unit": cand,
				"id": cid,
				"stacks": cur_stacks,
				"dist_sq": d_sq,
			})

		if candidates.is_empty():
			continue

		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var sa: int = int(a["stacks"])
			var sb: int = int(b["stacks"])
			if sa != sb:
				return sa < sb
			var da: float = float(a["dist_sq"])
			var db: float = float(b["dist_sq"])
			if not is_equal_approx(da, db):
				return da < db
			return int(a["id"]) < int(b["id"])
		)

		var linked: int = 0
		for c: Dictionary in candidates:
			if linked >= max_links:
				break
			var target_u: Unit = c["unit"] as Unit
			var tid: int = int(c["id"])
			if not unit_accum.has(tid):
				unit_accum[tid] = {
					"unit": target_u,
					"stacks": 0,
					"fire_rate_bonus": 0.0,
					"range_bonus": 0.0,
					"beam_ramp_bonus": 0.0,
				}
			var acc: Dictionary = unit_accum[tid] as Dictionary
			var next_stacks: int = int(acc["stacks"]) + 1
			if next_stacks > MAX_TETHER_STACKS:
				continue
			acc["stacks"] = next_stacks
			acc["fire_rate_bonus"] = float(acc["fire_rate_bonus"]) + fr_bonus
			acc["range_bonus"] = float(acc["range_bonus"]) + rng_bonus
			acc["beam_ramp_bonus"] = float(acc["beam_ramp_bonus"]) + ramp_bonus
			new_links.append({
				"from_node": em_node,
				"to_node": target_u,
				"from_pos": em_pos,
				"to_pos": target_u.global_position,
				"team": em_team,
				"stack_index": next_stacks,
			})
			linked += 1

	for acc_val: Variant in unit_accum.values():
		var acc: Dictionary = acc_val as Dictionary
		var target_u: Unit = acc["unit"] as Unit
		if not is_instance_valid(target_u) or target_u.is_dead or target_u.status_effect_component == null:
			continue
		var stacks: int = int(acc["stacks"])
		target_u.status_effect_component.apply_effect(&"optical_tether", {
			"duration": TETHER_TTL,
			"label": "Lattice Link x%d" % stacks,
			"attack_speed_mult": 1.0 + float(acc["fire_rate_bonus"]),
			"bonus_attack_range": float(acc["range_bonus"]),
			"beam_ramp_speed_mult": 1.0 + float(acc["beam_ramp_bonus"]),
			"tether_stacks": stacks,
		})

	active_links = new_links
