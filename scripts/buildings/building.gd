class_name Building
extends StaticBody2D

const PRODUCTION_COMPONENT_SCRIPT: GDScript = preload("res://scripts/buildings/production_component.gd")
const ENEMY_TROOPER_DATA_PATH: String = "res://resources/units/enemy_trooper_data.tres"
const HEALTH_BAR_WIDTH: float = 76.0
const CONSTRUCT_BAR_WIDTH: float = 68.0
const DEPOSIT_PULSE_DURATION: float = 0.25
const HIT_FLASH_DURATION: float = 0.08

signal selection_changed(building: Building, selected: bool)
signal health_changed(building: Building, current_hp: float, max_hp: float)
signal status_changed(building: Building)
signal destroyed(building: Building)
signal construction_progress_changed(building: Building, progress: float, is_constructed: bool)
signal construction_completed(building: Building)
signal staffing_changed(building: Building, assigned_count: int, max_slots: int)
signal training_changed(building: Building)
signal rally_changed(building: Building)

@export var team: Unit.Team = Unit.Team.PLAYER
@export var building_type_id: StringName = &"command_core"
@export var display_name: String = "Command Core"
@export var max_hp: float = 1500.0
@export var vision_range: float = 450.0
@export var footprint_radius: float = 46.0
@export var selection_radius: float = 54.0
@export var is_resource_dropoff: bool = true
@export var accepted_resources: Array[StringName] = [&"biomass"]
@export var bandwidth_provided: int = 10
@export var always_show_health_bar: bool = false
@export var build_time: float = 4.0
@export var is_constructed: bool = true
@export var max_staff_slots: int = 0
@export var compute_tick_interval: float = 3.0
@export var compute_per_engineer: int = 5
@export var can_set_rally: bool = true
@export var batch_production_count: int = 1
@export var base_batch_cost_multiplier: float = 1.0
@export var trainable_unit_data: Array[UnitData] = []
@export var trainable_unit_scenes: Array[PackedScene] = []
@export var researchable_upgrades: Array[UpgradeData] = []

@onready var selection_ring: Node2D = get_node_or_null("SelectionRing") as Node2D
@onready var body_visual: Node2D = get_node_or_null("BodyVisual") as Node2D
@onready var core_glow: Polygon2D = get_node_or_null("BodyVisual/CoreGlow") as Polygon2D
@onready var health_bar_root: Node2D = get_node_or_null("HealthBar") as Node2D
@onready var health_bar_fill: ColorRect = get_node_or_null("HealthBar/Fill") as ColorRect
@onready var construct_bar_root: Node2D = get_node_or_null("ConstructBar") as Node2D
@onready var construct_bar_fill: ColorRect = get_node_or_null("ConstructBar/Fill") as ColorRect
@onready var staff_slots_root: Node2D = get_node_or_null("StaffSlots") as Node2D

var current_hp: float = 1500.0
var is_selected: bool = false
var is_destroyed: bool = false
var has_been_spotted: bool = false
var construction_progress: float = 1.0
var claimed_vent: ResourceNode = null
var assigned_engineers: Array[Unit] = []
var production_component: ProductionComponent = null

var _has_rally: bool = false
var _rally_position: Vector2 = Vector2.ZERO
var _rally_target: Node2D = null
var _construction_elapsed: float = 0.0
var _deposit_pulse_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _base_core_color: Color = Color(0.22, 0.94, 0.88, 1.0)
var _compute_tick_timer: float = 0.0


func _ready() -> void:
	add_to_group("buildings")
	add_to_group("selectable_buildings")
	if is_constructed:
		current_hp = max_hp
		construction_progress = 1.0
		_construction_elapsed = build_time
	else:
		current_hp = maxf(1.0, max_hp * 0.10)
		construction_progress = 0.0
		_construction_elapsed = 0.0
	if team == Unit.Team.ENEMY and building_type_id == &"bio_lab":
		_apply_enemy_bio_lab_roster()
	_apply_team_visuals()
	if core_glow != null:
		_base_core_color = core_glow.color
	if selection_ring != null:
		selection_ring.visible = is_selected

	production_component = get_node_or_null("ProductionComponent") as ProductionComponent
	if production_component == null and (not trainable_unit_data.is_empty() or not researchable_upgrades.is_empty()):
		production_component = PRODUCTION_COMPONENT_SCRIPT.new()
		production_component.name = "ProductionComponent"
		add_child(production_component)
	if production_component != null:
		production_component.queue_changed.connect(func(_q: Array[Dictionary], _p: float, _d: float) -> void:
			training_changed.emit(self)
			status_changed.emit(self)
		)

	_update_construction_visuals()
	_update_health_bar()
	_update_staff_slot_visuals()
	if is_constructed:
		_register_with_economy()
		var econ_ready: EconomyManager = _get_economy_manager()
		if econ_ready != null:
			econ_ready.notify_building_tech_changed(team)
	add_to_group("nav_bake_obstacles")
	_request_navmesh_rebake()


