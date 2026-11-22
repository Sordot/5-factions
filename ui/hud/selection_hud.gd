class_name SelectionHUD
extends Control

@export var selection_controller_path: NodePath

@onready var bottom_panel: PanelContainer = %BottomPanel
@onready var portrait_swatch: ColorRect = %PortraitSwatch
@onready var unit_name_label: Label = %UnitNameLabel
@onready var unit_hp_label: Label = %UnitHPLabel
@onready var unit_stats_label: Label = %UnitStatsLabel
@onready var subgroup_tabs_row: HBoxContainer = %SubgroupTabsRow
@onready var unit_badges_grid: GridContainer = %UnitBadgesGrid
@onready var ability_row: HBoxContainer = %AbilityRow
@onready var btn_cmd_move: Button = %BtnCmdMove
@onready var btn_cmd_stop: Button = %BtnCmdStop
@onready var btn_cmd_hold: Button = %BtnCmdHold
@onready var btn_cmd_amove: Button = %BtnCmdAMove

var _selection_controller: SelectionController = null
var _connected_units: Array[Unit] = []
var _active_subgroup_units: Array[Unit] = []
var _active_abilities: Array[AbilityData] = []
var _ability_buttons: Dictionary = {}
var _targeting_ability: AbilityData = null


func _ready() -> void:
	_selection_controller = get_node_or_null(selection_controller_path) as SelectionController
	if _selection_controller != null:
		_selection_controller.selection_changed.connect(_on_selection_changed)
		_selection_controller.ability_targeting_changed.connect(_on_ability_targeting_changed)

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


func _on_selection_changed(selected_units: Array[Unit], subgroups: Array[Dictionary], active_subgroup_index: int) -> void:
	_disconnect_unit_signals()
	_active_subgroup_units = []
	_active_abilities = []

	if selected_units.is_empty() or subgroups.is_empty():
		bottom_panel.visible = false
		return

	bottom_panel.visible = true
	var safe_idx: int = clampi(active_subgroup_index, 0, subgroups.size() - 1)
	var active_group: Dictionary = subgroups[safe_idx]
	_active_subgroup_units = active_group["units"]

	_connect_unit_signals(_active_subgroup_units)
	_rebuild_subgroup_tabs(subgroups, safe_idx)
	_rebuild_unit_badges(_active_subgroup_units)
	_rebuild_ability_buttons(active_group)
	_refresh_left_panel(active_group)
	_refresh_all_ability_states()


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


func _connect_unit_signals(units: Array[Unit]) -> void:
	for item: Variant in units:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item
		if not unit.health_changed.is_connected(_on_unit_health_changed):
			unit.health_changed.connect(_on_unit_health_changed)
		if not unit.ability_cooldown_updated.is_connected(_on_unit_ability_cooldown_updated):
			unit.ability_cooldown_updated.connect(_on_unit_ability_cooldown_updated)
		_connected_units.append(unit)


func _disconnect_unit_signals() -> void:
	for item: Variant in _connected_units:
		if is_instance_valid(item) and item is Unit:
			var unit: Unit = item
			if unit.health_changed.is_connected(_on_unit_health_changed):
				unit.health_changed.disconnect(_on_unit_health_changed)
			if unit.ability_cooldown_updated.is_connected(_on_unit_ability_cooldown_updated):
				unit.ability_cooldown_updated.disconnect(_on_unit_ability_cooldown_updated)
	_connected_units.clear()


func _refresh_left_panel(active_group: Dictionary) -> void:
	var data: UnitData = active_group.get("data", null) as UnitData
	var units: Array[Unit] = active_group.get("units", [])
	var count: int = units.size()
	var display_name: String = active_group.get("display_name", "Unit")
	unit_name_label.text = "%s  x%d" % [display_name, count]

	if data != null and data.unit_type_id == &"scout_unit":
		portrait_swatch.color = Color(0.98, 0.78, 0.24, 1.0)
	else:
		portrait_swatch.color = Color(0.24, 0.92, 0.88, 1.0)

	if count > 0 and is_instance_valid(units[0]) and data != null:
		var lead: Unit = units[0]
		unit_hp_label.text = "HP: %d / %d" % [int(round(lead.current_hp)), int(round(data.max_hp))]
		unit_stats_label.text = "DMG: %d  |  SPD: %d  |  RNG: %d" % [
			int(round(data.attack_damage)),
			int(round(data.move_speed)),
			int(round(data.attack_range)),
		]
	else:
		unit_hp_label.text = "HP: --"
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
		btn.custom_minimum_size = Vector2(150.0, 36.0)
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

	var is_targeting: bool = (_targeting_ability != null and _targeting_ability.ability_id == ability_id)
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
