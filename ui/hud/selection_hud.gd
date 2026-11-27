class_name SelectionHUD
extends Control

const WIREFRAME_GRID_SCRIPT: GDScript = preload("res://ui/hud/selection_wireframe_grid.gd")
const COMMAND_CARD_BUILDER_SCRIPT: GDScript = preload("res://ui/hud/command_card_builder.gd")
const SELECTION_TELEMETRY_RENDERER_SCRIPT: GDScript = preload("res://ui/hud/selection_telemetry_renderer.gd")

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

var _card_builder: CommandCardBuilder = COMMAND_CARD_BUILDER_SCRIPT.new()
var _telemetry: SelectionTelemetryRenderer = SELECTION_TELEMETRY_RENDERER_SCRIPT.new()

var _selection_controller: SelectionController = null
var _economy_manager: EconomyManager = null
var _connected_units: Array[Unit] = []
var _inspected_entity: Node = null
var _selected_buildings: Array[Building] = []
var _connected_buildings: Array[Building] = []
var _building_subgroups: Array[Dictionary] = []
var _active_building_subgroup_index: int = 0
var _active_subgroup_units: Array[Unit] = []
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
var _wireframe_grid: SelectionWireframeGrid = null
var _last_unit_subgroups: Array[Dictionary] = []
var _last_active_subgroup_idx: int = 0


func _ready() -> void:
	_setup_dynamic_bar_styles()
	_setup_wireframe_selection_grid()
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


func _on_teams_reconfigured(_mode: StringName = &"") -> void:
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
	var desired_half_w: float = 376.0
	var center_x: float = vp_width * 0.5
	if center_x - desired_half_w < minimap_clearance:
		var avail_w: float = clampf(vp_width - minimap_clearance - 12.0, 680.0, 756.0)
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

	_card_builder.apply_theme_to_grid(self)

	if _wireframe_grid != null:
		_wireframe_grid.apply_faction_theme(_active_hud_faction_id, _active_hud_accent)


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
		"G":
			return &"cmd_ability_g"
	return &""


func _get_ability_hotkey_display(hotkey_label: String, compact: bool = true) -> String:
	var act: StringName = _get_ability_action_name(hotkey_label)
	if act != &"" and SettingsManager != null:
		return SettingsManager.get_action_short_label(act) if compact else SettingsManager.get_action_display_label(act, false)
	return hotkey_label


func _on_keybind_changed(_action_name: StringName) -> void:
	_card_builder.refresh_dynamic_command_labels(self)
	_card_builder.refresh_stance_button(self)
	_card_builder.refresh_deploy_button(self)
	if not _card_builder.active_abilities.is_empty():
		_card_builder.refresh_all_ability_states(self)
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_card_builder.refresh_building_card(self, _inspected_entity as Building)
		if _building_subgroups.size() > 1:
			_telemetry.rebuild_building_subgroup_tabs(self, _building_subgroups, _active_building_subgroup_index)
	if _selection_controller != null and _selection_controller.subgroups.size() > 1:
		_telemetry.rebuild_subgroup_tabs(self, _selection_controller.subgroups, _selection_controller.active_subgroup_index)


func _on_display_settings_changed(category: StringName) -> void:
	if category == &"display" or category == &"all":
		call_deferred("_adjust_layout_for_minimap")
	if category == &"controls" or category == &"gameplay" or category == &"all":
		_on_keybind_changed(&"")


func _on_patrol_targeting_changed(active: bool) -> void:
	_patrol_targeting = active
	_card_builder.refresh_dynamic_command_labels(self)


func _on_attack_move_targeting_changed(active: bool) -> void:
	_amove_targeting = active
	_card_builder.refresh_dynamic_command_labels(self)


func _on_overclock_targeting_changed(active: bool) -> void:
	_overclock_targeting = active
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_card_builder.refresh_building_card(self, _inspected_entity as Building)


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
	if not _card_builder.active_abilities.is_empty():
		_card_builder.refresh_all_ability_states(self)
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_card_builder.refresh_building_card(self, _inspected_entity as Building)


