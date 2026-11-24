class_name SelectionHUD
extends Control

@export var selection_controller_path: NodePath

@onready var control_group_row: HBoxContainer = %ControlGroupRow
@onready var command_tooltip: CommandTooltip = %CommandTooltip
@onready var bottom_panel: PanelContainer = %BottomPanel
@onready var portrait_swatch: ColorRect = %PortraitSwatch
@onready var unit_name_label: Label = %UnitNameLabel
@onready var entity_subtitle_label: Label = %EntitySubtitleLabel
@onready var hp_box: VBoxContainer = %HPBox
@onready var unit_hp_label: Label = %UnitHPLabel
@onready var unit_hp_bar: ProgressBar = %UnitHPBar
@onready var primary_gauge_box: VBoxContainer = %PrimaryGaugeBox
@onready var primary_gauge_label: Label = %PrimaryGaugeLabel
@onready var primary_gauge_bar: ProgressBar = %PrimaryGaugeBar
@onready var subgroup_tabs_row: HBoxContainer = %SubgroupTabsRow
@onready var unit_badges_grid: GridContainer = %UnitBadgesGrid
@onready var telemetry_grid: GridContainer = %TelemetryGrid
@onready var production_queue_box: VBoxContainer = %ProductionQueueBox
@onready var production_label: Label = %ProductionLabel
@onready var production_bar: ProgressBar = %ProductionBar
@onready var queue_slots_row: HBoxContainer = %QueueSlotsRow
@onready var standard_commands_row: HBoxContainer = %StandardCommandsRow
@onready var ability_row: GridContainer = %AbilityRow
@onready var read_only_label: Label = %ReadOnlyLabel
@onready var btn_cmd_move: Button = %BtnCmdMove
@onready var btn_cmd_stop: Button = %BtnCmdStop
@onready var btn_cmd_hold: Button = %BtnCmdHold
@onready var btn_cmd_patrol: Button = %BtnCmdPatrol
@onready var btn_cmd_amove: Button = %BtnCmdAMove

var _selection_controller: SelectionController = null
var _economy_manager: EconomyManager = null
var _connected_units: Array[Unit] = []
var _inspected_entity: Node = null
var _selected_buildings: Array[Building] = []
var _connected_buildings: Array[Building] = []
var _active_subgroup_units: Array[Unit] = []
var _active_abilities: Array[AbilityData] = []
var _ability_buttons: Dictionary = {}
var _building_action_buttons: Array[Dictionary] = []
var _targeting_ability: AbilityData = null
var _patrol_targeting: bool = false
var _hp_fill_style: StyleBoxFlat = null
var _gauge_fill_style: StyleBoxFlat = null


func _ready() -> void:
	_setup_dynamic_bar_styles()
	_selection_controller = get_node_or_null(selection_controller_path) as SelectionController
	if _selection_controller != null:
		_selection_controller.selection_changed.connect(_on_selection_changed)
		_selection_controller.inspection_changed.connect(_on_inspection_changed)
		_selection_controller.buildings_selection_changed.connect(_on_buildings_selection_changed)
		_selection_controller.control_groups_changed.connect(_on_control_groups_changed)
		_selection_controller.ability_targeting_changed.connect(_on_ability_targeting_changed)
		_selection_controller.patrol_targeting_changed.connect(_on_patrol_targeting_changed)
		_on_control_groups_changed(_selection_controller.get_control_groups_summary())

	if SettingsManager != null and not SettingsManager.keybind_changed.is_connected(_on_keybind_changed):
		SettingsManager.keybind_changed.connect(_on_keybind_changed)
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_display_settings_changed):
		SettingsManager.settings_changed.connect(_on_display_settings_changed)

	_connect_economy_manager()

	btn_cmd_stop.pressed.connect(func() -> void:
		if AudioManager != null:
			AudioManager.play_ui_click()
		if _selection_controller != null:
			_selection_controller.issue_stop_command()
	)
	btn_cmd_hold.pressed.connect(func() -> void:
		if AudioManager != null:
			AudioManager.play_ui_click()
		if _selection_controller != null:
			_selection_controller.issue_hold_command()
	)
	if btn_cmd_patrol != null:
		btn_cmd_patrol.pressed.connect(func() -> void:
			if _selection_controller != null:
				_selection_controller.begin_patrol_targeting()
		)
	btn_cmd_move.disabled = true
	btn_cmd_amove.disabled = true

	_bind_static_command_tooltips()
	_refresh_dynamic_command_labels()
	bottom_panel.visible = false
	call_deferred("_adjust_layout_for_minimap")
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_adjust_layout_for_minimap):
		get_viewport().size_changed.connect(_adjust_layout_for_minimap)


func _adjust_layout_for_minimap() -> void:
	if not is_inside_tree():
		return
	var minimap_node: Node = get_tree().get_first_node_in_group("tactical_minimap")
	var bottom_stack: Control = get_node_or_null("BottomStack") as Control
	if minimap_node == null or bottom_stack == null:
		return
	var vp_width: float = get_viewport_rect().size.x
	var minimap_clearance: float = 244.0
	var desired_half_w: float = 460.0
	var center_x: float = vp_width * 0.5
	if center_x - desired_half_w < minimap_clearance:
		var avail_w: float = maxf(680.0, vp_width - minimap_clearance - 12.0)
		var shift_center: float = minimap_clearance + avail_w * 0.5
		bottom_stack.offset_left = (shift_center - avail_w * 0.5) - center_x
		bottom_stack.offset_right = (shift_center + avail_w * 0.5) - center_x
	else:
		bottom_stack.offset_left = -desired_half_w
		bottom_stack.offset_right = desired_half_w


func _setup_dynamic_bar_styles() -> void:
	if bottom_panel != null:
		bottom_panel.add_to_group("blocks_edge_pan")
	if unit_hp_bar != null:
		_hp_fill_style = StyleBoxFlat.new()
		_hp_fill_style.bg_color = Color(0.24, 0.94, 0.74, 1.0)
		_hp_fill_style.set_corner_radius_all(2)
		unit_hp_bar.add_theme_stylebox_override("fill", _hp_fill_style)
	if primary_gauge_bar != null:
		_gauge_fill_style = StyleBoxFlat.new()
		_gauge_fill_style.bg_color = Color(0.32, 0.88, 1.0, 1.0)
		_gauge_fill_style.set_corner_radius_all(2)
		primary_gauge_bar.add_theme_stylebox_override("fill", _gauge_fill_style)
	if production_bar != null:
		var prod_fill: StyleBoxFlat = StyleBoxFlat.new()
		prod_fill.bg_color = Color(0.24, 0.96, 0.86, 1.0)
		prod_fill.set_corner_radius_all(2)
		production_bar.add_theme_stylebox_override("fill", prod_fill)


