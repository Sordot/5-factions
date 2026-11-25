class_name TechTreeOverlay
extends CanvasLayer

signal closed

@onready var root_control: Control = %RootControl
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var btn_close: Button = %BtnClose
@onready var faction_tabs_row: HBoxContainer = %FactionTabsRow
@onready var columns_row: HBoxContainer = %ColumnsRow

var _tracked_team: int = 0
var _selected_faction_id: StringName = &""
var _refresh_timer: float = 0.0
var _card_refs: Array[Dictionary] = []
var _upgrade_refs: Array[Dictionary] = []


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("tech_tree_overlay")
	if TeamManager != null:
		var human_team: int = TeamManager.get_local_human_team()
		_tracked_team = human_team if human_team >= 0 else 0
		_selected_faction_id = TeamManager.get_team_faction(_tracked_team)
	if btn_close != null:
		btn_close.pressed.connect(close_overlay)
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()
	_rebuild_faction_tabs()
	_rebuild_tree()


func _exit_tree() -> void:
	if SettingsManager != null:
		SettingsManager.call_deferred("refresh_mouse_mode")


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= 0.5:
		_refresh_timer = 0.0
		_refresh_live_states()


func _input(event: InputEvent) -> void:
	if not visible or event.is_echo():
		return
	if event.is_action_pressed("cmd_cancel") or event.is_action_pressed("ui_toggle_tech_tree"):
		get_viewport().set_input_as_handled()
		close_overlay()


func close_overlay() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	closed.emit()
	queue_free()


func _resolve_active_faction() -> FactionData:
	if TeamManager == null:
		return null
	if _selected_faction_id != &"":
		var f: FactionData = TeamManager.get_faction_data(_selected_faction_id)
		if f != null:
			return f
	var team_f: FactionData = TeamManager.get_team_faction_data(_tracked_team)
	if team_f != null:
		_selected_faction_id = team_f.faction_id
		return team_f
	var playable: Array[FactionData] = TeamManager.get_playable_factions()
	if not playable.is_empty():
		_selected_faction_id = playable[0].faction_id
		return playable[0]
	return null


func _rebuild_faction_tabs() -> void:
	if faction_tabs_row == null or TeamManager == null:
		return
	for child: Node in faction_tabs_row.get_children():
		child.queue_free()
	var playable: Array[FactionData] = TeamManager.get_playable_factions()
	if playable.size() <= 1:
		faction_tabs_row.visible = false
		return
	faction_tabs_row.visible = true
	for fdata: FactionData in playable:
		if fdata == null:
			continue
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = fdata.short_code if not fdata.short_code.is_empty() else fdata.display_name
		btn.custom_minimum_size = Vector2(96.0, 24.0)
		var is_sel: bool = (fdata.faction_id == _selected_faction_id)
		btn.modulate = fdata.hud_accent_color if is_sel else Color(0.72, 0.80, 0.86, 0.85)
		var fid: StringName = fdata.faction_id
		btn.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.play_ui_click()
			_selected_faction_id = fid
			_rebuild_faction_tabs()
			_rebuild_tree()
		)
		faction_tabs_row.add_child(btn)


