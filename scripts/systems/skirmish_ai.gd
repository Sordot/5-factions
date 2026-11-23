class_name SkirmishAICommander
extends Node

const CONDENSER_DATA_PATH: String = "res://resources/buildings/silica_condenser_data.tres"
const PYLON_DATA_PATH: String = "res://resources/buildings/synapse_pylon_data.tres"
const MAINFRAME_DATA_PATH: String = "res://resources/buildings/wetware_mainframe_data.tres"
const CLONING_VAT_DATA_PATH: String = "res://resources/buildings/cloning_vat_data.tres"
const FABRICATOR_DATA_PATH: String = "res://resources/buildings/synthetics_fabricator_data.tres"

const WORKER_DATA_PATH: String = "res://resources/units/worker_unit_data.tres"
const HARVESTER_DATA_PATH: String = "res://resources/units/silica_harvester_data.tres"
const ENGINEER_DATA_PATH: String = "res://resources/units/engineer_data.tres"
const CLONE_TROOPER_DATA_PATH: String = "res://resources/units/clone_trooper_data.tres"
const STINGER_DATA_PATH: String = "res://resources/units/stinger_data.tres"
const GOLIATH_DATA_PATH: String = "res://resources/units/goliath_frame_data.tres"

@export var ai_team: Unit.Team = Unit.Team.ENEMY
@export var enabled: bool = true
@export var decision_interval: float = 1.0
@export var target_worker_count: int = 6
@export var max_cloning_vats: int = 2
@export var max_bandwidth_cap: int = 44
@export var wave_squad_size: int = 6
@export var max_wave_interval: float = 50.0
@export var base_defense_radius: float = 440.0
@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)

var _condenser_data: BuildingData = null
var _pylon_data: BuildingData = null
var _mainframe_data: BuildingData = null
var _cloning_vat_data: BuildingData = null
var _fabricator_data: BuildingData = null
var _worker_data: UnitData = null
var _harvester_data: UnitData = null
var _engineer_data: UnitData = null
var _clone_trooper_data: UnitData = null
var _stinger_data: UnitData = null
var _goliath_data: UnitData = null

var _decision_timer: float = 0.0
var _wave_timer: float = 0.0
var _wave_number: int = 0
var _vat_production_counter: int = 0
var _dispatched_wave_units: Dictionary = {}
var _unit_last_pos: Dictionary = {}
var _unit_stall_ticks: Dictionary = {}


func _ready() -> void:
	add_to_group("skirmish_ai")
	_condenser_data = load(CONDENSER_DATA_PATH) as BuildingData
	_pylon_data = load(PYLON_DATA_PATH) as BuildingData
	_mainframe_data = load(MAINFRAME_DATA_PATH) as BuildingData
	_cloning_vat_data = load(CLONING_VAT_DATA_PATH) as BuildingData
	_fabricator_data = load(FABRICATOR_DATA_PATH) as BuildingData
	_worker_data = load(WORKER_DATA_PATH) as UnitData
	_harvester_data = load(HARVESTER_DATA_PATH) as UnitData
	_engineer_data = load(ENGINEER_DATA_PATH) as UnitData
	_clone_trooper_data = load(CLONE_TROOPER_DATA_PATH) as UnitData
	_stinger_data = load(STINGER_DATA_PATH) as UnitData
	_goliath_data = load(GOLIATH_DATA_PATH) as UnitData
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

	# 1. Assign idle workers & harvesters to gather, staff idle engineers, and resume unfinished sites.
	_assign_idle_workers(core)
	_assign_idle_harvesters()
	_assign_idle_engineers()
	_resume_unfinished_buildings()

	var aggro_enabled: bool = MatchManager.is_aggro_ai_enabled(get_tree())
	if not aggro_enabled:
		# Pause offensive AI pushes and aggressive target-seeking while Aggro AI is toggled OFF.
		return

	# 2. Recover any combat wave units that stalled behind obstacles.
	_recover_stalled_combat_units()

	# 3. Check for incoming threats against AI structures or workers.
	var under_attack: bool = _handle_base_defense()

	# 4. Economy, infrastructure, and GENESIS_V2 production loop using real EconomyManager resources.
	_manage_economy_and_production(econ, core)

	# 5. Coordinate attack waves when a combat squad is ready.
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


