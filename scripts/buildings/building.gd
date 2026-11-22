class_name Building
extends StaticBody2D

const HEALTH_BAR_WIDTH: float = 76.0
const CONSTRUCT_BAR_WIDTH: float = 68.0
const DEPOSIT_PULSE_DURATION: float = 0.25

signal selection_changed(building: Building, selected: bool)
signal health_changed(building: Building, current_hp: float, max_hp: float)
signal status_changed(building: Building)
signal destroyed(building: Building)
signal construction_progress_changed(building: Building, progress: float, is_constructed: bool)
signal construction_completed(building: Building)
signal staffing_changed(building: Building, assigned_count: int, max_slots: int)
signal training_changed(building: Building)

@export var team: Unit.Team = Unit.Team.PLAYER
@export var building_type_id: StringName = &"command_core"
@export var display_name: String = "Command Core"
@export var max_hp: float = 1500.0
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
@export var trainable_unit_data: Array[UnitData] = []
@export var trainable_unit_scenes: Array[PackedScene] = []

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
var construction_progress: float = 1.0
var claimed_vent: ResourceNode = null
var assigned_engineers: Array[Unit] = []

var _construction_elapsed: float = 0.0
var _deposit_pulse_timer: float = 0.0
var _base_core_color: Color = Color(0.22, 0.94, 0.88, 1.0)
var _compute_tick_timer: float = 0.0
var _training_queue: Array[Dictionary] = []
var _training_elapsed: float = 0.0
var _spawn_slot_index: int = 0


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
	if core_glow != null:
		_base_core_color = core_glow.color
	if selection_ring != null:
		selection_ring.visible = is_selected
	_update_construction_visuals()
	_update_health_bar()
	_update_staff_slot_visuals()
	if is_constructed:
		_register_with_economy()


func _exit_tree() -> void:
	if claimed_vent != null and is_instance_valid(claimed_vent):
		claimed_vent.release_building(self)
	_unregister_from_economy()


func _process(delta: float) -> void:
	if is_destroyed:
		return

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

	if not _training_queue.is_empty():
		_tick_unit_training(delta)


func begin_construction(data: BuildingData, target_team: Unit.Team, vent: ResourceNode = null) -> void:
	team = target_team
	if data != null:
		building_type_id = data.building_id
		display_name = data.display_name
		max_hp = data.max_hp
		build_time = data.build_time
		bandwidth_provided = data.bandwidth_provided
		is_resource_dropoff = data.is_dropoff
		accepted_resources = data.accepted_resources.duplicate()
		max_staff_slots = data.max_staff_slots

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
	selection_changed.emit(self, is_selected)


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
	if is_destroyed or not is_constructed:
		return false
	if slot_index < 0 or slot_index >= trainable_unit_data.size() or slot_index >= trainable_unit_scenes.size():
		return false
	var unit_data: UnitData = trainable_unit_data[slot_index]
	var unit_scene: PackedScene = trainable_unit_scenes[slot_index]
	if unit_data == null or unit_scene == null:
		return false
	var econ: EconomyManager = _get_economy_manager()
	if econ == null:
		return false
	if not econ.can_afford(team, unit_data.get_cost_dict()):
		return false
	var queued_bw: int = _get_queued_bandwidth_cost()
	return econ.has_bandwidth(team, unit_data.bandwidth_cost + queued_bw)


func queue_unit_training(slot_index: int) -> bool:
	if not can_train_unit(slot_index):
		return false
	var unit_data: UnitData = trainable_unit_data[slot_index]
	var unit_scene: PackedScene = trainable_unit_scenes[slot_index]
	var econ: EconomyManager = _get_economy_manager()
	if econ == null or not econ.spend_resources(team, unit_data.get_cost_dict()):
		return false
	_training_queue.append({
		"data": unit_data,
		"scene": unit_scene,
		"duration": maxf(0.5, unit_data.build_time),
	})
	training_changed.emit(self)
	status_changed.emit(self)
	return true


func get_training_queue_size() -> int:
	return _training_queue.size()


func get_active_training_status() -> Dictionary:
	if _training_queue.is_empty():
		return {}
	var front: Dictionary = _training_queue[0]
	var duration: float = maxf(0.1, float(front["duration"]))
	var data: UnitData = front["data"] as UnitData
	return {
		"display_name": data.display_name if data != null else "Unit",
		"progress": clampf(_training_elapsed / duration, 0.0, 1.0),
		"queue_size": _training_queue.size(),
	}


func pulse_deposit_feedback() -> void:
	_deposit_pulse_timer = DEPOSIT_PULSE_DURATION


func take_damage(amount: float) -> void:
	if is_destroyed or amount <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_update_health_bar()
	health_changed.emit(self, current_hp, max_hp)
	status_changed.emit(self)
	if current_hp <= 0.0:
		_destroy()