func _on_bandwidth_updated(team: int, _used: int, _cap: int) -> void:
	if not _is_local_human_team(team):
		return
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_render_inspected_entity(_inspected_entity, false)


func _on_tech_updated(team: int) -> void:
	if not _is_local_human_team(team):
		return
	if not _card_builder.active_abilities.is_empty():
		_card_builder.refresh_all_ability_states(self)
	if _inspected_entity is Building and is_instance_valid(_inspected_entity):
		_render_inspected_entity(_inspected_entity, false)


func _on_control_groups_changed(summary: Dictionary) -> void:
	_telemetry.rebuild_control_group_row(self, summary)


func _on_selection_changed(selected_units: Array[Unit], subgroups: Array[Dictionary], active_subgroup_index: int) -> void:
	_disconnect_unit_signals()
	_active_subgroup_units = []
	_card_builder.active_abilities.clear()
	_card_builder.clear_building_bindings()
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
	_last_unit_subgroups = subgroups
	_last_active_subgroup_idx = safe_idx
	subgroup_tabs_row.visible = not is_single_unit
	unit_badges_grid.visible = false
	if _wireframe_grid != null:
		_wireframe_grid.visible = not is_single_unit
		if not is_single_unit:
			_wireframe_grid.set_unit_subgroups(subgroups, safe_idx)
		else:
			_wireframe_grid.clear_grid()
	telemetry_grid.visible = is_single_unit
	production_queue_box.visible = false

	command_grid.visible = true
	read_only_label.visible = false

	if is_single_unit:
		var lead_data: Dictionary = InspectionHelper.get_inspection_data(selected_units[0])
		_telemetry.apply_left_column(self, lead_data)
		_telemetry.rebuild_telemetry_grid(self, lead_data["stats"])
	else:
		_telemetry.refresh_squad_left_column(self, active_group)
		_telemetry.rebuild_subgroup_tabs(self, subgroups, safe_idx)

	_card_builder.rebuild_unit_card(self, active_group)
	_card_builder.refresh_all_ability_states(self)
	_card_builder.refresh_dynamic_command_labels(self)
	_card_builder.refresh_stance_button(self)
	_card_builder.refresh_deploy_button(self)
	if _selection_controller != null:
		_on_control_groups_changed(_selection_controller.get_control_groups_summary())


func _on_inspection_changed(entity: Node) -> void:
	_disconnect_inspected_signals()
	_inspected_entity = entity if (entity != null and is_instance_valid(entity)) else null
	if command_tooltip != null:
		command_tooltip.hide_tooltip()

	if _inspected_entity == null:
		_card_builder.clear_building_bindings()
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
	var is_multi_building: bool = (entity is Building and _selected_buildings.size() > 1)
	bottom_panel.visible = true
	subgroup_tabs_row.visible = show_building_tabs
	if show_building_tabs:
		_telemetry.rebuild_building_subgroup_tabs(self, _building_subgroups, _active_building_subgroup_index)
	unit_badges_grid.visible = false
	if _wireframe_grid != null:
		_wireframe_grid.visible = is_multi_building
		if is_multi_building:
			_wireframe_grid.set_building_subgroups(_building_subgroups, _active_building_subgroup_index, _selected_buildings)
		else:
			_wireframe_grid.clear_grid()
	telemetry_grid.visible = not is_multi_building

	_card_builder.clear_unit_bindings()

	_telemetry.apply_left_column(self, info)
	if not is_multi_building:
		_telemetry.rebuild_telemetry_grid(self, info["stats"])
	_telemetry.refresh_production_queue_ui(self, entity)

	var post_match_inspect: bool = _is_post_match_inspection()
	var is_commandable: bool = bool(info.get("is_commandable", false)) and not post_match_inspect
	if is_commandable and entity is Building:
		var building: Building = entity as Building
		read_only_label.visible = false
		command_grid.visible = true
		if rebuild_actions:
			_card_builder.rebuild_building_card(self, building)
		else:
			_card_builder.refresh_building_card(self, building)
	else:
		if rebuild_actions:
			_card_builder.clear_command_grid(self)
		command_grid.visible = false
		read_only_label.visible = true
		read_only_label.text = "POST-MATCH INSPECTION — READ-ONLY" if post_match_inspect else String(info.get("readonly_label", "READ-ONLY TELEMETRY"))