func _exit_tree() -> void:
	if is_in_group("nav_bake_obstacles"):
		remove_from_group("nav_bake_obstacles")
	if production_component != null:
		production_component.cancel_all_and_refund(self)
	if claimed_vent != null and is_instance_valid(claimed_vent):
		claimed_vent.release_building(self)
	_unregister_from_economy()
	_request_navmesh_rebake()


func _process(delta: float) -> void:
	if is_destroyed:
		return

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		if _hit_flash_timer <= 0.0:
			_update_construction_visuals()

	if _deposit_pulse_timer > 0.0:
		_deposit_pulse_timer = maxf(0.0, _deposit_pulse_timer - delta)
		var t: float = _deposit_pulse_timer / DEPOSIT_PULSE_DURATION
		if core_glow != null:
			core_glow.color = _base_core_color.lerp(Color(0.55, 1.0, 0.78, 1.0), t)
		if _deposit_pulse_timer <= 0.0 and core_glow != null:
			core_glow.color = _base_core_color

	if not is_constructed:
		return

	if max_staff_slots > 0 and not assigned_engineers.is_empty():
		_tick_compute_generation(delta)

	if production_component != null:
		production_component.tick(self, delta)

	if is_selected and has_rally() and not _has_rally_overlay():
		queue_redraw()


func _draw() -> void:
	if not is_selected or not has_rally() or _has_rally_overlay():
		return
	var target_world: Vector2 = get_rally_world_position()
	var target_local: Vector2 = to_local(target_world)
	var is_smart: bool = (_rally_target != null and is_instance_valid(_rally_target))
	var rally_col: Color = Color(0.28, 1.0, 0.62, 0.88) if is_smart else Color(0.24, 0.92, 0.96, 0.85)
	draw_line(Vector2.ZERO, target_local, rally_col, 1.8, true)
	draw_arc(target_local, 10.0, 0.0, TAU, 20, rally_col, 2.0, true)
	# Crisp rally flag triangle
	var flag_pts: PackedVector2Array = PackedVector2Array([
		target_local + Vector2(0.0, -2.0),
		target_local + Vector2(0.0, -22.0),
		target_local + Vector2(14.0, -15.0),
		target_local + Vector2(0.0, -9.0),
	])
	draw_colored_polygon(flag_pts, rally_col)


func begin_construction(data: BuildingData, target_team: Unit.Team, vent: ResourceNode = null) -> void:
	team = target_team
	if data != null:
		building_type_id = data.building_id
		display_name = data.display_name
		max_hp = data.max_hp
		vision_range = data.vision_range
		build_time = data.build_time
		bandwidth_provided = data.bandwidth_provided
		is_resource_dropoff = data.is_dropoff
		accepted_resources = data.accepted_resources.duplicate()
		max_staff_slots = data.max_staff_slots
		can_set_rally = data.can_set_rally
		batch_production_count = maxi(1, data.batch_production_count)
		base_batch_cost_multiplier = maxf(1.0, data.base_batch_cost_multiplier)
		var resolved_units: Array[UnitData] = data.resolve_trainable_units()
		if not resolved_units.is_empty():
			trainable_unit_data = resolved_units
			trainable_unit_scenes = []
		if not data.researchable_upgrades.is_empty():
			researchable_upgrades = data.researchable_upgrades.duplicate()

	if team == Unit.Team.ENEMY and building_type_id == &"bio_lab":
		_apply_enemy_bio_lab_roster()
	_apply_team_visuals()

	if production_component == null and (not trainable_unit_data.is_empty() or not researchable_upgrades.is_empty()):
		production_component = PRODUCTION_COMPONENT_SCRIPT.new()
		production_component.name = "ProductionComponent"
		add_child(production_component)
		production_component.queue_changed.connect(func(_q: Array[Dictionary], _p: float, _d: float) -> void:
			training_changed.emit(self)
			status_changed.emit(self)
		)

	claimed_vent = vent
	if claimed_vent != null and is_instance_valid(claimed_vent):
		claimed_vent.claim_by_building(self)

	is_constructed = false
	_construction_elapsed = 0.0
	construction_progress = 0.0
	current_hp = maxf(1.0, max_hp * 0.10)
	_update_construction_visuals()
	_update_health_bar()
	_update_staff_slot_visuals()
	add_to_group("nav_bake_obstacles")
	_request_navmesh_rebake()

	if build_time <= 0.0:
		_complete_construction()


