class_name Building
extends StaticBody2D

const PRODUCTION_COMPONENT_SCRIPT: GDScript = preload("res://scripts/buildings/production_component.gd")
const TURRET_COMPONENT_SCRIPT: GDScript = preload("res://scripts/buildings/turret_component.gd")
const ENTITY_VISUALS_SCRIPT: GDScript = preload("res://ui/overlays/entity_visuals.gd")
const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")
const HEALTH_BAR_WIDTH: float = 76.0
const CONSTRUCT_BAR_WIDTH: float = 68.0
const DEPOSIT_PULSE_DURATION: float = 0.25
const HIT_FLASH_DURATION: float = 0.08
const COMPLETION_FLASH_DURATION: float = 0.22
const SALVAGE_DURATION: float = 4.0
const DEFAULT_BUILDING_COSTS: Dictionary = {
	&"nexus_vat": {"biomass": 400, "silica": 100, "compute": 0},
	&"silica_condenser": {"biomass": 75, "silica": 0, "compute": 0},
	&"wetware_mainframe": {"biomass": 100, "silica": 50, "compute": 0},
	&"synapse_pylon": {"biomass": 100, "silica": 0, "compute": 0},
	&"cloning_vat": {"biomass": 150, "silica": 50, "compute": 0},
	&"calibration_foundry": {"biomass": 125, "silica": 75, "compute": 0},
	&"synthetics_fabricator": {"biomass": 150, "silica": 100, "compute": 50},
	&"defense_turret": {"biomass": 100, "silica": 50, "compute": 0},
}

signal selection_changed(building: Building, selected: bool)
signal health_changed(building: Building, current_hp: float, max_hp: float)
signal status_changed(building: Building)
signal destroyed(building: Building)
signal construction_progress_changed(building: Building, progress: float, is_constructed: bool)
signal construction_completed(building: Building)
signal staffing_changed(building: Building, assigned_count: int, max_slots: int)
signal training_changed(building: Building)
signal rally_changed(building: Building)

@export var building_data: BuildingData = null
@export var team: Unit.Team = Unit.Team.PLAYER
@export var building_type_id: StringName = &"nexus_vat"
@export var display_name: String = "Nexus Vat"
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
@export var is_core_hub: bool = false
@export var batch_production_count: int = 1
@export var base_batch_cost_multiplier: float = 1.0
@export var trainable_unit_data: Array[UnitData] = []
@export var trainable_unit_scenes: Array[PackedScene] = []
@export var researchable_upgrades: Array[UpgradeData] = []
@export var has_turret: bool = false
@export var turret_damage: float = 0.0
@export var turret_attack_interval: float = 1.0
@export var turret_attack_range: float = 260.0
@export var turret_min_range: float = 0.0
@export var turret_splash_radius: float = 0.0
@export var turret_bonus_vs_armored: float = 1.0
@export var turret_tracer_style: StringName = &"pulse"
@export var turret_turn_speed: float = 7.0

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
var is_hovered: bool = false
var is_marquee_highlighted: bool = false
var completion_flash_timer: float = 0.0
var is_destroyed: bool = false
var has_been_spotted: bool = false
var construction_progress: float = 1.0
var claimed_vent: ResourceNode = null
var assigned_engineers: Array[Unit] = []
var production_component: ProductionComponent = null
var turret_component: TurretComponent = null

var _has_rally: bool = false
var _rally_position: Vector2 = Vector2.ZERO
var _rally_target: Node2D = null
var _rally_resource_type: StringName = &""
var rally_target_unit: Unit = null
var construction_costs: Dictionary = {}
var is_salvaging: bool = false
var salvage_elapsed: float = 0.0
var _construction_elapsed: float = 0.0
var _deposit_pulse_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _base_core_color: Color = Color(0.22, 0.94, 0.88, 1.0)
var _compute_tick_timer: float = 0.0
var _entity_visuals: EntityVisuals = null


func _ready() -> void:
	add_to_group("buildings")
	add_to_group("selectable_buildings")
	if SpatialGrid != null:
		SpatialGrid.register_building(self)
	if building_data != null:
		_sync_turret_from_data(building_data)
	if building_type_id == &"nexus_vat":
		is_core_hub = true
	if construction_costs.is_empty():
		construction_costs = _get_default_costs_for_type(building_type_id)
	if is_constructed:
		current_hp = max_hp
		construction_progress = 1.0
		_construction_elapsed = build_time
	else:
		current_hp = maxf(1.0, max_hp * 0.10)
		construction_progress = 0.0
		_construction_elapsed = 0.0
	_setup_procedural_visuals()
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

	_ensure_turret_component()

	_update_construction_visuals()
	_update_health_bar()
	_update_staff_slot_visuals()
	if is_constructed:
		_register_with_economy()
		var econ_ready: EconomyManager = _get_economy_manager()
		if econ_ready != null:
			econ_ready.notify_building_tech_changed(team)
	add_to_group("nav_bake_obstacles")
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)
	_request_navmesh_rebake()