func _bind_static_command_tooltips() -> void:
	_attach_tooltip(btn_cmd_move, "Move", "RMB", "Right-Click Ground", "Orders selected units to navigate to the target location.")
	_attach_dynamic_action_tooltip(btn_cmd_stop, "Stop", &"cmd_stop", "Immediate", "Cancels current movement, patrol, gathering, construction, or target and flushes command queue.")
	_attach_dynamic_action_tooltip(btn_cmd_hold, "Hold Position", &"cmd_hold", "Immediate", "Locks unit position while engaging enemies inside attack range.")
	_attach_dynamic_action_tooltip(btn_cmd_patrol, "Patrol", &"cmd_patrol", "Click Waypoint (Shift Chains Loop)", "Loops units continuously between waypoints while engaging enemies encountered along the path.")
	_attach_dynamic_action_tooltip(btn_cmd_amove, "Attack-Move", &"cmd_attack_move", "Smart-Cast at Cursor", "Moves toward cursor and automatically engages hostile targets along the way.")


func _attach_dynamic_action_tooltip(btn: Button, title: String, action_name: StringName, meta: String, desc: String) -> void:
	if btn == null:
		return
	btn.tooltip_text = ""
	btn.mouse_entered.connect(func() -> void:
		if command_tooltip != null:
			var hk: String = SettingsManager.get_action_display_label(action_name, false) if SettingsManager != null else ""
			command_tooltip.show_tooltip(title, hk, meta, desc)
	)
	btn.mouse_exited.connect(func() -> void:
		if command_tooltip != null:
			command_tooltip.hide_tooltip()
	)


func _get_compact_action_badge(action_name: StringName, fallback: String) -> String:
	if SettingsManager == null:
		return fallback
	return SettingsManager.get_action_display_label(action_name, true)


func _get_ability_action_name(hotkey_label: String) -> StringName:
	match hotkey_label.strip_edges().to_upper():
		"Q":
			return &"cmd_ability_q"
		"W":
			return &"cmd_ability_w"
		"E":
			return &"cmd_ability_e"
		"R":
			return &"cmd_ability_r"
		"T":
			return &"cmd_ability_t"
		"Y":
			return &"cmd_ability_y"
		"F":
			return &"cmd_ability_f"
	return &""


func _get_ability_hotkey_display(hotkey_label: String, compact: bool = true) -> String:
	var act: StringName = _get_ability_action_name(hotkey_label)
	if act != &"" and SettingsManager != null:
		return SettingsManager.get_action_display_label(act, compact)
	return hotkey_label


func _on_keybind_changed(_action_name: StringName) -> void:
	_refresh_dynamic_command_labels()
	_refresh_stance_button()
	if not _active_abilities.is_empty():
		_refresh_all_ability_states()
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_refresh_building_action_buttons(_inspected_entity as Building)
	if _selection_controller != null and _selection_controller.subgroups.size() > 1:
		_rebuild_subgroup_tabs(_selection_controller.subgroups, _selection_controller.active_subgroup_index)


func _on_display_settings_changed(category: StringName) -> void:
	if category == &"display" or category == &"all":
		call_deferred("_adjust_layout_for_minimap")


func _refresh_dynamic_command_labels() -> void:
	var k_stop: String = _get_compact_action_badge(&"cmd_stop", "S")
	var k_patrol: String = _get_compact_action_badge(&"cmd_patrol", "P")
	var k_amove: String = _get_compact_action_badge(&"cmd_attack_move", "A")
	if btn_cmd_stop != null:
		btn_cmd_stop.text = ("Stop (%s)" % k_stop) if not k_stop.is_empty() else "Stop"
	if btn_cmd_patrol != null:
		var p_prefix: String = "Patrol*" if _patrol_targeting else "Patrol"
		btn_cmd_patrol.text = ("%s (%s)" % [p_prefix, k_patrol]) if not k_patrol.is_empty() else p_prefix
		btn_cmd_patrol.modulate = Color(1.0, 0.86, 0.30, 1.0) if _patrol_targeting else Color.WHITE
	if btn_cmd_amove != null:
		btn_cmd_amove.text = ("Atk-Mv (%s)" % k_amove) if not k_amove.is_empty() else "Atk-Mv"


func _on_patrol_targeting_changed(active: bool) -> void:
	_patrol_targeting = active
	_refresh_dynamic_command_labels()


func _on_buildings_selection_changed(buildings: Array[Building]) -> void:
	_disconnect_multi_building_signals()
	_selected_buildings = buildings.duplicate()
	for b: Building in _selected_buildings:
		if is_instance_valid(b) and not b.is_destroyed:
			if not b.status_changed.is_connected(_on_inspected_entity_updated):
				b.status_changed.connect(_on_inspected_entity_updated)
			_connected_buildings.append(b)
	if not _selected_buildings.is_empty() and is_instance_valid(_selected_buildings[0]):
		_inspected_entity = _selected_buildings[0]
		_render_inspected_entity(_inspected_entity, true)
	if _selection_controller != null:
		_on_control_groups_changed(_selection_controller.get_control_groups_summary())


func _disconnect_multi_building_signals() -> void:
	for b: Building in _connected_buildings:
		if is_instance_valid(b) and b.status_changed.is_connected(_on_inspected_entity_updated):
			b.status_changed.disconnect(_on_inspected_entity_updated)
	_connected_buildings.clear()


func _attach_tooltip(btn: Button, title: String, hotkey: String, meta: String, desc: String) -> void:
	if btn == null:
		return
	btn.tooltip_text = ""
	btn.mouse_entered.connect(func() -> void:
		if command_tooltip != null:
			command_tooltip.show_tooltip(title, hotkey, meta, desc)
	)
	btn.mouse_exited.connect(func() -> void:
		if command_tooltip != null:
			command_tooltip.hide_tooltip()
	)


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
	if not _economy_manager.tech_changed.is_connected(_on_tech_updated):
		_economy_manager.tech_changed.connect(_on_tech_updated)


func _on_economy_updated(team: int, _resources: Dictionary) -> void:
	if team != int(Unit.Team.PLAYER):
		return
	if not _active_abilities.is_empty():
		_refresh_all_ability_states()
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_refresh_building_action_buttons(_inspected_entity as Building)


func _on_bandwidth_updated(team: int, _used: int, _cap: int) -> void:
	if team != int(Unit.Team.PLAYER):
		return
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_render_inspected_entity(_inspected_entity, false)


func _on_tech_updated(team: int) -> void:
	if team != int(Unit.Team.PLAYER):
		return
	if not _active_abilities.is_empty():
		_refresh_all_ability_states()
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_render_inspected_entity(_inspected_entity, false)


