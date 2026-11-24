class_name SkirmishAICommander
extends Node

const MapLandmarkScript = preload("res://scripts/world/map_landmark.gd")

const CONDENSER_DATA_PATH: String = "res://resources/buildings/silica_condenser_data.tres"
const PYLON_DATA_PATH: String = "res://resources/buildings/synapse_pylon_data.tres"
const MAINFRAME_DATA_PATH: String = "res://resources/buildings/wetware_mainframe_data.tres"
const CLONING_VAT_DATA_PATH: String = "res://resources/buildings/cloning_vat_data.tres"
const FOUNDRY_DATA_PATH: String = "res://resources/buildings/calibration_foundry_data.tres"
const FABRICATOR_DATA_PATH: String = "res://resources/buildings/synthetics_fabricator_data.tres"

const WORKER_DATA_PATH: String = "res://resources/units/worker_unit_data.tres"
const HARVESTER_DATA_PATH: String = "res://resources/units/silica_harvester_data.tres"
const ENGINEER_DATA_PATH: String = "res://resources/units/engineer_data.tres"
const CLONE_TROOPER_DATA_PATH: String = "res://resources/units/clone_trooper_data.tres"
const STINGER_DATA_PATH: String = "res://resources/units/stinger_data.tres"
const SYMBIOTE_DATA_PATH: String = "res://resources/units/symbiote_data.tres"
const LANCE_RIG_DATA_PATH: String = "res://resources/units/lance_rig_data.tres"
const SIGNAL_JAMMER_DATA_PATH: String = "res://resources/units/signal_jammer_data.tres"
const GOLIATH_DATA_PATH: String = "res://resources/units/goliath_frame_data.tres"
const ARC_LANCER_DATA_PATH: String = "res://resources/units/arc_lancer_data.tres"
const MORTAR_DATA_PATH: String = "res://resources/units/chrysalis_mortar_data.tres"

const UPG_BATCH_EFFICIENCY_PATH: String = "res://resources/upgrades/batch_efficiency.tres"
const UPG_ADRENAL_POTENCY_PATH: String = "res://resources/upgrades/adrenal_potency.tres"
const UPG_COMPUTE_OVERDRIVE_PATH: String = "res://resources/upgrades/compute_overdrive.tres"

@export var ai_team: Unit.Team = Unit.Team.ENEMY
@export var enabled: bool = true
@export var decision_interval: float = 1.0
@export var target_worker_count: int = 6
@export var max_cloning_vats: int = 2
@export var max_bandwidth_cap: int = 56
@export var wave_squad_size: int = 6
@export var max_wave_interval: float = 48.0
@export var base_defense_radius: float = 440.0
@export var arena_bounds: Rect2 = Rect2(-1300.0, -950.0, 2600.0, 1900.0)

var _condenser_data: BuildingData = null
var _pylon_data: BuildingData = null
var _mainframe_data: BuildingData = null
var _cloning_vat_data: BuildingData = null
var _foundry_data: BuildingData = null
var _fabricator_data: BuildingData = null
var _worker_data: UnitData = null
var _harvester_data: UnitData = null
var _engineer_data: UnitData = null
var _clone_trooper_data: UnitData = null
var _stinger_data: UnitData = null
var _symbiote_data: UnitData = null
var _lance_rig_data: UnitData = null
var _signal_jammer_data: UnitData = null
var _goliath_data: UnitData = null
var _arc_lancer_data: UnitData = null
var _mortar_data: UnitData = null
var _upg_batch_efficiency: UpgradeData = null
var _upg_adrenal_potency: UpgradeData = null
var _upg_compute_overdrive: UpgradeData = null

var _decision_timer: float = 0.0
var _wave_timer: float = 0.0
var _wave_number: int = 0
var _vat_production_counter: int = 0
var _foundry_production_counter: int = 0
var _fab_production_counter: int = 0
var _ai_difficulty: int = 1
var _ai_playstyle: int = 0
var _dispatched_wave_units: Dictionary = {}
var _unit_last_pos: Dictionary = {}
var _unit_stall_ticks: Dictionary = {}


