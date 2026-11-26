class_name SelectionHUD
extends Control

const COMMAND_ICON_BUTTON_SCRIPT: GDScript = preload("res://ui/hud/command_icon_button.gd")

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
@onready var command_grid: GridContainer = %CommandGrid
@onready var read_only_label: Label = %ReadOnlyLabel

var _selection_controller: SelectionController = null
var _economy_manager: EconomyManager = null
var _connected_units: Array[Unit] = []
var _inspected_entity: Node = null
var _selected_buildings: Array[Building] = []
var _connected_buildings: Array[Building] = []
var _building_subgroups: Array[Dictionary] = []
var _active_building_subgroup_index: int = 0
var _active_subgroup_units: Array[Unit] = []
var _active_abilities: Array[AbilityData] = []
var _unit_cmd_tiles: Dictionary = {}
var _ability_buttons: Dictionary = {}
var _building_action_buttons: Array[Dictionary] = []
var _targeting_ability: AbilityData = null
var _patrol_targeting: bool = false
var _amove_targeting: bool = false
var _overclock_targeting: bool = false
var _hp_fill_style: StyleBoxFlat = null
var _shield_fill_style: StyleBoxFlat = null
var _gauge_fill_style: StyleBoxFlat = null
var _prod_fill_style: StyleBoxFlat = null
var _shield_label: Label = null
var _shield_bar: ProgressBar = null

var _active_hud_faction_id: StringName = &""
var _active_hud_accent: Color = Color(0.20, 0.96, 0.86, 1.0)
var _active_hud_primary: Color = Color(0.90, 0.96, 0.98, 1.0)
var _faction_frame_overlay: Control = null


func _ready() -> void:
	_setup_dynamic_bar_styles()
	_selection_controller = get_node_or_null(selection_controller_path) as SelectionController
	if _selection_controller != null:
		_selection_controller.selection_changed.connect(_on_selection_changed)
		_selection_controller.inspection_changed.connect(_on_inspection_changed)
		_selection_controller.buildings_selection_changed.connect(_on_buildings_selection_changed)
		if _selection_controller.has_signal("building_subgroups_changed"):
			_selection_controller.building_subgroups_changed.connect(_on_building_subgroups_changed)
		_selection_controller.control_groups_changed.connect(_on_control_groups_changed)
		_selection_controller.ability_targeting_changed.connect(_on_ability_targeting_changed)
		_selection_controller.patrol_targeting_changed.connect(_on_patrol_targeting_changed)
		if _selection_controller.has_signal("attack_move_targeting_changed"):
			_selection_controller.attack_move_targeting_changed.connect(_on_attack_move_targeting_changed)
		if _selection_controller.has_signal("overclock_targeting_changed"):
			_selection_controller.overclock_targeting_changed.connect(_on_overclock_targeting_changed)
		_on_control_groups_changed(_selection_controller.get_control_groups_summary())

	if SettingsManager != null and not SettingsManager.keybind_changed.is_connected(_on_keybind_changed):
		SettingsManager.keybind_changed.connect(_on_keybind_changed)
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_display_settings_changed):
		SettingsManager.settings_changed.connect(_on_display_settings_changed)
	if TeamManager != null and TeamManager.has_signal("teams_reconfigured") and not TeamManager.teams_reconfigured.is_connected(_on_teams_reconfigured):
		TeamManager.teams_reconfigured.connect(_on_teams_reconfigured)

	_connect_economy_manager()
	_apply_faction_hud_theme(true)
	bottom_panel.visible = false
	call_deferred("_adjust_layout_for_minimap")
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_adjust_layout_for_minimap):
		get_viewport().size_changed.connect(_adjust_layout_for_minimap)


func _on_teams_reconfigured() -> void:
	_apply_faction_hud_theme(true)


func _adjust_layout_for_minimap() -> void:
	if not is_inside_tree():
		return
	var bottom_stack: Control = get_node_or_null("BottomStack") as Control
	if bottom_stack == null:
		return
	var vp_width: float = get_viewport_rect().size.x
	var minimap_node: Node = get_tree().get_first_node_in_group("tactical_minimap")
	var minimap_clearance: float = 248.0 if minimap_node != null else 12.0
	var desired_half_w: float = 370.0
	var center_x: float = vp_width * 0.5
	if center_x - desired_half_w < minimap_clearance:
		var avail_w: float = clampf(vp_width - minimap_clearance - 12.0, 680.0, 748.0)
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
	if hp_box != null and unit_hp_label != null and unit_hp_bar != null and _shield_bar == null:
		var header_row: HBoxContainer = HBoxContainer.new()
		header_row.name = "HPShieldHeaderRow"
		header_row.add_theme_constant_override("separation", 4)
		hp_box.add_child(header_row)
		hp_box.move_child(header_row, 0)
		unit_hp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_hp_label.reparent(header_row, false)

		_shield_label = Label.new()
		_shield_label.name = "UnitShieldLabel"
		_shield_label.add_theme_font_size_override("font_size", 9)
		_shield_label.add_theme_color_override("font_color", Color(0.220, 0.741, 0.973, 1.0))
		_shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_shield_label.visible = false
		header_row.add_child(_shield_label)

		_shield_bar = ProgressBar.new()
		_shield_bar.name = "UnitShieldBar"
		_shield_bar.custom_minimum_size = Vector2(0, 4)
		_shield_bar.show_percentage = false
		_shield_bar.visible = false
		_shield_fill_style = StyleBoxFlat.new()
		_shield_fill_style.bg_color = Color(0.220, 0.741, 0.973, 1.0)
		_shield_fill_style.set_corner_radius_all(2)
		_shield_bar.add_theme_stylebox_override("fill", _shield_fill_style)
		hp_box.add_child(_shield_bar)
		hp_box.move_child(_shield_bar, 1)
	if primary_gauge_bar != null:
		_gauge_fill_style = StyleBoxFlat.new()
		_gauge_fill_style.bg_color = Color(0.32, 0.88, 1.0, 1.0)
		_gauge_fill_style.set_corner_radius_all(2)
		primary_gauge_bar.add_theme_stylebox_override("fill", _gauge_fill_style)
	if production_bar != null:
		_prod_fill_style = StyleBoxFlat.new()
		_prod_fill_style.bg_color = Color(0.24, 0.96, 0.86, 1.0)
		_prod_fill_style.set_corner_radius_all(2)
		production_bar.add_theme_stylebox_override("fill", _prod_fill_style)


func _resolve_active_hud_faction_id() -> StringName:
	if TeamManager == null:
		return &"genesis_v2"
	var is_spec: bool = TeamManager.has_method("is_spectator_mode") and TeamManager.is_spectator_mode()
	if not is_spec:
		return FactionHudTheme.resolve_local_faction_id()
	var inspect_team: int = -1
	if not _active_subgroup_units.is_empty() and is_instance_valid(_active_subgroup_units[0]):
		inspect_team = int(_active_subgroup_units[0].team)
	elif _inspected_entity != null and is_instance_valid(_inspected_entity):
		if _inspected_entity is Building:
			inspect_team = int((_inspected_entity as Building).team)
		elif _inspected_entity is Unit:
			inspect_team = int((_inspected_entity as Unit).team)
	if inspect_team >= 0 and TeamManager.has_method("get_team_faction"):
		var sfid: StringName = TeamManager.get_team_faction(inspect_team)
		if sfid != &"":
			return sfid
	return &"spectator"


func _apply_faction_hud_theme(force: bool = false) -> void:
	var fid: StringName = _resolve_active_hud_faction_id()
	if not force and fid == _active_hud_faction_id:
		return
	_active_hud_faction_id = fid

	var pal: Dictionary = FactionHudTheme.get_palette(fid)
	_active_hud_accent = pal["accent"] as Color
	_active_hud_primary = pal["primary"] as Color

	if bottom_panel != null:
		bottom_panel.add_theme_stylebox_override("panel", FactionHudTheme.make_panel_style(fid, false))
		_faction_frame_overlay = FactionHudTheme.attach_frame_overlay(bottom_panel, fid, &"selection")

	if command_grid != null:
		for child: Node in command_grid.get_children():
			if child is CommandIconButton:
				(child as CommandIconButton).apply_faction_theme(_active_hud_faction_id, _active_hud_accent, _active_hud_primary)


func _get_compact_action_badge(action_name: StringName, fallback: String) -> String:
	if SettingsManager == null:
		return fallback
	return SettingsManager.get_action_short_label(action_name)


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
		return SettingsManager.get_action_short_label(act) if compact else SettingsManager.get_action_display_label(act, false)
	return hotkey_label


func _on_keybind_changed(_action_name: StringName) -> void:
	_refresh_dynamic_command_labels()
	_refresh_stance_button()
	_refresh_deploy_button()
	if not _active_abilities.is_empty():
		_refresh_all_ability_states()
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_refresh_building_action_buttons(_inspected_entity as Building)
		if _building_subgroups.size() > 1:
			_rebuild_building_subgroup_tabs(_building_subgroups, _active_building_subgroup_index)
	if _selection_controller != null and _selection_controller.subgroups.size() > 1:
		_rebuild_subgroup_tabs(_selection_controller.subgroups, _selection_controller.active_subgroup_index)


func _on_display_settings_changed(category: StringName) -> void:
	if category == &"display" or category == &"all":
		call_deferred("_adjust_layout_for_minimap")
	if category == &"controls" or category == &"gameplay" or category == &"all":
		_on_keybind_changed(&"")