func _on_control_groups_changed(summary: Dictionary) -> void:
	if control_group_row == null:
		return
	for child: Node in control_group_row.get_children():
		child.queue_free()

	var rich: Dictionary = _selection_controller.get_control_group_summaries() if (_selection_controller != null and _selection_controller.has_method("get_control_group_summaries")) else {}
	if summary.is_empty() and rich.is_empty():
		control_group_row.visible = false
		return

	control_group_row.visible = true
	for num: int in range(1, 10):
		if not rich.has(num) and not summary.has(num):
			continue
		var info: Dictionary = rich.get(num, {}) as Dictionary
		var count: int = int(info.get("count", summary.get(num, 0)))
		if count <= 0:
			continue
		var label_str: String = String(info.get("label", "Group"))
		var is_active: bool = bool(info.get("is_active", false))
		var is_building: bool = bool(info.get("is_building", false))
		var pill: Button = Button.new()
		pill.focus_mode = Control.FOCUS_NONE
		pill.add_to_group("blocks_edge_pan")
		pill.add_theme_font_size_override("font_size", 11)
		pill.text = ("[%d] %s ×%d" % [num, _shorten_unit_name(label_str), count]) if is_building else ("[%d] ×%d" % [num, count])
		pill.modulate = Color(0.36, 1.0, 0.90, 1.0) if is_active else (Color(0.96, 0.84, 0.44, 0.92) if is_building else Color(0.76, 0.88, 0.94, 0.90))
		var captured_num: int = num
		pill.pressed.connect(func() -> void:
			if _selection_controller != null:
				_selection_controller.recall_control_group(captured_num, true)
		)
		var kind_label: String = "Structure(s)" if is_building else "Unit(s)"
		_attach_tooltip(
			pill,
			"Control Group %d — %s" % [num, label_str],
			str(num),
			"%d %s Assigned" % [count, kind_label],
			"Click or press %d to select. Double-click or double-tap to center camera. Ctrl+%d to reassign." % [num, num]
		)
		control_group_row.add_child(pill)


func _on_selection_changed(selected_units: Array[Unit], subgroups: Array[Dictionary], active_subgroup_index: int) -> void:
	_disconnect_unit_signals()
	_active_subgroup_units = []
	_active_abilities = []
	_building_action_buttons.clear()
	if command_tooltip != null:
		command_tooltip.hide_tooltip()

	if selected_units.is_empty() or subgroups.is_empty():
		if _inspected_entity != null and is_instance_valid(_inspected_entity):
			_render_inspected_entity(_inspected_entity, true)
		else:
			bottom_panel.visible = false
		return

	_disconnect_inspected_signals()
	_inspected_entity = null

	bottom_panel.visible = true
	var safe_idx: int = clampi(active_subgroup_index, 0, subgroups.size() - 1)
	var active_group: Dictionary = subgroups[safe_idx]
	_active_subgroup_units = active_group["units"]

	_connect_unit_signals(_active_subgroup_units)

	var is_single_unit: bool = (selected_units.size() == 1 and is_instance_valid(selected_units[0]))
	subgroup_tabs_row.visible = not is_single_unit
	unit_badges_grid.visible = not is_single_unit
	telemetry_grid.visible = is_single_unit
	production_queue_box.visible = false

	standard_commands_row.visible = true
	ability_row.visible = true
	read_only_label.visible = false

	if is_single_unit:
		var lead_data: Dictionary = InspectionHelper.get_inspection_data(selected_units[0])
		_apply_left_column(lead_data)
		_rebuild_telemetry_grid(lead_data["stats"])
	else:
		_refresh_squad_left_column(active_group)
		_rebuild_subgroup_tabs(subgroups, safe_idx)
		_rebuild_unit_badges(_active_subgroup_units)

	_rebuild_ability_buttons(active_group)
	_refresh_all_ability_states()
	_refresh_stance_button()
	if _selection_controller != null:
		_on_control_groups_changed(_selection_controller.get_control_groups_summary())


func _on_inspection_changed(entity: Node) -> void:
	_disconnect_inspected_signals()
	_inspected_entity = entity if (entity != null and is_instance_valid(entity)) else null
	if command_tooltip != null:
		command_tooltip.hide_tooltip()

	if _inspected_entity == null:
		_building_action_buttons.clear()
		if _active_subgroup_units.is_empty():
			bottom_panel.visible = false
		return

	_connect_inspected_signals(_inspected_entity)
	_render_inspected_entity(_inspected_entity, true)


func _render_inspected_entity(entity: Node, rebuild_actions: bool) -> void:
	if entity == null or not is_instance_valid(entity):
		bottom_panel.visible = false
		return

	var info: Dictionary = InspectionHelper.get_inspection_data(entity)
	if entity is Building and _selected_buildings.size() > 1:
		var lead_b: Building = entity as Building
		var same_type_count: int = 0
		var total_queued: int = 0
		for sb: Building in _selected_buildings:
			if is_instance_valid(sb) and not sb.is_destroyed:
				if sb.building_type_id == lead_b.building_type_id:
					same_type_count += 1
				total_queued += sb.get_training_queue_size()
		if same_type_count == _selected_buildings.size():
			info["title"] = "%s  x%d" % [lead_b.display_name, _selected_buildings.size()]
		else:
			info["title"] = "%s (+%d)" % [lead_b.display_name, _selected_buildings.size() - 1]
		info["subtitle"] = "MULTI-PRODUCTION GROUP (%d QUEUED)" % total_queued
	bottom_panel.visible = true
	subgroup_tabs_row.visible = false
	unit_badges_grid.visible = false
	telemetry_grid.visible = true
	standard_commands_row.visible = false

	_ability_buttons.clear()
	_active_abilities.clear()

	_apply_left_column(info)
	_rebuild_telemetry_grid(info["stats"])
	_refresh_production_queue_ui(entity)

	var is_commandable: bool = bool(info.get("is_commandable", false))
	if is_commandable and entity is Building:
		var building: Building = entity
		read_only_label.visible = false
		if rebuild_actions:
			_rebuild_building_action_buttons(building)
		else:
			_refresh_building_action_buttons(building)
	else:
		if rebuild_actions:
			_clear_ability_row()
		ability_row.visible = false
		read_only_label.visible = true
		read_only_label.text = String(info.get("readonly_label", "READ-ONLY TELEMETRY"))