func _ready() -> void:
	add_to_group("skirmish_ai")
	_condenser_data = load(CONDENSER_DATA_PATH) as BuildingData
	_pylon_data = load(PYLON_DATA_PATH) as BuildingData
	_mainframe_data = load(MAINFRAME_DATA_PATH) as BuildingData
	_cloning_vat_data = load(CLONING_VAT_DATA_PATH) as BuildingData
	_foundry_data = load(FOUNDRY_DATA_PATH) as BuildingData
	_fabricator_data = load(FABRICATOR_DATA_PATH) as BuildingData
	_worker_data = load(WORKER_DATA_PATH) as UnitData
	_harvester_data = load(HARVESTER_DATA_PATH) as UnitData
	_engineer_data = load(ENGINEER_DATA_PATH) as UnitData
	_clone_trooper_data = load(CLONE_TROOPER_DATA_PATH) as UnitData
	_stinger_data = load(STINGER_DATA_PATH) as UnitData
	_symbiote_data = load(SYMBIOTE_DATA_PATH) as UnitData
	_lance_rig_data = load(LANCE_RIG_DATA_PATH) as UnitData
	_signal_jammer_data = load(SIGNAL_JAMMER_DATA_PATH) as UnitData
	_goliath_data = load(GOLIATH_DATA_PATH) as UnitData
	_arc_lancer_data = load(ARC_LANCER_DATA_PATH) as UnitData
	_mortar_data = load(MORTAR_DATA_PATH) as UnitData
	_upg_batch_efficiency = load(UPG_BATCH_EFFICIENCY_PATH) as UpgradeData
	_upg_adrenal_potency = load(UPG_ADRENAL_POTENCY_PATH) as UpgradeData
	_upg_compute_overdrive = load(UPG_COMPUTE_OVERDRIVE_PATH) as UpgradeData
	_apply_lobby_ai_profile()
	call_deferred("_setup_initial_rallies")


func _apply_lobby_ai_profile() -> void:
	if GameConfig == null:
		return
	_ai_difficulty = int(GameConfig.ai_difficulty)
	_ai_playstyle = int(GameConfig.ai_playstyle)

	match _ai_difficulty:
		int(GameConfig.AIDifficulty.RELAXED):
			decision_interval = 1.6
			target_worker_count = 4
			wave_squad_size = 4
			max_wave_interval = 64.0
			max_cloning_vats = 1
		int(GameConfig.AIDifficulty.BRUTAL):
			decision_interval = 0.7
			target_worker_count = 8
			wave_squad_size = 8
			max_wave_interval = 36.0
			max_cloning_vats = 3
		_:
			decision_interval = 1.0
			target_worker_count = 6
			wave_squad_size = 6
			max_wave_interval = 48.0
			max_cloning_vats = 2

	if _ai_playstyle == int(GameConfig.AIPlaystyle.SWARM_RUSH):
		wave_squad_size = maxi(4, wave_squad_size - 1)
		max_wave_interval *= 0.78
		max_cloning_vats = maxi(max_cloning_vats, 2)
	elif _ai_playstyle == int(GameConfig.AIPlaystyle.SYNTHETICS_TECH):
		max_wave_interval *= 1.12


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

	# 2. Recover any combat wave units that stalled behind obstacles & trigger active combat abilities.
	_recover_stalled_combat_units()
	_trigger_combat_abilities()

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
		if unit.command_state != Unit.CommandState.IDLE or not unit.command_queue.is_empty():
			continue
		if unit.is_carrying_cargo():
			if unit.command_return_cargo(core):
				continue
		var best_node: ResourceNode = _pick_least_crowded_resource(unit.global_position, biomass_nodes)
		if best_node != null:
			unit.command_gather(best_node)


func _assign_idle_harvesters() -> void:
	var silica_nodes: Array[ResourceNode] = []
	for b: Building in _get_team_buildings(ai_team):
		if b.building_type_id == &"silica_condenser" and b.is_constructed:
			for rn: ResourceNode in _get_resources_near(b.global_position, &"silica", 520.0):
				if not silica_nodes.has(rn):
					silica_nodes.append(rn)
	for unit: Unit in _get_team_units(ai_team):
		if unit.get_unit_type_id() != &"silica_harvester":
			continue
		if unit.command_state != Unit.CommandState.IDLE or not unit.command_queue.is_empty():
			continue
		if unit.is_carrying_cargo():
			if unit.command_return_cargo():
				continue
		var vein: ResourceNode = _pick_least_crowded_resource(unit.global_position, silica_nodes) if not silica_nodes.is_empty() else _find_nearest_resource(unit.global_position, &"silica")
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
		if not unit.can_staff_compute() or unit.command_state != Unit.CommandState.IDLE or not unit.command_queue.is_empty():
			continue
		for mf: Building in open_mainframes:
			if mf.can_accept_staff(unit):
				unit.command_staff_building(mf)
				break