func _assign_idle_harvesters() -> void:
	for unit: Unit in _get_team_units(ai_team):
		if unit.get_unit_type_id() != &"silica_harvester":
			continue
		if unit.command_state != Unit.CommandState.IDLE:
			continue
		if unit.is_carrying_cargo():
			if unit.command_return_cargo():
				continue
		var vein: ResourceNode = _find_nearest_resource(unit.global_position, &"silica")
		if vein != null:
			unit.command_gather(vein)


func _recover_stalled_combat_units() -> void:
	var live_ids: Dictionary = {}
	for u: Unit in _get_team_units(ai_team):
		if not _is_combat_unit(u):
			continue
		var uid: int = u.get_instance_id()
		live_ids[uid] = true
		var is_traveling: bool = (
			u.command_state == Unit.CommandState.MOVING
			or (u.command_state == Unit.CommandState.ATTACK_MOVING and (u.current_target == null or not is_instance_valid(u.current_target)))
		)
		if not is_traveling:
			_unit_last_pos[uid] = u.global_position
			_unit_stall_ticks[uid] = 0
			continue
		if _unit_last_pos.has(uid):
			var prev_pos: Vector2 = _unit_last_pos[uid]
			if u.global_position.distance_to(prev_pos) < 18.0:
				var ticks: int = int(_unit_stall_ticks.get(uid, 0)) + 1
				_unit_stall_ticks[uid] = ticks
				if ticks >= 3:
					_unit_stall_ticks[uid] = 0
					var final_dest: Vector2 = _select_wave_target(_wave_number)
					var to_dest: Vector2 = final_dest - u.global_position
					var dir: Vector2 = to_dest.normalized() if to_dest.length_squared() > 4.0 else Vector2.LEFT
					var side_sign: float = 1.0 if ((uid + _wave_number) % 2) == 0 else -1.0
					var detour: Vector2 = u.global_position + Vector2(-dir.y, dir.x) * (150.0 * side_sign) + dir * 75.0
					detour = Vector2(
						clampf(detour.x, arena_bounds.position.x + 80.0, arena_bounds.end.x - 80.0),
						clampf(detour.y, arena_bounds.position.y + 80.0, arena_bounds.end.y - 80.0)
					)
					u.command_move(detour)
					u.command_attack_move(final_dest, true)
			else:
				_unit_stall_ticks[uid] = 0
		_unit_last_pos[uid] = u.global_position

	for k: Variant in _unit_last_pos.keys():
		if not live_ids.has(k):
			_unit_last_pos.erase(k)
			_unit_stall_ticks.erase(k)