func get_inspection_data() -> Dictionary:
	var accent: Color = Color(0.22, 0.88, 0.94, 1.0)
	if building_type_id == &"silica_refinery":
		accent = Color(0.98, 0.78, 0.28, 1.0)
	elif building_type_id == &"compute_node":
		accent = Color(0.32, 0.84, 1.0, 1.0)
	elif building_type_id == &"bandwidth_relay":
		accent = Color(0.76, 0.58, 1.0, 1.0)
	elif team == Unit.Team.ENEMY:
		accent = Color(1.0, 0.36, 0.26, 1.0)

	var affil: StringName = &"player" if team == Unit.Team.PLAYER else &"enemy"
	var stats: Array[Dictionary] = []

	if not is_constructed:
		var pct: int = int(round(construction_progress * 100.0))
		var has_builder: bool = _has_active_builder()
		stats.append({"label": "Construction", "value": "%d%% Complete" % pct})
		stats.append({"label": "Builder", "value": "Worker Active" if has_builder else "Awaiting Worker"})
		stats.append({"label": "Build Time", "value": "%.1fs Total" % build_time})
		stats.append({"label": "Hull Integrity", "value": "%d / %d" % [int(round(current_hp)), int(round(max_hp))]})
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
	var has_commands: bool = (team == Unit.Team.PLAYER) and (max_staff_slots > 0 or not trainable_unit_data.is_empty())

	if max_staff_slots > 0:
		subtitle = "FRIENDLY FACILITY"
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
	elif building_type_id == &"command_core":
		subtitle = "COMMAND HEADQUARTERS"
		var bw_str: String = "%d / %d" % [econ.get_bandwidth_used(team), econ.get_bandwidth_cap(team)] if econ != null else "--"
		stats.append({"label": "Drop-Off", "value": "Biomass"})
		stats.append({"label": "Bandwidth", "value": "+%d Capacity" % bandwidth_provided})
		stats.append({"label": "Network", "value": bw_str})
		var train_st: Dictionary = get_active_training_status()
		if not train_st.is_empty():
			stats.append({"label": "Training", "value": "%s (%d%%)" % [String(train_st["display_name"]), int(round(float(train_st["progress"]) * 100.0))]})
		else:
			stats.append({"label": "Status", "value": "Operational"})
	elif building_type_id == &"silica_refinery":
		subtitle = "FRIENDLY FACILITY"
		var harvesters: int = _count_friendly_harvesters()
		stats.append({"label": "Drop-Off", "value": "Silica"})
		stats.append({"label": "Harvesters", "value": "%d Active" % harvesters})
		var train_st_r: Dictionary = get_active_training_status()
		if not train_st_r.is_empty():
			stats.append({"label": "Training", "value": "%s (%d%%)" % [String(train_st_r["display_name"]), int(round(float(train_st_r["progress"]) * 100.0))]})
		else:
			stats.append({"label": "Status", "value": "Operational"})
		stats.append({"label": "Throughput", "value": "25 Silica / Trip"})
	elif building_type_id == &"bandwidth_relay":
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


func _destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	eject_engineers()
	if claimed_vent != null and is_instance_valid(claimed_vent):
		claimed_vent.release_building(self)
	set_selected(false)
	_unregister_from_economy()
	destroyed.emit(self)
	queue_free()


func _tick_compute_generation(delta: float) -> void:
	var prev_count: int = assigned_engineers.size()
	_prune_assigned_engineers()
	if assigned_engineers.size() != prev_count:
		_update_staff_slot_visuals()
		staffing_changed.emit(self, assigned_engineers.size(), max_staff_slots)
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


func _tick_unit_training(delta: float) -> void:
	var front: Dictionary = _training_queue[0]
	var duration: float = maxf(0.1, float(front["duration"]))
	_training_elapsed += delta
	if _training_elapsed < duration:
		training_changed.emit(self)
		status_changed.emit(self)
		return

	_training_elapsed = 0.0
	_training_queue.remove_at(0)
	var unit_scene: PackedScene = front["scene"] as PackedScene
	_spawn_trained_unit(unit_scene)
	training_changed.emit(self)
	status_changed.emit(self)


func _spawn_trained_unit(unit_scene: PackedScene) -> void:
	if unit_scene == null or not is_inside_tree():
		return
	var scene_root: Node = get_tree().current_scene
	var units_container: Node = scene_root.get_node_or_null("Units") if scene_root != null else null
	if units_container == null:
		units_container = get_parent()
	if units_container == null:
		return
	var node: Node = unit_scene.instantiate()
	if not (node is Unit):
		node.queue_free()
		return
	var unit: Unit = node
	unit.team = team
	var angle: float = float(_spawn_slot_index) * 0.95
	_spawn_slot_index = (_spawn_slot_index + 1) % 8
	var spawn_dist: float = footprint_radius + 26.0
	unit.global_position = global_position + Vector2.RIGHT.rotated(angle) * spawn_dist
	units_container.add_child(unit)


func _get_queued_bandwidth_cost() -> int:
	var total: int = 0
	for entry: Dictionary in _training_queue:
		var data: UnitData = entry["data"] as UnitData
		if data != null:
			total += maxi(0, data.bandwidth_cost)
	return total


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
			body_visual.modulate = Color(0.62, 0.88, 0.96, alpha)
	if construct_bar_root != null and construct_bar_fill != null:
		construct_bar_root.visible = not is_constructed
		construct_bar_fill.size.x = CONSTRUCT_BAR_WIDTH * clampf(construction_progress, 0.0, 1.0)


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