func _refresh_production_queue_ui(entity: Node) -> void:
	if production_queue_box == null:
		return
	if not (entity is Building) or not is_instance_valid(entity):
		production_queue_box.visible = false
		return
	var building: Building = entity
	if not building.is_constructed or building.production_component == null or building.production_component.get_queue_size() == 0:
		production_queue_box.visible = false
		return

	production_queue_box.visible = true
	var status: Dictionary = building.get_active_training_status()
	var pct: int = int(round(float(status.get("progress", 0.0)) * 100.0))
	var kind: StringName = status.get("kind", ProductionComponent.KIND_UNIT)
	var active_name: String = String(status.get("display_name", "Unit"))
	var batch_cnt: int = int(status.get("batch_count", 1))
	if kind == ProductionComponent.KIND_UPGRADE:
		production_label.text = "Researching %s  (%d%%)" % [active_name, pct]
	elif batch_cnt > 1:
		production_label.text = "Cloning %s x%d  (%d%%)" % [active_name, batch_cnt, pct]
	else:
		production_label.text = "Training %s  (%d%%)" % [active_name, pct]
	production_bar.max_value = 100.0
	production_bar.value = float(pct)

	for child: Node in queue_slots_row.get_children():
		child.queue_free()

	var queue: Array[Dictionary] = building.production_component.get_queue()
	for i: int in range(queue.size()):
		var entry: Dictionary = queue[i]
		var entry_kind: StringName = entry.get("kind", ProductionComponent.KIND_UNIT)
		var slot_btn: Button = Button.new()
		slot_btn.focus_mode = Control.FOCUS_NONE
		slot_btn.add_theme_font_size_override("font_size", 10)
		var captured_b: Building = building
		var captured_idx: int = i
		slot_btn.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			if is_instance_valid(captured_b):
				captured_b.cancel_queued_unit(captured_idx)
		)

		if entry_kind == ProductionComponent.KIND_UPGRADE:
			var upg: UpgradeData = entry.get("data", null) as UpgradeData
			var upg_name: String = upg.display_name if upg != null else "Upgrade"
			slot_btn.text = "[%d] %s" % [i + 1, _shorten_unit_name(upg_name)]
			slot_btn.modulate = Color(1.0, 0.86, 0.42, 1.0) if i == 0 else Color(0.88, 0.78, 0.56, 0.9)
			var refund_upg: String = String(entry.get("cost_label", "100%"))
			_attach_tooltip(
				slot_btn,
				"Cancel %s" % upg_name,
				"LMB",
				"100%% Refund: %s" % refund_upg,
				"Click to cancel this queued upgrade and refund 100% of resources."
			)
		else:
			var u_data: UnitData = entry.get("data", null) as UnitData
			var b_cnt: int = int(entry.get("batch_count", 1))
			var short_name: String = _shorten_unit_name(u_data.display_name) if u_data != null else "Unit"
			slot_btn.text = "[%d] %s%s" % [i + 1, short_name, (" x%d" % b_cnt) if b_cnt > 1 else ""]
			slot_btn.modulate = Color(0.45, 0.98, 0.92, 1.0) if i == 0 else Color(0.76, 0.86, 0.92, 0.9)
			var refund_str: String = String(entry.get("cost_label", u_data.get_cost_label() if u_data != null else "100%"))
			var bw_val: int = int(entry.get("bandwidth_cost", u_data.bandwidth_cost if u_data != null else 1))
			_attach_tooltip(
				slot_btn,
				"Cancel %s%s" % [u_data.display_name if u_data != null else "Unit", (" (x%d)" % b_cnt) if b_cnt > 1 else ""],
				"LMB",
				"100%% Refund: %s  •  Frees %d BW" % [refund_str, bw_val],
				"Click to cancel this queued production and refund 100% of resources and reserved Bandwidth."
			)
		queue_slots_row.add_child(slot_btn)


func _shorten_unit_name(full_name: String) -> String:
	return full_name.replace("Worker Drone", "Worker").replace("Systems Engineer", "Engineer").replace("Silica Harvester", "Harvester").replace("Recon Scout", "Scout").replace("Test Unit", "Infantry").replace("Clone Trooper", "Clone").replace("Signal Jammer", "Jammer").replace("Goliath Frame", "Goliath").replace("Chrysalis Mortar", "Mortar").replace("Batch Efficiency", "Batch Eff.").replace("Adrenal Potency", "Adrenal Pot.").replace("Compute Overdrive", "Overdrive")


func _build_unit_class_traits_label(u_data: UnitData) -> String:
	if u_data == null:
		return ""
	var tags: PackedStringArray = PackedStringArray()
	if u_data.unit_type_id == &"goliath_frame" or u_data.unit_type_id == &"arc_lancer":
		tags.append("Heavy Synthetic")
	elif u_data.is_armored:
		tags.append("Armored")
	else:
		tags.append("Light")

	if u_data.bonus_vs_armored > 0.0:
		tags.append("+vs Armored")
	if u_data.aoe_attack_radius > 0.0:
		tags.append("AoE Splash")
	if u_data.line_pierce_width > 0.0:
		tags.append("Line Pierce")
	if u_data.min_attack_range > 0.0:
		tags.append("Min Range")
	if u_data.heal_aura_rate > 0.0:
		tags.append("Heal Aura")
	if u_data.ignore_friendly_unit_collision:
		tags.append("Colossus Stride")
	return " • ".join(tags)


func _apply_left_column(info: Dictionary) -> void:
	var accent: Color = info.get("accent_color", Color(0.24, 0.92, 0.88, 1.0))
	portrait_swatch.color = accent
	unit_name_label.text = String(info.get("title", "Entity"))
	entity_subtitle_label.text = String(info.get("subtitle", "TELEMETRY"))
	entity_subtitle_label.modulate = accent

	var show_hp: bool = bool(info.get("show_hp_bar", false))
	hp_box.visible = show_hp
	if show_hp:
		var cur_hp: float = float(info.get("hp_current", 0.0))
		var max_hp: float = maxf(1.0, float(info.get("hp_max", 1.0)))
		unit_hp_label.text = "HP: %s / %s" % [
			InspectionHelper.format_number(int(round(cur_hp))),
			InspectionHelper.format_number(int(round(max_hp))),
		]
		unit_hp_bar.max_value = max_hp
		unit_hp_bar.value = clampf(cur_hp, 0.0, max_hp)
		var is_enemy: bool = (info.get("affiliation", &"neutral") == &"enemy")
		if _hp_fill_style != null:
			_hp_fill_style.bg_color = Color(0.96, 0.34, 0.26, 1.0) if is_enemy else Color(0.24, 0.94, 0.74, 1.0)

	var show_primary: bool = bool(info.get("show_primary_bar", false))
	primary_gauge_box.visible = show_primary
	if show_primary:
		primary_gauge_label.text = String(info.get("primary_bar_label", ""))
		primary_gauge_bar.max_value = maxf(1.0, float(info.get("primary_bar_max", 100.0)))
		primary_gauge_bar.value = clampf(float(info.get("primary_bar_value", 0.0)), 0.0, primary_gauge_bar.max_value)
		if _gauge_fill_style != null:
			_gauge_fill_style.bg_color = info.get("primary_bar_color", accent)


func _refresh_squad_left_column(active_group: Dictionary) -> void:
	var units: Array[Unit] = active_group.get("units", [])
	if units.is_empty() or not is_instance_valid(units[0]):
		return
	var lead_info: Dictionary = InspectionHelper.get_inspection_data(units[0])
	lead_info["title"] = "%s  x%d" % [String(active_group.get("display_name", "Unit")), units.size()]
	_apply_left_column(lead_info)