func _rebuild_tree() -> void:
	if columns_row == null or not is_inside_tree():
		return
	for child: Node in columns_row.get_children():
		child.queue_free()
	_card_refs.clear()
	_upgrade_refs.clear()

	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	var faction: FactionData = _resolve_active_faction()
	var hk: String = SettingsManager.get_action_display_label(&"ui_toggle_tech_tree", true) if SettingsManager != null else "U"
	if btn_close != null:
		btn_close.text = ("Close (%s)" % hk) if not hk.is_empty() else "Close"

	var accent_col: Color = faction.hud_accent_color if faction != null else Color(0.32, 0.98, 0.92, 1.0)
	var fac_code: String = faction.short_code if (faction != null and not faction.short_code.is_empty()) else (faction.display_name if faction != null else "FACTION")
	var fac_name: String = faction.display_name if faction != null else "Unknown Faction"
	var team_fac_id: StringName = TeamManager.get_team_faction(_tracked_team) if TeamManager != null else &""
	var is_local_faction: bool = (faction != null and faction.faction_id == team_fac_id)

	if title_label != null:
		title_label.text = "%s // TACTICAL TECH TREE & COUNTER MATRIX" % fac_code
		title_label.add_theme_color_override("font_color", accent_col)

	if subtitle_label != null:
		var team_tag: String = TeamManager.get_team_display_name(_tracked_team) if TeamManager != null else "PLAYER"
		var mode_note: String = "Owned structures & tech highlighted live" if is_local_faction else "Reference dossier (non-active faction)"
		subtitle_label.text = "%s  •  Tracking: %s  •  %s  •  Press %s or Esc to close" % [
			fac_name,
			team_tag,
			mode_note,
			hk if not hk.is_empty() else "Esc",
		]

	if faction == null:
		return

	var tier_defs: Array[Dictionary] = [
		{"tier": 0, "header": "TIER 0 // CORE & ECONOMY", "accent": accent_col, "buildings": []},
		{"tier": 1, "header": "TIER 1 // PRODUCTION & COUNTERS", "accent": Color(0.98, 0.78, 0.30, 1.0), "buildings": []},
		{"tier": 2, "header": "TIER 2 // HEAVY & ELITE", "accent": Color(0.42, 0.94, 1.0, 1.0), "buildings": []},
	]

	for bdata: BuildingData in faction.building_roster:
		if bdata == null or bdata.tech_tier < 0:
			continue
		var bucket_idx: int = clampi(bdata.tech_tier, 0, 2)
		(tier_defs[bucket_idx]["buildings"] as Array).append(bdata)

	for tier_def: Dictionary in tier_defs:
		var col_vbox: VBoxContainer = VBoxContainer.new()
		col_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col_vbox.add_theme_constant_override("separation", 8)

		var hdr: Label = Label.new()
		hdr.text = String(tier_def["header"])
		hdr.add_theme_font_size_override("font_size", 12)
		hdr.add_theme_color_override("font_color", tier_def["accent"] as Color)
		col_vbox.add_child(hdr)

		for b_raw: Variant in (tier_def["buildings"] as Array):
			if b_raw is BuildingData:
				var card: PanelContainer = _build_tech_card(b_raw as BuildingData, faction, econ, is_local_faction)
				col_vbox.add_child(card)

		columns_row.add_child(col_vbox)