func _resume_unfinished_buildings() -> void:
	for b: Building in _get_team_buildings(ai_team):
		if b.is_destroyed or b.is_constructed:
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
	var constructed_condensers: Array[Building] = []
	var constructed_condenser: Building = null
	var mainframes: Array[Building] = []
	var constructed_mainframes: Array[Building] = []
	var constructed_mainframe: Building = null
	var cloning_vats: Array[Building] = []
	var constructed_vats: Array[Building] = []
	var foundries: Array[Building] = []
	var constructed_foundries: Array[Building] = []
	var fabricators: Array[Building] = []
	var constructed_fabricators: Array[Building] = []
	var unfinished_pylons: int = 0
	var staffed_engineers: int = 0
	var total_mainframe_slots: int = 0

	for b: Building in buildings:
		if b.building_type_id == &"silica_condenser":
			condensers.append(b)
			if b.is_constructed:
				constructed_condensers.append(b)
				constructed_condenser = b
		elif b.building_type_id == &"wetware_mainframe":
			mainframes.append(b)
			if b.is_constructed:
				constructed_mainframes.append(b)
				constructed_mainframe = b
				staffed_engineers += b.get_assigned_engineer_count()
				total_mainframe_slots += b.max_staff_slots
		elif b.building_type_id == &"cloning_vat":
			cloning_vats.append(b)
			if b.is_constructed:
				constructed_vats.append(b)
		elif b.building_type_id == &"calibration_foundry":
			foundries.append(b)
			if b.is_constructed:
				constructed_foundries.append(b)
		elif b.building_type_id == &"synthetics_fabricator":
			fabricators.append(b)
			if b.is_constructed:
				constructed_fabricators.append(b)
		elif b.building_type_id == &"synapse_pylon" and not b.is_constructed:
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

	var is_swarm_rush: bool = (_ai_playstyle == int(GameConfig.AIPlaystyle.SWARM_RUSH)) if GameConfig != null else false
	var is_synth_tech: bool = (_ai_playstyle == int(GameConfig.AIPlaystyle.SYNTHETICS_TECH)) if GameConfig != null else false
	var is_brutal: bool = (_ai_difficulty == int(GameConfig.AIDifficulty.BRUTAL)) if GameConfig != null else false

	# Priority 1: Ensure baseline worker core (3 early on Swarm Rush, 4 baseline).
	var early_workers: int = 3 if is_swarm_rush else 4
	if total_workers < early_workers:
		if _worker_data != null and core.get_training_queue_size() < 2 and core.can_train_unit_data(_worker_data):
			core.queue_unit_data(_worker_data)
		return

	# Swarm Rush builds its first Cloning Vat before the Silica Condenser for rapid infantry pressure.
	if is_swarm_rush and cloning_vats.is_empty() and _cloning_vat_data != null:
		if econ.can_afford(ai_team, _cloning_vat_data.get_cost_dict()):
			var to_c_rush: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var rush_vat: Building = _try_place_and_build(_cloning_vat_data, core.global_position + to_c_rush * 175.0, core.global_position)
			if rush_vat != null:
				rush_vat.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.36))
			return
		if biomass < _cloning_vat_data.biomass_cost:
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

	# Priority 4: Train automated Silica Harvesters once Condensers are online (scales with expansion).
	var desired_harvesters: int = 3 if (constructed_condensers.size() >= 2 or is_brutal) else (2 if constructed_vats.size() >= 1 else 1)
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

	# Priority 7: Wetware Mainframes on natural & contested expansion Compute Vents + Engineers.
	var exp_vent_biomass: int = 160 if (is_synth_tech or is_brutal) else 220
	if (not constructed_vats.is_empty() or is_synth_tech) and _mainframe_data != null:
		if mainframes.is_empty():
			var vent: ResourceNode = _find_nearest_unoccupied_vent(core.global_position, 580.0)
			if vent != null and econ.can_afford(ai_team, _mainframe_data.get_cost_dict()):
				_try_place_and_build_on_vent(_mainframe_data, vent)
		elif mainframes.size() == 1 and constructed_mainframes.size() >= 1 and staffed_engineers >= 1 and biomass >= exp_vent_biomass:
			var exp_vent: ResourceNode = _find_nearest_unoccupied_vent(core.global_position, 1650.0)
			if exp_vent != null and econ.can_afford(ai_team, _mainframe_data.get_cost_dict()):
				_try_place_and_build_on_vent(_mainframe_data, exp_vent)

	var desired_engineers: int = mini(4, total_mainframe_slots)
	if constructed_mainframe != null and _engineer_data != null and total_engineers < desired_engineers:
		if core.get_training_queue_size() < 2 and core.can_train_unit_data(_engineer_data):
			core.queue_unit_data(_engineer_data)

	# Priority 7.5: Expand Silica economy to NW/SE expansion cluster once Tier-1 is established.
	var exp_cond_biomass: int = 180 if is_brutal else 240
	if condensers.size() < 2 and not constructed_condensers.is_empty() and not constructed_vats.is_empty() and biomass >= exp_cond_biomass and _condenser_data != null:
		if econ.can_afford(ai_team, _condenser_data.get_cost_dict()):
			var exp_vein: ResourceNode = _find_expansion_silica_vein(core.global_position, condensers)
			if exp_vein != null:
				var exp_anchor: Vector2 = exp_vein.global_position.lerp(core.global_position, 0.16)
				_try_place_and_build(_condenser_data, exp_anchor, exp_vein.global_position)

	# Priority 8: Mid-game Upgrades at Cloning Vat (Batch Efficiency -> Adrenal Potency).
	if not constructed_vats.is_empty():
		var primary_vat: Building = constructed_vats[0]
		if primary_vat.production_component != null and primary_vat.get_training_queue_size() < 2:
			if _upg_batch_efficiency != null and primary_vat.production_component.can_queue_upgrade(primary_vat, _upg_batch_efficiency):
				primary_vat.production_component.enqueue_upgrade(primary_vat, _upg_batch_efficiency)
			elif _upg_adrenal_potency != null and econ.has_upgrade(ai_team, UpgradeManager.UPGRADE_BATCH_EFFICIENCY) and primary_vat.production_component.can_queue_upgrade(primary_vat, _upg_adrenal_potency):
				primary_vat.production_component.enqueue_upgrade(primary_vat, _upg_adrenal_potency)

	# Priority 9: Late-game Tier-2 Synthetics Fabricator (prioritized ahead of Foundry for Synthetics Tech).
	if fabricators.is_empty() and not constructed_vats.is_empty() and _fabricator_data != null and compute >= _fabricator_data.compute_cost:
		if econ.can_afford(ai_team, _fabricator_data.get_cost_dict()):
			var to_center_f: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_f: Vector2 = Vector2(-to_center_f.y, to_center_f.x)
			var fab_anchor: Vector2 = core.global_position + to_center_f * 165.0 - perp_f * 145.0
			var built_fab: Building = _try_place_and_build(_fabricator_data, fab_anchor, core.global_position)
			if built_fab != null:
				built_fab.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))

	# Priority 10: Mid-game Calibration Foundry for Lance-Rigs & Signal Jammers.
	var allow_foundry: bool = (not is_synth_tech or not fabricators.is_empty())
	if allow_foundry and foundries.is_empty() and constructed_mainframe != null and _foundry_data != null and silica >= _foundry_data.silica_cost:
		if econ.can_afford(ai_team, _foundry_data.get_cost_dict()):
			var to_center_cf: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp_cf: Vector2 = Vector2(-to_center_cf.y, to_center_cf.x)
			var cf_anchor: Vector2 = core.global_position + to_center_cf * 160.0 + perp_cf * 145.0
			var built_cf: Building = _try_place_and_build(_foundry_data, cf_anchor, core.global_position)
			if built_cf != null:
				built_cf.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))

	# Priority 11: Late-game Compute Overdrive upgrade & Synthetics Fabricator heavy mix (Goliath / Arc-Lancer / Mortar).
	for fab: Building in constructed_fabricators:
		if not fab.has_rally():
			fab.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))
		if fab.get_training_queue_size() >= 2:
			continue
		if _upg_compute_overdrive != null and fab.production_component != null and fab.production_component.can_queue_upgrade(fab, _upg_compute_overdrive):
			fab.production_component.enqueue_upgrade(fab, _upg_compute_overdrive)
			continue
		var fab_roll: int = _fab_production_counter % 3
		var heavy_choice: UnitData = _goliath_data
		if fab_roll == 1 and _arc_lancer_data != null:
			heavy_choice = _arc_lancer_data
		elif fab_roll == 2 and _mortar_data != null:
			heavy_choice = _mortar_data
		if heavy_choice != null and fab.can_train_unit_data(heavy_choice):
			fab.queue_unit_data(heavy_choice)
			_fab_production_counter += 1
		elif _goliath_data != null and fab.can_train_unit_data(_goliath_data):
			fab.queue_unit_data(_goliath_data)
			_fab_production_counter += 1

	# Priority 12: Calibration Foundry production (Lance-Rigs & Signal Jammers).
	for foundry: Building in constructed_foundries:
		if not foundry.has_rally():
			foundry.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))
		if foundry.get_training_queue_size() >= 2:
			continue
		var want_jammer: bool = (_foundry_production_counter % 3 == 2) and _signal_jammer_data != null and foundry.can_train_unit_data(_signal_jammer_data)
		var foundry_choice: UnitData = _signal_jammer_data if want_jammer else _lance_rig_data
		if foundry_choice != null and foundry.can_train_unit_data(foundry_choice):
			foundry.queue_unit_data(foundry_choice)
			_foundry_production_counter += 1

	# Priority 13: Batch-clone GENESIS_V2 core swarm (weighted by AI playstyle).
	var hold_for_fab: bool = is_synth_tech and fabricators.is_empty() and constructed_mainframe != null and compute >= 15
	if not hold_for_fab:
		for vat: Building in constructed_vats:
			if not vat.has_rally():
				vat.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))
			if vat.get_training_queue_size() >= 2:
				continue
			var slot: int = _vat_production_counter % 10
			var chosen: UnitData = _clone_trooper_data
			if is_swarm_rush:
				if slot == 9 and _symbiote_data != null and vat.can_train_unit_data(_symbiote_data):
					chosen = _symbiote_data
				elif (slot == 1 or slot == 4 or slot == 7) and _stinger_data != null and vat.can_train_unit_data(_stinger_data):
					chosen = _stinger_data
			else:
				if slot == 9 and _symbiote_data != null and vat.can_train_unit_data(_symbiote_data):
					chosen = _symbiote_data
				elif (slot == 2 or slot == 6) and _stinger_data != null and vat.can_train_unit_data(_stinger_data):
					chosen = _stinger_data
			if chosen != null and vat.can_train_unit_data(chosen):
				vat.queue_unit_data(chosen)
				_vat_production_counter += 1

	# Priority 14: Additional Cloning Vat when floating surplus Biomass (earlier for Swarm Rush).
	var extra_vat_biomass: int = 200 if is_swarm_rush else (230 if is_brutal else 280)
	var extra_vat_silica: int = 40 if is_swarm_rush else 60
	if _cloning_vat_data != null and cloning_vats.size() < max_cloning_vats and biomass >= extra_vat_biomass and silica >= extra_vat_silica:
		if econ.can_afford(ai_team, _cloning_vat_data.get_cost_dict()):
			var to_center2: Vector2 = (Vector2.ZERO - core.global_position).normalized()
			var perp: Vector2 = Vector2(-to_center2.y, to_center2.x)
			var vat_anchor2: Vector2 = core.global_position + to_center2 * 180.0 + perp * 130.0
			var second_vat: Building = _try_place_and_build(_cloning_vat_data, vat_anchor2, core.global_position)
			if second_vat != null:
				second_vat.set_rally_position(core.global_position.lerp(Vector2.ZERO, 0.34))


