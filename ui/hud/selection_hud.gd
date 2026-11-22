class_name SelectionHUD
extends Control

@export var selection_controller_path: NodePath

@onready var bottom_panel: PanelContainer = %BottomPanel
@onready var portrait_swatch: ColorRect = %PortraitSwatch
@onready var unit_name_label: Label = %UnitNameLabel
@onready var unit_hp_label: Label = %UnitHPLabel
@onready var unit_hp_bar: ProgressBar = %UnitHPBar
@onready var unit_stats_label: Label = %UnitStatsLabel
@onready var subgroup_tabs_row: HBoxContainer = %SubgroupTabsRow
@onready var unit_badges_grid: GridContainer = %UnitBadgesGrid
@onready var building_info_label: Label = %BuildingInfoLabel
@onready var standard_commands_row: HBoxContainer = %StandardCommandsRow
@onready var ability_row: HBoxContainer = %AbilityRow
@onready var btn_cmd_move: Button = %BtnCmdMove
@onready var btn_cmd_stop: Button = %BtnCmdStop
@onready var btn_cmd_hold: Button = %BtnCmdHold
@onready var btn_cmd_amove: Button = %BtnCmdAMove

var _selection_controller: SelectionController = null
var _economy_manager: EconomyManager = null
var _connected_units: Array[Unit] = []
var _selected_building: Building = null
var _active_subgroup_units: Array[Unit] = []
var _active_abilities: Array[AbilityData] = []
var _ability_buttons: Dictionary = {}
var _building_action_buttons: Array[Dictionary] = []
var _targeting_ability: AbilityData = null


func _ready() -> void:
	_selection_controller = get_node_or_null(selection_controller_path) as SelectionController
	if _selection_controller != null:
		_selection_controller.selection_changed.connect(_on_selection_changed)
		_selection_controller.building_selection_changed.connect(_on_building_selection_changed)
		_selection_controller.ability_targeting_changed.connect(_on_ability_targeting_changed)

	_connect_economy_manager()

	btn_cmd_stop.pressed.connect(func() -> void:
		if _selection_controller != null:
			_selection_controller.issue_stop_command()
	)
	btn_cmd_hold.pressed.connect(func() -> void:
		if _selection_controller != null:
			_selection_controller.issue_hold_command()
	)
	btn_cmd_move.disabled = true
	btn_cmd_amove.disabled = true

	bottom_panel.visible = false


func _connect_economy_manager() -> void:
	if not is_inside_tree():
		return
	_economy_manager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if _economy_manager == null:
		return
	if not _economy_manager.resources_changed.is_connected(_on_economy_updated):
		_economy_manager.resources_changed.connect(_on_economy_updated)
	if not _economy_manager.bandwidth_changed.is_connected(_on_bandwidth_updated):
		_economy_manager.bandwidth_changed.connect(_on_bandwidth_updated)


func _on_economy_updated(team: int, _resources: Dictionary) -> void:
	if team != int(Unit.Team.PLAYER):
		return
	if not _active_abilities.is_empty():
		_refresh_all_ability_states()
	if _selected_building != null and is_instance_valid(_selected_building):
		_refresh_building_action_buttons(_selected_building)


func _on_bandwidth_updated(team: int, _used: int, _cap: int) -> void:
	if team != int(Unit.Team.PLAYER):
		return
	if _selected_building != null and is_instance_valid(_selected_building):
		_refresh_building_action_buttons(_selected_building)


func _on_selection_changed(selected_units: Array[Unit], subgroups: Array[Dictionary], active_subgroup_index: int) -> void:
	_disconnect_unit_signals()
	_active_subgroup_units = []
	_active_abilities = []
	_building_action_buttons.clear()

	if selected_units.is_empty() or subgroups.is_empty():
		if _selected_building != null and is_instance_valid(_selected_building) and not _selected_building.is_destroyed:
			_show_building_panel(_selected_building)
		else:
			bottom_panel.visible = false
		return

	_disconnect_building_signals()
	_selected_building = null
	bottom_panel.visible = true
	subgroup_tabs_row.visible = true
	unit_badges_grid.visible = true
	building_info_label.visible = false
	standard_commands_row.visible = true
	ability_row.visible = true

	var safe_idx: int = clampi(active_subgroup_index, 0, subgroups.size() - 1)
	var active_group: Dictionary = subgroups[safe_idx]
	_active_subgroup_units = active_group["units"]

	_connect_unit_signals(_active_subgroup_units)
	_rebuild_subgroup_tabs(subgroups, safe_idx)
	_rebuild_unit_badges(_active_subgroup_units)
	_rebuild_ability_buttons(active_group)
	_refresh_left_panel(active_group)
	_refresh_all_ability_states()