func _is_post_match_inspection() -> bool:
	if not is_inside_tree():
		return false
	var mm: Node = get_tree().get_first_node_in_group("match_manager")
	return mm != null and is_instance_valid(mm) and bool(mm.get("is_inspecting_post_match"))


func _on_inspected_entity_updated(_arg1: Variant = null, _arg2: Variant = null, _arg3: Variant = null) -> void:
	if _inspected_entity == null or not is_instance_valid(_inspected_entity):
		bottom_panel.visible = false
		return
	_render_inspected_entity(_inspected_entity, false)


func _on_inspected_building_construction_changed(building: Building, _progress: float, constructed: bool) -> void:
	if building == _inspected_entity and is_instance_valid(building):
		_render_inspected_entity(building, constructed)


func _on_inspected_building_progress_updated(building: Building) -> void:
	if building == _inspected_entity and is_instance_valid(building):
		_telemetry.update_production_progress_bar(self, building)


func _on_inspected_entity_removed(_arg: Variant = null) -> void:
	_disconnect_inspected_signals()
	_inspected_entity = null
	_card_builder.clear_building_bindings()
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
		if b.has_signal("training_progress_updated") and not b.training_progress_updated.is_connected(_on_inspected_building_progress_updated):
			b.training_progress_updated.connect(_on_inspected_building_progress_updated)
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
	elif entity.is_in_group("hyper_uplinks"):
		if entity.has_signal("capture_state_changed") and not entity.is_connected("capture_state_changed", _on_inspected_entity_updated):
			entity.connect("capture_state_changed", _on_inspected_entity_updated)
		if entity.has_signal("controller_changed") and not entity.is_connected("controller_changed", _on_inspected_entity_updated):
			entity.connect("controller_changed", _on_inspected_entity_updated)
	elif entity.is_in_group("fog_ghost_handles"):
		if entity.has_signal("ghost_invalidated") and not entity.is_connected("ghost_invalidated", _on_inspected_entity_removed):
			entity.connect("ghost_invalidated", _on_inspected_entity_removed)


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
		if b.has_signal("training_progress_updated") and b.training_progress_updated.is_connected(_on_inspected_building_progress_updated):
			b.training_progress_updated.disconnect(_on_inspected_building_progress_updated)
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
	elif _inspected_entity.is_in_group("hyper_uplinks"):
		if _inspected_entity.has_signal("capture_state_changed") and _inspected_entity.is_connected("capture_state_changed", _on_inspected_entity_updated):
			_inspected_entity.disconnect("capture_state_changed", _on_inspected_entity_updated)
		if _inspected_entity.has_signal("controller_changed") and _inspected_entity.is_connected("controller_changed", _on_inspected_entity_updated):
			_inspected_entity.disconnect("controller_changed", _on_inspected_entity_updated)
	elif _inspected_entity.is_in_group("fog_ghost_handles"):
		if _inspected_entity.has_signal("ghost_invalidated") and _inspected_entity.is_connected("ghost_invalidated", _on_inspected_entity_removed):
			_inspected_entity.disconnect("ghost_invalidated", _on_inspected_entity_removed)


func _on_ability_targeting_changed(active_ability: AbilityData) -> void:
	_targeting_ability = active_ability
	_card_builder.refresh_all_ability_states(self)


func _on_unit_health_changed(_unit: Unit, _current_hp: float, _max_hp: float) -> void:
	_refresh_selected_units_display()