func _refresh_dynamic_command_labels() -> void:
	var k_stop: String = _get_compact_action_badge(&"cmd_stop", "S")
	var k_patrol: String = _get_compact_action_badge(&"cmd_patrol", "P")
	var k_amove: String = _get_compact_action_badge(&"cmd_attack_move", "A")
	var btn_stop: CommandIconButton = _unit_cmd_tiles.get(&"stop", null) as CommandIconButton
	if btn_stop != null and is_instance_valid(btn_stop):
		btn_stop.hotkey_text = k_stop
		btn_stop.queue_redraw()
	var btn_patrol: CommandIconButton = _unit_cmd_tiles.get(&"patrol", null) as CommandIconButton
	if btn_patrol != null and is_instance_valid(btn_patrol):
		btn_patrol.hotkey_text = k_patrol
		btn_patrol.set_tile_state("TGT" if _patrol_targeting else "", Color(1.0, 0.86, 0.30, 1.0), _patrol_targeting)
	var btn_amove: CommandIconButton = _unit_cmd_tiles.get(&"amove", null) as CommandIconButton
	if btn_amove != null and is_instance_valid(btn_amove):
		btn_amove.hotkey_text = k_amove
		btn_amove.set_tile_state("TGT" if _amove_targeting else "", Color(1.0, 0.36, 0.44, 1.0), _amove_targeting)


func _on_patrol_targeting_changed(active: bool) -> void:
	_patrol_targeting = active
	_refresh_dynamic_command_labels()


func _on_attack_move_targeting_changed(active: bool) -> void:
	_amove_targeting = active
	_refresh_dynamic_command_labels()


func _on_overclock_targeting_changed(active: bool) -> void:
	_overclock_targeting = active
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_refresh_building_action_buttons(_inspected_entity as Building)


func _on_building_subgroups_changed(b_subgroups: Array[Dictionary], active_index: int) -> void:
	_building_subgroups = b_subgroups
	_active_building_subgroup_index = active_index
	if _selection_controller != null and not _selected_buildings.is_empty():
		var active_b: Array[Building] = _selection_controller.get_active_building_subgroup_buildings()
		if not active_b.is_empty() and is_instance_valid(active_b[0]):
			if _inspected_entity != active_b[0]:
				_disconnect_inspected_signals()
				_inspected_entity = active_b[0]
				_connect_inspected_signals(_inspected_entity)
			_render_inspected_entity(_inspected_entity, true)


func _on_buildings_selection_changed(buildings: Array[Building]) -> void:
	_disconnect_multi_building_signals()
	_selected_buildings = buildings.duplicate()
	if _selection_controller != null:
		_building_subgroups = _selection_controller.building_subgroups
		_active_building_subgroup_index = _selection_controller.active_building_subgroup_index
	else:
		_building_subgroups = []
		_active_building_subgroup_index = 0
	for b: Building in _selected_buildings:
		if is_instance_valid(b) and not b.is_destroyed:
			if not b.status_changed.is_connected(_on_inspected_entity_updated):
				b.status_changed.connect(_on_inspected_entity_updated)
			_connected_buildings.append(b)
	var lead_b: Building = null
	if _selection_controller != null:
		var active_b: Array[Building] = _selection_controller.get_active_building_subgroup_buildings()
		if not active_b.is_empty() and is_instance_valid(active_b[0]):
			lead_b = active_b[0]
	if lead_b == null and not _selected_buildings.is_empty() and is_instance_valid(_selected_buildings[0]):
		lead_b = _selected_buildings[0]
	if lead_b != null:
		if _inspected_entity != lead_b:
			_disconnect_inspected_signals()
			_inspected_entity = lead_b
			_connect_inspected_signals(_inspected_entity)
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


func _is_local_human_team(team: int) -> bool:
	if TeamManager != null:
		var local_t: int = TeamManager.get_local_human_team()
		return local_t >= 0 and team == local_t
	return team == int(Unit.Team.PLAYER)


func _on_economy_updated(team: int, _resources: Dictionary) -> void:
	if not _is_local_human_team(team):
		return
	if not _active_abilities.is_empty():
		_refresh_all_ability_states()
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_refresh_building_action_buttons(_inspected_entity as Building)


func _on_bandwidth_updated(team: int, _used: int, _cap: int) -> void:
	if not _is_local_human_team(team):
		return
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_render_inspected_entity(_inspected_entity, false)


func _on_tech_updated(team: int) -> void:
	if not _is_local_human_team(team):
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
		pill.add_theme_font_size_override("font_size", 10)
		pill.text = ("[%d] %s ×%d" % [num, _shorten_unit_name(label_str), count]) if is_building else ("[%d] ×%d" % [num, count])
		pill.modulate = _active_hud_accent if is_active else (Color(0.96, 0.84, 0.44, 0.92) if is_building else Color(0.76, 0.88, 0.94, 0.90))
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
			"Click or press %d to select. Double-tap to center. Ctrl+%d assign, Shift+%d add, Alt+%d steal." % [num, num, num, num]
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

	_apply_faction_hud_theme(false)
	_connect_unit_signals(_active_subgroup_units)

	var is_single_unit: bool = (selected_units.size() == 1 and is_instance_valid(selected_units[0]))
	subgroup_tabs_row.visible = not is_single_unit
	unit_badges_grid.visible = not is_single_unit
	telemetry_grid.visible = is_single_unit
	production_queue_box.visible = false

	command_grid.visible = true
	read_only_label.visible = false

	if is_single_unit:
		var lead_data: Dictionary = InspectionHelper.get_inspection_data(selected_units[0])
		_apply_left_column(lead_data)
		_rebuild_telemetry_grid(lead_data["stats"])
	else:
		_refresh_squad_left_column(active_group)
		_rebuild_subgroup_tabs(subgroups, safe_idx)
		_rebuild_unit_badges(_active_subgroup_units)

	_rebuild_unit_command_card(active_group)
	_refresh_all_ability_states()
	_refresh_dynamic_command_labels()
	_refresh_stance_button()
	_refresh_deploy_button()
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

	_apply_faction_hud_theme(false)

	var info: Dictionary = InspectionHelper.get_inspection_data(entity)
	var show_building_tabs: bool = false
	if entity is Building and _selected_buildings.size() > 1:
		var lead_b: Building = entity as Building
		if _selection_controller != null:
			_building_subgroups = _selection_controller.building_subgroups
			_active_building_subgroup_index = _selection_controller.active_building_subgroup_index
		if _building_subgroups.size() > 1:
			show_building_tabs = true
			var safe_b_idx: int = clampi(_active_building_subgroup_index, 0, _building_subgroups.size() - 1)
			var active_grp: Dictionary = _building_subgroups[safe_b_idx]
			var grp_bldgs: Array = active_grp.get("buildings", [])
			var active_cnt: int = maxi(1, grp_bldgs.size())
			info["title"] = "%s  x%d" % [lead_b.display_name, active_cnt]
			info["subtitle"] = "SUBGROUP %d/%d • %d BUILDINGS SELECTED" % [safe_b_idx + 1, _building_subgroups.size(), _selected_buildings.size()]
		else:
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
			info["subtitle"] = "MULTI-PRODUCTION (%d QUEUED)" % total_queued
	bottom_panel.visible = true
	subgroup_tabs_row.visible = show_building_tabs
	if show_building_tabs:
		_rebuild_building_subgroup_tabs(_building_subgroups, _active_building_subgroup_index)
	unit_badges_grid.visible = false
	telemetry_grid.visible = true

	_unit_cmd_tiles.clear()
	_ability_buttons.clear()
	_active_abilities.clear()

	_apply_left_column(info)
	_rebuild_telemetry_grid(info["stats"])
	_refresh_production_queue_ui(entity)

	var post_match_inspect: bool = _is_post_match_inspection()
	var is_commandable: bool = bool(info.get("is_commandable", false)) and not post_match_inspect
	if is_commandable and entity is Building:
		var building: Building = entity as Building
		read_only_label.visible = false
		command_grid.visible = true
		if rebuild_actions:
			_rebuild_building_action_buttons(building)
		else:
			_refresh_building_action_buttons(building)
	else:
		if rebuild_actions:
			_clear_command_grid()
		command_grid.visible = false
		read_only_label.visible = true
		read_only_label.text = "POST-MATCH INSPECTION — READ-ONLY" if post_match_inspect else String(info.get("readonly_label", "READ-ONLY TELEMETRY"))


func _is_post_match_inspection() -> bool:
	if not is_inside_tree():
		return false
	var mm: Node = get_tree().get_first_node_in_group("match_manager")
	return mm != null and is_instance_valid(mm) and bool(mm.get("is_inspecting_post_match"))