func _trigger_combat_abilities() -> void:
	for u: Unit in _get_team_units(ai_team):
		if u.data == null or u.data.abilities.is_empty() or u.current_target == null or not is_instance_valid(u.current_target):
			continue
		var dist: float = u.global_position.distance_to(u.current_target.global_position)
		for ab: AbilityData in u.data.abilities:
			if ab == null or ab.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
				continue
			if not u.is_ability_ready(ab):
				continue
			if ab.ability_id == &"adrenal_surge" and dist <= u.data.attack_range + 45.0:
				u.command_cast_ability(ab, u.global_position, u)
				break
			elif (ab.ability_id == &"static_pulse" or ab.ability_id == &"seismic_slam") and dist <= maxf(80.0, ab.aoe_radius * 0.92):
				u.command_cast_ability(ab, u.global_position, u)
				break
			elif ab.ability_id == &"spore_barrage" and dist <= ab.cast_range and dist >= 100.0:
				u.command_cast_ability(ab, u.current_target.global_position)
				break


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

	# Alternate direct Hyper-Uplink Plaza / base pushes with North Conduit & South Relay Trench flanks.
	var use_flank: bool = (_wave_number >= 2 and (_wave_number % 2) == 0)
	var flank_wp: Vector2 = Vector2.ZERO
	if use_flank:
		var north_lane: bool = ((_wave_number / 2) % 2) == 1
		flank_wp = _get_flank_corridor_waypoint(north_lane)

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
	for node: Node in get_tree().get_nodes_in_group("map_landmarks"):
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