func _exit_tree() -> void:
	if SpatialGrid != null:
		SpatialGrid.unregister_building(self)
	_disconnect_rally_unit_signal()
	if SettingsManager != null and SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.disconnect(_on_settings_changed)
	if is_in_group("nav_bake_obstacles"):
		remove_from_group("nav_bake_obstacles")
	if production_component != null:
		production_component.cancel_all_and_refund(self)
	if claimed_vent != null and is_instance_valid(claimed_vent):
		claimed_vent.release_building(self)
	_unregister_from_economy()
	_request_navmesh_rebake()


func _on_settings_changed(category: StringName) -> void:
	if category == &"gameplay" or category == &"all":
		_update_health_bar()
		queue_redraw()


func _process(delta: float) -> void:
	if is_destroyed:
		return

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		if _hit_flash_timer <= 0.0:
			_update_construction_visuals()

	if completion_flash_timer > 0.0:
		completion_flash_timer = maxf(0.0, completion_flash_timer - delta)

	if _deposit_pulse_timer > 0.0:
		_deposit_pulse_timer = maxf(0.0, _deposit_pulse_timer - delta)
		var t: float = _deposit_pulse_timer / DEPOSIT_PULSE_DURATION
		if core_glow != null:
			core_glow.color = _base_core_color.lerp(Color(0.55, 1.0, 0.78, 1.0), t)
		if _deposit_pulse_timer <= 0.0 and core_glow != null:
			core_glow.color = _base_core_color

	if not is_constructed:
		return

	if is_salvaging:
		salvage_elapsed += delta
		queue_redraw()
		status_changed.emit(self)
		if salvage_elapsed >= SALVAGE_DURATION:
			_complete_salvage()
			return

	if max_staff_slots > 0 and not assigned_engineers.is_empty():
		_tick_compute_generation(delta)

	if production_component != null and not is_salvaging:
		production_component.tick(self, delta)

	if turret_component != null and has_turret:
		turret_component.tick(delta)
		if is_selected and turret_component.explicit_target != null:
			queue_redraw()

	if is_selected and has_rally() and not _has_rally_overlay():
		queue_redraw()


func _should_draw_turret_range_ring() -> bool:
	if not is_selected or not has_turret or turret_attack_range <= 0.0:
		return false
	var mode: int = SettingsManager.attack_range_mode if SettingsManager != null else 1
	if mode == 2:
		return false
	if mode == 0:
		return true
	if turret_component != null and turret_component.explicit_target != null and is_instance_valid(turret_component.explicit_target):
		return true
	if is_inside_tree():
		var sel: Node = get_tree().get_first_node_in_group("selection_controller")
		if sel != null and sel.has_method("is_targeting_command_active") and bool(sel.call("is_targeting_command_active")):
			return true
	return false


func _draw_dashed_ring(center: Vector2, radius: float, col: Color, width: float, dash_count: int) -> void:
	var step: float = TAU / float(maxi(8, dash_count))
	for i: int in range(dash_count):
		var a0: float = float(i) * step
		var a1: float = a0 + step * 0.54
		draw_arc(center, radius, a0, a1, 4, col, width, true)