func _refresh_production_queue_ui(entity: Node) -> void:
	if production_queue_box == null:
		return
	if not (entity is Building) or not is_instance_valid(entity):
		production_queue_box.visible = false
		return
	var building: Building = entity as Building
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
		production_label.text = "Research %s (%d%%)" % [_shorten_unit_name(active_name), pct]
	elif batch_cnt > 1:
		production_label.text = "Cloning %s x%d (%d%%)" % [_shorten_unit_name(active_name), batch_cnt, pct]
	else:
		production_label.text = "Training %s (%d%%)" % [_shorten_unit_name(active_name), pct]
	if building.is_overclocked():
		production_label.text += " [%.1fx]" % building.overclock_speed_mult
		if _prod_fill_style != null:
			_prod_fill_style.bg_color = Color(1.0, 0.624, 0.110, 1.0)
	elif _prod_fill_style != null:
		_prod_fill_style.bg_color = _active_hud_accent
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
		slot_btn.add_theme_font_size_override("font_size", 9)
		var captured_b: Building = building
		var captured_idx: int = i
		slot_btn.pressed.connect(func() -> void:
			if _is_post_match_inspection():
				return
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
	return full_name.replace("Worker Drone", "Worker").replace("Systems Engineer", "Engineer").replace("Silica Harvester", "Harvester").replace("Recon Scout", "Scout").replace("Test Unit", "Infantry").replace("Clone Trooper", "Clone").replace("Signal Jammer", "Jammer").replace("Goliath Frame", "Goliath").replace("Chrysalis Mortar", "Mortar").replace("Batch Efficiency", "Batch Eff.").replace("Adrenal Potency", "Adrenal Pot.").replace("Compute Overdrive", "Overdrive").replace("Anvil Siege-Walker", "Anvil").replace("Monolith Dreadnought", "Dreadnought").replace("Null-Grid Projector", "Null-Grid").replace("Hardened Plating", "Plating").replace("Rapid Capacitors", "Capacitors").replace("Hyper-Velocity Rails", "HV Rails").replace("Bulwark Automaton", "Bulwark").replace("Picket Drone", "Picket").replace("Rail-Sentinel", "Rail-Snt").replace("Aegis Relay", "Aegis").replace("Servo-Drone", "Servo").replace("Ore Crawler", "Crawler")


func _build_unit_class_traits_label(u_data: UnitData) -> String:
	if u_data == null:
		return ""
	var tags: PackedStringArray = PackedStringArray()
	if u_data.unit_type_id == &"goliath_frame" or u_data.unit_type_id == &"arc_lancer" or u_data.unit_type_id == &"monolith_dreadnought" or u_data.unit_type_id == &"anvil_siege_walker":
		tags.append("Heavy Chassis")
	elif u_data.is_armored:
		tags.append("Armored")
	else:
		tags.append("Light")

	if u_data.can_deploy:
		tags.append("Deployable")
	if u_data.max_shield > 0.0:
		tags.append("Shielded")
	if u_data.bonus_vs_armored > 0.0:
		tags.append("+vs Armored")
	if u_data.aoe_attack_radius > 0.0 or u_data.deployed_aoe_radius > 0.0:
		tags.append("AoE Splash")
	if u_data.line_pierce_width > 0.0:
		tags.append("Line Pierce")
	if u_data.min_attack_range > 0.0 or u_data.deployed_min_attack_range > 0.0:
		tags.append("Min Range")
	if u_data.heal_aura_rate > 0.0:
		tags.append("Heal Aura")
	if u_data.ignore_friendly_unit_collision:
		tags.append("Colossus Stride")
	return " • ".join(tags)


func _apply_left_column(info: Dictionary) -> void:
	var accent: Color = info.get("accent_color", _active_hud_accent) as Color
	portrait_swatch.color = accent
	unit_name_label.text = String(info.get("title", "Entity"))
	entity_subtitle_label.text = String(info.get("subtitle", "TELEMETRY"))
	entity_subtitle_label.modulate = accent

	var show_hp: bool = bool(info.get("show_hp_bar", false))
	hp_box.visible = show_hp
	if show_hp:
		var cur_hp: float = float(info.get("hp_current", 0.0))
		var max_hp: float = maxf(1.0, float(info.get("hp_max", 1.0)))
		unit_hp_label.text = "HP %s/%s" % [
			InspectionHelper.format_number(int(round(cur_hp))),
			InspectionHelper.format_number(int(round(max_hp))),
		]
		unit_hp_bar.max_value = max_hp
		unit_hp_bar.value = clampf(cur_hp, 0.0, max_hp)
		var is_enemy: bool = (info.get("affiliation", &"neutral") == &"enemy")
		if _hp_fill_style != null:
			_hp_fill_style.bg_color = Color(0.96, 0.34, 0.26, 1.0) if is_enemy else Color(0.24, 0.94, 0.74, 1.0)

		var show_shd: bool = bool(info.get("show_shield_bar", false)) and float(info.get("shield_max", 0.0)) > 0.0
		if _shield_label != null and _shield_bar != null:
			_shield_label.visible = show_shd
			_shield_bar.visible = show_shd
			if show_shd:
				var cur_shd: float = float(info.get("shield_current", 0.0))
				var max_shd: float = maxf(1.0, float(info.get("shield_max", 1.0)))
				_shield_label.text = "SH %s/%s" % [
					InspectionHelper.format_number(int(round(cur_shd))),
					InspectionHelper.format_number(int(round(max_shd))),
				]
				_shield_bar.max_value = max_shd
				_shield_bar.value = clampf(cur_shd, 0.0, max_shd)
	elif _shield_label != null and _shield_bar != null:
		_shield_label.visible = false
		_shield_bar.visible = false

	var show_primary: bool = bool(info.get("show_primary_bar", false))
	primary_gauge_box.visible = show_primary
	if show_primary:
		primary_gauge_label.text = String(info.get("primary_bar_label", ""))
		primary_gauge_bar.max_value = maxf(1.0, float(info.get("primary_bar_max", 100.0)))
		primary_gauge_bar.value = clampf(float(info.get("primary_bar_value", 0.0)), 0.0, primary_gauge_bar.max_value)
		if _gauge_fill_style != null:
			_gauge_fill_style.bg_color = info.get("primary_bar_color", accent) as Color


func _refresh_squad_left_column(active_group: Dictionary) -> void:
	var units: Array[Unit] = active_group.get("units", [])
	if units.is_empty() or not is_instance_valid(units[0]):
		return
	var lead_info: Dictionary = InspectionHelper.get_inspection_data(units[0])
	lead_info["title"] = "%s x%d" % [String(active_group.get("display_name", "Unit")), units.size()]
	_apply_left_column(lead_info)


func _rebuild_telemetry_grid(stats: Variant) -> void:
	for child: Node in telemetry_grid.get_children():
		child.queue_free()

	if not (stats is Array):
		return
	for item: Variant in stats:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item as Dictionary
		var cell: HBoxContainer = HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 4)

		var k_label: Label = Label.new()
		k_label.text = "%s:" % String(entry.get("label", ""))
		k_label.add_theme_font_size_override("font_size", 10)
		k_label.add_theme_color_override("font_color", Color(0.58, 0.72, 0.80, 0.90) if _active_hud_faction_id != &"monolith_os" else Color(0.76, 0.75, 0.72, 0.90))
		cell.add_child(k_label)

		var v_label: Label = Label.new()
		v_label.text = String(entry.get("value", ""))
		v_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v_label.clip_text = true
		v_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v_label.add_theme_font_size_override("font_size", 11)
		var val_col: Color = entry.get("color", Color(0.94, 0.98, 1.0, 1.0)) as Color
		v_label.add_theme_color_override("font_color", val_col)
		cell.add_child(v_label)

		telemetry_grid.add_child(cell)


# =============================================================================
# COMPACT 4x3 ICON COMMAND CARD HELPERS
# =============================================================================

func _clear_command_grid() -> void:
	for child: Node in command_grid.get_children():
		child.queue_free()
	_building_action_buttons.clear()
	_unit_cmd_tiles.clear()
	_ability_buttons.clear()
	_active_abilities.clear()


func _new_icon_tile() -> CommandIconButton:
	var tile: CommandIconButton = COMMAND_ICON_BUTTON_SCRIPT.new() as CommandIconButton
	tile.apply_faction_theme(_active_hud_faction_id, _active_hud_accent, _active_hud_primary)
	return tile


func _populate_12_slot_grid(slots: Array) -> void:
	command_grid.columns = 4
	for i: int in range(12):
		var item: Variant = slots[i] if i < slots.size() else null
		if item is CommandIconButton:
			command_grid.add_child(item as CommandIconButton)
		else:
			var empty_tile: CommandIconButton = _new_icon_tile()
			empty_tile.setup_empty_socket()
			command_grid.add_child(empty_tile)


func _get_unit_icon_accent(u_data: UnitData) -> Color:
	if u_data == null:
		return _active_hud_accent
	if u_data.can_staff_compute:
		return Color(0.28, 0.86, 1.0, 1.0)
	if u_data.can_gather and u_data.auto_gather_on_spawn:
		return Color(1.0, 0.76, 0.24, 1.0)
	if u_data.has_tag(&"support") or u_data.heal_aura_rate > 0.0:
		return Color(0.24, 0.96, 0.72, 1.0) if _active_hud_faction_id != &"monolith_os" else Color(0.220, 0.741, 0.973, 1.0)
	if u_data.has_tag(&"heavy") or u_data.has_tag(&"siege"):
		return Color(1.0, 0.64, 0.16, 1.0)
	return _active_hud_accent


func _get_building_icon_accent(b_data: BuildingData) -> Color:
	if b_data == null:
		return _active_hud_accent
	var bid: StringName = b_data.building_id
	if bid == &"silica_condenser" or bid == &"silica_smelter":
		return Color(1.0, 0.76, 0.26, 1.0)
	if bid == &"wetware_mainframe" or bid == &"logic_monolith" or bid == &"capacitor_pylon":
		return Color(0.28, 0.84, 1.0, 1.0)
	if bid == &"synapse_pylon":
		return Color(0.76, 0.58, 1.0, 1.0)
	if bid == &"defense_turret" or bid == &"bastion_emplacement":
		return Color(1.0, 0.46, 0.26, 1.0)
	return _active_hud_accent


# =============================================================================
# BUILDING 4x3 ICON COMMAND CARD
# =============================================================================