func _rebuild_telemetry_grid(stats: Variant) -> void:
	for child: Node in telemetry_grid.get_children():
		child.queue_free()

	if not (stats is Array):
		return
	for item: Variant in stats:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var cell: HBoxContainer = HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 6)

		var k_label: Label = Label.new()
		k_label.text = "%s:" % String(entry.get("label", ""))
		k_label.add_theme_font_size_override("font_size", 11)
		k_label.add_theme_color_override("font_color", Color(0.56, 0.74, 0.82, 0.9))
		cell.add_child(k_label)

		var v_label: Label = Label.new()
		v_label.text = String(entry.get("value", ""))
		v_label.add_theme_font_size_override("font_size", 12)
		var val_col: Color = entry.get("color", Color(0.92, 0.98, 1.0, 1.0)) as Color
		v_label.add_theme_color_override("font_color", val_col)
		cell.add_child(v_label)

		telemetry_grid.add_child(cell)


func _clear_ability_row() -> void:
	for child: Node in ability_row.get_children():
		child.queue_free()
	_building_action_buttons.clear()


func _rebuild_building_action_buttons(building: Building) -> void:
	_clear_ability_row()

	if not building.is_constructed:
		ability_row.columns = 2
		var cancel_btn: Button = Button.new()
		cancel_btn.focus_mode = Control.FOCUS_NONE
		cancel_btn.custom_minimum_size = Vector2(214.0, 32.0)
		cancel_btn.add_theme_font_size_override("font_size", 11)
		cancel_btn.text = "[X] Cancel Build (75% Refund)"
		cancel_btn.modulate = Color(1.0, 0.52, 0.34, 1.0)
		var captured_b_cancel: Building = building
		cancel_btn.pressed.connect(func() -> void:
			if is_instance_valid(captured_b_cancel):
				captured_b_cancel.cancel_construction()
		)
		_attach_tooltip(
			cancel_btn,
			"Cancel %s" % building.display_name,
			"LMB",
			"75%% Refund: %s" % building.get_refund_label(0.75),
			"Immediately cancels this unfinished scaffold, refunds 75% of construction resources, releases workers, and updates pathing."
		)
		ability_row.add_child(cancel_btn)
		_building_action_buttons.append({
			"kind": "cancel_build",
			"button": cancel_btn,
		})
		ability_row.visible = true
		return

	var total_actions: int = (1 if building.max_staff_slots > 0 else 0) + building.trainable_unit_data.size() + building.researchable_upgrades.size() + 1
	var use_compact: bool = total_actions > 4
	ability_row.columns = 3 if use_compact else 2
	var btn_min_size: Vector2 = Vector2(146.0, 28.0) if use_compact else Vector2(214.0, 29.0)
	var btn_font_size: int = 10 if use_compact else 11

	var has_buttons: bool = false

	if building.max_staff_slots > 0:
		has_buttons = true
		var eject_btn: Button = Button.new()
		eject_btn.focus_mode = Control.FOCUS_NONE
		eject_btn.custom_minimum_size = Vector2(168.0, 34.0)
		eject_btn.add_theme_font_size_override("font_size", 12)
		var captured_building: Building = building
		eject_btn.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			if _selection_controller != null and _selected_buildings.size() > 1:
				_selection_controller.eject_engineers_from_selected_buildings()
			elif is_instance_valid(captured_building):
				captured_building.eject_engineers()
		)
		_attach_dynamic_action_tooltip(
			eject_btn,
			"Eject Engineers",
			&"cmd_ability_e",
			"Instant Release",
			"Releases all Engineers currently staffed inside this Wetware Mainframe back onto the battlefield."
		)
		ability_row.add_child(eject_btn)
		_building_action_buttons.append({
			"kind": "eject",
			"button": eject_btn,
		})

	for i: int in range(building.trainable_unit_data.size()):
		var u_data: UnitData = building.trainable_unit_data[i]
		if u_data == null:
			continue
		has_buttons = true
		var train_btn: Button = Button.new()
		train_btn.focus_mode = Control.FOCUS_NONE
		train_btn.custom_minimum_size = btn_min_size
		train_btn.add_theme_font_size_override("font_size", btn_font_size)
		var captured_b: Building = building
		var captured_slot: int = i
		var captured_u: UnitData = u_data
		train_btn.pressed.connect(func() -> void:
			if _selection_controller != null and _selected_buildings.size() > 1:
				_selection_controller.queue_unit_distributed(captured_u)
			elif is_instance_valid(captured_b):
				captured_b.queue_unit_training(captured_slot)
		)
		train_btn.tooltip_text = ""
		train_btn.mouse_entered.connect(func() -> void:
			if command_tooltip == null or not is_instance_valid(captured_b):
				return
			var b_info: Dictionary = captured_b.get_unit_batch_info(captured_u)
			var b_cnt: int = int(b_info["batch_count"])
			var traits_line: String = _build_unit_class_traits_label(captured_u)
			var meta_line: String = "Cost: %s / %d BW  •  %.1fs" % [String(b_info["cost_label"]), int(b_info["bandwidth_cost"]), float(b_info["duration"])]
			if not traits_line.is_empty():
				meta_line = "%s  •  %s" % [traits_line, meta_line]
			var desc: String = "Queues a %s (max 5 in queue). Reserves Bandwidth immediately." % captured_u.display_name
			if b_cnt > 1:
				var mult_val: float = float(b_info["cost_multiplier"])
				var eff_note: String = " (Batch Efficiency Active)" if mult_val <= 1.55 else " (1.75x Batch Cost)"
				desc = "Parallel Batch Cloning: spawns %d %ss simultaneously for %.2fx single-unit cost%s." % [b_cnt, captured_u.display_name, mult_val, eff_note]
			command_tooltip.show_tooltip(
				("Clone %s (x%d)" % [captured_u.display_name, b_cnt]) if b_cnt > 1 else ("Train %s" % captured_u.display_name),
				"",
				meta_line,
				desc
			)
		)
		train_btn.mouse_exited.connect(func() -> void:
			if command_tooltip != null:
				command_tooltip.hide_tooltip()
		)
		ability_row.add_child(train_btn)
		_building_action_buttons.append({
			"kind": "train",
			"slot": i,
			"data": u_data,
			"button": train_btn,
		})

	for j: int in range(building.researchable_upgrades.size()):
		var upg: UpgradeData = building.researchable_upgrades[j]
		if upg == null:
			continue
		has_buttons = true
		var upg_btn: Button = Button.new()
		upg_btn.focus_mode = Control.FOCUS_NONE
		upg_btn.custom_minimum_size = btn_min_size
		upg_btn.add_theme_font_size_override("font_size", btn_font_size)
		var captured_b_u: Building = building
		var captured_upg_idx: int = j
		upg_btn.pressed.connect(func() -> void:
			if is_instance_valid(captured_b_u):
				captured_b_u.queue_upgrade_research(captured_upg_idx)
		)
		var upg_meta: String = "Upgrade  •  Cost: %s  •  %.1fs" % [upg.get_cost_label(), upg.research_time]
		_attach_tooltip(
			upg_btn,
			"Research: %s" % upg.display_name,
			upg.hotkey_label,
			upg_meta,
			upg.description
		)
		ability_row.add_child(upg_btn)
		_building_action_buttons.append({
			"kind": "upgrade",
			"slot": j,
			"data": upg,
			"button": upg_btn,
		})

	# Salvage / Decommission button for completed friendly structures
	has_buttons = true
	var salvage_btn: Button = Button.new()
	salvage_btn.focus_mode = Control.FOCUS_NONE
	salvage_btn.custom_minimum_size = btn_min_size
	salvage_btn.add_theme_font_size_override("font_size", btn_font_size)
	var captured_b_salv: Building = building
	salvage_btn.pressed.connect(func() -> void:
		if is_instance_valid(captured_b_salv):
			captured_b_salv.toggle_salvage()
	)
	salvage_btn.tooltip_text = ""
	salvage_btn.mouse_entered.connect(func() -> void:
		if command_tooltip == null or not is_instance_valid(captured_b_salv):
			return
		if not captured_b_salv.can_salvage():
			command_tooltip.show_tooltip("Salvage Unavailable", "", "Protected Core", "Cannot salvage last Nexus Vat.")
		elif captured_b_salv.is_salvaging:
			command_tooltip.show_tooltip("Cancel Salvage", "LMB", "Stops Decommission", "Halts the active 4.0s decommission countdown and keeps this structure online.")
		else:
			command_tooltip.show_tooltip(
				"Salvage %s" % captured_b_salv.display_name,
				"LMB",
				"4.0s Countdown  •  50%% Refund: %s" % captured_b_salv.get_refund_label(0.50),
				"Decommissions this structure after 4.0s (click again to cancel), refunding 50% of resources, ejecting Engineers, and freeing Bandwidth."
			)
	)
	salvage_btn.mouse_exited.connect(func() -> void:
		if command_tooltip != null:
			command_tooltip.hide_tooltip()
	)
	ability_row.add_child(salvage_btn)
	_building_action_buttons.append({
		"kind": "salvage",
		"button": salvage_btn,
	})

	ability_row.visible = has_buttons
	_refresh_building_action_buttons(building)