func _on_building_selection_changed(building: Building) -> void:
	_disconnect_building_signals()
	_selected_building = building if (building != null and is_instance_valid(building) and not building.is_destroyed) else null

	if _selected_building == null:
		_building_action_buttons.clear()
		if _active_subgroup_units.is_empty():
			bottom_panel.visible = false
		return

	_connect_building_signals(_selected_building)
	_show_building_panel(_selected_building, true)


func _show_building_panel(building: Building, rebuild_actions: bool = false) -> void:
	bottom_panel.visible = true
	subgroup_tabs_row.visible = false
	unit_badges_grid.visible = false
	building_info_label.visible = true
	standard_commands_row.visible = false

	_ability_buttons.clear()
	_active_abilities.clear()

	if building.building_type_id == &"silica_refinery":
		portrait_swatch.color = Color(0.98, 0.78, 0.28, 1.0)
	elif building.building_type_id == &"compute_node":
		portrait_swatch.color = Color(0.32, 0.84, 1.0, 1.0)
	elif building.building_type_id == &"bandwidth_relay":
		portrait_swatch.color = Color(0.76, 0.58, 1.0, 1.0)
	else:
		portrait_swatch.color = Color(0.22, 0.88, 0.94, 1.0)

	unit_name_label.text = building.display_name
	unit_hp_label.text = "HP: %d / %d" % [int(round(building.current_hp)), int(round(building.max_hp))]
	if unit_hp_bar != null:
		unit_hp_bar.max_value = maxf(1.0, building.max_hp)
		unit_hp_bar.value = clampf(building.current_hp, 0.0, building.max_hp)

	if not building.is_constructed:
		var pct: int = int(round(building.construction_progress * 100.0))
		unit_stats_label.text = "Constructing: %d%%" % pct
		building_info_label.text = "Under Construction (%d%%)  —  Worker building..." % pct
		ability_row.visible = false
		if rebuild_actions:
			_clear_ability_row()
		return

	var stat_parts: PackedStringArray = PackedStringArray()
	if building.bandwidth_provided > 0:
		stat_parts.append("+%d Bandwidth" % building.bandwidth_provided)
	if building.max_staff_slots > 0:
		stat_parts.append("Engineers: %d / %d" % [building.get_assigned_engineer_count(), building.max_staff_slots])
	if building.is_resource_dropoff:
		var res_names: PackedStringArray = PackedStringArray()
		for r: StringName in building.accepted_resources:
			res_names.append(String(r).capitalize())
		stat_parts.append("%s Drop-Off" % "/".join(res_names))
	unit_stats_label.text = "  |  ".join(stat_parts) if not stat_parts.is_empty() else "Structure"

	var info_parts: PackedStringArray = PackedStringArray()
	if building.max_staff_slots > 0:
		var staffed: int = building.get_assigned_engineer_count()
		var rate: int = staffed * building.compute_per_engineer
		info_parts.append("Engineers: %d / %d  (+%d Compute / %.0fs)" % [staffed, building.max_staff_slots, rate, building.compute_tick_interval])
	if building.is_resource_dropoff:
		var drop_res: PackedStringArray = PackedStringArray()
		for r: StringName in building.accepted_resources:
			drop_res.append(String(r).capitalize())
		info_parts.append("%s Drop-Off" % "/".join(drop_res))
	if building.bandwidth_provided > 0:
		info_parts.append("+%d Bandwidth" % building.bandwidth_provided)

	var train_status: Dictionary = building.get_active_training_status()
	if not train_status.is_empty():
		var t_pct: int = int(round(float(train_status["progress"]) * 100.0))
		info_parts.append("Training %s (%d%%) [Q:%d]" % [String(train_status["display_name"]), t_pct, int(train_status["queue_size"])])

	building_info_label.text = "  |  ".join(info_parts) if not info_parts.is_empty() else "Friendly Structure"

	if rebuild_actions:
		_rebuild_building_action_buttons(building)
	else:
		_refresh_building_action_buttons(building)