func _rebuild_building_action_buttons(building: Building) -> void:
	_clear_command_grid()
	var slots: Array = []
	slots.resize(12)

	if not building.is_constructed:
		var cancel_tile: CommandIconButton = _new_icon_tile()
		cancel_tile.setup_tile(&"cancel_build", &"danger", "", Color(1.0, 0.42, 0.30, 1.0))
		cancel_tile.set_tile_state("75%", Color(1.0, 0.74, 0.36, 1.0))
		var captured_b_cancel: Building = building
		cancel_tile.pressed.connect(func() -> void:
			if is_instance_valid(captured_b_cancel):
				captured_b_cancel.cancel_construction()
		)
		_attach_tooltip(
			cancel_tile,
			"Cancel %s" % building.display_name,
			"LMB",
			"75%% Refund: %s" % building.get_refund_label(0.75),
			"Immediately cancels this unfinished scaffold, refunds 75% of construction resources, releases workers, and updates pathing."
		)
		slots[11] = cancel_tile
		_building_action_buttons.append({
			"kind": "cancel_build",
			"button": cancel_tile,
		})
		_populate_12_slot_grid(slots)
		command_grid.visible = true
		return

	# Row 1 (Slots 0..2): Trainable units Q / W / E
	var train_actions: Array[StringName] = [&"cmd_ability_q", &"cmd_ability_w", &"cmd_ability_e"]
	var train_fallbacks: PackedStringArray = PackedStringArray(["Q", "W", "E"])
	for i: int in range(mini(3, building.trainable_unit_data.size())):
		var u_data: UnitData = building.trainable_unit_data[i]
		if u_data == null:
			continue
		var t_act: StringName = train_actions[i]
		var t_fb: String = train_fallbacks[i]
		var hk_short: String = _get_compact_action_badge(t_act, t_fb)
		var train_tile: CommandIconButton = _new_icon_tile()
		train_tile.setup_tile(u_data.unit_type_id, &"unit", hk_short, _get_unit_icon_accent(u_data))
		var captured_b: Building = building
		var captured_slot: int = i
		var captured_u: UnitData = u_data
		train_tile.pressed.connect(func() -> void:
			var shift_batch: bool = Input.is_key_pressed(KEY_SHIFT)
			if shift_batch:
				if _selection_controller != null:
					_selection_controller.queue_unit_distributed_batch(captured_u, 5, captured_b)
				elif is_instance_valid(captured_b):
					var q_cnt: int = 0
					for _k: int in range(5):
						if captured_b.queue_unit_training(captured_slot, false):
							q_cnt += 1
						else:
							if q_cnt == 0:
								captured_b.queue_unit_training(captured_slot, true)
							break
					if q_cnt > 0 and AudioManager != null:
						AudioManager.play_ui_click()
			elif _selection_controller != null and _selected_buildings.size() > 1:
				_selection_controller.queue_unit_distributed(captured_u)
			elif is_instance_valid(captured_b):
				captured_b.queue_unit_training(captured_slot)
		)
		train_tile.tooltip_text = ""
		train_tile.mouse_entered.connect(func() -> void:
			if command_tooltip == null or not is_instance_valid(captured_b):
				return
			var hk_full: String = SettingsManager.get_action_display_label(t_act, false) if SettingsManager != null else t_fb
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
			desc += "\n[Shift+%s / Shift+Click: Queue x5]" % hk_full
			command_tooltip.show_tooltip(
				("Clone %s (x%d)" % [captured_u.display_name, b_cnt]) if b_cnt > 1 else ("Train %s" % captured_u.display_name),
				hk_full,
				meta_line,
				desc
			)
		)
		train_tile.mouse_exited.connect(func() -> void:
			if command_tooltip != null:
				command_tooltip.hide_tooltip()
		)
		slots[i] = train_tile
		_building_action_buttons.append({
			"kind": "train",
			"slot": i,
			"action": t_act,
			"fallback": t_fb,
			"data": u_data,
			"button": train_tile,
		})

	# Row 2 (Slots 4..5): Researchable upgrades R / T
	var upg_actions: Array[StringName] = [&"cmd_ability_r", &"cmd_ability_t"]
	var upg_fallbacks: PackedStringArray = PackedStringArray(["R", "T"])
	for j: int in range(mini(2, building.researchable_upgrades.size())):
		var upg: UpgradeData = building.researchable_upgrades[j]
		if upg == null:
			continue
		var u_act: StringName = upg_actions[j]
		var u_fb: String = upg_fallbacks[j]
		var hk_u: String = _get_compact_action_badge(u_act, u_fb)
		var upg_tile: CommandIconButton = _new_icon_tile()
		upg_tile.setup_tile(upg.upgrade_id, &"upgrade", hk_u, Color(1.0, 0.84, 0.34, 1.0))
		var captured_b_u: Building = building
		var captured_upg_idx: int = j
		var captured_upg: UpgradeData = upg
		upg_tile.pressed.connect(func() -> void:
			var started: bool = false
			if _selection_controller != null:
				var scoped_u: Array[Building] = _selection_controller.get_active_building_subgroup_buildings()
				for cand_u: Building in scoped_u:
					if is_instance_valid(cand_u) and not cand_u.is_destroyed and cand_u.is_constructed:
						var u_idx: int = cand_u.researchable_upgrades.find(captured_upg)
						if u_idx >= 0 and cand_u.can_research_upgrade(u_idx):
							if cand_u.queue_upgrade_research(u_idx):
								started = true
								break
			if not started and is_instance_valid(captured_b_u):
				captured_b_u.queue_upgrade_research(captured_upg_idx)
		)
		upg_tile.tooltip_text = ""
		upg_tile.mouse_entered.connect(func() -> void:
			if command_tooltip == null:
				return
			var hk_uf: String = SettingsManager.get_action_display_label(u_act, false) if SettingsManager != null else u_fb
			var upg_meta: String = "Upgrade  •  Cost: %s  •  %.1fs" % [captured_upg.get_cost_label(), captured_upg.research_time]
			command_tooltip.show_tooltip("Research: %s" % captured_upg.display_name, hk_uf, upg_meta, captured_upg.description)
		)
		upg_tile.mouse_exited.connect(func() -> void:
			if command_tooltip != null:
				command_tooltip.hide_tooltip()
		)
		slots[4 + j] = upg_tile
		_building_action_buttons.append({
			"kind": "upgrade",
			"slot": j,
			"action": u_act,
			"fallback": u_fb,
			"data": upg,
			"button": upg_tile,
		})

	# Row 3 Slot 8: Facility Special (F) — Core Overclock or Eject Engineers
	if building.has_overclock_ability():
		var hk_oc: String = _get_compact_action_badge(&"cmd_ability_f", "F")
		var oc_tile: CommandIconButton = _new_icon_tile()
		oc_tile.setup_tile(&"overclock", &"special", hk_oc, Color(1.0, 0.624, 0.110, 1.0))
		var captured_b_oc: Building = building
		oc_tile.pressed.connect(func() -> void:
			if _selection_controller != null:
				if _selection_controller.is_overclock_targeting:
					_selection_controller.cancel_overclock_targeting()
				elif not _selection_controller.begin_overclock_targeting() and AudioManager != null:
					AudioManager.play_error()
		)
		oc_tile.tooltip_text = ""
		oc_tile.mouse_entered.connect(func() -> void:
			if command_tooltip != null and is_instance_valid(captured_b_oc):
				var hk_oc_full: String = SettingsManager.get_action_display_label(&"cmd_ability_f", false) if SettingsManager != null else "F"
				var spd_m: float = captured_b_oc.get_overclock_config_speed_mult()
				var dur_s: float = captured_b_oc.get_overclock_config_duration()
				var cd_s: float = captured_b_oc.get_overclock_config_cooldown()
				command_tooltip.show_tooltip(
					"Core Overclock",
					hk_oc_full,
					"%.1fx Speed  •  %.0fs Duration  •  %.0fs Cooldown" % [spd_m, dur_s, cd_s],
					"Target any friendly production or research structure to boost its unit training and upgrade speed by %.1fx." % spd_m
				)
		)
		oc_tile.mouse_exited.connect(func() -> void:
			if command_tooltip != null:
				command_tooltip.hide_tooltip()
		)
		slots[8] = oc_tile
		_building_action_buttons.append({
			"kind": "overclock",
			"button": oc_tile,
		})
	elif building.max_staff_slots > 0:
		var hk_ej: String = _get_compact_action_badge(&"cmd_ability_f", "F")
		var eject_tile: CommandIconButton = _new_icon_tile()
		eject_tile.setup_tile(&"eject_engineers", &"special", hk_ej, Color(0.32, 0.88, 1.0, 1.0))
		var captured_building: Building = building
		eject_tile.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			if _selection_controller != null and _selected_buildings.size() > 1:
				_selection_controller.eject_engineers_from_selected_buildings()
			elif is_instance_valid(captured_building):
				captured_building.eject_engineers()
		)
		_attach_dynamic_action_tooltip(
			eject_tile,
			"Eject Engineers",
			&"cmd_ability_f",
			"Instant Release (F or E)",
			"Releases all Engineers / Grid-Techs currently staffed inside this facility back onto the battlefield."
		)
		slots[8] = eject_tile
		_building_action_buttons.append({
			"kind": "eject",
			"button": eject_tile,
		})

	# Row 3 Slot 11 (bottom-right): Salvage (click-only)
	var salv_tile: CommandIconButton = _new_icon_tile()
	salv_tile.setup_tile(&"salvage", &"danger", "", Color(1.0, 0.54, 0.34, 1.0))
	var captured_b_salv: Building = building
	salv_tile.pressed.connect(func() -> void:
		if not is_instance_valid(captured_b_salv):
			return
		if captured_b_salv.is_salvaging:
			captured_b_salv.cancel_salvage()
		else:
			captured_b_salv.begin_salvage()
	)
	salv_tile.tooltip_text = ""
	salv_tile.mouse_entered.connect(func() -> void:
		if command_tooltip == null or not is_instance_valid(captured_b_salv):
			return
		if captured_b_salv.is_salvaging:
			var rem_s: float = maxf(0.0, Building.SALVAGE_DURATION - captured_b_salv.salvage_elapsed)
			command_tooltip.show_tooltip(
				"Cancel Salvage",
				"LMB",
				"%.1fs Remaining" % rem_s,
				"Aborts the salvage timer and restores this building to active service."
			)
		elif not captured_b_salv.can_salvage():
			command_tooltip.show_tooltip(
				"Salvage Locked",
				"",
				"Last Command Hub",
				"Cannot salvage your final Command Hub."
			)
		else:
			command_tooltip.show_tooltip(
				"Salvage %s" % captured_b_salv.display_name,
				"LMB",
				"4.0s Timer  •  50%% Refund: %s" % captured_b_salv.get_refund_label(0.50),
				"Deconstructs this structure over 4.0 seconds (click-only for safety), refunding 50% of its cost and clearing pathing."
			)
	)
	salv_tile.mouse_exited.connect(func() -> void:
		if command_tooltip != null:
			command_tooltip.hide_tooltip()
	)
	slots[11] = salv_tile
	_building_action_buttons.append({
		"kind": "salvage",
		"button": salv_tile,
	})

	_populate_12_slot_grid(slots)
	command_grid.visible = true
	_refresh_building_action_buttons(building)