func advance_construction(delta: float) -> bool:
	if is_destroyed or is_constructed:
		return true
	var total_time: float = maxf(0.1, build_time)
	_construction_elapsed = minf(total_time, _construction_elapsed + delta)
	construction_progress = clampf(_construction_elapsed / total_time, 0.0, 1.0)
	var hp_gain: float = (max_hp * 0.90) * (delta / total_time)
	current_hp = minf(max_hp, current_hp + hp_gain)
	_update_construction_visuals()
	_update_health_bar()
	health_changed.emit(self, current_hp, max_hp)
	construction_progress_changed.emit(self, construction_progress, false)
	status_changed.emit(self)

	if _construction_elapsed >= total_time:
		_complete_construction()
		return true
	return false


func _complete_construction() -> void:
	if is_constructed:
		return
	is_constructed = true
	_construction_elapsed = build_time
	construction_progress = 1.0
	current_hp = max_hp
	_update_construction_visuals()
	_update_health_bar()
	_update_staff_slot_visuals()
	pulse_deposit_feedback()
	_register_with_economy()
	var econ_done: EconomyManager = _get_economy_manager()
	if econ_done != null:
		econ_done.notify_building_tech_changed(team)
	health_changed.emit(self, current_hp, max_hp)
	construction_progress_changed.emit(self, 1.0, true)
	construction_completed.emit(self)
	status_changed.emit(self)


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	if is_node_ready():
		if selection_ring != null:
			selection_ring.visible = is_selected
		_update_health_bar()
		queue_redraw()
	selection_changed.emit(self, is_selected)


func set_rally_position(world_pos: Vector2) -> void:
	if not can_set_rally:
		return
	_has_rally = true
	_rally_position = world_pos
	_rally_target = null
	queue_redraw()
	rally_changed.emit(self)
	status_changed.emit(self)


func set_rally_target(target: Node2D) -> void:
	if not can_set_rally or target == null or not is_instance_valid(target):
		return
	_has_rally = true
	_rally_target = target
	_rally_position = target.global_position
	queue_redraw()
	rally_changed.emit(self)
	status_changed.emit(self)


func has_rally() -> bool:
	if _rally_target != null and not is_instance_valid(_rally_target):
		_rally_target = null
	return _has_rally


func get_rally_world_position() -> Vector2:
	if _rally_target != null and is_instance_valid(_rally_target):
		return _rally_target.global_position
	return _rally_position


func get_rally_target() -> Node2D:
	if _rally_target != null and is_instance_valid(_rally_target):
		return _rally_target
	return null


func _has_rally_overlay() -> bool:
	return is_inside_tree() and get_tree().get_first_node_in_group("rally_point_overlay") != null


func apply_rally_to_unit(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit) or unit.is_dead:
		return
	if not has_rally():
		return

	if _rally_target != null and is_instance_valid(_rally_target):
		if _rally_target is ResourceNode:
			var res_node: ResourceNode = _rally_target
			if not res_node.is_depleted() and unit.can_gather_resource(res_node.resource_type):
				unit.command_gather(res_node)
				return
		elif _rally_target is Building:
			var target_b: Building = _rally_target
			if not target_b.is_destroyed and target_b.max_staff_slots > 0 and unit.can_staff_compute():
				if unit.command_staff_building(target_b):
					return

	unit.command_move(get_rally_world_position())


func contains_point(world_point: Vector2) -> bool:
	if is_destroyed:
		return false
	return global_position.distance_squared_to(world_point) <= selection_radius * selection_radius