func _draw() -> void:
	if _should_draw_turret_range_ring():
		var atk_r: float = turret_attack_range + footprint_radius
		var tc: Color = TeamManager.get_team_color(int(team)) if TeamManager != null else (Color(0.28, 0.94, 0.96, 1.0) if team == Unit.Team.PLAYER else Color(1.0, 0.38, 0.28, 1.0))
		var ring_col: Color = Color(tc.r, tc.g, tc.b, 0.34)
		draw_circle(Vector2.ZERO, atk_r, Color(tc.r, tc.g, tc.b, 0.03))
		_draw_dashed_ring(Vector2.ZERO, atk_r, ring_col, 1.6, 44 if atk_r > 240.0 else 32)
		if turret_min_range > 0.0:
			var min_r: float = turret_min_range + footprint_radius
			draw_circle(Vector2.ZERO, min_r, Color(1.0, 0.28, 0.24, 0.05))
			_draw_dashed_ring(Vector2.ZERO, min_r, Color(1.0, 0.36, 0.28, 0.44), 1.4, 20)

	if is_selected and turret_component != null and turret_component.explicit_target != null and is_instance_valid(turret_component.explicit_target):
		var tgt_local: Vector2 = to_local(turret_component.explicit_target.global_position)
		draw_line(Vector2.ZERO, tgt_local, Color(1.0, 0.34, 0.32, 0.55), 1.4, true)
		draw_arc(tgt_local, 14.0, 0.0, TAU, 18, Color(1.0, 0.38, 0.32, 0.85), 1.6, true)

	if is_salvaging and is_constructed and not is_destroyed:
		var prog: float = clampf(salvage_elapsed / SALVAGE_DURATION, 0.0, 1.0)
		var bar_w: float = 72.0
		var bar_h: float = 6.0
		var bar_pos: Vector2 = Vector2(-bar_w * 0.5, footprint_radius + 10.0)
		var pulse: float = 0.72 + 0.28 * sin(salvage_elapsed * 9.0)
		draw_rect(Rect2(bar_pos - Vector2(1.0, 1.0), Vector2(bar_w + 2.0, bar_h + 2.0)), Color(0.04, 0.06, 0.09, 0.92), true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * prog, bar_h)), Color(1.0, 0.70, 0.20, pulse), true)
		draw_arc(Vector2.ZERO, footprint_radius + 6.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 32, Color(1.0, 0.72, 0.22, pulse), 2.4, true)

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
		building_data = data
		building_type_id = data.building_id
		display_name = data.display_name
		construction_costs = data.get_cost_dict()
		max_hp = data.max_hp
		vision_range = data.vision_range
		build_time = data.build_time
		bandwidth_provided = data.bandwidth_provided
		is_resource_dropoff = data.is_dropoff
		accepted_resources = data.accepted_resources.duplicate()
		max_staff_slots = data.max_staff_slots
		can_set_rally = data.can_set_rally
		is_core_hub = data.is_core_hub or building_type_id == &"nexus_vat"
		batch_production_count = maxi(1, data.batch_production_count)
		base_batch_cost_multiplier = maxf(1.0, data.base_batch_cost_multiplier)
		_sync_turret_from_data(data)
		var resolved_units: Array[UnitData] = data.resolve_trainable_units()
		if not resolved_units.is_empty():
			trainable_unit_data = resolved_units
			trainable_unit_scenes = []
		if not data.researchable_upgrades.is_empty():
			researchable_upgrades = data.researchable_upgrades.duplicate()

	_apply_team_visuals()

	if production_component == null and (not trainable_unit_data.is_empty() or not researchable_upgrades.is_empty()):
		production_component = PRODUCTION_COMPONENT_SCRIPT.new()
		production_component.name = "ProductionComponent"
		add_child(production_component)
		production_component.queue_changed.connect(func(_q: Array[Dictionary], _p: float, _d: float) -> void:
			training_changed.emit(self)
			status_changed.emit(self)
		)

	_ensure_turret_component()

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
	if not is_in_group("nav_bake_obstacles"):
		add_to_group("nav_bake_obstacles")
		_request_navmesh_rebake()

	if build_time <= 0.0:
		_complete_construction()


func _sync_turret_from_data(data: BuildingData) -> void:
	if data == null:
		return
	has_turret = data.has_turret
	turret_damage = data.turret_damage
	turret_attack_interval = data.turret_attack_interval
	turret_attack_range = data.turret_attack_range
	turret_min_range = data.turret_min_range
	turret_splash_radius = data.turret_splash_radius
	turret_bonus_vs_armored = data.turret_bonus_vs_armored
	turret_tracer_style = data.turret_tracer_style
	turret_turn_speed = data.turret_turn_speed


func _ensure_turret_component() -> void:
	if not has_turret:
		return
	if turret_component == null:
		turret_component = get_node_or_null("TurretComponent") as TurretComponent
	if turret_component == null:
		turret_component = TURRET_COMPONENT_SCRIPT.new() as TurretComponent
		turret_component.name = "TurretComponent"
		add_child(turret_component)
	if turret_component != null:
		turret_component.bind_building(self)


func command_turret_focus_target(target: Node2D) -> bool:
	if turret_component == null or not has_turret:
		return false
	var ok: bool = turret_component.set_explicit_target(target)
	if ok:
		queue_redraw()
		status_changed.emit(self)
	return ok


func get_turret_angle() -> float:
	if turret_component != null:
		return turret_component.turret_angle
	return 0.0 if int(team) == 0 else PI


func get_turret_recoil() -> float:
	if turret_component != null:
		return turret_component.recoil_offset
	return 0.0


func advance_construction(delta: float) -> bool:
	if is_destroyed or is_constructed:
		return true
	var speed_mult: float = GameConfig.get_build_speed_multiplier() if (GameConfig != null and GameConfig.has_method("get_build_speed_multiplier")) else 1.0
	var eff_delta: float = delta * speed_mult
	var total_time: float = maxf(0.1, build_time)
	_construction_elapsed = minf(total_time, _construction_elapsed + eff_delta)
	construction_progress = clampf(_construction_elapsed / total_time, 0.0, 1.0)
	var hp_gain: float = (max_hp * 0.90) * (eff_delta / total_time)
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
	completion_flash_timer = COMPLETION_FLASH_DURATION
	if get_parent() != null:
		var vfx_col: Color = TeamManager.get_team_color(int(team)) if TeamManager != null else Color(0.24, 0.96, 0.88, 1.0)
		var cfx: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
		cfx.z_index = 54
		get_parent().add_child(cfx)
		cfx.call("setup_building_complete", global_position, footprint_radius, vfx_col)
	_register_with_economy()
	var econ_done: EconomyManager = _get_economy_manager()
	if econ_done != null:
		econ_done.notify_building_tech_changed(team)
	if team == Unit.Team.PLAYER:
		var mm: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if mm != null:
			mm.push_tactical_alert(global_position, &"tech_complete", "%s Complete" % display_name)
		elif AudioManager != null:
			AudioManager.play_build_sfx(&"build_complete", global_position)
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
		if _entity_visuals != null and is_instance_valid(_entity_visuals):
			_entity_visuals.queue_redraw()
		_update_health_bar()
		queue_redraw()
	selection_changed.emit(self, is_selected)