func _refresh_building_action_buttons(building: Building) -> void:
	if building == null or not is_instance_valid(building):
		return
	if _economy_manager == null:
		_connect_economy_manager()

	for entry: Dictionary in _building_action_buttons:
		var kind: String = String(entry["kind"])
		var btn: CommandIconButton = entry["button"] as CommandIconButton
		if btn == null or not is_instance_valid(btn):
			continue
		if kind == "overclock":
			var k_oc: String = _get_compact_action_badge(&"cmd_ability_f", "F")
			btn.hotkey_text = k_oc
			var any_ready: bool = false
			var min_cd: float = INF
			var max_cd: float = maxf(1.0, building.get_overclock_config_cooldown())
			var hub_list: Array[Building] = []
			if _selection_controller != null and _building_subgroups.size() > 1:
				hub_list = _selection_controller.get_active_building_subgroup_buildings()
			elif _selected_buildings.size() > 1:
				hub_list = _selected_buildings
			else:
				hub_list.append(building)
			for sb: Building in hub_list:
				if is_instance_valid(sb) and not sb.is_destroyed and sb.has_overclock_ability():
					if sb.can_cast_overclock():
						any_ready = true
						min_cd = 0.0
					else:
						min_cd = minf(min_cd, sb.get_overclock_cooldown_remaining())
			if any_ready:
				btn.disabled = false
				btn.set_tile_state("TGT" if _overclock_targeting else "", Color(1.0, 0.84, 0.28, 1.0), _overclock_targeting, false, false, 0.0, 0.0)
			else:
				btn.disabled = true
				var cd_rem: float = 0.0 if min_cd == INF else min_cd
				btn.set_tile_state("", Color(1.0, 0.72, 0.24, 1.0), false, false, false, cd_rem, max_cd)
		elif kind == "eject":
			var count: int = building.get_assigned_engineer_count()
			btn.hotkey_text = _get_compact_action_badge(&"cmd_ability_f", "F")
			btn.disabled = count <= 0
			btn.set_tile_state(str(count) if count > 0 else "", Color(0.45, 0.96, 1.0, 1.0), false, count <= 0)
		elif kind == "train":
			var slot: int = int(entry["slot"])
			var u_data: UnitData = entry["data"] as UnitData
			btn.hotkey_text = _get_compact_action_badge(entry["action"] as StringName, String(entry["fallback"]))
			var b_info: Dictionary = building.get_unit_batch_info(u_data)
			var b_cnt: int = int(b_info["batch_count"])
			var can_train: bool = building.can_train_unit(slot)
			btn.disabled = false
			var b_tag: String = "×%d" % b_cnt if b_cnt > 1 else ""
			btn.set_tile_state(b_tag, Color(0.32, 0.98, 0.84, 1.0), false, not can_train)
		elif kind == "upgrade":
			var u_slot: int = int(entry["slot"])
			var upg: UpgradeData = entry["data"] as UpgradeData
			btn.hotkey_text = _get_compact_action_badge(entry["action"] as StringName, String(entry["fallback"]))
			var is_done: bool = _economy_manager != null and _economy_manager.has_upgrade(building.team, upg.upgrade_id)
			var is_prog: bool = _economy_manager != null and _economy_manager.is_upgrade_in_progress(building.team, upg.upgrade_id)
			if is_done:
				btn.disabled = true
				btn.set_tile_state("DONE", Color(0.36, 0.98, 0.64, 1.0), false, false)
			elif is_prog:
				btn.disabled = true
				btn.set_tile_state("ACT", Color(1.0, 0.86, 0.36, 1.0), true, false)
			else:
				var can_res: bool = building.can_research_upgrade(u_slot)
				btn.disabled = false
				btn.set_tile_state("", Color(1.0, 0.86, 0.42, 1.0), false, not can_res)
		elif kind == "salvage":
			var can_s: bool = building.can_salvage()
			if building.is_salvaging:
				var rem_s: float = maxf(0.0, Building.SALVAGE_DURATION - building.salvage_elapsed)
				btn.disabled = false
				btn.set_tile_state("CXL", Color(1.0, 0.78, 0.24, 1.0), true, false, false, rem_s, Building.SALVAGE_DURATION)
			elif not can_s:
				btn.disabled = true
				btn.set_tile_state("LOCK", Color(0.76, 0.44, 0.44, 0.90), false, false, true)
			else:
				btn.disabled = false
				btn.set_tile_state("50%", Color(1.0, 0.62, 0.38, 0.96), false, false)


# =============================================================================
# UNIT 4x3 ICON COMMAND CARD
# =============================================================================

func _make_std_cmd_tile(key_id: StringName) -> CommandIconButton:
	var tile: CommandIconButton = _new_icon_tile()
	match key_id:
		&"move":
			tile.setup_tile(&"cmd_move", &"command", "RMB", Color(0.42, 0.96, 0.88, 1.0))
			tile.disabled = true
			_attach_tooltip(tile, "Move", "RMB", "Right-Click Ground", "Orders selected units to navigate to the target location.")
		&"stop":
			tile.setup_tile(&"cmd_stop", &"command", _get_compact_action_badge(&"cmd_stop", "S"), Color(0.84, 0.90, 0.96, 1.0))
			tile.pressed.connect(func() -> void:
				if AudioManager != null:
					AudioManager.play_ui_click()
				if _selection_controller != null:
					_selection_controller.issue_stop_command()
			)
			_attach_dynamic_action_tooltip(tile, "Stop", &"cmd_stop", "Immediate", "Cancels current movement, patrol, gathering, construction, or target and flushes command queue.")
		&"hold":
			tile.setup_tile(&"cmd_hold", &"command", _get_compact_action_badge(&"cmd_hold", "H"), Color(1.0, 0.84, 0.32, 1.0))
			tile.pressed.connect(func() -> void:
				if AudioManager != null:
					AudioManager.play_ui_click()
				if _selection_controller != null:
					_selection_controller.issue_hold_command()
			)
			_attach_dynamic_action_tooltip(tile, "Hold Position", &"cmd_hold", "Immediate", "Locks unit position while engaging enemies inside attack range.")
		&"defensive":
			tile.setup_tile(&"cmd_defensive", &"command", _get_compact_action_badge(&"cmd_defensive_stance", "D"), Color(0.28, 0.98, 0.80, 1.0))
			tile.pressed.connect(func() -> void:
				if AudioManager != null:
					AudioManager.play_ui_click()
				if _selection_controller != null:
					_selection_controller.issue_defensive_command()
			)
			_attach_dynamic_action_tooltip(tile, "Defensive Stance", &"cmd_defensive_stance", "Immediate (260px Leash)", "Auto-acquires nearby enemies and chases up to 260px from anchor before smoothly returning.")
		&"patrol":
			tile.setup_tile(&"cmd_patrol", &"command", _get_compact_action_badge(&"cmd_patrol", "P"), Color(0.46, 0.90, 1.0, 1.0))
			tile.pressed.connect(func() -> void:
				if _selection_controller != null:
					_selection_controller.begin_patrol_targeting()
			)
			_attach_dynamic_action_tooltip(tile, "Patrol", &"cmd_patrol", "Click Waypoint (Shift Chains Loop)", "Loops units continuously between waypoints while engaging enemies encountered along the path.")
		&"amove":
			tile.setup_tile(&"cmd_amove", &"command", _get_compact_action_badge(&"cmd_attack_move", "A"), Color(1.0, 0.38, 0.44, 1.0))
			tile.pressed.connect(func() -> void:
				if _selection_controller != null:
					_selection_controller.begin_attack_move_targeting()
			)
			tile.tooltip_text = ""
			tile.mouse_entered.connect(func() -> void:
				if command_tooltip != null:
					var hk: String = SettingsManager.get_action_display_label(&"cmd_attack_move", false) if SettingsManager != null else "A"
					var click_confirm: bool = SettingsManager != null and SettingsManager.attack_move_mode == SettingsManager.AttackMoveMode.CLICK_TO_CONFIRM
					var meta_txt: String = "Click Target (Shift Chains)" if click_confirm else "Quick-Cast at Cursor (Shift Chains)"
					command_tooltip.show_tooltip("Attack-Move", hk, meta_txt, "Moves toward target point and automatically engages hostile targets along the way.")
			)
			tile.mouse_exited.connect(func() -> void:
				if command_tooltip != null:
					command_tooltip.hide_tooltip()
			)
	_unit_cmd_tiles[key_id] = tile
	return tile