func accepts_resource(resource_type: StringName) -> bool:
	if is_destroyed or not is_constructed or not is_resource_dropoff:
		return false
	return accepted_resources.has(resource_type)


func can_accept_staff(unit: Unit) -> bool:
	if is_destroyed or not is_constructed or max_staff_slots <= 0:
		return false
	if unit == null or not is_instance_valid(unit) or unit.is_dead or unit.team != team:
		return false
	if not unit.can_staff_compute():
		return false
	_prune_assigned_engineers()
	if assigned_engineers.has(unit):
		return false
	return assigned_engineers.size() < max_staff_slots


func assign_engineer(engineer: Unit) -> bool:
	if not can_accept_staff(engineer):
		return false
	assigned_engineers.append(engineer)
	engineer.enter_staffed_building(self)
	_update_staff_slot_visuals()
	pulse_deposit_feedback()
	staffing_changed.emit(self, assigned_engineers.size(), max_staff_slots)
	status_changed.emit(self)
	return true


func eject_engineers() -> Array[Unit]:
	_prune_assigned_engineers()
	var released: Array[Unit] = []
	var count: int = assigned_engineers.size()
	if count == 0:
		return released
	var eject_radius: float = footprint_radius + 24.0
	for i: int in range(count):
		var eng: Unit = assigned_engineers[i]
		if not is_instance_valid(eng) or eng.is_dead:
			continue
		var angle: float = (TAU * float(i) / float(maxi(1, count))) + 0.4
		var exit_pos: Vector2 = global_position + Vector2.RIGHT.rotated(angle) * eject_radius
		eng.exit_staffed_building(exit_pos)
		released.append(eng)
	assigned_engineers.clear()
	_compute_tick_timer = 0.0
	_update_staff_slot_visuals()
	staffing_changed.emit(self, 0, max_staff_slots)
	status_changed.emit(self)
	return released


func get_assigned_engineer_count() -> int:
	_prune_assigned_engineers()
	return assigned_engineers.size()


func can_train_unit(slot_index: int) -> bool:
	if production_component == null or slot_index < 0 or slot_index >= trainable_unit_data.size():
		return false
	var scene_override: PackedScene = trainable_unit_scenes[slot_index] if slot_index < trainable_unit_scenes.size() else null
	return production_component.can_queue_unit(self, trainable_unit_data[slot_index], scene_override)


func queue_unit_training(slot_index: int) -> bool:
	if production_component == null or slot_index < 0 or slot_index >= trainable_unit_data.size():
		return false
	var scene_override: PackedScene = trainable_unit_scenes[slot_index] if slot_index < trainable_unit_scenes.size() else null
	return production_component.enqueue_unit(self, trainable_unit_data[slot_index], scene_override)


func can_train_unit_data(unit_data: UnitData, scene_override: PackedScene = null) -> bool:
	if production_component == null or unit_data == null:
		return false
	return production_component.can_queue_unit(self, unit_data, scene_override)


func queue_unit_data(unit_data: UnitData, scene_override: PackedScene = null) -> bool:
	if production_component == null or unit_data == null:
		return false
	return production_component.enqueue_unit(self, unit_data, scene_override)


func can_research_upgrade(upgrade_index: int) -> bool:
	if production_component == null or upgrade_index < 0 or upgrade_index >= researchable_upgrades.size():
		return false
	return production_component.can_queue_upgrade(self, researchable_upgrades[upgrade_index])


func queue_upgrade_research(upgrade_index: int) -> bool:
	if production_component == null or upgrade_index < 0 or upgrade_index >= researchable_upgrades.size():
		return false
	return production_component.enqueue_upgrade(self, researchable_upgrades[upgrade_index])


func get_unit_batch_info(unit_data: UnitData) -> Dictionary:
	if production_component != null:
		return production_component.get_effective_unit_batch_info(self, unit_data)
	return {
		"batch_count": maxi(1, batch_production_count),
		"cost_multiplier": 1.0,
		"costs": unit_data.get_cost_dict() if unit_data != null else {},
		"cost_label": unit_data.get_cost_label() if unit_data != null else "Free",
		"bandwidth_cost": (unit_data.bandwidth_cost if unit_data != null else 0) * maxi(1, batch_production_count),
		"duration": unit_data.train_time if unit_data != null else 1.0,
	}