func _clear_ability_row() -> void:
	for child: Node in ability_row.get_children():
		child.queue_free()
	_building_action_buttons.clear()


func _rebuild_building_action_buttons(building: Building) -> void:
	_clear_ability_row()

	if not building.is_constructed:
		ability_row.visible = false
		return

	var has_buttons: bool = false

	# Compute Node: Eject Engineers button
	if building.max_staff_slots > 0:
		has_buttons = true
		var eject_btn: Button = Button.new()
		eject_btn.focus_mode = Control.FOCUS_NONE
		eject_btn.custom_minimum_size = Vector2(150.0, 34.0)
		eject_btn.add_theme_font_size_override("font_size", 12)
		eject_btn.tooltip_text = "Release all staffed Engineers from this Compute Node."
		var captured_building: Building = building
		eject_btn.pressed.connect(func() -> void:
			if is_instance_valid(captured_building):
				captured_building.eject_engineers()
		)
		ability_row.add_child(eject_btn)
		_building_action_buttons.append({
			"kind": "eject",
			"button": eject_btn,
		})

	# Production buildings: Trainable unit buttons
	for i: int in range(mini(building.trainable_unit_data.size(), building.trainable_unit_scenes.size())):
		var u_data: UnitData = building.trainable_unit_data[i]
		if u_data == null:
			continue
		has_buttons = true
		var train_btn: Button = Button.new()
		train_btn.focus_mode = Control.FOCUS_NONE
		train_btn.custom_minimum_size = Vector2(138.0, 34.0)
		train_btn.add_theme_font_size_override("font_size", 12)
		train_btn.tooltip_text = "Train %s (%s, %d BW, %.1fs)" % [u_data.display_name, u_data.get_cost_label(), u_data.bandwidth_cost, u_data.build_time]
		var captured_b: Building = building
		var captured_slot: int = i
		train_btn.pressed.connect(func() -> void:
			if is_instance_valid(captured_b):
				captured_b.queue_unit_training(captured_slot)
		)
		ability_row.add_child(train_btn)
		_building_action_buttons.append({
			"kind": "train",
			"slot": i,
			"data": u_data,
			"button": train_btn,
		})

	ability_row.visible = has_buttons
	_refresh_building_action_buttons(building)