func _assign_idle_engineers() -> void:
	var open_mainframes: Array[Building] = []
	for b: Building in _get_team_buildings(ai_team):
		if b.is_constructed and b.max_staff_slots > 0 and b.get_assigned_engineer_count() < b.max_staff_slots:
			open_mainframes.append(b)
	if open_mainframes.is_empty():
		return
	for unit: Unit in _get_team_units(ai_team):
		if not unit.can_staff_compute() or unit.command_state != Unit.CommandState.IDLE:
			continue
		for mf: Building in open_mainframes:
			if mf.can_accept_staff(unit):
				unit.command_staff_building(mf)
				break


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
	var engineer_count: int = 0
	for u: Unit in units:
		var uid: StringName = u.get_unit_type_id()
		if uid == &"worker":
			worker_count += 1
		elif uid == &"silica_harvester":
			harvester_count += 1
		elif uid == &"engineer":
			engineer_count += 1

	var condensers: Array[Building] = []
	var constructed_condenser: Building = null
	var mainframes: Array[Building] = []
	var constructed_mainframe: Building = null
	var cloning_vats: Array[Building] = []
	var constructed_vats: Array[Building] = []
	var fabricators: Array[Building] = []
	var constructed_fabricators: Array[Building] = []
	var unfinished_pylons: int = 0
	var staffed_engineers: int = 0

	for b: Building in buildings:
		if b.building_type_id == &"silica_condenser" or b.building_type_id == &"silica_refinery":
			condensers.append(b)
			if b.is_constructed:
				constructed_condenser = b
		elif b.building_type_id == &"wetware_mainframe" or b.building_type_id == &"compute_node":
			mainframes.append(b)
			if b.is_constructed:
				constructed_mainframe = b
				staffed_engineers += b.get_assigned_engineer_count()
		elif b.building_type_id == &"cloning_vat" or b.building_type_id == &"bio_lab":
			cloning_vats.append(b)
			if b.is_constructed:
				constructed_vats.append(b)
		elif b.building_type_id == &"synthetics_fabricator":
			fabricators.append(b)
			if b.is_constructed:
				constructed_fabricators.append(b)
		elif (b.building_type_id == &"synapse_pylon" or b.building_type_id == &"bandwidth_relay") and not b.is_constructed:
			unfinished_pylons += 1

	var queued_workers: int = _count_queued_unit_type(buildings, &"worker")
	var queued_harvesters: int = _count_queued_unit_type(buildings, &"silica_harvester")
	var queued_engineers: int = _count_queued_unit_type(buildings, &"engineer")
	var total_workers: int = worker_count + queued_workers
	var total_harvesters: int = harvester_count + queued_harvesters
	var total_engineers: int = engineer_count + staffed_engineers + queued_engineers

	var bw_used: int = econ.get_bandwidth_used(ai_team)
	var bw_cap: int = econ.get_bandwidth_cap(ai_team)
	var needs_pylon: bool = (bw_used >= bw_cap - 4) and unfinished_pylons == 0 and bw_cap < max_bandwidth_cap
	var biomass: int = econ.get_resource(ai_team, EconomyManager.RESOURCE_BIOMASS)
	var silica: int = econ.get_resource(ai_team, EconomyManager.RESOURCE_SILICA)
	var compute: int = econ.get_resource(ai_team, EconomyManager.RESOURCE_COMPUTE)

	# Priority 1: Ensure baseline worker core (3 workers).
	if total_workers < 3:
		if _worker_data != null and core.get_training_queue_size() < 2 and core.can_train_unit_data(_worker_data):
			core.queue_unit_data(_worker_data)
		return

	# Priority 2: Build Silica Condenser near enemy Silica Vein.
	if condensers.is_empty():
		if _condenser_data != null and econ.can_afford(ai_team, _condenser_data.get_cost_dict()):
			var vein: ResourceNode = _find_nearest_resource(core.global_position, &"silica")
			var anchor: Vector2 = core.global_position.lerp(vein.global_position, 0.58) if vein != null else (core.global_position + Vector2(-120.0, 180.0))
			_try_place_and_build(_condenser_data, anchor, core.global_position)
		return

	# Priority 3: Expand Bandwidth cap via Synapse Pylon before hitting population block.
	if needs_pylon:
		if _pylon_data != null and econ.can_afford(ai_team, _pylon_data.get_cost_dict()):
			var away_dir: Vector2 = (core.global_position - Vector2.ZERO).normalized()
			var pylon_anchor: Vector2 = core.global_position + away_dir * 125.0
			_try_place_and_build(_pylon_data, pylon_anchor, core.global_position)
		return

	# Priority 4: Train automated Silica Harvester once Condenser is online.
	var desired_harvesters: int = 2 if constructed_vats.size() >= 1 else 1
	if _harvester_data != null and constructed_condenser != null and total_harvesters < desired_harvesters:
		var trainer: Building = constructed_condenser if constructed_condenser.can_train_unit_data(_harvester_data) else core
		if trainer.get_training_queue_size() < 2 and trainer.can_train_unit_data(_harvester_data):
			trainer.queue_unit_data(_harvester_data)
			return

	# Priority 5: Construct primary Tier-1 Cloning Vat on the forward edge facing the map center.
	if cloning_vats.is_empty() and _cloning_vat_data != null:
		if econ.can_afford(ai_team, _cloning_vat_data.get_cost_dict()):
			var to_center: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var vat_anchor: Vector2 = core.global_position + to_center * 175.0
			var built_vat: Building = _try_place_and_build(_cloning_vat_data, vat_anchor, core.global_position)
			if built_vat != null:
				built_vat.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))
			return
		if biomass < _cloning_vat_data.biomass_cost:
			return

	# Priority 6: Saturate workers up to target_worker_count.
	if _worker_data != null and total_workers < target_worker_count:
		if core.get_training_queue_size() < 2 and core.can_train_unit_data(_worker_data):
			core.queue_unit_data(_worker_data)

	# Priority 7: Mid-game Wetware Mainframe on nearby Compute Vent + Engineers for Compute economy.
	if mainframes.is_empty() and not constructed_vats.is_empty() and _mainframe_data != null:
		var vent: ResourceNode = _find_nearest_unoccupied_vent(core.global_position, 520.0)
		if vent != null and econ.can_afford(ai_team, _mainframe_data.get_cost_dict()):
			_try_place_and_build_on_vent(_mainframe_data, vent)

	if constructed_mainframe != null and _engineer_data != null and total_engineers < constructed_mainframe.max_staff_slots:
		if core.get_training_queue_size() < 2 and core.can_train_unit_data(_engineer_data):
			core.queue_unit_data(_engineer_data)

	# Priority 8: Late-game Tier-2 Synthetics Fabricator once Cloning Vat & Compute are online.
	if fabricators.is_empty() and not constructed_vats.is_empty() and _fabricator_data != null and compute >= _fabricator_data.compute_cost:
		if econ.can_afford(ai_team, _fabricator_data.get_cost_dict()):
			var to_center_f: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_f: Vector2 = Vector2(-to_center_f.y, to_center_f.x)
			var fab_anchor: Vector2 = core.global_position + to_center_f * 165.0 - perp_f * 140.0
			var built_fab: Building = _try_place_and_build(_fabricator_data, fab_anchor, core.global_position)
			if built_fab != null:
				built_fab.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))

	# Priority 9: Train heavy Goliath Frames from constructed Synthetics Fabricators.
	for fab: Building in constructed_fabricators:
		if not fab.has_rally():
			fab.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))
		if _goliath_data != null and fab.get_training_queue_size() < 2 and fab.can_train_unit_data(_goliath_data):
			fab.queue_unit_data(_goliath_data)

	# Priority 10: Batch-clone Clone Troopers (and occasional Stingers) from constructed Cloning Vats.
	for vat: Building in constructed_vats:
		if not vat.has_rally():
			vat.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))
		if vat.get_training_queue_size() >= 2:
			continue
		var want_stinger: bool = (_vat_production_counter % 3 == 2) and _stinger_data != null and vat.can_train_unit_data(_stinger_data)
		var chosen: UnitData = _stinger_data if want_stinger else _clone_trooper_data
		if chosen != null and vat.can_train_unit_data(chosen):
			vat.queue_unit_data(chosen)
			_vat_production_counter += 1

	# Priority 11: Second Cloning Vat when floating surplus Biomass.
	if _cloning_vat_data != null and cloning_vats.size() < max_cloning_vats and biomass >= 280 and silica >= 60:
		if econ.can_afford(ai_team, _cloning_vat_data.get_cost_dict()):
			var to_center2: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp: Vector2 = Vector2(-to_center2.y, to_center2.x)
			var vat_anchor2: Vector2 = core.global_position + to_center2 * 180.0 + perp * 130.0
			var second_vat: Building = _try_place_and_build(_cloning_vat_data, vat_anchor2, core.global_position)
			if second_vat != null:
				second_vat.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))