func _make_ability_tile(ability: AbilityData) -> CommandIconButton:
	var tile: CommandIconButton = _new_icon_tile()
	var hk_compact: String = _get_ability_hotkey_display(ability.hotkey_label, true)
	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT and ability.building_to_build != null:
		tile.setup_tile(ability.building_to_build.building_id, &"building", hk_compact, _get_building_icon_accent(ability.building_to_build))
	else:
		tile.setup_tile(ability.ability_id, &"ability", hk_compact, ability.effect_color)

	var captured_ability: AbilityData = ability
	tile.pressed.connect(func() -> void:
		if _selection_controller != null:
			_selection_controller.request_ability_slot(captured_ability, Input.is_key_pressed(KEY_SHIFT))
	)
	if ability.allow_autocast:
		tile.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb: InputEventMouseButton = ev as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
					_toggle_subgroup_autocast(captured_ability.ability_id)
					tile.accept_event()
		)
	tile.tooltip_text = ""
	tile.mouse_entered.connect(func() -> void:
		if command_tooltip != null:
			var dynamic_meta: String = _build_ability_tooltip_meta(captured_ability)
			var hk_full: String = _get_ability_hotkey_display(captured_ability.hotkey_label, false)
			command_tooltip.show_tooltip(captured_ability.display_name, hk_full, dynamic_meta, captured_ability.description)
	)
	tile.mouse_exited.connect(func() -> void:
		if command_tooltip != null:
			command_tooltip.hide_tooltip()
	)
	_ability_buttons[ability.ability_id] = {
		"button": tile,
		"ability": ability,
	}
	return tile


func _make_auto_repair_tile(data: UnitData) -> CommandIconButton:
	var rep_tile: CommandIconButton = _new_icon_tile()
	rep_tile.setup_tile(&"auto_repair", &"special", "", Color(0.38, 1.0, 0.84, 1.0))
	rep_tile.pressed.connect(func() -> void:
		_toggle_subgroup_auto_repair()
	)
	rep_tile.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				_toggle_subgroup_auto_repair()
				rep_tile.accept_event()
	)
	rep_tile.tooltip_text = ""
	rep_tile.mouse_entered.connect(func() -> void:
		if command_tooltip != null:
			var is_on: bool = _is_subgroup_auto_repair_enabled()
			var state_str: String = "Auto-Cast ON" if is_on else "Auto-Cast OFF"
			var scope_str: String = "damaged friendly buildings & heavy synthetic units within 220px" if data.can_staff_compute else "damaged friendly buildings within 220px"
			command_tooltip.show_tooltip(
				"Auto-Repair",
				"RMB / LMB",
				"Radius: 220 px  •  [Right-Click: %s]" % state_str,
				"When IDLE, automatically repairs %s (~2B/1S per sec)." % scope_str
			)
	)
	rep_tile.mouse_exited.connect(func() -> void:
		if command_tooltip != null:
			command_tooltip.hide_tooltip()
	)
	_ability_buttons[&"__auto_repair__"] = {
		"button": rep_tile,
		"ability": null,
	}
	return rep_tile


func _make_deploy_tile(data: UnitData) -> CommandIconButton:
	var dep_tile: CommandIconButton = _new_icon_tile()
	dep_tile.setup_tile(&"deploy", &"special", _get_compact_action_badge(&"cmd_ability_e", "E"), Color(1.0, 0.624, 0.110, 1.0))
	var captured_u_data: UnitData = data
	dep_tile.pressed.connect(func() -> void:
		if _selection_controller != null:
			_selection_controller.toggle_deploy_active_subgroup()
	)
	dep_tile.tooltip_text = ""
	dep_tile.mouse_entered.connect(func() -> void:
		if command_tooltip != null and captured_u_data != null:
			var hk_dep: String = SettingsManager.get_action_display_label(&"cmd_ability_e", false) if SettingsManager != null else "E"
			var meta_parts: PackedStringArray = PackedStringArray(["Transition: %.1fs" % captured_u_data.deploy_duration])
			if captured_u_data.deployed_attack_range > 0.0:
				meta_parts.append("Range: %dpx" % int(round(captured_u_data.deployed_attack_range)))
			if captured_u_data.deployed_attack_damage > 0.0:
				meta_parts.append("Dmg: %d" % int(round(captured_u_data.deployed_attack_damage)))
			if captured_u_data.deployed_damage_reduction_bonus > 0.0:
				meta_parts.append("+%d%% Armor" % int(round(captured_u_data.deployed_damage_reduction_bonus * 100.0)))
			command_tooltip.show_tooltip(
				"Deploy / Anchor Stance",
				hk_dep,
				"  •  ".join(meta_parts),
				"Anchors the chassis in place to engage heavy deployed weaponry. Move orders will not accidentally undeploy anchored units."
			)
	)
	dep_tile.mouse_exited.connect(func() -> void:
		if command_tooltip != null:
			command_tooltip.hide_tooltip()
	)
	_ability_buttons[&"__deploy__"] = {
		"button": dep_tile,
		"ability": null,
	}
	return dep_tile


func _rebuild_unit_command_card(active_group: Dictionary) -> void:
	_clear_command_grid()
	var data: UnitData = active_group.get("data", null) as UnitData
	var slots: Array = []
	slots.resize(12)

	var valid_abilities: Array[AbilityData] = []
	var build_ability_count: int = 0
	if data != null:
		for ab: AbilityData in data.abilities:
			if ab != null:
				valid_abilities.append(ab)
				_active_abilities.append(ab)
				if ab.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
					build_ability_count += 1

	var supports_auto_repair: bool = data != null and (data.can_gather or data.can_staff_compute or data.unit_type_id == &"worker" or data.unit_type_id == &"engineer")
	var supports_deploy: bool = data != null and data.can_deploy

	if build_ability_count >= 5:
		# Builder layout (Worker Drone / Servo-Drone): 12 exact slots in 4x3 grid!
		# Row 1: Move, Stop, Hold, Auto-Repair
		# Row 2..3: All 7-8 build abilities neatly aligned
		slots[0] = _make_std_cmd_tile(&"move")
		slots[1] = _make_std_cmd_tile(&"stop")
		slots[2] = _make_std_cmd_tile(&"hold")
		if supports_auto_repair:
			slots[3] = _make_auto_repair_tile(data)
		var cursor_b: int = 4
		for ab: AbilityData in valid_abilities:
			if cursor_b >= 12:
				break
			slots[cursor_b] = _make_ability_tile(ab)
			cursor_b += 1
	else:
		# Standard / Combat / Specialist layout
		# Row 1: Move, Stop, Hold, Defend
		# Row 2: Patrol, Atk-Move, Abilities...
		# Row 3: Remaining Abilities, Deploy, Auto-Repair
		slots[0] = _make_std_cmd_tile(&"move")
		slots[1] = _make_std_cmd_tile(&"stop")
		slots[2] = _make_std_cmd_tile(&"hold")
		slots[3] = _make_std_cmd_tile(&"defensive")
		slots[4] = _make_std_cmd_tile(&"patrol")
		slots[5] = _make_std_cmd_tile(&"amove")
		var cursor_u: int = 6
		for ab: AbilityData in valid_abilities:
			if cursor_u >= 12:
				break
			slots[cursor_u] = _make_ability_tile(ab)
			cursor_u += 1
		if supports_deploy and cursor_u < 12:
			slots[cursor_u] = _make_deploy_tile(data)
			cursor_u += 1
		if supports_auto_repair and cursor_u < 12:
			slots[cursor_u] = _make_auto_repair_tile(data)
			cursor_u += 1

	_populate_12_slot_grid(slots)
	command_grid.visible = true


# =============================================================================
# SIGNALS, SUBGROUPS & REFRESH HELPERS
# =============================================================================

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
		var res_node: ResourceNode = entity as ResourceNode
		if not res_node.amount_changed.is_connected(_on_inspected_entity_updated):
			res_node.amount_changed.connect(_on_inspected_entity_updated)
		if not res_node.status_changed.is_connected(_on_inspected_entity_updated):
			res_node.status_changed.connect(_on_inspected_entity_updated)
		if not res_node.depleted.is_connected(_on_inspected_entity_removed):
			res_node.depleted.connect(_on_inspected_entity_removed)
	elif entity is Building:
		var b: Building = entity as Building
		if not b.status_changed.is_connected(_on_inspected_entity_updated):
			b.status_changed.connect(_on_inspected_entity_updated)
		if not b.construction_progress_changed.is_connected(_on_inspected_building_construction_changed):
			b.construction_progress_changed.connect(_on_inspected_building_construction_changed)
		if not b.destroyed.is_connected(_on_inspected_entity_removed):
			b.destroyed.connect(_on_inspected_entity_removed)
	elif entity is Unit:
		var u: Unit = entity as Unit
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
	elif entity.is_in_group("salvage_cores"):
		if entity.has_signal("status_changed") and not entity.is_connected("status_changed", _on_inspected_entity_updated):
			entity.connect("status_changed", _on_inspected_entity_updated)
		if entity.has_signal("claimed") and not entity.is_connected("claimed", _on_inspected_entity_removed):
			entity.connect("claimed", _on_inspected_entity_removed)
		if entity.has_signal("expired") and not entity.is_connected("expired", _on_inspected_entity_removed):
			entity.connect("expired", _on_inspected_entity_removed)
	elif entity.is_in_group("sensor_relays"):
		if entity.has_signal("state_changed") and not entity.is_connected("state_changed", _on_inspected_entity_updated):
			entity.connect("state_changed", _on_inspected_entity_updated)