func _on_unit_ability_cooldown_updated(ability_id: StringName, _remaining: float, _duration: float) -> void:
	_card_builder.refresh_single_ability_button(self, ability_id)


func _on_unit_cargo_changed(_unit: Unit, _resource_type: StringName, _amount: int) -> void:
	_refresh_selected_units_display()


func _on_unit_status_changed(_unit: Unit) -> void:
	_refresh_selected_units_display()


func _on_unit_stance_changed(_unit: Unit, _new_stance: Unit.Stance) -> void:
	_card_builder.refresh_stance_button(self)
	_card_builder.refresh_deploy_button(self)


func _refresh_selected_units_display() -> void:
	if _selection_controller == null:
		return
	var active_group: Dictionary = _selection_controller.get_active_subgroup()
	if active_group.is_empty():
		return
	if _selection_controller.selected_units.size() == 1 and is_instance_valid(_selection_controller.selected_units[0]):
		var lead_info: Dictionary = InspectionHelper.get_inspection_data(_selection_controller.selected_units[0])
		_telemetry.apply_left_column(self, lead_info)
		_telemetry.rebuild_telemetry_grid(self, lead_info["stats"])
	else:
		_telemetry.refresh_squad_left_column(self, active_group)
		if _wireframe_grid != null and _wireframe_grid.visible:
			_wireframe_grid.redraw_visible_tiles()
	_card_builder.refresh_stance_button(self)
	_card_builder.refresh_deploy_button(self)


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


func _setup_wireframe_selection_grid() -> void:
	if unit_badges_grid == null or _wireframe_grid != null:
		return
	var center_panel: Node = unit_badges_grid.get_parent()
	if center_panel == null:
		return
	unit_badges_grid.visible = false
	_wireframe_grid = WIREFRAME_GRID_SCRIPT.new() as SelectionWireframeGrid
	_wireframe_grid.name = "SelectionWireframeGrid"
	_wireframe_grid.visible = false
	_wireframe_grid.entity_tile_clicked.connect(_on_wireframe_tile_clicked)
	_wireframe_grid.entity_tile_right_clicked.connect(_on_wireframe_tile_right_clicked)
	_wireframe_grid.entity_tile_hovered.connect(_on_wireframe_tile_hovered)
	_wireframe_grid.entity_tile_unhovered.connect(_on_wireframe_tile_unhovered)
	center_panel.add_child(_wireframe_grid)
	center_panel.move_child(_wireframe_grid, unit_badges_grid.get_index())


func _on_wireframe_tile_clicked(entity: Node, shift_held: bool, ctrl_held: bool, is_double_click: bool) -> void:
	if _selection_controller == null or entity == null or not is_instance_valid(entity):
		return
	if command_tooltip != null:
		command_tooltip.hide_tooltip()
	if ctrl_held and shift_held:
		_selection_controller.remove_entity_type_from_selection(entity)
	elif ctrl_held or is_double_click:
		_selection_controller.filter_selection_to_entity_type(entity)
	elif shift_held:
		_selection_controller.deselect_entity(entity)
	else:
		_selection_controller.select_only_entity(entity)


func _on_wireframe_tile_right_clicked(entity: Node) -> void:
	if _selection_controller == null or entity == null or not is_instance_valid(entity):
		return
	if command_tooltip != null:
		command_tooltip.hide_tooltip()
	_selection_controller.focus_camera_on_entity(entity)


func _on_wireframe_tile_hovered(entity: Node, _tile_global_rect: Rect2) -> void:
	_telemetry.show_wireframe_hover_tooltip(self, entity)


func _on_wireframe_tile_unhovered(_entity: Node) -> void:
	if command_tooltip != null:
		command_tooltip.hide_tooltip()


func _rebuild_unit_badges(_units: Array[Unit]) -> void:
	if _wireframe_grid != null and _wireframe_grid.visible:
		_wireframe_grid.redraw_visible_tiles()
