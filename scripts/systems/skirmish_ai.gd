class_name SkirmishAICommander
extends Node

const REFINERY_DATA_PATH: String = "res://resources/buildings/silica_refinery_data.tres"
const RELAY_DATA_PATH: String = "res://resources/buildings/bandwidth_relay_data.tres"
const BIOLAB_DATA_PATH: String = "res://resources/buildings/bio_lab_data.tres"

const WORKER_DATA_PATH: String = "res://resources/units/worker_unit_data.tres"
const HARVESTER_DATA_PATH: String = "res://resources/units/silica_harvester_data.tres"
const TROOPER_DATA_PATH: String = "res://resources/units/enemy_trooper_data.tres"

@export var ai_team: Unit.Team = Unit.Team.ENEMY
@export var enabled: bool = true
@export var decision_interval: float = 1.0
@export var target_worker_count: int = 6
@export var max_bio_labs: int = 2
@export var max_bandwidth_cap: int = 34
@export var wave_squad_size: int = 4
@export var max_wave_interval: float = 52.0
@export var base_defense_radius: float = 440.0
@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)

var _refinery_data: BuildingData = null
var _relay_data: BuildingData = null
var _biolab_data: BuildingData = null
var _worker_data: UnitData = null
var _harvester_data: UnitData = null
var _trooper_data: UnitData = null

var _decision_timer: float = 0.0
var _wave_timer: float = 0.0
var _wave_number: int = 0
var _dispatched_wave_units: Dictionary = {}


func _ready() -> void:
	add_to_group("skirmish_ai")
	_refinery_data = load(REFINERY_DATA_PATH) as BuildingData
	_relay_data = load(RELAY_DATA_PATH) as BuildingData
	_biolab_data = load(BIOLAB_DATA_PATH) as BuildingData
	_worker_data = load(WORKER_DATA_PATH) as UnitData
	_harvester_data = load(HARVESTER_DATA_PATH) as UnitData
	_trooper_data = load(TROOPER_DATA_PATH) as UnitData
	call_deferred("_setup_initial_rallies")


func _process(delta: float) -> void:
	if not enabled:
		return
	_wave_timer += delta
	_decision_timer += delta
	if _decision_timer < maxf(0.25, decision_interval):
		return
	_decision_timer = 0.0
	_run_decision_tick()


func _setup_initial_rallies() -> void:
	var core: Building = _find_ai_command_core()
	if core == null:
		return
	var nearest_bio: ResourceNode = _find_nearest_resource(core.global_position, &"biomass")
	if nearest_bio != null:
		core.set_rally_target(nearest_bio)


func _run_decision_tick() -> void:
	var econ: EconomyManager = _get_economy_manager()
	if econ == null:
		return
	var core: Building = _find_ai_command_core()
	if core == null:
		return

	# 1. Assign idle workers to harvest Biomass and resume any abandoned construction sites.
	_assign_idle_workers(core)
	_resume_unfinished_buildings()

	# 2. Check for incoming threats against AI structures or workers.
	var under_attack: bool = _handle_base_defense()

	# 3. Economy, infrastructure, and production loop using real EconomyManager resources.
	_manage_economy_and_production(econ, core)

	# 4. Coordinate attack waves when a combat squad is ready.
	if not under_attack:
		_manage_attack_waves(core)


func _assign_idle_workers(core: Building) -> void:
	var biomass_nodes: Array[ResourceNode] = _get_resources_near(core.global_position, &"biomass", 750.0)
	if biomass_nodes.is_empty():
		biomass_nodes = _get_resources_near(core.global_position, &"biomass", 3000.0)
	if biomass_nodes.is_empty():
		return

	for unit: Unit in _get_team_units(ai_team):
		if unit.get_unit_type_id() != &"worker":
			continue
		if unit.command_state != Unit.CommandState.IDLE:
			continue
		if unit.is_carrying_cargo():
			if unit.command_return_cargo(core):
				continue
		var best_node: ResourceNode = _pick_least_crowded_resource(unit.global_position, biomass_nodes)
		if best_node != null:
			unit.command_gather(best_node)


func _resume_unfinished_buildings() -> void:
	for b: Building in _get_team_buildings(ai_team):
		if b.is_constructed:
			continue
		if _has_worker_building(b):
			continue
		var worker: Unit = _find_available_worker(b.global_position)
		if worker != null:
			worker.command_construct_building(b)