func _disconnect_inspected_signals() -> void:
	if _inspected_entity == null or not is_instance_valid(_inspected_entity):
		return
	if _inspected_entity is ResourceNode:
		var res_node: ResourceNode = _inspected_entity as ResourceNode
		if res_node.amount_changed.is_connected(_on_inspected_entity_updated):
			res_node.amount_changed.disconnect(_on_inspected_entity_updated)
		if res_node.status_changed.is_connected(_on_inspected_entity_updated):
			res_node.status_changed.disconnect(_on_inspected_entity_updated)
		if res_node.depleted.is_connected(_on_inspected_entity_removed):
			res_node.depleted.disconnect(_on_inspected_entity_removed)
	elif _inspected_entity is Building:
		var b: Building = _inspected_entity as Building
		if b.status_changed.is_connected(_on_inspected_entity_updated):
			b.status_changed.disconnect(_on_inspected_entity_updated)
		if b.construction_progress_changed.is_connected(_on_inspected_building_construction_changed):
			b.construction_progress_changed.disconnect(_on_inspected_building_construction_changed)
		if b.destroyed.is_connected(_on_inspected_entity_removed):
			b.destroyed.disconnect(_on_inspected_entity_removed)
	elif _inspected_entity is Unit:
		var u: Unit = _inspected_entity as Unit
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
	elif _inspected_entity.is_in_group("salvage_cores"):
		if _inspected_entity.has_signal("status_changed") and _inspected_entity.is_connected("status_changed", _on_inspected_entity_updated):
			_inspected_entity.disconnect("status_changed", _on_inspected_entity_updated)
		if _inspected_entity.has_signal("claimed") and _inspected_entity.is_connected("claimed", _on_inspected_entity_removed):
			_inspected_entity.disconnect("claimed", _on_inspected_entity_removed)
		if _inspected_entity.has_signal("expired") and _inspected_entity.is_connected("expired", _on_inspected_entity_removed):
			_inspected_entity.disconnect("expired", _on_inspected_entity_removed)
	elif _inspected_entity.is_in_group("sensor_relays"):
		if _inspected_entity.has_signal("state_changed") and _inspected_entity.is_connected("state_changed", _on_inspected_entity_updated):
			_inspected_entity.disconnect("state_changed", _on_inspected_entity_updated)


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
	_refresh_deploy_button()


func _refresh_stance_button() -> void:
	if _selection_controller == null:
		return
	var btn_hold: CommandIconButton = _unit_cmd_tiles.get(&"hold", null) as CommandIconButton
	var btn_def: CommandIconButton = _unit_cmd_tiles.get(&"defensive", null) as CommandIconButton
	if btn_hold == null and btn_def == null:
		return
	var living_count: int = 0
	var hold_count: int = 0
	var defensive_count: int = 0
	for item: Variant in _selection_controller.selected_units:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var u: Unit = item as Unit
		if u.is_dead or u.is_staffed:
			continue
		living_count += 1
		if u.stance == Unit.Stance.HOLD_POSITION:
			hold_count += 1
		elif u.stance == Unit.Stance.DEFENSIVE:
			defensive_count += 1

	if btn_hold != null and is_instance_valid(btn_hold):
		btn_hold.hotkey_text = _get_compact_action_badge(&"cmd_hold", "H")
		if living_count > 0 and hold_count == living_count:
			btn_hold.set_tile_state("ON", Color(1.0, 0.84, 0.32, 1.0), true)
		elif hold_count > 0:
			btn_hold.set_tile_state("*", Color(1.0, 0.90, 0.56, 1.0), true)
		else:
			btn_hold.set_tile_state("", Color(1.0, 0.84, 0.32, 1.0), false)

	if btn_def != null and is_instance_valid(btn_def):
		btn_def.hotkey_text = _get_compact_action_badge(&"cmd_defensive_stance", "D")
		if living_count > 0 and defensive_count == living_count:
			btn_def.set_tile_state("ON", Color(0.28, 0.98, 0.80, 1.0), true)
		elif defensive_count > 0:
			btn_def.set_tile_state("*", Color(0.56, 0.98, 0.88, 1.0), true)
		else:
			btn_def.set_tile_state("", Color(0.28, 0.98, 0.80, 1.0), false)


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
	_refresh_deploy_button()


func _connect_unit_signals(units: Array[Unit]) -> void:
	for item: Variant in units:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item as Unit
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
			var unit: Unit = item as Unit
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

	var max_tabs: int = mini(subgroups.size(), 4)
	for i: int in range(max_tabs):
		var group: Dictionary = subgroups[i]
		var group_units: Array[Unit] = group["units"]
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 10)
		var prefix: String = ">" if i == active_index else ""
		btn.text = "%s%s (%d)" % [prefix, _shorten_unit_name(String(group["display_name"])), group_units.size()]
		btn.modulate = _active_hud_accent if i == active_index else Color(0.72, 0.78, 0.84, 0.85)
		var captured_idx: int = i
		btn.pressed.connect(func() -> void:
			if _selection_controller != null:
				_selection_controller.set_active_subgroup(captured_idx)
		)
		subgroup_tabs_row.add_child(btn)

	if subgroups.size() > max_tabs:
		var more_tabs: Label = Label.new()
		more_tabs.text = "+%d" % (subgroups.size() - max_tabs)
		more_tabs.add_theme_font_size_override("font_size", 10)
		more_tabs.modulate = Color(0.75, 0.85, 0.90, 0.85)
		subgroup_tabs_row.add_child(more_tabs)

	if subgroups.size() > 1:
		var k_tab: String = _get_compact_action_badge(&"ui_cycle_subgroup", "Tab")
		if not k_tab.is_empty():
			var hint: Label = Label.new()
			hint.text = "[%s]" % k_tab
			hint.add_theme_font_size_override("font_size", 10)
			hint.modulate = _active_hud_accent
			subgroup_tabs_row.add_child(hint)


func _shorten_building_name(full_name: String) -> String:
	return full_name.replace("Assembly Bay", "Assembly").replace("Ballistics Lab", "Ballistics").replace("Siege Gantry", "Gantry").replace("Foundry Core", "Foundry").replace("Cloning Vat", "Cloning").replace("Calibration Foundry", "Calibration").replace("Synthetics Fabricator", "Synthetics").replace("Nexus Vat", "Nexus").replace("Logic Monolith", "Logic").replace("Wetware Mainframe", "Mainframe").replace("Silica Smelter", "Smelter").replace("Silica Condenser", "Condenser").replace("Capacitor Pylon", "Capacitor").replace("Synapse Pylon", "Synapse").replace("Bastion Emplacement", "Bastion").replace("Defense Turret", "Turret")


func _rebuild_building_subgroup_tabs(b_subgroups: Array[Dictionary], active_index: int) -> void:
	for child: Node in subgroup_tabs_row.get_children():
		child.queue_free()

	var safe_active: int = clampi(active_index, 0, maxi(0, b_subgroups.size() - 1))
	var max_tabs: int = mini(b_subgroups.size(), 4)
	for i: int in range(max_tabs):
		var group: Dictionary = b_subgroups[i]
		var grp_bldgs: Array = group.get("buildings", [])
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 10)
		var prefix: String = ">" if i == safe_active else ""
		btn.text = "%s%s (%d)" % [prefix, _shorten_building_name(String(group.get("display_name", "Structure"))), grp_bldgs.size()]
		btn.modulate = _active_hud_accent if i == safe_active else Color(0.72, 0.78, 0.84, 0.85)
		var captured_idx: int = i
		btn.pressed.connect(func() -> void:
			if _selection_controller != null:
				_selection_controller.set_active_building_subgroup(captured_idx)
		)
		subgroup_tabs_row.add_child(btn)

	if b_subgroups.size() > max_tabs:
		var more_tabs: Label = Label.new()
		more_tabs.text = "+%d" % (b_subgroups.size() - max_tabs)
		more_tabs.add_theme_font_size_override("font_size", 10)
		more_tabs.modulate = Color(0.75, 0.85, 0.90, 0.85)
		subgroup_tabs_row.add_child(more_tabs)

	if b_subgroups.size() > 1:
		var k_tab: String = _get_compact_action_badge(&"ui_cycle_subgroup", "Tab")
		if not k_tab.is_empty():
			var hint: Label = Label.new()
			hint.text = "[%s]" % k_tab
			hint.add_theme_font_size_override("font_size", 10)
			hint.modulate = _active_hud_accent
			subgroup_tabs_row.add_child(hint)