func set_marquee_highlighted(active: bool) -> void:
	if is_marquee_highlighted == active:
		return
	is_marquee_highlighted = active
	if _entity_visuals != null and is_instance_valid(_entity_visuals):
		_entity_visuals.queue_redraw()
	queue_redraw()


func set_hovered(hovered: bool) -> void:
	if is_hovered == hovered:
		return
	is_hovered = hovered
	if _entity_visuals != null and is_instance_valid(_entity_visuals):
		_entity_visuals.queue_redraw()
	queue_redraw()


func is_actively_producing() -> bool:
	if is_destroyed or not is_constructed or is_salvaging:
		return false
	if production_component != null and production_component.get_queue_size() > 0:
		return true
	if max_staff_slots > 0 and get_assigned_engineer_count() > 0:
		return true
	return false


func set_rally_position(world_pos: Vector2) -> void:
	if not can_set_rally:
		return
	_disconnect_rally_unit_signal()
	_has_rally = true
	_rally_position = world_pos
	_rally_target = null
	_rally_resource_type = &""
	rally_target_unit = null
	queue_redraw()
	rally_changed.emit(self)
	status_changed.emit(self)


func set_rally_target(target: Node2D) -> void:
	if not can_set_rally or target == null or not is_instance_valid(target):
		return
	if target is Unit:
		set_rally_target_unit(target as Unit)
		return
	_disconnect_rally_unit_signal()
	_has_rally = true
	_rally_target = target
	_rally_resource_type = (target as ResourceNode).resource_type if (target is ResourceNode and not (target as ResourceNode).is_vent) else &""
	rally_target_unit = null
	_rally_position = target.global_position
	queue_redraw()
	rally_changed.emit(self)
	status_changed.emit(self)


func set_rally_target_unit(target_unit: Unit) -> void:
	if not can_set_rally or target_unit == null or not is_instance_valid(target_unit):
		return
	if target_unit.is_dead or target_unit.is_staffed or target_unit.team != team:
		return
	_disconnect_rally_unit_signal()
	_has_rally = true
	rally_target_unit = target_unit
	_rally_target = target_unit
	_rally_resource_type = &""
	_rally_position = target_unit.global_position
	if not target_unit.died.is_connected(_on_rally_target_unit_died):
		target_unit.died.connect(_on_rally_target_unit_died)
	queue_redraw()
	rally_changed.emit(self)
	status_changed.emit(self)


func _disconnect_rally_unit_signal() -> void:
	if rally_target_unit != null and is_instance_valid(rally_target_unit):
		if rally_target_unit.died.is_connected(_on_rally_target_unit_died):
			rally_target_unit.died.disconnect(_on_rally_target_unit_died)


func _on_rally_target_unit_died(unit: Unit) -> void:
	if unit != rally_target_unit:
		return
	if is_instance_valid(unit):
		_rally_position = unit.global_position
	rally_target_unit = null
	_rally_target = null
	queue_redraw()
	rally_changed.emit(self)
	status_changed.emit(self)


func has_rally() -> bool:
	if rally_target_unit != null:
		if not is_instance_valid(rally_target_unit) or rally_target_unit.is_dead or rally_target_unit.is_staffed:
			if is_instance_valid(rally_target_unit):
				_rally_position = rally_target_unit.global_position
			rally_target_unit = null
			_rally_target = null
		else:
			_rally_position = rally_target_unit.global_position
	elif _rally_target != null and not is_instance_valid(_rally_target):
		_rally_target = null
	return _has_rally


func get_rally_world_position() -> Vector2:
	if rally_target_unit != null:
		if is_instance_valid(rally_target_unit) and not rally_target_unit.is_dead and not rally_target_unit.is_staffed:
			_rally_position = rally_target_unit.global_position
			return _rally_position
		if is_instance_valid(rally_target_unit):
			_rally_position = rally_target_unit.global_position
		rally_target_unit = null
		_rally_target = null
	if _rally_target != null and is_instance_valid(_rally_target):
		return _rally_target.global_position
	return _rally_position


func get_rally_target() -> Node2D:
	if rally_target_unit != null:
		if is_instance_valid(rally_target_unit) and not rally_target_unit.is_dead and not rally_target_unit.is_staffed:
			return rally_target_unit
		rally_target_unit = null
		_rally_target = null
	if _rally_target != null and is_instance_valid(_rally_target):
		return _rally_target
	return null