func _handle_base_defense() -> bool:
	var ai_buildings: Array[Building] = _get_team_buildings(ai_team)
	var ai_workers: Array[Unit] = []
	for u: Unit in _get_team_units(ai_team):
		if u.get_unit_type_id() == &"worker" or u.get_unit_type_id() == &"silica_harvester":
			ai_workers.append(u)

	var threat_unit: Unit = null
	var closest_threat_dist_sq: float = INF
	var def_r_sq: float = base_defense_radius * base_defense_radius
	var worker_def_sq: float = 220.0 * 220.0

	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var hostile: Unit = node
		if hostile.is_dead or hostile.is_staffed or hostile.team == ai_team:
			continue
		var is_threatening: bool = false
		var min_d_sq: float = INF
		for b: Building in ai_buildings:
			var d_sq: float = hostile.global_position.distance_squared_to(b.global_position)
			if d_sq <= def_r_sq:
				is_threatening = true
				min_d_sq = minf(min_d_sq, d_sq)
		if not is_threatening:
			for w: Unit in ai_workers:
				var d_sq: float = hostile.global_position.distance_squared_to(w.global_position)
				if d_sq <= worker_def_sq:
					is_threatening = true
					min_d_sq = minf(min_d_sq, d_sq)
		if is_threatening and min_d_sq < closest_threat_dist_sq:
			closest_threat_dist_sq = min_d_sq
			threat_unit = hostile

	if threat_unit == null:
		return false

	# Pull nearby idle or staging combat troopers to defend the base.
	for u: Unit in _get_team_units(ai_team):
		if not _is_combat_unit(u):
			continue
		var near_base: bool = u.global_position.distance_to(threat_unit.global_position) <= 780.0
		if not near_base:
			continue
		if u.command_state == Unit.CommandState.IDLE or u.command_state == Unit.CommandState.MOVING:
			u.command_attack_move(threat_unit.global_position)
		elif u.command_state == Unit.CommandState.ATTACK_MOVING and u.current_target == null:
			if u.global_position.distance_to(threat_unit.global_position) > 220.0:
				u.command_attack_move(threat_unit.global_position)
	return true