func get_vision_range() -> float:
	if not is_constructed:
		return maxf(120.0, vision_range * 0.55)
	return maxf(120.0, vision_range)


func cancel_queued_unit(queue_index: int) -> bool:
	if production_component == null:
		return false
	return production_component.cancel_queue_item(self, queue_index)


func get_training_queue_size() -> int:
	return production_component.get_queue_size() if production_component != null else 0


func get_active_training_status() -> Dictionary:
	return production_component.get_active_training_status() if production_component != null else {}


func pulse_deposit_feedback() -> void:
	_deposit_pulse_timer = DEPOSIT_PULSE_DURATION


func take_damage(amount: float) -> void:
	if is_destroyed or amount <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_hit_flash_timer = HIT_FLASH_DURATION
	if is_node_ready() and body_visual != null:
		body_visual.modulate = Color(1.9, 2.2, 2.3, 1.0)
	_update_health_bar()
	health_changed.emit(self, current_hp, max_hp)
	status_changed.emit(self)
	if current_hp <= 0.0:
		_destroy()


func get_inspection_data() -> Dictionary:
	var accent: Color = Color(0.22, 0.88, 0.94, 1.0)
	if building_type_id == &"silica_refinery" or building_type_id == &"silica_condenser":
		accent = Color(0.98, 0.78, 0.28, 1.0)
	elif building_type_id == &"compute_node" or building_type_id == &"wetware_mainframe":
		accent = Color(0.32, 0.84, 1.0, 1.0)
	elif building_type_id == &"bandwidth_relay" or building_type_id == &"synapse_pylon":
		accent = Color(0.76, 0.58, 1.0, 1.0)
	elif building_type_id == &"bio_lab" or building_type_id == &"cloning_vat":
		accent = Color(0.24, 0.94, 0.72, 1.0)
	elif building_type_id == &"calibration_foundry":
		accent = Color(0.96, 0.64, 0.26, 1.0)
	elif building_type_id == &"synthetics_fabricator":
		accent = Color(0.36, 0.96, 1.0, 1.0)
	elif team == Unit.Team.ENEMY:
		accent = Color(1.0, 0.36, 0.26, 1.0)

	var affil: StringName = &"player" if team == Unit.Team.PLAYER else &"enemy"
	var stats: Array[Dictionary] = []

	if not is_constructed:
		var pct: int = int(round(construction_progress * 100.0))
		stats.append({"label": "Construction", "value": "%d%% Complete" % pct})
		stats.append({"label": "Builder", "value": "Worker Active" if _has_active_builder() else "Awaiting Worker"})
		stats.append({"label": "Build Time", "value": "%.1fs Total" % build_time})
		stats.append({"label": "Hull", "value": "%d / %d" % [int(round(current_hp)), int(round(max_hp))]})
		return {
			"title": display_name,
			"subtitle": "UNDER CONSTRUCTION",
			"affiliation": affil,
			"accent_color": accent,
			"ring_color": accent,
			"show_hp_bar": true,
			"hp_current": current_hp,
			"hp_max": max_hp,
			"show_primary_bar": true,
			"primary_bar_label": "Building: %d%% — Under Construction" % pct,
			"primary_bar_value": construction_progress * 100.0,
			"primary_bar_max": 100.0,
			"primary_bar_color": Color(0.32, 0.96, 1.0, 1.0),
			"stats": stats,
			"is_commandable": false,
			"readonly_label": "CONSTRUCTION IN PROGRESS",
		}

	var econ: EconomyManager = _get_economy_manager()
	var show_primary: bool = false
	var primary_label: String = ""
	var primary_val: float = 0.0
	var primary_max: float = 1.0
	var primary_col: Color = accent
	var subtitle: String = "FRIENDLY STRUCTURE" if team == Unit.Team.PLAYER else "HOSTILE STRUCTURE"
	var has_commands: bool = (team == Unit.Team.PLAYER) and (max_staff_slots > 0 or not trainable_unit_data.is_empty() or not researchable_upgrades.is_empty())

	if max_staff_slots > 0:
		subtitle = "COMPUTE FACILITY"
		var staffed: int = get_assigned_engineer_count()
		var rate: int = staffed * compute_per_engineer
		show_primary = true
		primary_label = "Engineers: %d / %d Staffed" % [staffed, max_staff_slots]
		primary_val = float(staffed)
		primary_max = float(maxi(1, max_staff_slots))
		primary_col = Color(0.32, 0.88, 1.0, 1.0)
		var rate_str: String = "+%d / %.1fs" % [rate, compute_tick_interval] if staffed > 0 else "0 / %.1fs (Assign Eng)" % compute_tick_interval
		stats.append({"label": "Compute Rate", "value": rate_str})
		stats.append({"label": "Vent Status", "value": "Active Thermal Vent"})
		stats.append({"label": "Staff Slots", "value": "%d / %d Engineers" % [staffed, max_staff_slots]})
		stats.append({"label": "Construction", "value": "Operational"})
	elif building_type_id == &"nexus_vat" or building_type_id == &"command_core":
		subtitle = "GENESIS_V2 PRIMARY HUB" if team == Unit.Team.PLAYER else "HOSTILE NEXUS VAT"
		var bw_str: String = "%d / %d" % [econ.get_bandwidth_used(team), econ.get_bandwidth_cap(team)] if econ != null else "--"
		stats.append({"label": "Drop-Off", "value": "Biomass"})
		stats.append({"label": "Bandwidth", "value": "+%d Capacity" % bandwidth_provided})
		stats.append({"label": "Network", "value": bw_str})
		stats.append({"label": "Rally", "value": _get_rally_summary()})
	elif building_type_id == &"cloning_vat":
		subtitle = "TIER-1 BATCH CLONING" if team == Unit.Team.PLAYER else "HOSTILE CLONING VAT"
		var mult: float = econ.get_batch_cost_multiplier(team, base_batch_cost_multiplier) if econ != null else base_batch_cost_multiplier
		var spd: int = int(round((econ.get_production_speed_multiplier(team) if econ != null else 1.0) * 100.0))
		stats.append({"label": "Batch Output", "value": "x%d Units (%.2fx Cost)" % [batch_production_count, mult]})
		stats.append({"label": "Prod Speed", "value": "%d%%" % spd})
		stats.append({"label": "Rally", "value": _get_rally_summary()})
		stats.append({"label": "Tech", "value": "Unlocks Fabricator"})
	elif building_type_id == &"calibration_foundry":
		subtitle = "TIER-1.5 MECH COUNTER" if team == Unit.Team.PLAYER else "HOSTILE FOUNDRY"
		var spd_f: int = int(round((econ.get_production_speed_multiplier(team) if econ != null else 1.0) * 100.0))
		stats.append({"label": "Roster", "value": "Lance-Rig / Jammer"})
		stats.append({"label": "Prod Speed", "value": "%d%%" % spd_f})
		stats.append({"label": "Rally", "value": _get_rally_summary()})
		stats.append({"label": "Role", "value": "Anti-Armor & Utility"})
	elif building_type_id == &"synthetics_fabricator":
		subtitle = "TIER-2 HEAVY SYNTHETICS" if team == Unit.Team.PLAYER else "HOSTILE FABRICATOR"
		var spd_s: int = int(round((econ.get_production_speed_multiplier(team) if econ != null else 1.0) * 100.0))
		stats.append({"label": "Roster", "value": "Goliath / Arc / Mortar"})
		stats.append({"label": "Prod Speed", "value": "%d%%" % spd_s})
		stats.append({"label": "Rally", "value": _get_rally_summary()})
		stats.append({"label": "Role", "value": "Heavy Compute Pivot"})
	elif building_type_id == &"bio_lab":
		subtitle = "MILITARY PRODUCTION"
		var spd: int = int(round((econ.get_production_speed_multiplier(team) if econ != null else 1.0) * 100.0))
		stats.append({"label": "Roster", "value": "Infantry / Scout"})
		stats.append({"label": "Prod Speed", "value": "%d%%" % spd})
		stats.append({"label": "Rally", "value": _get_rally_summary()})
		stats.append({"label": "Status", "value": "Operational"})
	elif building_type_id == &"silica_condenser" or building_type_id == &"silica_refinery":
		subtitle = "SILICA REFINING FACILITY"
		stats.append({"label": "Drop-Off", "value": "Silica"})
		stats.append({"label": "Harvesters", "value": "%d Active" % _count_friendly_harvesters()})
		stats.append({"label": "Rally", "value": _get_rally_summary()})
		stats.append({"label": "Throughput", "value": "25 Silica / Trip"})
	elif building_type_id == &"synapse_pylon" or building_type_id == &"bandwidth_relay":
		subtitle = "INFRASTRUCTURE NODE"
		var bw_net: String = "%d / %d" % [econ.get_bandwidth_used(team), econ.get_bandwidth_cap(team)] if econ != null else "--"
		stats.append({"label": "Bandwidth", "value": "+%d Capacity" % bandwidth_provided})
		stats.append({"label": "Network", "value": bw_net})
		stats.append({"label": "Status", "value": "Online"})
		stats.append({"label": "Role", "value": "Population Relay"})
	else:
		stats.append({"label": "Status", "value": "Operational"})

	return {
		"title": display_name,
		"subtitle": subtitle,
		"affiliation": affil,
		"accent_color": accent,
		"ring_color": accent,
		"show_hp_bar": true,
		"hp_current": current_hp,
		"hp_max": max_hp,
		"show_primary_bar": show_primary,
		"primary_bar_label": primary_label,
		"primary_bar_value": primary_val,
		"primary_bar_max": primary_max,
		"primary_bar_color": primary_col,
		"stats": stats,
		"is_commandable": has_commands,
		"readonly_label": "PASSIVE INFRASTRUCTURE" if team == Unit.Team.PLAYER else "READ-ONLY TELEMETRY",
	}