func get_cluster_saturation() -> Dictionary:
	if not is_inside_tree() or not is_constructed or is_destroyed:
		return {"assigned": 0, "capacity": 0, "has_nodes": false}
	var res_type: StringName = &""
	var search_radius: float = 0.0
	if is_core_hub or building_type_id == &"nexus_vat":
		res_type = &"biomass"
		search_radius = 520.0
	elif building_type_id == &"silica_condenser":
		res_type = &"silica"
		search_radius = 420.0
	else:
		return {"assigned": 0, "capacity": 0, "has_nodes": false}

	var r_sq: float = search_radius * search_radius
	var total_assigned: int = 0
	var total_cap: int = 0
	var node_count: int = 0
	var tid: int = int(team)
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node as ResourceNode
		if rn.is_depleted() or rn.is_vent or rn.resource_type != res_type:
			continue
		if global_position.distance_squared_to(rn.global_position) <= r_sq:
			total_assigned += rn.get_assigned_count(tid)
			total_cap += maxi(1, rn.max_harvesters)
			node_count += 1
	return {
		"assigned": total_assigned,
		"capacity": total_cap,
		"has_nodes": node_count > 0,
		"resource_type": res_type,
	}


func _has_rally_overlay() -> bool:
	return is_inside_tree() and get_tree().get_first_node_in_group("rally_point_overlay") != null


func apply_rally_to_unit(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit) or unit.is_dead:
		return
	if not has_rally():
		return

	if rally_target_unit != null and is_instance_valid(rally_target_unit) and not rally_target_unit.is_dead and not rally_target_unit.is_staffed:
		_rally_position = rally_target_unit.global_position
		if unit.data != null and unit.data.attack_damage > 0.0 and not unit.data.can_gather:
			unit.command_attack_move(_rally_position)
		else:
			unit.command_move(_rally_position)
		return

	if _rally_target != null and is_instance_valid(_rally_target):
		if _rally_target is ResourceNode:
			var res_node: ResourceNode = _rally_target
			if not res_node.is_depleted() and unit.can_gather_resource(res_node.resource_type):
				var chosen: ResourceNode = ResourceNode.pick_best_cluster_node(res_node, unit, int(team))
				if chosen == null:
					chosen = res_node
				chosen.assign_worker(unit)
				unit.command_gather(chosen, false)
				return
		elif _rally_target is Building:
			var target_b: Building = _rally_target
			if not target_b.is_destroyed and target_b.max_staff_slots > 0 and unit.can_staff_compute():
				if unit.command_staff_building(target_b):
					return
	elif _rally_resource_type != &"" and unit.can_gather_resource(_rally_resource_type):
		# Original rallied resource node depleted; spill cleanly into surviving cluster near rally point
		var search_pos: Vector2 = _rally_position if _rally_position != Vector2.ZERO else global_position
		var fallback_rn: ResourceNode = ResourceNode.pick_best_cluster_node_from_pos(
			get_tree(),
			search_pos,
			_rally_resource_type,
			unit,
			int(team),
			480.0,
			1100.0
		)
		if fallback_rn != null:
			fallback_rn.assign_worker(unit)
			unit.command_gather(fallback_rn, false)
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


func queue_unit_training(slot_index: int, play_audio: bool = true) -> bool:
	if production_component == null or slot_index < 0 or slot_index >= trainable_unit_data.size():
		return false
	var scene_override: PackedScene = trainable_unit_scenes[slot_index] if slot_index < trainable_unit_scenes.size() else null
	return production_component.enqueue_unit(self, trainable_unit_data[slot_index], scene_override, play_audio)


func can_train_unit_data(unit_data: UnitData, scene_override: PackedScene = null) -> bool:
	if production_component == null or unit_data == null:
		return false
	return production_component.can_queue_unit(self, unit_data, scene_override)


func queue_unit_data(unit_data: UnitData, scene_override: PackedScene = null, play_audio: bool = true) -> bool:
	if production_component == null or unit_data == null:
		return false
	return production_component.enqueue_unit(self, unit_data, scene_override, play_audio)


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


func cancel_last_queued() -> bool:
	if production_component == null:
		return false
	return production_component.cancel_last_queued(self)


func get_training_queue_size() -> int:
	return production_component.get_queue_size() if production_component != null else 0


func get_active_training_status() -> Dictionary:
	return production_component.get_active_training_status() if production_component != null else {}


func pulse_deposit_feedback() -> void:
	_deposit_pulse_timer = DEPOSIT_PULSE_DURATION


func repair(amount: float) -> void:
	if is_destroyed or not is_constructed or amount <= 0.0:
		return
	var next_hp: float = minf(max_hp, current_hp + amount)
	if is_equal_approx(next_hp, current_hp):
		return
	current_hp = next_hp
	_update_health_bar()
	health_changed.emit(self, current_hp, max_hp)
	status_changed.emit(self)


func get_refund_dict(ratio: float) -> Dictionary:
	var src: Dictionary = construction_costs if not construction_costs.is_empty() else _get_default_costs_for_type(building_type_id)
	var out: Dictionary = {}
	for key: Variant in src.keys():
		var amt: int = int(floor(float(int(src[key])) * ratio + 0.5))
		if amt > 0:
			out[key] = amt
	return out


func get_refund_label(ratio: float) -> String:
	var refund: Dictionary = get_refund_dict(ratio)
	var parts: PackedStringArray = PackedStringArray()
	var b: int = int(refund.get(EconomyManager.RESOURCE_BIOMASS, 0))
	var s: int = int(refund.get(EconomyManager.RESOURCE_SILICA, 0))
	var c: int = int(refund.get(EconomyManager.RESOURCE_COMPUTE, 0))
	if b > 0:
		parts.append("%dB" % b)
	if s > 0:
		parts.append("%dS" % s)
	if c > 0:
		parts.append("%dC" % c)
	return " / ".join(parts) if not parts.is_empty() else "0"