func _manage_economy_and_production(econ: EconomyManager, core: Building) -> void:
	var buildings: Array[Building] = _get_team_buildings(ai_team)
	var units: Array[Unit] = _get_team_units(ai_team)

	var worker_count: int = 0
	var harvester_count: int = 0
	for u: Unit in units:
		var uid: StringName = u.get_unit_type_id()
		if uid == &"worker":
			worker_count += 1
		elif uid == &"silica_harvester":
			harvester_count += 1

	var refineries: Array[Building] = []
	var constructed_refinery: Building = null
	var bio_labs: Array[Building] = []
	var constructed_bio_labs: Array[Building] = []
	var unfinished_relays: int = 0

	for b: Building in buildings:
		if b.building_type_id == &"silica_refinery":
			refineries.append(b)
			if b.is_constructed:
				constructed_refinery = b
		elif b.building_type_id == &"bio_lab":
			bio_labs.append(b)
			if b.is_constructed:
				constructed_bio_labs.append(b)
		elif b.building_type_id == &"bandwidth_relay" and not b.is_constructed:
			unfinished_relays += 1

	# Account for units already queued in production so we don't over-train workers/harvesters.
	var queued_workers: int = _count_queued_unit_type(buildings, &"worker")
	var queued_harvesters: int = _count_queued_unit_type(buildings, &"silica_harvester")
	var total_workers: int = worker_count + queued_workers
	var total_harvesters: int = harvester_count + queued_harvesters

	var bw_used: int = econ.get_bandwidth_used(ai_team)
	var bw_cap: int = econ.get_bandwidth_cap(ai_team)
	var needs_relay: bool = (bw_used >= bw_cap - 2) and unfinished_relays == 0 and bw_cap < max_bandwidth_cap
	var biomass: int = econ.get_resource(ai_team, EconomyManager.RESOURCE_BIOMASS)
	var silica: int = econ.get_resource(ai_team, EconomyManager.RESOURCE_SILICA)

	# Priority 1: Ensure baseline worker core (3 workers).
	if total_workers < 3:
		if _worker_data != null and core.get_training_queue_size() < 2 and core.can_train_unit_data(_worker_data):
			core.queue_unit_data(_worker_data)
		return

	# Priority 2: Build Silica Refinery near enemy Silica Vein.
	if refineries.is_empty():
		if _refinery_data != null and econ.can_afford(ai_team, _refinery_data.get_cost_dict()):
			var vein: ResourceNode = _find_nearest_resource(core.global_position, &"silica")
			var anchor: Vector2 = core.global_position.lerp(vein.global_position, 0.58) if vein != null else (core.global_position + Vector2(-120.0, 180.0))
			_try_place_and_build(_refinery_data, anchor, core.global_position)
		return

	# Priority 3: Expand Bandwidth cap before hitting population block.
	if needs_relay:
		if _relay_data != null and econ.can_afford(ai_team, _relay_data.get_cost_dict()):
			var away_dir: Vector2 = (core.global_position - Vector2.ZERO).normalized()
			var relay_anchor: Vector2 = core.global_position + away_dir * 125.0
			_try_place_and_build(_relay_data, relay_anchor, core.global_position)
		return

	# Priority 4: Train automated Silica Harvester once Refinery is online.
	var desired_harvesters: int = 2 if constructed_bio_labs.size() >= 1 else 1
	if _harvester_data != null and constructed_refinery != null and total_harvesters < desired_harvesters:
		var trainer: Building = constructed_refinery if constructed_refinery.can_train_unit_data(_harvester_data) else core
		if trainer.get_training_queue_size() < 2 and trainer.can_train_unit_data(_harvester_data):
			trainer.queue_unit_data(_harvester_data)
			return

	# Priority 5: Construct primary Bio-Lab on the forward edge facing the map center.
	if bio_labs.is_empty() and _biolab_data != null:
		if econ.can_afford(ai_team, _biolab_data.get_cost_dict()):
			var to_center: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var lab_anchor: Vector2 = core.global_position + to_center * 175.0
			var built_lab: Building = _try_place_and_build(_biolab_data, lab_anchor, core.global_position)
			if built_lab != null:
				built_lab.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))
			return
		# If we already have enough Silica for Bio-Lab, hold Biomass to build it immediately.
		if silica >= _biolab_data.silica_cost and biomass < _biolab_data.biomass_cost:
			return

	# Priority 6: Saturate workers up to target_worker_count.
	if _worker_data != null and total_workers < target_worker_count:
		if core.get_training_queue_size() < 2 and core.can_train_unit_data(_worker_data):
			core.queue_unit_data(_worker_data)

	# Priority 7: Train Hostile Troopers continuously from constructed Bio-Labs.
	for lab: Building in constructed_bio_labs:
		if not lab.has_rally():
			lab.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))
		if _trooper_data != null and lab.get_training_queue_size() < 2 and lab.can_train_unit_data(_trooper_data):
			lab.queue_unit_data(_trooper_data)

	# Priority 8: Late-game second Bio-Lab when floating surplus resources.
	if _biolab_data != null and bio_labs.size() < max_bio_labs and biomass >= 260 and silica >= 100:
		if econ.can_afford(ai_team, _biolab_data.get_cost_dict()):
			var to_center2: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp: Vector2 = Vector2(-to_center2.y, to_center2.x)
			var lab_anchor2: Vector2 = core.global_position + to_center2 * 180.0 + perp * 130.0
			var second_lab: Building = _try_place_and_build(_biolab_data, lab_anchor2, core.global_position)
			if second_lab != null:
				second_lab.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))


func _manage_attack_waves(core: Building) -> void:
	_prune_dispatched_units()
	var staging_units: Array[Unit] = []
	for u: Unit in _get_team_units(ai_team):
		if not _is_combat_unit(u):
			continue
		var u_id: int = u.get_instance_id()
		if u.command_state == Unit.CommandState.IDLE:
			# Clear stale dispatch mark if unit finished its previous order.
			_dispatched_wave_units.erase(u_id)
			staging_units.append(u)
		elif not _dispatched_wave_units.has(u_id) and u.global_position.distance_to(core.global_position) <= 580.0:
			if u.command_state == Unit.CommandState.MOVING:
				staging_units.append(u)

	var ready_by_size: bool = staging_units.size() >= wave_squad_size
	var ready_by_timer: bool = _wave_timer >= max_wave_interval and staging_units.size() >= maxi(2, wave_squad_size - 1)
	if not ready_by_size and not ready_by_timer:
		return

	_wave_number += 1
	_wave_timer = 0.0

	var target_pos: Vector2 = _select_wave_target(_wave_number)
	var router: CommandRouter = _get_command_router()
	var destinations: Array[Vector2] = []
	if router != null:
		destinations = router.assign_group_destinations(staging_units, target_pos)

	for i: int in range(staging_units.size()):
		var trooper: Unit = staging_units[i]
		var dest: Vector2 = destinations[i] if i < destinations.size() else target_pos
		trooper.command_attack_move(dest)
		_dispatched_wave_units[trooper.get_instance_id()] = true