func _get_rally_summary() -> String:
	if not has_rally():
		return "Default (RMB to Set)"
	if _rally_target != null and is_instance_valid(_rally_target):
		if _rally_target is ResourceNode:
			return "Auto-Gather (%s)" % (_rally_target as ResourceNode).display_name
		if _rally_target is Building:
			return "Auto-Staff (%s)" % (_rally_target as Building).display_name
	return "Ground Point"


func _destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	if is_in_group("nav_bake_obstacles"):
		remove_from_group("nav_bake_obstacles")
	if production_component != null:
		production_component.cancel_all_and_refund(self)
	eject_engineers()
	if claimed_vent != null and is_instance_valid(claimed_vent):
		claimed_vent.release_building(self)
	set_selected(false)
	_unregister_from_economy()
	var econ_dead: EconomyManager = _get_economy_manager()
	if econ_dead != null:
		econ_dead.notify_building_tech_changed(team)
	_request_navmesh_rebake()
	destroyed.emit(self)
	queue_free()


func _request_navmesh_rebake() -> void:
	if not is_inside_tree():
		return
	var nav_reg: Node = get_tree().get_first_node_in_group("arena_nav_region")
	if nav_reg != null and nav_reg.has_method("request_rebake"):
		nav_reg.call("request_rebake")