func cancel_construction() -> bool:
	if is_destroyed or is_constructed:
		return false
	var econ: EconomyManager = _get_economy_manager()
	if econ != null:
		var refund: Dictionary = get_refund_dict(0.75)
		for key: Variant in refund.keys():
			econ.add_resource(int(team), key as StringName, int(refund[key]), false)
	if AudioManager != null:
		AudioManager.play_ui_click()
	_destroy()
	return true


func can_salvage() -> bool:
	if is_destroyed or not is_constructed:
		return false
	if is_core_hub or building_type_id == &"nexus_vat":
		# Prevent salvaging the team's sole remaining Nexus Vat
		var core_count: int = 0
		if is_inside_tree():
			for node: Node in get_tree().get_nodes_in_group("buildings"):
				if node is Building and is_instance_valid(node):
					var b: Building = node
					if not b.is_destroyed and not b.is_queued_for_deletion() and b.team == team and (b.is_core_hub or b.building_type_id == &"nexus_vat"):
						core_count += 1
		if core_count <= 1:
			return false
	return true


func toggle_salvage() -> bool:
	if is_salvaging:
		cancel_salvage()
		return false
	return start_salvage()


func start_salvage() -> bool:
	if not can_salvage():
		if AudioManager != null:
			AudioManager.play_error()
		return false
	is_salvaging = true
	salvage_elapsed = 0.0
	if AudioManager != null:
		AudioManager.play_ui_click()
	queue_redraw()
	status_changed.emit(self)
	return true


func cancel_salvage() -> void:
	if not is_salvaging:
		return
	is_salvaging = false
	salvage_elapsed = 0.0
	if AudioManager != null:
		AudioManager.play_ui_click()
	queue_redraw()
	status_changed.emit(self)


func _complete_salvage() -> void:
	if is_destroyed:
		return
	is_salvaging = false
	var econ: EconomyManager = _get_economy_manager()
	if econ != null:
		var refund: Dictionary = get_refund_dict(0.50)
		for key: Variant in refund.keys():
			econ.add_resource(int(team), key as StringName, int(refund[key]), false)
	_destroy()


func _get_default_costs_for_type(type_id: StringName) -> Dictionary:
	if DEFAULT_BUILDING_COSTS.has(type_id):
		var raw: Dictionary = DEFAULT_BUILDING_COSTS[type_id]
		var out: Dictionary = {}
		if int(raw.get("biomass", 0)) > 0:
			out[EconomyManager.RESOURCE_BIOMASS] = int(raw["biomass"])
		if int(raw.get("silica", 0)) > 0:
			out[EconomyManager.RESOURCE_SILICA] = int(raw["silica"])
		if int(raw.get("compute", 0)) > 0:
			out[EconomyManager.RESOURCE_COMPUTE] = int(raw["compute"])
		return out
	return {}


func take_damage(amount: float, attacker: Node = null) -> void:
	if is_destroyed or amount <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_hit_flash_timer = HIT_FLASH_DURATION
	if is_node_ready() and body_visual != null:
		body_visual.modulate = Color(1.9, 2.2, 2.3, 1.0)
	_update_health_bar()
	var is_local_owned: bool = TeamManager.is_team_controlled_by_local_human(int(team)) if TeamManager != null else (team == Unit.Team.PLAYER)
	if is_local_owned and is_inside_tree():
		var mm: MatchManager = get_tree().get_first_node_in_group("match_manager") as MatchManager
		if mm != null:
			mm.push_tactical_alert(global_position, &"under_attack", "%s Under Attack!" % display_name)
	health_changed.emit(self, current_hp, max_hp)
	status_changed.emit(self)
	if current_hp <= 0.0:
		if attacker != null and is_instance_valid(attacker) and attacker is Unit:
			var killer: Unit = attacker as Unit
			var is_enemy_killer: bool = TeamManager.are_enemies(int(killer.team), int(team)) if TeamManager != null else (killer.team != team)
			if not killer.is_dead and is_enemy_killer:
				killer.register_kill(self)
		_destroy()