func _select_wave_target(wave_idx: int) -> Vector2:
	var uplink: HyperUplink = get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	# Odd waves contest the central Data Hyper-Uplink (unless AI already controls it).
	if (wave_idx % 2) == 1 and uplink != null and uplink.controlling_team != int(ai_team):
		return uplink.global_position

	# Even waves (or follow-up waves while holding uplink) push the Player's Command Core.
	var player_core: Building = _find_opposing_command_core()
	if player_core != null:
		return player_core.global_position

	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node
			if not b.is_destroyed and b.team != ai_team:
				return b.global_position

	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node):
			var u: Unit = node
			if not u.is_dead and not u.is_staffed and u.team != ai_team:
				return u.global_position

	return Vector2.ZERO


func _try_place_and_build(data: BuildingData, preferred_pos: Vector2, fallback_origin: Vector2) -> Building:
	var econ: EconomyManager = _get_economy_manager()
	if econ == null or data == null or data.scene == null:
		return null
	if not econ.can_afford(ai_team, data.get_cost_dict()):
		return null

	var worker: Unit = _find_available_worker(preferred_pos)
	if worker == null:
		return null

	var spot: Vector2 = _find_valid_build_position(data, preferred_pos, fallback_origin)
	if spot == Vector2.INF:
		return null

	if not econ.spend_resources(ai_team, data.get_cost_dict()):
		return null

	var scene_root: Node = get_tree().current_scene
	var buildings_container: Node = scene_root.get_node_or_null("Buildings") if scene_root != null else null
	if buildings_container == null:
		buildings_container = get_parent()
	if buildings_container == null:
		return null

	var instance: Node = data.scene.instantiate()
	if not (instance is Building):
		instance.queue_free()
		return null

	var new_building: Building = instance
	new_building.global_position = spot
	new_building.is_constructed = false
	buildings_container.add_child(new_building)
	new_building.begin_construction(data, ai_team)
	_nudge_units_out_of_building(new_building)

	worker.command_construct_building(new_building)
	return new_building


func _find_valid_build_position(data: BuildingData, preferred_pos: Vector2, fallback_origin: Vector2) -> Vector2:
	var anchors: Array[Vector2] = [preferred_pos, fallback_origin]
	var radii: PackedFloat32Array = PackedFloat32Array([0.0, 75.0, 125.0, 175.0, 230.0, 290.0])
	var angle_steps: int = 12

	for anchor: Vector2 in anchors:
		for r: float in radii:
			if r <= 0.1:
				if _is_build_spot_valid(data, anchor):
					return anchor
				continue
			for k: int in range(angle_steps):
				var angle: float = TAU * float(k) / float(angle_steps)
				var candidate: Vector2 = anchor + Vector2.RIGHT.rotated(angle) * r
				if _is_build_spot_valid(data, candidate):
					return candidate
	return Vector2.INF


func _is_build_spot_valid(data: BuildingData, world_pos: Vector2) -> bool:
	var router: CommandRouter = _get_command_router()
	if router != null:
		var eval: Dictionary = router.evaluate_build_placement(data, world_pos, ai_team)
		return bool(eval.get("valid", false))

	var half: Vector2 = data.footprint_size * 0.5
	var safe_bounds: Rect2 = Rect2(
		arena_bounds.position + half + Vector2(8.0, 8.0),
		arena_bounds.size - data.footprint_size - Vector2(16.0, 16.0)
	)
	if not safe_bounds.has_point(world_pos):
		return false
	var new_radius: float = data.get_footprint_radius()
	for node: Node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if is_instance_valid(node) and node.has_method("overlaps_circle"):
			if node.overlaps_circle(world_pos, new_radius + 8.0):
				return false
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node) and not (node as Building).is_destroyed:
			var min_d: float = (node as Building).footprint_radius + new_radius + 10.0
			if (node as Building).global_position.distance_squared_to(world_pos) < min_d * min_d:
				return false
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node
			if rn.is_depleted() or rn.is_vent:
				continue
			var min_d: float = rn.collision_radius + new_radius + 8.0
			if rn.global_position.distance_squared_to(world_pos) < min_d * min_d:
				return false
	return true


func _find_available_worker(near_pos: Vector2) -> Unit:
	var best_idle: Unit = null
	var best_idle_d_sq: float = INF
	var best_gathering: Unit = null
	var best_gather_d_sq: float = INF

	for u: Unit in _get_team_units(ai_team):
		if not u.can_construct():
			continue
		if u.command_state == Unit.CommandState.CONSTRUCTING:
			continue
		var d_sq: float = u.global_position.distance_squared_to(near_pos)
		if u.command_state == Unit.CommandState.IDLE:
			if d_sq < best_idle_d_sq:
				best_idle_d_sq = d_sq
				best_idle = u
		elif u.command_state == Unit.CommandState.GATHERING:
			if d_sq < best_gather_d_sq:
				best_gather_d_sq = d_sq
				best_gathering = u

	return best_idle if best_idle != null else best_gathering