func _build_tech_card(bdata: BuildingData, faction: FactionData, econ: EconomyManager, track_live: bool) -> PanelContainer:
	var owned: bool = track_live and econ != null and econ.has_constructed_building(_tracked_team, bdata.building_id)
	var prereq_ids: Array[StringName] = bdata.get_prerequisite_ids()
	var req_met: bool = true
	if track_live and not prereq_ids.is_empty():
		for pid: StringName in prereq_ids:
			if econ == null or not econ.has_constructed_building(_tracked_team, pid):
				req_met = false
				break

	var panel: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(2 if owned else 1)
	if owned:
		sb.bg_color = Color(0.06, 0.16, 0.19, 0.96)
		sb.border_color = faction.hud_accent_color
	elif track_live and not req_met:
		sb.bg_color = Color(0.08, 0.07, 0.09, 0.92)
		sb.border_color = Color(0.62, 0.36, 0.34, 0.72)
	else:
		sb.bg_color = Color(0.05, 0.09, 0.13, 0.94)
		sb.border_color = Color(0.26, 0.56, 0.68, 0.72)
	panel.add_theme_stylebox_override("panel", sb)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)

	var top: HBoxContainer = HBoxContainer.new()
	var name_lbl: Label = Label.new()
	name_lbl.text = bdata.display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", faction.hud_accent_color if owned else Color(0.92, 0.98, 1.0, 1.0))
	top.add_child(name_lbl)

	var status_lbl: Label = Label.new()
	status_lbl.add_theme_font_size_override("font_size", 10)
	if not track_live:
		status_lbl.text = "[TIER %d]" % bdata.tech_tier
		status_lbl.add_theme_color_override("font_color", Color(0.62, 0.82, 0.90, 0.85))
	elif owned:
		status_lbl.text = "[ONLINE]"
		status_lbl.add_theme_color_override("font_color", Color(0.28, 1.0, 0.68, 1.0))
	elif not req_met:
		status_lbl.text = "[LOCKED]"
		status_lbl.add_theme_color_override("font_color", Color(1.0, 0.46, 0.36, 0.95))
	else:
		status_lbl.text = "[AVAILABLE]"
		status_lbl.add_theme_color_override("font_color", Color(0.62, 0.82, 0.90, 0.85))
	top.add_child(status_lbl)
	vbox.add_child(top)

	var cost_parts: PackedStringArray = PackedStringArray()
	var cost_str: String = bdata.get_cost_label()
	if not cost_str.is_empty():
		cost_parts.append(cost_str)
	if not bdata.tech_tree_summary.is_empty():
		cost_parts.append(bdata.tech_tree_summary)
	if not cost_parts.is_empty():
		var cost_lbl: Label = Label.new()
		cost_lbl.text = "  •  ".join(cost_parts)
		cost_lbl.add_theme_font_size_override("font_size", 10)
		cost_lbl.add_theme_color_override("font_color", Color(0.96, 0.82, 0.40, 0.95))
		vbox.add_child(cost_lbl)

	var prereq_lines: PackedStringArray = PackedStringArray()
	if not prereq_ids.is_empty():
		var req_names: PackedStringArray = PackedStringArray()
		for pid: StringName in prereq_ids:
			var req_b: BuildingData = faction.get_building_by_id(pid)
			req_names.append(req_b.display_name if req_b != null else String(pid).capitalize())
		prereq_lines.append("Requires: %s" % ", ".join(req_names))
	elif bdata.requires_vent:
		prereq_lines.append("Build on Compute Vent")
	var pr_lbl: Label = null
	if not prereq_lines.is_empty():
		pr_lbl = Label.new()
		pr_lbl.text = "  •  ".join(prereq_lines)
		pr_lbl.add_theme_font_size_override("font_size", 10)
		pr_lbl.add_theme_color_override("font_color", Color(0.46, 0.92, 0.96, 0.90) if req_met else Color(1.0, 0.56, 0.38, 0.95))
		vbox.add_child(pr_lbl)

	_card_refs.append({
		"bdata": bdata,
		"faction": faction,
		"track_live": track_live,
		"sb": sb,
		"name_lbl": name_lbl,
		"status_lbl": status_lbl,
		"pr_lbl": pr_lbl,
	})

	var trainable: Array[UnitData] = bdata.resolve_trainable_units()
	if not trainable.is_empty():
		var batch_tag: String = " x%d" % bdata.batch_production_count if bdata.batch_production_count > 1 else ""
		for udata: UnitData in trainable:
			if udata == null:
				continue
			var u_cost: String = udata.get_cost_label()
			var role_tag: String = (" — %s" % udata.role_tags_display) if not udata.role_tags_display.is_empty() else ""
			var ul: Label = Label.new()
			ul.text = "• %s%s (%s)%s" % [udata.display_name, batch_tag, u_cost, role_tag]
			ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ul.add_theme_font_size_override("font_size", 10)
			ul.add_theme_color_override("font_color", Color(0.84, 0.93, 0.97, 0.94))
			vbox.add_child(ul)
	elif not bdata.tech_tree_summary.is_empty():
		var desc_lbl: Label = Label.new()
		desc_lbl.text = "• %s" % bdata.tech_tree_summary
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", Color(0.84, 0.93, 0.97, 0.94))
		vbox.add_child(desc_lbl)

	for upg: UpgradeData in bdata.researchable_upgrades:
		if upg == null:
			continue
		var done: bool = track_live and econ != null and econ.has_upgrade(_tracked_team, upg.upgrade_id)
		var prog: bool = track_live and econ != null and econ.is_upgrade_in_progress(_tracked_team, upg.upgrade_id)
		var tag: String = "[DONE] " if done else ("[RESEARCHING] " if prog else "[UPG] ")
		var upg_cost: String = _format_upgrade_cost(upg)
		var upg_lbl: Label = Label.new()
		upg_lbl.text = "%s%s (%s) — %s" % [tag, upg.display_name, upg_cost, upg.description]
		upg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		upg_lbl.add_theme_font_size_override("font_size", 10)
		if done:
			upg_lbl.add_theme_color_override("font_color", Color(0.32, 1.0, 0.72, 1.0))
		elif prog:
			upg_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.34, 1.0))
		else:
			upg_lbl.add_theme_color_override("font_color", Color(0.96, 0.84, 0.50, 0.92))
		vbox.add_child(upg_lbl)
		_upgrade_refs.append({
			"upg": upg,
			"lbl": upg_lbl,
			"cost_str": upg_cost,
			"track_live": track_live,
		})

	panel.add_child(vbox)
	return panel