func get_inspection_data() -> Dictionary:
	var accent: Color = Color(0.22, 0.88, 0.94, 1.0)
	if building_type_id == &"silica_condenser":
		accent = Color(0.98, 0.78, 0.28, 1.0)
	elif building_type_id == &"wetware_mainframe":
		accent = Color(0.32, 0.84, 1.0, 1.0)
	elif building_type_id == &"synapse_pylon":
		accent = Color(0.76, 0.58, 1.0, 1.0)
	elif building_type_id == &"cloning_vat":
		accent = Color(0.24, 0.94, 0.72, 1.0)
	elif building_type_id == &"calibration_foundry":
		accent = Color(0.96, 0.64, 0.26, 1.0)
	elif building_type_id == &"synthetics_fabricator":
		accent = Color(0.36, 0.96, 1.0, 1.0)
	elif team == Unit.Team.ENEMY:
		accent = Color(1.0, 0.36, 0.26, 1.0)

	var affil: StringName = &"player" if team == Unit.Team.PLAYER else &"enemy"
	var stats: Array[Dictionary] = []

	var is_local_owned: bool = TeamManager.is_team_controlled_by_local_human(int(team)) if TeamManager != null else (team == Unit.Team.PLAYER)

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
			"is_commandable": is_local_owned,
			"readonly_label": "CONSTRUCTION IN PROGRESS",
		}

	var econ: EconomyManager = _get_economy_manager()
	var show_primary: bool = false
	var primary_label: String = ""
	var primary_val: float = 0.0
	var primary_max: float = 1.0
	var primary_col: Color = accent
	var subtitle: String = "FRIENDLY STRUCTURE" if is_local_owned else "HOSTILE STRUCTURE"
	var has_commands: bool = is_local_owned

	if max_staff_slots > 0:
		subtitle = "COMPUTE FACILITY"
		var staffed: int = get_assigned_engineer_count()
		var yield_mult: float = GameConfig.get_yield_multiplier() if (GameConfig != null and GameConfig.has_method("get_yield_multiplier")) else 1.0
		var rate: int = int(round(float(staffed * compute_per_engineer) * yield_mult))
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
	elif has_turret:
		subtitle = "STATIC DEFENSE TURRET" if is_local_owned else "HOSTILE DEFENSE TURRET"
		var dmg_str: String = "%d (%.2fx Arm)" % [int(round(turret_damage)), turret_bonus_vs_armored] if turret_bonus_vs_armored > 1.0 else "%d" % int(round(turret_damage))
		stats.append({"label": "Damage", "value": dmg_str})
		stats.append({"label": "Range / Rate", "value": "%dpx / %.2fs" % [int(round(turret_attack_range)), turret_attack_interval]})
		if turret_splash_radius > 0.0:
			stats.append({"label": "Splash", "value": "%dpx Radius" % int(round(turret_splash_radius))})
		else:
			stats.append({"label": "Armor Class", "value": "Armored Structure"})
		var tgt_txt: String = "Locked Target" if (turret_component != null and turret_component.explicit_target != null and is_instance_valid(turret_component.explicit_target)) else ("Auto (RMB Focus)" if is_local_owned else "Automated")
		stats.append({"label": "Targeting", "value": tgt_txt})
	elif is_core_hub or building_type_id == &"nexus_vat":
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
	elif building_type_id == &"silica_condenser":
		subtitle = "SILICA REFINING FACILITY"
		stats.append({"label": "Drop-Off", "value": "Silica"})
		stats.append({"label": "Harvesters", "value": "%d Active" % _count_friendly_harvesters()})
		stats.append({"label": "Rally", "value": _get_rally_summary()})
		stats.append({"label": "Throughput", "value": "25 Silica / Trip"})
	elif building_type_id == &"synapse_pylon":
		subtitle = "INFRASTRUCTURE NODE"
		var bw_net: String = "%d / %d" % [econ.get_bandwidth_used(team), econ.get_bandwidth_cap(team)] if econ != null else "--"
		stats.append({"label": "Bandwidth", "value": "+%d Capacity" % bandwidth_provided})
		stats.append({"label": "Network", "value": bw_net})
		stats.append({"label": "Status", "value": "Online"})
		stats.append({"label": "Role", "value": "Population Relay"})
	else:
		stats.append({"label": "Status", "value": "Operational"})

	if is_salvaging:
		var rem_s: float = maxf(0.0, SALVAGE_DURATION - salvage_elapsed)
		show_primary = true
		primary_label = "SALVAGING (50%% REFUND) — %.1fs" % rem_s
		primary_val = salvage_elapsed
		primary_max = SALVAGE_DURATION
		primary_col = Color(1.0, 0.72, 0.22, 1.0)

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
	if rally_target_unit != null and is_instance_valid(rally_target_unit) and not rally_target_unit.is_dead:
		var u_name: String = rally_target_unit.data.display_name if rally_target_unit.data != null else "Unit"
		return "Follow (%s)" % u_name
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
	var burst_col: Color = TeamManager.get_team_color(int(team)) if TeamManager != null else (Color(0.32, 0.96, 0.90, 1.0) if team == Unit.Team.PLAYER else Color(1.0, 0.40, 0.26, 1.0))
	if is_inside_tree():
		var scars: Node = get_tree().get_first_node_in_group("battle_scars")
		if scars != null and scars.has_method("add_scar"):
			scars.call("add_scar", &"scorch_large", global_position, maxf(34.0, footprint_radius * 0.92), burst_col)
	var viewer_b: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var is_friendly_b_view: bool = viewer_b < 0 or (TeamManager.are_allies(viewer_b, int(team)) if TeamManager != null else (team == Unit.Team.PLAYER))
	if get_parent() != null and (is_friendly_b_view or visible):
		var fx: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
		fx.z_index = 54
		get_parent().add_child(fx)
		fx.call("setup_death_burst", global_position, maxf(28.0, footprint_radius * 0.95), burst_col, true)
	if (is_core_hub or building_type_id == &"nexus_vat") and is_inside_tree():
		var cam: Node = get_tree().get_first_node_in_group("rts_camera")
		if cam != null and cam.has_method("add_camera_shake"):
			cam.call("add_camera_shake", 5.0, 0.20, global_position)
	if AudioManager != null and (is_friendly_b_view or visible):
		var is_major_explosion: bool = is_core_hub or building_type_id == &"nexus_vat" or (TeamManager != null and TeamManager.is_team_controlled_by_local_human(int(team)))
		AudioManager.play_explosion_sfx(global_position, -2.5, is_major_explosion)
	destroyed.emit(self)
	queue_free()