func _tick_compute_generation(delta: float) -> void:
	var prev_count: int = assigned_engineers.size()
	_prune_assigned_engineers()
	if assigned_engineers.size() != prev_count:
		_update_staff_slot_visuals()
		staffing_changed.emit(self, assigned_engineers.size(), max_staff_slots)
		status_changed.emit(self)
	if assigned_engineers.is_empty():
		_compute_tick_timer = 0.0
		return

	_compute_tick_timer += delta
	if _compute_tick_timer < compute_tick_interval:
		return
	_compute_tick_timer -= compute_tick_interval

	var econ: EconomyManager = _get_economy_manager()
	if econ != null:
		var yield_amount: int = assigned_engineers.size() * compute_per_engineer
		econ.add_resource(team, EconomyManager.RESOURCE_COMPUTE, yield_amount)
	pulse_deposit_feedback()


func _has_active_builder() -> bool:
	if not is_inside_tree():
		return false
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node):
			var u: Unit = node
			if not u.is_dead and u.command_state == Unit.CommandState.CONSTRUCTING and u._construction_target == self:
				return true
	return false


func _count_friendly_harvesters() -> int:
	if not is_inside_tree():
		return 0
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("units"):
		if node is Unit and is_instance_valid(node):
			var u: Unit = node
			if not u.is_dead and u.team == team and u.get_unit_type_id() == &"silica_harvester":
				count += 1
	return count