func _refresh_building_action_buttons(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if _economy_manager == null:
		_connect_economy_manager()
	for entry: Dictionary in _building_action_buttons:
		var btn: Button = entry["button"] as Button
		if btn == null or not is_instance_valid(btn):
			continue
		var kind: String = String(entry["kind"])
		if kind == "eject":
			var count: int = building.get_assigned_engineer_count()
			var k_eject: String = _get_compact_action_badge(&"cmd_ability_e", "E")
			btn.text = ("[%s] Eject Engineers (%d)" % [k_eject, count]) if not k_eject.is_empty() else ("Eject Engineers (%d)" % count)
			btn.disabled = count <= 0
			btn.modulate = Color(0.55, 0.92, 1.0, 1.0) if count > 0 else Color(0.6, 0.64, 0.7, 0.7)
		elif kind == "train":
			var slot: int = int(entry["slot"])
			var u_data: UnitData = entry["data"] as UnitData
			var b_info: Dictionary = building.get_unit_batch_info(u_data)
			var b_cnt: int = int(b_info["batch_count"])
			var short_name: String = _shorten_unit_name(u_data.display_name)
			var batch_tag: String = " x%d" % b_cnt if b_cnt > 1 else ""
			btn.text = "%s%s (%s | %dBW)" % [short_name, batch_tag, String(b_info["cost_label"]), int(b_info["bandwidth_cost"])]
			var can_train: bool = building.can_train_unit(slot)
			btn.disabled = false
			btn.modulate = Color(0.55, 1.0, 0.95, 1.0) if can_train else Color(0.56, 0.6, 0.66, 0.68)
		elif kind == "upgrade":
			var u_slot: int = int(entry["slot"])
			var upg: UpgradeData = entry["data"] as UpgradeData
			var short_upg: String = _shorten_unit_name(upg.display_name)
			var is_done: bool = _economy_manager != null and _economy_manager.has_upgrade(building.team, upg.upgrade_id)
			var is_prog: bool = _economy_manager != null and _economy_manager.is_upgrade_in_progress(building.team, upg.upgrade_id)
			if is_done:
				btn.text = "%s [DONE]" % short_upg
				btn.disabled = true
				btn.modulate = Color(0.36, 0.98, 0.64, 0.85)
			elif is_prog:
				btn.text = "%s [ACTIVE]" % short_upg
				btn.disabled = true
				btn.modulate = Color(1.0, 0.86, 0.42, 0.85)
			else:
				var can_res: bool = building.can_research_upgrade(u_slot)
				btn.text = "%s (%s)" % [short_upg, upg.get_cost_label()]
				btn.disabled = false
				btn.modulate = Color(1.0, 0.86, 0.42, 1.0) if can_res else Color(0.62, 0.60, 0.54, 0.68)
		elif kind == "salvage":
			var can_s: bool = building.can_salvage()
			if building.is_salvaging:
				var rem_s: float = maxf(0.0, Building.SALVAGE_DURATION - building.salvage_elapsed)
				btn.text = "[X] Cancel Salvage (%.1fs)" % rem_s
				btn.disabled = false
				btn.modulate = Color(1.0, 0.78, 0.24, 1.0)
			elif not can_s:
				btn.text = "[X] Salvage (Locked)"
				btn.disabled = true
				btn.modulate = Color(0.56, 0.58, 0.62, 0.58)
			else:
				btn.text = "[X] Salvage (50%)"
				btn.disabled = false
				btn.modulate = Color(1.0, 0.58, 0.36, 0.94)


func _on_inspected_entity_updated(_arg1: Variant = null, _arg2: Variant = null, _arg3: Variant = null) -> void:
	if _inspected_entity == null or not is_instance_valid(_inspected_entity):
		bottom_panel.visible = false
		return
	_render_inspected_entity(_inspected_entity, false)


func _on_inspected_building_construction_changed(building: Building, _progress: float, constructed: bool) -> void:
	if building == _inspected_entity and is_instance_valid(building):
		_render_inspected_entity(building, constructed)


func _on_inspected_entity_removed(_arg: Variant = null) -> void:
	_disconnect_inspected_signals()
	_inspected_entity = null
	_building_action_buttons.clear()
	if _active_subgroup_units.is_empty():
		bottom_panel.visible = false


func _connect_inspected_signals(entity: Node) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	if entity is ResourceNode:
		var res_node: ResourceNode = entity
		if not res_node.amount_changed.is_connected(_on_inspected_entity_updated):
			res_node.amount_changed.connect(_on_inspected_entity_updated)
		if not res_node.status_changed.is_connected(_on_inspected_entity_updated):
			res_node.status_changed.connect(_on_inspected_entity_updated)
		if not res_node.depleted.is_connected(_on_inspected_entity_removed):
			res_node.depleted.connect(_on_inspected_entity_removed)
	elif entity is Building:
		var b: Building = entity
		if not b.status_changed.is_connected(_on_inspected_entity_updated):
			b.status_changed.connect(_on_inspected_entity_updated)
		if not b.construction_progress_changed.is_connected(_on_inspected_building_construction_changed):
			b.construction_progress_changed.connect(_on_inspected_building_construction_changed)
		if not b.destroyed.is_connected(_on_inspected_entity_removed):
			b.destroyed.connect(_on_inspected_entity_removed)
	elif entity is Unit:
		var u: Unit = entity
		if not u.health_changed.is_connected(_on_inspected_entity_updated):
			u.health_changed.connect(_on_inspected_entity_updated)
		if not u.status_changed.is_connected(_on_inspected_entity_updated):
			u.status_changed.connect(_on_inspected_entity_updated)
		if not u.died.is_connected(_on_inspected_entity_removed):
			u.died.connect(_on_inspected_entity_removed)
	elif entity.is_in_group("destructible_barricades"):
		if entity.has_signal("health_changed") and not entity.is_connected("health_changed", _on_inspected_entity_updated):
			entity.connect("health_changed", _on_inspected_entity_updated)
		if entity.has_signal("status_changed") and not entity.is_connected("status_changed", _on_inspected_entity_updated):
			entity.connect("status_changed", _on_inspected_entity_updated)
		if entity.has_signal("destroyed") and not entity.is_connected("destroyed", _on_inspected_entity_removed):
			entity.connect("destroyed", _on_inspected_entity_removed)


func _disconnect_inspected_signals() -> void:
	if _inspected_entity == null or not is_instance_valid(_inspected_entity):
		return
	if _inspected_entity is ResourceNode:
		var res_node: ResourceNode = _inspected_entity
		if res_node.amount_changed.is_connected(_on_inspected_entity_updated):
			res_node.amount_changed.disconnect(_on_inspected_entity_updated)
		if res_node.status_changed.is_connected(_on_inspected_entity_updated):
			res_node.status_changed.disconnect(_on_inspected_entity_updated)
		if res_node.depleted.is_connected(_on_inspected_entity_removed):
			res_node.depleted.disconnect(_on_inspected_entity_removed)
	elif _inspected_entity is Building:
		var b: Building = _inspected_entity
		if b.status_changed.is_connected(_on_inspected_entity_updated):
			b.status_changed.disconnect(_on_inspected_entity_updated)
		if b.construction_progress_changed.is_connected(_on_inspected_building_construction_changed):
			b.construction_progress_changed.disconnect(_on_inspected_building_construction_changed)
		if b.destroyed.is_connected(_on_inspected_entity_removed):
			b.destroyed.disconnect(_on_inspected_entity_removed)
	elif _inspected_entity is Unit:
		var u: Unit = _inspected_entity
		if u.health_changed.is_connected(_on_inspected_entity_updated):
			u.health_changed.disconnect(_on_inspected_entity_updated)
		if u.status_changed.is_connected(_on_inspected_entity_updated):
			u.status_changed.disconnect(_on_inspected_entity_updated)
		if u.died.is_connected(_on_inspected_entity_removed):
			u.died.disconnect(_on_inspected_entity_removed)
	elif _inspected_entity.is_in_group("destructible_barricades"):
		if _inspected_entity.has_signal("health_changed") and _inspected_entity.is_connected("health_changed", _on_inspected_entity_updated):
			_inspected_entity.disconnect("health_changed", _on_inspected_entity_updated)
		if _inspected_entity.has_signal("status_changed") and _inspected_entity.is_connected("status_changed", _on_inspected_entity_updated):
			_inspected_entity.disconnect("status_changed", _on_inspected_entity_updated)
		if _inspected_entity.has_signal("destroyed") and _inspected_entity.is_connected("destroyed", _on_inspected_entity_removed):
			_inspected_entity.disconnect("destroyed", _on_inspected_entity_removed)


func _on_ability_targeting_changed(active_ability: AbilityData) -> void:
	_targeting_ability = active_ability
	_refresh_all_ability_states()


func _on_unit_health_changed(_unit: Unit, _current_hp: float, _max_hp: float) -> void:
	_refresh_selected_units_display()


func _on_unit_ability_cooldown_updated(ability_id: StringName, _remaining: float, _duration: float) -> void:
	_refresh_single_ability_button(ability_id)


func _on_unit_cargo_changed(_unit: Unit, _resource_type: StringName, _amount: int) -> void:
	_refresh_selected_units_display()


func _on_unit_status_changed(_unit: Unit) -> void:
	_refresh_selected_units_display()


func _on_unit_stance_changed(_unit: Unit, _new_stance: Unit.Stance) -> void:
	_refresh_stance_button()


func _refresh_stance_button() -> void:
	if btn_cmd_hold == null or _selection_controller == null:
		return
	var living_count: int = 0
	var hold_count: int = 0
	for item: Variant in _selection_controller.selected_units:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var u: Unit = item
		if u.is_dead or u.is_staffed:
			continue
		living_count += 1
		if u.stance == Unit.Stance.HOLD_POSITION:
			hold_count += 1
	var k_hold: String = _get_compact_action_badge(&"cmd_hold", "H")
	var hold_suffix: String = (" (%s)" % k_hold) if not k_hold.is_empty() else ""
	if living_count > 0 and hold_count == living_count:
		btn_cmd_hold.text = "Hold: ON%s" % hold_suffix
		btn_cmd_hold.modulate = Color(1.0, 0.84, 0.32, 1.0)
	elif hold_count > 0:
		btn_cmd_hold.text = "Hold*%s" % hold_suffix
		btn_cmd_hold.modulate = Color(1.0, 0.90, 0.56, 1.0)
	else:
		btn_cmd_hold.text = "Hold%s" % hold_suffix
		btn_cmd_hold.modulate = Color.WHITE


func _refresh_selected_units_display() -> void:
	if _selection_controller == null:
		return
	var active_group: Dictionary = _selection_controller.get_active_subgroup()
	if active_group.is_empty():
		return
	if _selection_controller.selected_units.size() == 1 and is_instance_valid(_selection_controller.selected_units[0]):
		var lead_info: Dictionary = InspectionHelper.get_inspection_data(_selection_controller.selected_units[0])
		_apply_left_column(lead_info)
		_rebuild_telemetry_grid(lead_info["stats"])
	else:
		_refresh_squad_left_column(active_group)
		_rebuild_unit_badges(_active_subgroup_units)
	_refresh_stance_button()


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
		if not unit.status_changed.is_connected(_on_unit_status_changed):
			unit.status_changed.connect(_on_unit_status_changed)
		if not unit.stance_changed.is_connected(_on_unit_stance_changed):
			unit.stance_changed.connect(_on_unit_stance_changed)
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
			if unit.status_changed.is_connected(_on_unit_status_changed):
				unit.status_changed.disconnect(_on_unit_status_changed)
			if unit.stance_changed.is_connected(_on_unit_stance_changed):
				unit.stance_changed.disconnect(_on_unit_stance_changed)
	_connected_units.clear()


func _rebuild_subgroup_tabs(subgroups: Array[Dictionary], active_index: int) -> void:
	for child: Node in subgroup_tabs_row.get_children():
		child.queue_free()

	for i: int in range(subgroups.size()):
		var group: Dictionary = subgroups[i]
		var group_units: Array[Unit] = group["units"]
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 11)
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
		var k_tab: String = _get_compact_action_badge(&"ui_cycle_subgroup", "Tab")
		if not k_tab.is_empty():
			var hint: Label = Label.new()
			hint.text = " [%s]" % k_tab
			hint.add_theme_font_size_override("font_size", 11)
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
		var max_hp: float = maxf(1.0, unit.get_max_hp())
		var pct: int = int(round((unit.current_hp / max_hp) * 100.0))
		badge.text = "[%d%%]" % pct
		badge.add_theme_font_size_override("font_size", 11)
		badge.modulate = Color(0.32, 0.96, 0.76, 1.0) if pct > 50 else Color(1.0, 0.56, 0.28, 1.0)
		unit_badges_grid.add_child(badge)

	if units.size() > max_badges:
		var more: Label = Label.new()
		more.text = "+%d" % (units.size() - max_badges)
		more.add_theme_font_size_override("font_size", 11)
		unit_badges_grid.add_child(more)