func _request_navmesh_rebake() -> void:
	if not is_inside_tree():
		return
	var nav_reg: Node = get_tree().get_first_node_in_group("arena_nav_region")
	if nav_reg != null and nav_reg.has_method("request_rebake"):
		nav_reg.call("request_rebake")
	var fog: Node = get_tree().get_first_node_in_group("fog_of_war")
	if fog != null and fog.has_method("invalidate_building_vision_cache"):
		fog.call("invalidate_building_vision_cache")


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
		var yield_mult: float = GameConfig.get_yield_multiplier() if (GameConfig != null and GameConfig.has_method("get_yield_multiplier")) else 1.0
		var yield_amount: int = maxi(1, int(round(float(assigned_engineers.size() * compute_per_engineer) * yield_mult)))
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


func _setup_procedural_visuals() -> void:
	if body_visual == null:
		return
	for child: Node in body_visual.get_children():
		if child is CanvasItem and child != _entity_visuals:
			(child as CanvasItem).visible = false
	if _entity_visuals == null:
		_entity_visuals = ENTITY_VISUALS_SCRIPT.new()
		_entity_visuals.name = "EntityVisuals"
		body_visual.add_child(_entity_visuals)
	_entity_visuals.bind_building(self)


func _update_construction_visuals() -> void:
	if body_visual != null:
		body_visual.modulate = Color.WHITE
	if _entity_visuals != null:
		_entity_visuals.queue_redraw()
	if construct_bar_root != null and construct_bar_fill != null:
		construct_bar_root.visible = not is_constructed
		construct_bar_fill.size.x = CONSTRUCT_BAR_WIDTH * clampf(construction_progress, 0.0, 1.0)


func _apply_team_visuals() -> void:
	if _entity_visuals != null:
		_entity_visuals.team = int(team)
		_entity_visuals.queue_redraw()
	if int(team) == 0:
		return
	var tc: Color = TeamManager.get_team_color(int(team)) if TeamManager != null else Color(0.98, 0.34, 0.26, 1.0)
	if core_glow != null:
		core_glow.color = tc
		_base_core_color = core_glow.color
	if body_visual != null:
		var outer_hull: Polygon2D = body_visual.get_node_or_null("OuterHull") as Polygon2D
		if outer_hull != null:
			outer_hull.color = tc.darkened(0.72)
		var twin_vat: Polygon2D = body_visual.get_node_or_null("TwinVatLeft") as Polygon2D
		if twin_vat != null:
			twin_vat.color = Color(tc.r, tc.g, tc.b, 0.96)
		var hull_border: Line2D = body_visual.get_node_or_null("HullBorder") as Line2D
		if hull_border != null:
			hull_border.default_color = Color(tc.lightened(0.12).r, tc.lightened(0.12).g, tc.lightened(0.12).b, 0.90)
	if health_bar_fill != null:
		health_bar_fill.color = tc
	if selection_ring != null:
		var ring_fill: Polygon2D = selection_ring.get_node_or_null("Fill") as Polygon2D
		if ring_fill != null:
			ring_fill.color = Color(tc.r, tc.g, tc.b, 0.16)
		var ring_outline: Line2D = selection_ring.get_node_or_null("Outline") as Line2D
		if ring_outline != null:
			ring_outline.default_color = Color(tc.r, tc.g, tc.b, 0.95)
	var name_tag: Label = get_node_or_null("NameTag") as Label
	if name_tag != null:
		var tag_col: Color = tc.lightened(0.35)
		name_tag.add_theme_color_override("font_color", Color(tag_col.r, tag_col.g, tag_col.b, 0.92))


func _update_staff_slot_visuals() -> void:
	if _entity_visuals != null:
		_entity_visuals.queue_redraw()
	if staff_slots_root == null:
		return
	# EntityVisuals renders integrated staffing pips directly on the Wetware Mainframe silhouette.
	staff_slots_root.visible = false


func _update_health_bar() -> void:
	if health_bar_root == null or health_bar_fill == null:
		return
	var max_val: float = maxf(1.0, max_hp)
	var ratio: float = clampf(current_hp / max_val, 0.0, 1.0)
	health_bar_fill.size.x = HEALTH_BAR_WIDTH * ratio
	var mode: int = SettingsManager.health_bar_mode if SettingsManager != null else 0
	if mode == 1:
		health_bar_root.visible = true
	elif mode == 2:
		health_bar_root.visible = is_selected
	else:
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