func _find_expansion_silica_vein(core_pos: Vector2, existing_condensers: Array[Building]) -> ResourceNode:
	var best: ResourceNode = null
	var best_d_sq: float = INF
	var min_sep_sq: float = 420.0 * 420.0
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node
		if rn.is_depleted() or rn.is_vent or rn.resource_type != &"silica":
			continue
		var too_close: bool = false
		for cond: Building in existing_condensers:
			if is_instance_valid(cond) and cond.global_position.distance_squared_to(rn.global_position) < min_sep_sq:
				too_close = true
				break
		if too_close:
			continue
		var d_sq: float = core_pos.distance_squared_to(rn.global_position)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best = rn
	return best


func _get_flank_corridor_waypoint(north_lane: bool) -> Vector2:
	var best_pos: Vector2 = Vector2(-80.0, -810.0) if north_lane else Vector2(80.0, 810.0)
	for node: Node in get_tree().get_nodes_in_group("map_landmarks"):
		if not (node is MapLandmarkScript) or not is_instance_valid(node):
			continue
		var lm: MapLandmarkScript = node
		if lm.visual_style != MapLandmarkScript.VisualStyle.RELAY_ARCH:
			continue
		if north_lane and lm.global_position.y < -200.0:
			return lm.global_position
		if not north_lane and lm.global_position.y > 200.0:
			return lm.global_position
	return best_pos


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
		# Never interrupt a worker mid-way through a queued command chain.
		if not u.command_queue.is_empty():
			continue
		var d_sq: float = u.global_position.distance_squared_to(near_pos)
		if u.command_state == Unit.CommandState.IDLE:
			if d_sq < best_idle_d_sq:
				best_idle_d_sq = d_sq
				best_idle = u
		elif u.command_state == Unit.CommandState.GATHERING:
			# Do not pull workers currently hauling cargo back to base.
			if u.gather_component != null and u.gather_component.state == GatherComponent.GatherState.GATHER_RETURNING_TO_BASE and u.is_carrying_cargo():
				continue
			if d_sq < best_gather_d_sq:
				best_gather_d_sq = d_sq
				best_gathering = u

	return best_idle if best_idle != null else best_gathering


func _has_worker_building(target_b: Building) -> bool:
	for u: Unit in _get_team_units(ai_team):
		if u.command_state == Unit.CommandState.CONSTRUCTING and u._construction_target == target_b:
			return true
		for queued_cmd: Dictionary in u.command_queue:
			if queued_cmd.get("type", &"") == &"build" and queued_cmd.get("target", null) == target_b:
				return true
	return false


func _find_ai_command_core() -> Building:
	for b: Building in _get_team_buildings(ai_team):
		if b.is_core_hub or b.building_type_id == &"nexus_vat":
			return b
	return null


func _find_opposing_command_core() -> Building:
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			var b: Building = node
			if not b.is_destroyed and b.team != ai_team and (b.is_core_hub or b.building_type_id == &"nexus_vat"):
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
	CommandRouter.nudge_units_out_of_building(building, arena_bounds)


func _get_economy_manager() -> EconomyManager:
	return get_tree().get_first_node_in_group("economy_manager") as EconomyManager


func _get_command_router() -> CommandRouter:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("SelectionController/CommandRouter") as CommandRouter