func _refresh_live_states() -> void:
	if not is_inside_tree():
		return
	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	for ref: Dictionary in _card_refs:
		var track_live: bool = bool(ref["track_live"])
		if not track_live:
			continue
		var bdata: BuildingData = ref["bdata"] as BuildingData
		var faction: FactionData = ref["faction"] as FactionData
		var sb: StyleBoxFlat = ref["sb"] as StyleBoxFlat
		var name_lbl: Label = ref["name_lbl"] as Label
		var status_lbl: Label = ref["status_lbl"] as Label
		var pr_lbl: Label = ref["pr_lbl"] as Label
		if bdata == null or sb == null or not is_instance_valid(status_lbl):
			continue
		var owned: bool = econ != null and econ.has_constructed_building(_tracked_team, bdata.building_id)
		var prereq_ids: Array[StringName] = bdata.get_prerequisite_ids()
		var req_met: bool = true
		for pid: StringName in prereq_ids:
			if econ == null or not econ.has_constructed_building(_tracked_team, pid):
				req_met = false
				break
		sb.set_border_width_all(2 if owned else 1)
		if owned:
			sb.bg_color = Color(0.06, 0.16, 0.19, 0.96)
			sb.border_color = faction.hud_accent_color
			status_lbl.text = "[ONLINE]"
			status_lbl.add_theme_color_override("font_color", Color(0.28, 1.0, 0.68, 1.0))
			if is_instance_valid(name_lbl):
				name_lbl.add_theme_color_override("font_color", faction.hud_accent_color)
		elif not req_met:
			sb.bg_color = Color(0.08, 0.07, 0.09, 0.92)
			sb.border_color = Color(0.62, 0.36, 0.34, 0.72)
			status_lbl.text = "[LOCKED]"
			status_lbl.add_theme_color_override("font_color", Color(1.0, 0.46, 0.36, 0.95))
			if is_instance_valid(name_lbl):
				name_lbl.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0, 1.0))
		else:
			sb.bg_color = Color(0.05, 0.09, 0.13, 0.94)
			sb.border_color = Color(0.26, 0.56, 0.68, 0.72)
			status_lbl.text = "[AVAILABLE]"
			status_lbl.add_theme_color_override("font_color", Color(0.62, 0.82, 0.90, 0.85))
			if is_instance_valid(name_lbl):
				name_lbl.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0, 1.0))
		if pr_lbl != null and is_instance_valid(pr_lbl):
			pr_lbl.add_theme_color_override("font_color", Color(0.46, 0.92, 0.96, 0.90) if req_met else Color(1.0, 0.56, 0.38, 0.95))

	for uref: Dictionary in _upgrade_refs:
		var track_live: bool = bool(uref["track_live"])
		if not track_live:
			continue
		var upg: UpgradeData = uref["upg"] as UpgradeData
		var upg_lbl: Label = uref["lbl"] as Label
		if upg == null or not is_instance_valid(upg_lbl):
			continue
		var done: bool = econ != null and econ.has_upgrade(_tracked_team, upg.upgrade_id)
		var prog: bool = econ != null and econ.is_upgrade_in_progress(_tracked_team, upg.upgrade_id)
		var tag: String = "[DONE] " if done else ("[RESEARCHING] " if prog else "[UPG] ")
		upg_lbl.text = "%s%s (%s) — %s" % [tag, upg.display_name, String(uref["cost_str"]), upg.description]
		if done:
			upg_lbl.add_theme_color_override("font_color", Color(0.32, 1.0, 0.72, 1.0))
		elif prog:
			upg_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.34, 1.0))
		else:
			upg_lbl.add_theme_color_override("font_color", Color(0.96, 0.84, 0.50, 0.92))


func _format_upgrade_cost(upg: UpgradeData) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if upg.biomass_cost > 0:
		parts.append("%dB" % upg.biomass_cost)
	if upg.silica_cost > 0:
		parts.append("%dS" % upg.silica_cost)
	if upg.compute_cost > 0:
		parts.append("%dC" % upg.compute_cost)
	return "/".join(parts) if not parts.is_empty() else "Free"