func _rebuild_ability_buttons(active_group: Dictionary) -> void:
	for child: Node in ability_row.get_children():
		child.queue_free()
	_ability_buttons.clear()
	_active_abilities.clear()

	var data: UnitData = active_group.get("data", null) as UnitData
	if data == null:
		return

	var valid_count: int = 0
	for ab: AbilityData in data.abilities:
		if ab != null:
			valid_count += 1
	var use_grid_4x2: bool = valid_count > 4
	ability_row.columns = 4 if use_grid_4x2 else 2
	var ab_min_size: Vector2 = Vector2(114.0, 27.0) if use_grid_4x2 else Vector2(214.0, 29.0)
	var ab_font_size: int = 10 if use_grid_4x2 else 11

	for ability: AbilityData in data.abilities:
		if ability == null:
			continue
		_active_abilities.append(ability)
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = ab_min_size
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", ab_font_size)
		var captured_ability: AbilityData = ability
		btn.pressed.connect(func() -> void:
			if _selection_controller != null:
				_selection_controller.request_ability_slot(captured_ability, Input.is_key_pressed(KEY_SHIFT))
		)
		btn.tooltip_text = ""
		btn.mouse_entered.connect(func() -> void:
			if command_tooltip != null:
				var dynamic_meta: String = _build_ability_tooltip_meta(captured_ability)
				var hk_full: String = _get_ability_hotkey_display(captured_ability.hotkey_label, false)
				command_tooltip.show_tooltip(captured_ability.display_name, hk_full, dynamic_meta, captured_ability.description)
		)
		btn.mouse_exited.connect(func() -> void:
			if command_tooltip != null:
				command_tooltip.hide_tooltip()
		)
		ability_row.add_child(btn)
		_ability_buttons[ability.ability_id] = {
			"button": btn,
			"ability": ability,
		}