func _prune_assigned_engineers() -> void:
	var valid: Array[Unit] = []
	for item: Variant in assigned_engineers:
		if is_instance_valid(item) and item is Unit:
			var eng: Unit = item
			if not eng.is_dead and not eng.is_queued_for_deletion():
				valid.append(eng)
	assigned_engineers = valid


func _update_construction_visuals() -> void:
	if body_visual != null:
		if is_constructed:
			body_visual.modulate = Color.WHITE
		else:
			var alpha: float = lerpf(0.48, 0.92, construction_progress)
			if team == Unit.Team.ENEMY:
				body_visual.modulate = Color(1.0, 0.62, 0.56, alpha)
			else:
				body_visual.modulate = Color(0.62, 0.88, 0.96, alpha)
	if construct_bar_root != null and construct_bar_fill != null:
		construct_bar_root.visible = not is_constructed
		construct_bar_fill.size.x = CONSTRUCT_BAR_WIDTH * clampf(construction_progress, 0.0, 1.0)


func _apply_enemy_bio_lab_roster() -> void:
	var trooper_data: UnitData = load(ENEMY_TROOPER_DATA_PATH) as UnitData
	if trooper_data != null:
		trainable_unit_data = [trooper_data]
		trainable_unit_scenes = []


func _apply_team_visuals() -> void:
	if team != Unit.Team.ENEMY:
		return
	if core_glow != null:
		core_glow.color = Color(1.0, 0.30, 0.24, 1.0)
		_base_core_color = core_glow.color
	if body_visual != null:
		var outer_hull: Polygon2D = body_visual.get_node_or_null("OuterHull") as Polygon2D
		if outer_hull != null:
			outer_hull.color = Color(0.24, 0.14, 0.16, 1.0)
		var twin_vat: Polygon2D = body_visual.get_node_or_null("TwinVatLeft") as Polygon2D
		if twin_vat != null:
			twin_vat.color = Color(0.96, 0.30, 0.24, 0.96)
		var hull_border: Line2D = body_visual.get_node_or_null("HullBorder") as Line2D
		if hull_border != null:
			hull_border.default_color = Color(1.0, 0.42, 0.34, 0.90)
	if health_bar_fill != null:
		health_bar_fill.color = Color(0.98, 0.34, 0.26, 1.0)
	if selection_ring != null:
		var ring_fill: Polygon2D = selection_ring.get_node_or_null("Fill") as Polygon2D
		if ring_fill != null:
			ring_fill.color = Color(1.0, 0.30, 0.24, 0.16)
		var ring_outline: Line2D = selection_ring.get_node_or_null("Outline") as Line2D
		if ring_outline != null:
			ring_outline.default_color = Color(1.0, 0.36, 0.26, 0.95)
	var name_tag: Label = get_node_or_null("NameTag") as Label
	if name_tag != null:
		name_tag.add_theme_color_override("font_color", Color(1.0, 0.68, 0.64, 0.92))


func _update_staff_slot_visuals() -> void:
	if staff_slots_root == null:
		return
	staff_slots_root.visible = is_constructed and max_staff_slots > 0
	var count: int = assigned_engineers.size()
	var idx: int = 0
	for child: Node in staff_slots_root.get_children():
		if child is ColorRect:
			var pip: ColorRect = child
			pip.color = Color(0.32, 0.92, 1.0, 1.0) if idx < count else Color(0.16, 0.24, 0.32, 0.95)
			idx += 1


func _update_health_bar() -> void:
	if health_bar_root == null or health_bar_fill == null:
		return
	var max_val: float = maxf(1.0, max_hp)
	var ratio: float = clampf(current_hp / max_val, 0.0, 1.0)
	health_bar_fill.size.x = HEALTH_BAR_WIDTH * ratio
	health_bar_root.visible = always_show_health_bar or is_selected or not is_constructed or ratio < 0.999


func _get_economy_manager() -> EconomyManager:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("economy_manager") as EconomyManager


func _register_with_economy() -> void:
	if not is_constructed or bandwidth_provided <= 0 or not is_inside_tree():
		return
	var econ: EconomyManager = _get_economy_manager()
	if econ != null:
		econ.register_bandwidth_provider(self, team, bandwidth_provided)


func _unregister_from_economy() -> void:
	if not is_inside_tree():
		return
	var econ: EconomyManager = _get_economy_manager()
	if econ != null:
		econ.unregister_bandwidth_provider(self)