func _refresh_building_action_buttons(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	for entry: Dictionary in _building_action_buttons:
		var btn: Button = entry["button"] as Button
		if btn == null or not is_instance_valid(btn):
			continue
		var kind: String = String(entry["kind"])
		if kind == "eject":
			var count: int = building.get_assigned_engineer_count()
			btn.text = "Eject Engineers (%d)" % count
			btn.disabled = count <= 0
			btn.modulate = Color(0.55, 0.92, 1.0, 1.0) if count > 0 else Color(0.6, 0.64, 0.7, 0.7)
		elif kind == "train":
			var slot: int = int(entry["slot"])
			var u_data: UnitData = entry["data"] as UnitData
			var short_name: String = u_data.display_name.replace("Worker Drone", "Worker").replace("Systems Engineer", "Engineer").replace("Silica Harvester", "Harvester")
			btn.text = "%s (%s)" % [short_name, u_data.get_cost_label()]
			var can_train: bool = building.can_train_unit(slot)
			btn.disabled = not can_train
			btn.modulate = Color(0.55, 1.0, 0.95, 1.0) if can_train else Color(0.56, 0.6, 0.66, 0.68)


func _on_building_health_changed(building: Building, _current_hp: float, _max_hp: float) -> void:
	if building == _selected_building and is_instance_valid(building):
		_show_building_panel(building, false)


func _on_building_construction_changed(building: Building, _progress: float, constructed: bool) -> void:
	if building == _selected_building and is_instance_valid(building):
		_show_building_panel(building, constructed)


func _on_building_staffing_changed(building: Building, _assigned: int, _max_slots: int) -> void:
	if building == _selected_building and is_instance_valid(building):
		_show_building_panel(building, false)


func _on_building_training_changed(building: Building) -> void:
	if building == _selected_building and is_instance_valid(building):
		_show_building_panel(building, false)


func _on_building_destroyed(building: Building) -> void:
	if building == _selected_building:
		_disconnect_building_signals()
		_selected_building = null
		_building_action_buttons.clear()
		if _active_subgroup_units.is_empty():
			bottom_panel.visible = false


func _connect_building_signals(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if not building.health_changed.is_connected(_on_building_health_changed):
		building.health_changed.connect(_on_building_health_changed)
	if not building.construction_progress_changed.is_connected(_on_building_construction_changed):
		building.construction_progress_changed.connect(_on_building_construction_changed)
	if not building.staffing_changed.is_connected(_on_building_staffing_changed):
		building.staffing_changed.connect(_on_building_staffing_changed)
	if not building.training_changed.is_connected(_on_building_training_changed):
		building.training_changed.connect(_on_building_training_changed)
	if not building.destroyed.is_connected(_on_building_destroyed):
		building.destroyed.connect(_on_building_destroyed)


func _disconnect_building_signals() -> void:
	if _selected_building != null and is_instance_valid(_selected_building):
		if _selected_building.health_changed.is_connected(_on_building_health_changed):
			_selected_building.health_changed.disconnect(_on_building_health_changed)
		if _selected_building.construction_progress_changed.is_connected(_on_building_construction_changed):
			_selected_building.construction_progress_changed.disconnect(_on_building_construction_changed)
		if _selected_building.staffing_changed.is_connected(_on_building_staffing_changed):
			_selected_building.staffing_changed.disconnect(_on_building_staffing_changed)
		if _selected_building.training_changed.is_connected(_on_building_training_changed):
			_selected_building.training_changed.disconnect(_on_building_training_changed)
		if _selected_building.destroyed.is_connected(_on_building_destroyed):
			_selected_building.destroyed.disconnect(_on_building_destroyed)


func _on_ability_targeting_changed(active_ability: AbilityData) -> void:
	_targeting_ability = active_ability
	_refresh_all_ability_states()


func _on_unit_health_changed(_unit: Unit, _current_hp: float, _max_hp: float) -> void:
	if _selection_controller == null:
		return
	var active_group: Dictionary = _selection_controller.get_active_subgroup()
	if not active_group.is_empty():
		_refresh_left_panel(active_group)
		_rebuild_unit_badges(_active_subgroup_units)


func _on_unit_ability_cooldown_updated(ability_id: StringName, _remaining: float, _duration: float) -> void:
	_refresh_single_ability_button(ability_id)


func _on_unit_cargo_changed(_unit: Unit, _resource_type: StringName, _amount: int) -> void:
	if _selection_controller == null:
		return
	var active_group: Dictionary = _selection_controller.get_active_subgroup()
	if not active_group.is_empty():
		_refresh_left_panel(active_group)


func _connect_unit_signals(units: Array[Unit]) -> void:
	for item: Variant in units:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item
		if not unit.health_changed.is_connected(_on_unit_health_changed):
			unit.health_changed.connect(_on_unit_health_changed)
		if not unit.ability_cooldown_updated.is_connected(_on_unit_ability_cooldown_updated):
			unit.ability_cooldown_updated.connect(_on_unit_ability_cooldown_updated)
		if not unit.cargo_changed.is_connected(_on_unit_cargo_changed):
			unit.cargo_changed.connect(_on_unit_cargo_changed)
		_connected_units.append(unit)


func _disconnect_unit_signals() -> void:
	for item: Variant in _connected_units:
		if is_instance_valid(item) and item is Unit:
			var unit: Unit = item
			if unit.health_changed.is_connected(_on_unit_health_changed):
				unit.health_changed.disconnect(_on_unit_health_changed)
			if unit.ability_cooldown_updated.is_connected(_on_unit_ability_cooldown_updated):
				unit.ability_cooldown_updated.disconnect(_on_unit_ability_cooldown_updated)
			if unit.cargo_changed.is_connected(_on_unit_cargo_changed):
				unit.cargo_changed.disconnect(_on_unit_cargo_changed)
	_connected_units.clear()


func _refresh_left_panel(active_group: Dictionary) -> void:
	var data: UnitData = active_group.get("data", null) as UnitData
	var units: Array[Unit] = active_group.get("units", [])
	var count: int = units.size()
	var display_name: String = active_group.get("display_name", "Unit")
	unit_name_label.text = "%s  x%d" % [display_name, count]

	if data != null and data.unit_type_id == &"scout_unit":
		portrait_swatch.color = Color(0.98, 0.78, 0.24, 1.0)
	elif data != null and data.unit_type_id == &"silica_harvester":
		portrait_swatch.color = Color(0.96, 0.68, 0.22, 1.0)
	elif data != null and data.can_staff_compute:
		portrait_swatch.color = Color(0.32, 0.82, 1.0, 1.0)
	elif data != null and data.can_gather:
		portrait_swatch.color = Color(0.28, 0.94, 0.56, 1.0)
	else:
		portrait_swatch.color = Color(0.24, 0.92, 0.88, 1.0)

	if count > 0 and is_instance_valid(units[0]) and data != null:
		var lead: Unit = units[0]
		unit_hp_label.text = "HP: %d / %d" % [int(round(lead.current_hp)), int(round(data.max_hp))]
		if unit_hp_bar != null:
			unit_hp_bar.max_value = maxf(1.0, data.max_hp)
			unit_hp_bar.value = clampf(lead.current_hp, 0.0, data.max_hp)
		if data.can_gather:
			unit_stats_label.text = "CARRY: %d / %d  |  SPD: %d" % [
				lead.get_carried_amount(),
				data.carry_capacity,
				int(round(data.move_speed)),
			]
		elif data.can_staff_compute:
			unit_stats_label.text = "ROLE: Compute Staff  |  SPD: %d" % int(round(data.move_speed))
		else:
			unit_stats_label.text = "DMG: %d  |  SPD: %d  |  RNG: %d" % [
				int(round(data.attack_damage)),
				int(round(data.move_speed)),
				int(round(data.attack_range)),
			]
	else:
		unit_hp_label.text = "HP: --"
		if unit_hp_bar != null:
			unit_hp_bar.value = 0.0
		unit_stats_label.text = ""


func _rebuild_subgroup_tabs(subgroups: Array[Dictionary], active_index: int) -> void:
	for child: Node in subgroup_tabs_row.get_children():
		child.queue_free()

	for i: int in range(subgroups.size()):
		var group: Dictionary = subgroups[i]
		var group_units: Array[Unit] = group["units"]
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		var prefix: String = "> " if i == active_index else ""
		btn.text = "%s%s (x%d)" % [prefix, String(group["display_name"]), group_units.size()]
		if i == active_index:
			btn.modulate = Color(0.55, 1.0, 0.96, 1.0)
		else:
			btn.modulate = Color(0.72, 0.78, 0.84, 0.85)
		var captured_idx: int = i
		btn.pressed.connect(func() -> void:
			if _selection_controller != null:
				_selection_controller.set_active_subgroup(captured_idx)
		)
		subgroup_tabs_row.add_child(btn)

	if subgroups.size() > 1:
		var hint: Label = Label.new()
		hint.text = " [Tab]"
		hint.modulate = Color(0.55, 0.9, 0.92, 0.85)
		subgroup_tabs_row.add_child(hint)


func _rebuild_unit_badges(units: Array[Unit]) -> void:
	for child: Node in unit_badges_grid.get_children():
		child.queue_free()

	var max_badges: int = mini(units.size(), 12)
	for i: int in range(max_badges):
		var unit: Unit = units[i]
		if not is_instance_valid(unit) or unit.is_dead:
			continue
		var badge: Label = Label.new()
		var max_hp: float = maxf(1.0, unit.data.max_hp if unit.data != null else 100.0)
		var pct: int = int(round((unit.current_hp / max_hp) * 100.0))
		badge.text = "[%d%%]" % pct
		badge.modulate = Color(0.32, 0.96, 0.76, 1.0) if pct > 50 else Color(1.0, 0.56, 0.28, 1.0)
		unit_badges_grid.add_child(badge)

	if units.size() > max_badges:
		var more: Label = Label.new()
		more.text = "+%d" % (units.size() - max_badges)
		unit_badges_grid.add_child(more)


func _rebuild_ability_buttons(active_group: Dictionary) -> void:
	for child: Node in ability_row.get_children():
		child.queue_free()
	_ability_buttons.clear()
	_active_abilities.clear()

	var data: UnitData = active_group.get("data", null) as UnitData
	if data == null:
		return

	for ability: AbilityData in data.abilities:
		if ability == null:
			continue
		_active_abilities.append(ability)
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(142.0, 34.0)
		btn.add_theme_font_size_override("font_size", 11)
		btn.tooltip_text = ability.description
		var captured_ability: AbilityData = ability
		btn.pressed.connect(func() -> void:
			if _selection_controller != null:
				_selection_controller.request_ability_slot(captured_ability)
		)
		ability_row.add_child(btn)
		_ability_buttons[ability.ability_id] = {
			"button": btn,
			"ability": ability,
		}


func _refresh_all_ability_states() -> void:
	for ability: AbilityData in _active_abilities:
		_refresh_single_ability_button(ability.ability_id)


func _refresh_single_ability_button(ability_id: StringName) -> void:
	if not _ability_buttons.has(ability_id):
		return
	var entry: Dictionary = _ability_buttons[ability_id]
	var btn: Button = entry["button"]
	var ability: AbilityData = entry["ability"]

	var is_targeting: bool = (_targeting_ability != null and _targeting_ability.ability_id == ability_id)

	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT and ability.building_to_build != null:
		var b_data: BuildingData = ability.building_to_build
		var cost_text: String = b_data.get_cost_label()
		var can_afford: bool = true
		if _economy_manager == null:
			_connect_economy_manager()
		if _economy_manager != null:
			can_afford = _economy_manager.can_afford(Unit.Team.PLAYER, b_data.get_cost_dict())

		if is_targeting:
			btn.disabled = false
			btn.text = "[%s] %s (PLACE)" % [ability.hotkey_label, ability.display_name]
			btn.modulate = Color(1.0, 0.85, 0.32, 1.0)
		elif can_afford:
			btn.disabled = false
			btn.text = "[%s] %s (%s)" % [ability.hotkey_label, ability.display_name, cost_text]
			btn.modulate = Color(0.55, 1.0, 0.95, 1.0)
		else:
			btn.disabled = true
			btn.text = "[%s] %s (%s)" % [ability.hotkey_label, ability.display_name, cost_text]
			btn.modulate = Color(0.56, 0.6, 0.66, 0.68)
		return

	var min_cd: float = INF
	var ready_count: int = 0
	for item: Variant in _active_subgroup_units:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item
		if unit.is_dead:
			continue
		var rem: float = unit.get_ability_remaining_cooldown(ability_id)
		if rem <= 0.0:
			ready_count += 1
			min_cd = 0.0
		else:
			min_cd = minf(min_cd, rem)

	if ready_count > 0:
		btn.disabled = false
		if is_targeting:
			btn.text = "[%s] %s (TARGET)" % [ability.hotkey_label, ability.display_name]
			btn.modulate = Color(1.0, 0.85, 0.32, 1.0)
		else:
			btn.text = "[%s] %s" % [ability.hotkey_label, ability.display_name]
			btn.modulate = Color(0.55, 1.0, 0.95, 1.0)
	else:
		var display_cd: float = 0.0 if min_cd == INF else min_cd
		btn.disabled = true
		btn.text = "[%s] %s (%.1fs)" % [ability.hotkey_label, ability.display_name, display_cd]
		btn.modulate = Color(0.6, 0.64, 0.7, 0.75)