func _build_ability_tooltip_meta(ability: AbilityData) -> String:
	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT and ability.building_to_build != null:
		var b: BuildingData = ability.building_to_build
		var parts: PackedStringArray = PackedStringArray()
		parts.append("Cost: %s" % b.get_cost_label())
		parts.append("Build: %.1fs" % b.build_time)
		if b.bandwidth_provided > 0:
			parts.append("+%d BW" % b.bandwidth_provided)
		if b.requires_vent:
			parts.append("Requires: Compute Vent")
		if b.required_building_id != &"":
			var req_name: String = String(b.required_building_id).replace("_", " ").capitalize()
			var has_req: bool = _economy_manager != null and _economy_manager.has_constructed_building(Unit.Team.PLAYER, b.required_building_id)
			parts.append(("Requires: %s [OK]" % req_name) if has_req else ("LOCKED — Requires: %s" % req_name))
		return "  •  ".join(parts)

	var ab_parts: PackedStringArray = PackedStringArray()
	if ability.cooldown_duration > 0.0:
		ab_parts.append("Cooldown: %.1fs" % ability.cooldown_duration)
	if ability.cast_range > 0.0:
		ab_parts.append("Range: %d px" % int(round(ability.cast_range)))
	if ability.aoe_radius > 0.0 and (ability.target_type == AbilityData.TargetType.POINT_AOE or ability.ability_id == &"static_pulse" or ability.ability_id == &"seismic_slam"):
		ab_parts.append("Radius: %d px" % int(round(ability.aoe_radius)))
	if ability.effect_duration > 0.0:
		ab_parts.append("Duration: %.1fs" % ability.effect_duration)
	return "  •  ".join(ab_parts)


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
	var hk_compact: String = _get_ability_hotkey_display(ability.hotkey_label, true)
	var hk_prefix: String = ("[%s] " % hk_compact) if not hk_compact.is_empty() else ""

	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT and ability.building_to_build != null:
		var b_data: BuildingData = ability.building_to_build
		var cost_text: String = b_data.get_cost_label()
		var short_b: String = ability.display_name.replace("Silica Condenser", "Condenser").replace("Wetware Mainframe", "Mainframe").replace("Synapse Pylon", "Pylon").replace("Calibration Foundry", "Foundry").replace("Synthetics Fabricator", "Fabricator")
		var can_afford: bool = true
		var has_prereq: bool = true
		if _economy_manager == null:
			_connect_economy_manager()
		if _economy_manager != null:
			can_afford = _economy_manager.can_afford(Unit.Team.PLAYER, b_data.get_cost_dict())
			if b_data.required_building_id != &"":
				has_prereq = _economy_manager.has_constructed_building(Unit.Team.PLAYER, b_data.required_building_id)

		if not has_prereq:
			btn.disabled = false
			btn.text = "%s%s (LOCK)" % [hk_prefix, short_b]
			btn.modulate = Color(0.64, 0.44, 0.44, 0.68)
		elif is_targeting:
			btn.disabled = false
			btn.text = "%s%s*" % [hk_prefix, short_b]
			btn.modulate = Color(1.0, 0.85, 0.32, 1.0)
		elif can_afford:
			btn.disabled = false
			btn.text = "%s%s (%s)" % [hk_prefix, short_b, cost_text]
			btn.modulate = Color(0.55, 1.0, 0.95, 1.0)
		else:
			btn.disabled = false
			btn.text = "%s%s (%s)" % [hk_prefix, short_b, cost_text]
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
			btn.text = "%s%s (TARGET)" % [hk_prefix, ability.display_name]
			btn.modulate = Color(1.0, 0.85, 0.32, 1.0)
		else:
			btn.text = "%s%s" % [hk_prefix, ability.display_name]
			btn.modulate = Color(0.55, 1.0, 0.95, 1.0)
	else:
		var display_cd: float = 0.0 if min_cd == INF else min_cd
		btn.disabled = true
		btn.text = "%s%s (%.1fs)" % [hk_prefix, ability.display_name, display_cd]
		btn.modulate = Color(0.6, 0.64, 0.7, 0.75)