func _has_worker_building(target_b: Building) -> bool:
	for u: Unit in _get_team_units(ai_team):
		if u.command_state == Unit.CommandState.CONSTRUCTING and u._construction_target == target_b:
			return true
	return false


func _find_ai_command_core() -> Building:
	for b: Building in _get_team_buildings(ai_team):
		if b.building_type_id == &"command_core":
			return b
	return null


func _find_opposing_command_core() -> Building:
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node
			if not b.is_destroyed and b.team != ai_team and b.building_type_id == &"command_core":
				return b
	return null


func _get_team_buildings(target_team: Unit.Team) -> Array[Building]:
	var out: Array[Building] = []
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node
			if not b.is_destroyed and b.team == target_team:
				out.append(b)
	return out


func _get_team_units(target_team: Unit.Team) -> Array[Unit]:
	var out: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node):
			var u: Unit = node
			if not u.is_dead and not u.is_staffed and u.team == target_team:
				out.append(u)
	return out


func _is_combat_unit(unit: Unit) -> bool:
	if unit == null or unit.data == null:
		return false
	if unit.data.can_gather or unit.data.can_staff_compute:
		return false
	return unit.data.attack_damage > 0.0 and unit.data.move_speed > 0.0


func _count_queued_unit_type(buildings: Array[Building], type_id: StringName) -> int:
	var count: int = 0
	for b: Building in buildings:
		if b.production_component == null:
			continue
		for entry: Dictionary in b.production_component.get_queue():
			var udata: UnitData = entry.get("data", null) as UnitData
			if udata != null and udata.unit_type_id == type_id:
				count += 1
	return count


func _find_nearest_resource(origin: Vector2, res_type: StringName) -> ResourceNode:
	var best: ResourceNode = null
	var best_d_sq: float = INF
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node
			if rn.is_depleted() or rn.is_vent or rn.resource_type != res_type:
				continue
			var d_sq: float = origin.distance_squared_to(rn.global_position)
			if d_sq < best_d_sq:
				best_d_sq = d_sq
				best = rn
	return best


func _get_resources_near(origin: Vector2, res_type: StringName, max_radius: float) -> Array[ResourceNode]:
	var out: Array[ResourceNode] = []
	var max_r_sq: float = max_radius * max_radius
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node
			if rn.is_depleted() or rn.is_vent or rn.resource_type != res_type:
				continue
			if origin.distance_squared_to(rn.global_position) <= max_r_sq:
				out.append(rn)
	return out


func _pick_least_crowded_resource(worker_pos: Vector2, nodes: Array[ResourceNode]) -> ResourceNode:
	var best: ResourceNode = null
	var best_score: float = INF
	for rn: ResourceNode in nodes:
		if not is_instance_valid(rn) or rn.is_depleted():
			continue
		var assigned: int = 0
		for u: Unit in _get_team_units(ai_team):
			if u.gather_component != null and u.gather_component.is_active() and u.gather_component.target_node == rn:
				assigned += 1
		var dist: float = worker_pos.distance_to(rn.global_position)
		var score: float = float(assigned) * 180.0 + dist
		if score < best_score:
			best_score = score
			best = rn
	return best


func _prune_dispatched_units() -> void:
	var live_ids: Dictionary = {}
	for u: Unit in _get_team_units(ai_team):
		live_ids[u.get_instance_id()] = true
	for k: Variant in _dispatched_wave_units.keys():
		if not live_ids.has(k):
			_dispatched_wave_units.erase(k)


func _nudge_units_out_of_building(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	for node: Node in get_tree().get_nodes_in_group("units"):
		if not (node is Unit) or not is_instance_valid(node):
			continue
		var unit: Unit = node
		if unit.is_dead or unit.is_staffed:
			continue
		var unit_r: float = unit.data.collision_radius if unit.data != null else 14.0
		var min_dist: float = building.footprint_radius + unit_r + 6.0
		var diff: Vector2 = unit.global_position - building.global_position
		if diff.length_squared() < min_dist * min_dist:
			var dir: Vector2 = diff.normalized() if diff.length_squared() > 0.01 else Vector2.RIGHT
			unit.global_position = building.global_position + dir * min_dist


func _get_economy_manager() -> EconomyManager:
	return get_tree().get_first_node_in_group("economy_manager") as EconomyManager


func _get_command_router() -> CommandRouter:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("SelectionController/CommandRouter") as CommandRouter