func _manage_attack_waves(core: Building) -> void:
	_prune_dispatched_units()
	var staging_units: Array[Unit] = []
	for u: Unit in _get_team_units(ai_team):
		if not _is_combat_unit(u):
			continue
		var u_id: int = u.get_instance_id()
		if u.command_state == Unit.CommandState.IDLE:
			_dispatched_wave_units.erase(u_id)
			staging_units.append(u)
		elif not _dispatched_wave_units.has(u_id) and u.global_position.distance_to(core.global_position) <= 580.0:
			if u.command_state == Unit.CommandState.MOVING:
				staging_units.append(u)

	var ready_by_size: bool = staging_units.size() >= wave_squad_size
	var ready_by_timer: bool = _wave_timer >= max_wave_interval and staging_units.size() >= maxi(2, wave_squad_size - 2)
	if not ready_by_size and not ready_by_timer:
		return

	_wave_number += 1
	_wave_timer = 0.0

	var target_pos: Vector2 = _select_wave_target(_wave_number)
	var router: CommandRouter = _get_command_router()
	var destinations: Array[Vector2] = []
	if router != null:
		destinations = router.assign_group_destinations(staging_units, target_pos)

	# Alternate direct objective pushes with northern/southern flanking routes using Shift-queued legs.
	var use_flank: bool = (_wave_number >= 2 and (_wave_number % 2) == 0)
	var flank_wp: Vector2 = Vector2.ZERO
	if use_flank:
		var north_lane: bool = ((_wave_number / 2) % 2) == 1
		flank_wp = Vector2(-220.0, -560.0) if north_lane else Vector2(220.0, 560.0)

	var flank_slots: Array[Vector2] = []
	if use_flank and router != null:
		flank_slots = router.assign_group_destinations(staging_units, flank_wp)

	for i: int in range(staging_units.size()):
		var trooper: Unit = staging_units[i]
		var dest: Vector2 = destinations[i] if i < destinations.size() else target_pos
		if use_flank:
			var leg1: Vector2 = flank_slots[i] if i < flank_slots.size() else flank_wp
			trooper.command_attack_move(leg1, false)
			trooper.command_attack_move(dest, true)
		else:
			trooper.command_attack_move(dest, false)
		_dispatched_wave_units[trooper.get_instance_id()] = true