func _rebuild_unit_badges(units: Array[Unit]) -> void:
	for child: Node in unit_badges_grid.get_children():
		child.queue_free()

	var max_badges: int = mini(units.size(), 12)
	for i: int in range(max_badges):
		var unit: Unit = units[i]
		if not is_instance_valid(unit) or unit.is_dead:
			continue
		var max_hp: float = maxf(1.0, unit.get_max_hp())
		var hp_ratio: float = clampf(unit.current_hp / max_hp, 0.0, 1.0)
		var pct: int = int(round(hp_ratio * 100.0))
		if unit.has_shields():
			var tile: VBoxContainer = VBoxContainer.new()
			tile.add_theme_constant_override("separation", 1)
			tile.custom_minimum_size = Vector2(36.0, 0.0)

			var shd_ratio: float = clampf(unit.current_shield / maxf(1.0, unit.max_shield), 0.0, 1.0)
			var shd_bg: ColorRect = ColorRect.new()
			shd_bg.custom_minimum_size = Vector2(36.0, 2.0)
			shd_bg.color = Color(0.05, 0.08, 0.12, 0.90)
			var shd_fill: ColorRect = ColorRect.new()
			shd_fill.position = Vector2.ZERO
			shd_fill.size = Vector2(36.0 * shd_ratio, 2.0)
			shd_fill.color = Color(0.220, 0.741, 0.973, 1.0)
			shd_bg.add_child(shd_fill)
			tile.add_child(shd_bg)

			var hp_bg: ColorRect = ColorRect.new()
			hp_bg.custom_minimum_size = Vector2(36.0, 2.0)
			hp_bg.color = Color(0.05, 0.08, 0.12, 0.90)
			var hp_fill: ColorRect = ColorRect.new()
			hp_fill.position = Vector2.ZERO
			hp_fill.size = Vector2(36.0 * hp_ratio, 2.0)
			hp_fill.color = Color(0.32, 0.96, 0.76, 1.0) if pct > 50 else Color(1.0, 0.56, 0.28, 1.0)
			hp_bg.add_child(hp_fill)
			tile.add_child(hp_bg)

			var badge: Label = Label.new()
			badge.text = "[%d%%]" % pct
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge.add_theme_font_size_override("font_size", 9)
			badge.modulate = Color(0.32, 0.96, 0.76, 1.0) if pct > 50 else Color(1.0, 0.56, 0.28, 1.0)
			tile.add_child(badge)
			unit_badges_grid.add_child(tile)
		else:
			var badge: Label = Label.new()
			badge.text = "[%d%%]" % pct
			badge.add_theme_font_size_override("font_size", 10)
			badge.modulate = Color(0.32, 0.96, 0.76, 1.0) if pct > 50 else Color(1.0, 0.56, 0.28, 1.0)
			unit_badges_grid.add_child(badge)

	if units.size() > max_badges:
		var more: Label = Label.new()
		more.text = "+%d" % (units.size() - max_badges)
		more.add_theme_font_size_override("font_size", 10)
		unit_badges_grid.add_child(more)


func _toggle_subgroup_autocast(ability_id: StringName) -> void:
	var any_on: bool = _is_subgroup_autocast_enabled(ability_id)
	var next_state: bool = not any_on
	for item: Variant in _active_subgroup_units:
		if is_instance_valid(item) and item is Unit:
			var u: Unit = item as Unit
			if not u.is_dead and u.ability_component != null:
				u.ability_component.set_autocast_enabled(ability_id, next_state)
	if AudioManager != null:
		AudioManager.play_sfx(&"autocast_toggle", -3.0, 0.03)
	_refresh_single_ability_button(ability_id)


func _is_subgroup_autocast_enabled(ability_id: StringName) -> bool:
	for item: Variant in _active_subgroup_units:
		if is_instance_valid(item) and item is Unit:
			var u: Unit = item as Unit
			if not u.is_dead and u.ability_component != null and u.ability_component.is_autocast_enabled(ability_id):
				return true
	return false


func _toggle_subgroup_auto_repair() -> void:
	var next_state: bool = not _is_subgroup_auto_repair_enabled()
	for item: Variant in _active_subgroup_units:
		if is_instance_valid(item) and item is Unit:
			var u: Unit = item as Unit
			if not u.is_dead and u.repair_component != null and u.repair_component.has_method("set_auto_repair_enabled"):
				u.repair_component.call("set_auto_repair_enabled", next_state)
	if AudioManager != null:
		AudioManager.play_sfx(&"autocast_toggle", -3.0, 0.03)
	_refresh_auto_repair_button()


func _is_subgroup_auto_repair_enabled() -> bool:
	for item: Variant in _active_subgroup_units:
		if is_instance_valid(item) and item is Unit:
			var u: Unit = item as Unit
			if not u.is_dead and u.repair_component != null and bool(u.repair_component.get("auto_repair_enabled")):
				return true
	return false


func _refresh_auto_repair_button() -> void:
	if not _ability_buttons.has(&"__auto_repair__"):
		return
	var entry: Dictionary = _ability_buttons[&"__auto_repair__"]
	var btn: CommandIconButton = entry["button"] as CommandIconButton
	if btn == null or not is_instance_valid(btn):
		return
	var is_on: bool = _is_subgroup_auto_repair_enabled()
	btn.set_autocast_active(is_on)
	btn.set_tile_state("ON" if is_on else "OFF", Color(0.38, 1.0, 0.84, 1.0) if is_on else Color(0.68, 0.74, 0.80, 0.85), is_on)


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
			var local_t_tt: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
			var check_t_tt: int = local_t_tt if local_t_tt >= 0 else int(Unit.Team.PLAYER)
			var has_req: bool = _economy_manager != null and _economy_manager.has_constructed_building(check_t_tt, b.required_building_id)
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
	if ability.allow_autocast:
		var ac_on: bool = _is_subgroup_autocast_enabled(ability.ability_id)
		ab_parts.append("[Right-Click: Auto-Cast %s]" % ("ON" if ac_on else "OFF"))
	return "  •  ".join(ab_parts)


func _refresh_deploy_button() -> void:
	if not _ability_buttons.has(&"__deploy__"):
		return
	var entry: Dictionary = _ability_buttons[&"__deploy__"]
	var btn: CommandIconButton = entry["button"] as CommandIconButton
	if btn == null or not is_instance_valid(btn):
		return
	btn.hotkey_text = _get_compact_action_badge(&"cmd_ability_e", "E")
	var has_mobile: bool = false
	var has_deploying: bool = false
	var has_undeploying: bool = false
	var has_deployed: bool = false
	for item: Variant in _active_subgroup_units:
		if is_instance_valid(item) and item is Unit:
			var u: Unit = item as Unit
			if u.is_dead or not u.can_toggle_deploy():
				continue
			match u.deploy_state:
				Unit.DeployState.MOBILE:
					has_mobile = true
				Unit.DeployState.DEPLOYING:
					has_deploying = true
				Unit.DeployState.UNDEPLOYING:
					has_undeploying = true
				Unit.DeployState.DEPLOYED:
					has_deployed = true
	if has_deployed:
		btn.set_tile_state("ON", Color(1.0, 0.624, 0.110, 1.0), true)
	elif has_deploying or has_undeploying:
		btn.set_tile_state("...", Color(1.0, 0.80, 0.30, 1.0), true)
	elif has_mobile:
		btn.set_tile_state("", Color(0.55, 1.0, 0.95, 1.0), false)
	else:
		btn.set_tile_state("", Color(0.55, 1.0, 0.95, 1.0), false)


func _refresh_all_ability_states() -> void:
	for ability: AbilityData in _active_abilities:
		_refresh_single_ability_button(ability.ability_id)
	_refresh_auto_repair_button()
	_refresh_deploy_button()


func _refresh_single_ability_button(ability_id: StringName) -> void:
	if not _ability_buttons.has(ability_id):
		return
	var entry: Dictionary = _ability_buttons[ability_id]
	var btn: CommandIconButton = entry["button"] as CommandIconButton
	var ability: AbilityData = entry["ability"] as AbilityData
	if btn == null or not is_instance_valid(btn) or ability == null:
		return

	var ac_on: bool = ability.allow_autocast and _is_subgroup_autocast_enabled(ability_id)
	btn.set_autocast_active(ac_on)
	btn.hotkey_text = _get_ability_hotkey_display(ability.hotkey_label, true)

	var is_targeting: bool = (_targeting_ability != null and _targeting_ability.ability_id == ability_id)

	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT and ability.building_to_build != null:
		var b_data: BuildingData = ability.building_to_build
		var can_afford: bool = true
		var has_prereq: bool = true
		if _economy_manager == null:
			_connect_economy_manager()
		if _economy_manager != null:
			var local_t_b: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
			var check_t_b: int = local_t_b if local_t_b >= 0 else int(Unit.Team.PLAYER)
			can_afford = _economy_manager.can_afford(check_t_b, b_data.get_cost_dict())
			if b_data.required_building_id != &"":
				has_prereq = _economy_manager.has_constructed_building(check_t_b, b_data.required_building_id)

		btn.disabled = false
		if not has_prereq:
			btn.set_tile_state("LOCK", Color(0.95, 0.42, 0.42, 0.96), false, false, true)
		elif is_targeting:
			btn.set_tile_state("PLC", Color(1.0, 0.85, 0.32, 1.0), true, false, false)
		elif can_afford:
			btn.set_tile_state("", _active_hud_accent, false, false, false)
		else:
			btn.set_tile_state("", Color(0.56, 0.60, 0.66, 0.80), false, true, false)
		return

	var min_cd: float = INF
	var ready_count: int = 0
	for item: Variant in _active_subgroup_units:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item as Unit
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
		var badge: String = "TGT" if is_targeting else ("A" if ac_on else "")
		btn.set_tile_state(badge, Color(1.0, 0.85, 0.32, 1.0) if is_targeting else _active_hud_accent, is_targeting, false, false, 0.0, 0.0)
	else:
		var display_cd: float = 0.0 if min_cd == INF else min_cd
		btn.disabled = false if ability.allow_autocast else true
		btn.set_tile_state("A" if ac_on else "", _active_hud_accent, false, false, false, display_cd, maxf(0.1, ability.cooldown_duration))