func _select_wave_target(wave_idx: int) -> Vector2:
	var uplink: HyperUplink = get_tree().get_first_node_in_group("hyper_uplinks") as HyperUplink
	if (wave_idx % 2) == 1 and uplink != null and uplink.controlling_team != int(ai_team):
		return uplink.global_position

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
	if econ == null or data == null or data.resolve_scene() == null:
		return null
	if data.required_building_id != &"" and not econ.has_constructed_building(ai_team, data.required_building_id):
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

	return _instantiate_ai_building(data, spot, worker, null)


func _try_place_and_build_on_vent(data: BuildingData, vent: ResourceNode) -> Building:
	var econ: EconomyManager = _get_economy_manager()
	if econ == null or data == null or data.resolve_scene() == null or vent == null or not is_instance_valid(vent) or vent.is_occupied():
		return null
	if not econ.can_afford(ai_team, data.get_cost_dict()):
		return null
	var worker: Unit = _find_available_worker(vent.global_position)
	if worker == null:
		return null
	if not econ.spend_resources(ai_team, data.get_cost_dict()):
		return null
	return _instantiate_ai_building(data, vent.global_position, worker, vent)


func _instantiate_ai_building(data: BuildingData, spot: Vector2, worker: Unit, vent: ResourceNode) -> Building:
	var scene_root: Node = get_tree().current_scene
	var buildings_container: Node = scene_root.get_node_or_null("Buildings") if scene_root != null else null
	if buildings_container == null:
		buildings_container = get_parent()
	if buildings_container == null:
		return null

	var building_scene: PackedScene = data.resolve_scene()
	if building_scene == null:
		return null
	var instance: Node = building_scene.instantiate()
	if not (instance is Building):
		instance.queue_free()
		return null

	var new_building: Building = instance
	new_building.global_position = spot
	new_building.is_constructed = false
	buildings_container.add_child(new_building)
	new_building.begin_construction(data, ai_team, vent)
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


func _find_nearest_unoccupied_vent(origin: Vector2, max_radius: float) -> ResourceNode:
	var best: ResourceNode = null
	var best_d_sq: float = max_radius * max_radius
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if node is ResourceNode and is_instance_valid(node):
			var rn: ResourceNode = node
			if not rn.is_vent or rn.is_occupied():
				continue
			var d_sq: float = origin.distance_squared_to(rn.global_position)
			if d_sq <= best_d_sq:
				best_d_sq = d_sq
				best = rn
	return best


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
		if b.building_type_id == &"nexus_vat" or b.building_type_id == &"command_core":
			return b
	return null


func _find_opposing_command_core() -> Building:
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node
			if not b.is_destroyed and b.team != ai_team and (b.building_type_id == &"nexus_vat" or b.building_type_id == &"command_core"):
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
			if entry.get("kind", ProductionComponent.KIND_UNIT) != ProductionComponent.KIND_UNIT:
				continue
			var udata: UnitData = entry.get("data", null) as UnitData
			if udata != null and udata.unit_type_id == type_id:
				count += maxi(1, int(entry.get("batch_count", 1)))
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
