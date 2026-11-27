class_name SelectionTelemetryRenderer
extends RefCounted

var _short_name_cache: Dictionary = {}
var _short_name_cache_built: bool = false


func _ensure_short_name_cache() -> void:
	if _short_name_cache_built:
		return
	_short_name_cache_built = true
	if TeamManager == null or not TeamManager.has_method("get_playable_factions"):
		return
	for fd: FactionData in TeamManager.get_playable_factions():
		if fd == null:
			continue
		for u: UnitData in fd.unit_roster:
			if u != null and not u.display_name.is_empty():
				_short_name_cache[u.display_name] = u.get_short_name()
		for b: BuildingData in fd.building_roster:
			if b != null and not b.display_name.is_empty():
				_short_name_cache[b.display_name] = b.get_short_name()
		for upg: UpgradeData in fd.upgrade_roster:
			if upg != null and not upg.display_name.is_empty():
				_short_name_cache[upg.display_name] = upg.get_short_name()


func shorten_name(full_name: String) -> String:
	_ensure_short_name_cache()
	if _short_name_cache.has(full_name):
		return String(_short_name_cache[full_name])
	return full_name


func apply_left_column(hud: SelectionHUD, info: Dictionary) -> void:
	var accent: Color = info.get("accent_color", hud._active_hud_accent) as Color
	hud.portrait_swatch.color = accent
	hud.unit_name_label.text = String(info.get("title", "Entity"))
	hud.entity_subtitle_label.text = String(info.get("subtitle", "TELEMETRY"))
	hud.entity_subtitle_label.modulate = accent

	var show_hp: bool = bool(info.get("show_hp_bar", false))
	hud.hp_box.visible = show_hp
	if show_hp:
		var cur_hp: float = float(info.get("hp_current", 0.0))
		var max_hp: float = maxf(1.0, float(info.get("hp_max", 1.0)))
		hud.unit_hp_label.text = "HP %s/%s" % [
			InspectionHelper.format_number(int(round(cur_hp))),
			InspectionHelper.format_number(int(round(max_hp))),
		]
		hud.unit_hp_bar.max_value = max_hp
		hud.unit_hp_bar.value = clampf(cur_hp, 0.0, max_hp)
		var is_enemy: bool = (info.get("affiliation", &"neutral") == &"enemy")
		if hud._hp_fill_style != null:
			hud._hp_fill_style.bg_color = Color(0.96, 0.34, 0.26, 1.0) if is_enemy else Color(0.24, 0.94, 0.74, 1.0)

		var show_shd: bool = bool(info.get("show_shield_bar", false)) and float(info.get("shield_max", 0.0)) > 0.0
		if hud._shield_label != null and hud._shield_bar != null:
			hud._shield_label.visible = show_shd
			hud._shield_bar.visible = show_shd
			if show_shd:
				var cur_shd: float = float(info.get("shield_current", 0.0))
				var max_shd: float = maxf(1.0, float(info.get("shield_max", 1.0)))
				hud._shield_label.text = "SH %s/%s" % [
					InspectionHelper.format_number(int(round(cur_shd))),
					InspectionHelper.format_number(int(round(max_shd))),
				]
				hud._shield_bar.max_value = max_shd
				hud._shield_bar.value = clampf(cur_shd, 0.0, max_shd)
	elif hud._shield_label != null and hud._shield_bar != null:
		hud._shield_label.visible = false
		hud._shield_bar.visible = false

	var show_primary: bool = bool(info.get("show_primary_bar", false))
	hud.primary_gauge_box.visible = show_primary
	if show_primary:
		hud.primary_gauge_label.text = String(info.get("primary_bar_label", ""))
		hud.primary_gauge_bar.max_value = maxf(1.0, float(info.get("primary_bar_max", 100.0)))
		hud.primary_gauge_bar.value = clampf(float(info.get("primary_bar_value", 0.0)), 0.0, hud.primary_gauge_bar.max_value)
		if hud._gauge_fill_style != null:
			hud._gauge_fill_style.bg_color = info.get("primary_bar_color", accent) as Color


func refresh_squad_left_column(hud: SelectionHUD, active_group: Dictionary) -> void:
	var units: Array[Unit] = active_group.get("units", [])
	if units.is_empty() or not is_instance_valid(units[0]):
		return
	var lead_info: Dictionary = InspectionHelper.get_inspection_data(units[0])
	lead_info["title"] = "%s x%d" % [String(active_group.get("display_name", "Unit")), units.size()]
	apply_left_column(hud, lead_info)


func rebuild_telemetry_grid(hud: SelectionHUD, stats: Variant) -> void:
	for child: Node in hud.telemetry_grid.get_children():
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
		k_label.add_theme_color_override("font_color", Color(0.58, 0.72, 0.80, 0.90) if hud._active_hud_faction_id != &"monolith_os" else Color(0.76, 0.75, 0.72, 0.90))
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

		hud.telemetry_grid.add_child(cell)


func update_production_progress_bar(hud: SelectionHUD, building: Building) -> void:
	if hud == null or hud.production_queue_box == null:
		return
	if building == null or not is_instance_valid(building) or not building.is_constructed or building.production_component == null or building.production_component.get_queue_size() == 0:
		hud.production_queue_box.visible = false
		return

	hud.production_queue_box.visible = true
	var status: Dictionary = building.get_active_training_status()
	var pct: int = int(round(float(status.get("progress", 0.0)) * 100.0))
	if building.requires_power_grid and not building.is_powered:
		hud.production_label.text = "UNPOWERED — PAUSED (%d%%)" % pct
		if hud._prod_fill_style != null:
			hud._prod_fill_style.bg_color = Color(0.92, 0.42, 0.24, 0.95)
	else:
		var kind: StringName = status.get("kind", ProductionComponent.KIND_UNIT)
		var active_name: String = String(status.get("display_name", "Unit"))
		var batch_cnt: int = int(status.get("batch_count", 1))
		if kind == ProductionComponent.KIND_UPGRADE:
			hud.production_label.text = "Research %s (%d%%)" % [shorten_name(active_name), pct]
		elif batch_cnt > 1:
			hud.production_label.text = "Cloning %s x%d (%d%%)" % [shorten_name(active_name), batch_cnt, pct]
		else:
			hud.production_label.text = "Training %s (%d%%)" % [shorten_name(active_name), pct]
		if building.is_overclocked():
			hud.production_label.text += " [%.1fx]" % building.overclock_speed_mult
			if hud._prod_fill_style != null:
				hud._prod_fill_style.bg_color = Color(1.0, 0.624, 0.110, 1.0)
		elif hud._prod_fill_style != null:
			hud._prod_fill_style.bg_color = hud._active_hud_accent
	hud.production_bar.max_value = 100.0
	hud.production_bar.value = float(pct)


func refresh_production_queue_ui(hud: SelectionHUD, entity: Node) -> void:
	if hud.production_queue_box == null:
		return
	if not (entity is Building) or not is_instance_valid(entity):
		hud.production_queue_box.visible = false
		return
	var building: Building = entity as Building
	if not building.is_constructed or building.production_component == null or building.production_component.get_queue_size() == 0:
		hud.production_queue_box.visible = false
		return

	update_production_progress_bar(hud, building)

	for child: Node in hud.queue_slots_row.get_children():
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
			if not is_instance_valid(hud) or hud._is_post_match_inspection():
				return
			if AudioManager != null:
				AudioManager.play_ui_click()
			if is_instance_valid(captured_b):
				captured_b.cancel_queued_unit(captured_idx)
		)

		if entry_kind == ProductionComponent.KIND_UPGRADE:
			var upg: UpgradeData = entry.get("data", null) as UpgradeData
			var upg_name: String = upg.display_name if upg != null else "Upgrade"
			var upg_short: String = upg.get_short_name() if upg != null else shorten_name(upg_name)
			slot_btn.text = "[%d] %s" % [i + 1, upg_short]
			slot_btn.modulate = Color(1.0, 0.86, 0.42, 1.0) if i == 0 else Color(0.88, 0.78, 0.56, 0.9)
			var refund_upg: String = String(entry.get("cost_label", "100%"))
			hud._attach_tooltip(
				slot_btn,
				"Cancel %s" % upg_name,
				"LMB",
				"100%% Refund: %s" % refund_upg,
				"Click to cancel this queued upgrade and refund 100% of resources."
			)
		else:
			var u_data: UnitData = entry.get("data", null) as UnitData
			var b_cnt: int = int(entry.get("batch_count", 1))
			var short_name: String = u_data.get_short_name() if u_data != null else "Unit"
			slot_btn.text = "[%d] %s%s" % [i + 1, short_name, (" x%d" % b_cnt) if b_cnt > 1 else ""]
			slot_btn.modulate = Color(0.45, 0.98, 0.92, 1.0) if i == 0 else Color(0.76, 0.86, 0.92, 0.9)
			var refund_str: String = String(entry.get("cost_label", u_data.get_cost_label() if u_data != null else "100%"))
			var bw_val: int = int(entry.get("bandwidth_cost", u_data.bandwidth_cost if u_data != null else 1))
			hud._attach_tooltip(
				slot_btn,
				"Cancel %s%s" % [u_data.display_name if u_data != null else "Unit", (" (x%d)" % b_cnt) if b_cnt > 1 else ""],
				"LMB",
				"100%% Refund: %s  •  Frees %d BW" % [refund_str, bw_val],
				"Click to cancel this queued production and refund 100% of resources and reserved Bandwidth."
			)
		hud.queue_slots_row.add_child(slot_btn)


func rebuild_subgroup_tabs(hud: SelectionHUD, subgroups: Array[Dictionary], active_index: int) -> void:
	for child: Node in hud.subgroup_tabs_row.get_children():
		child.queue_free()

	var max_tabs: int = mini(subgroups.size(), 4)
	for i: int in range(max_tabs):
		var group: Dictionary = subgroups[i]
		var group_units: Array[Unit] = group["units"]
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 10)
		var prefix: String = ">" if i == active_index else ""
		btn.text = "%s%s (%d)" % [prefix, shorten_name(String(group["display_name"])), group_units.size()]
		btn.modulate = hud._active_hud_accent if i == active_index else Color(0.72, 0.78, 0.84, 0.85)
		var captured_idx: int = i
		btn.pressed.connect(func() -> void:
			if is_instance_valid(hud) and hud._selection_controller != null:
				hud._selection_controller.set_active_subgroup(captured_idx)
		)
		hud.subgroup_tabs_row.add_child(btn)

	if subgroups.size() > max_tabs:
		var more_tabs: Label = Label.new()
		more_tabs.text = "+%d" % (subgroups.size() - max_tabs)
		more_tabs.add_theme_font_size_override("font_size", 10)
		more_tabs.modulate = Color(0.75, 0.85, 0.90, 0.85)
		hud.subgroup_tabs_row.add_child(more_tabs)

	if subgroups.size() > 1:
		var k_tab: String = hud._get_compact_action_badge(&"ui_cycle_subgroup", "Tab")
		if not k_tab.is_empty():
			var hint: Label = Label.new()
			hint.text = "[%s]" % k_tab
			hint.add_theme_font_size_override("font_size", 10)
			hint.modulate = hud._active_hud_accent
			hud.subgroup_tabs_row.add_child(hint)


func rebuild_building_subgroup_tabs(hud: SelectionHUD, b_subgroups: Array[Dictionary], active_index: int) -> void:
	for child: Node in hud.subgroup_tabs_row.get_children():
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
		btn.text = "%s%s (%d)" % [prefix, shorten_name(String(group.get("display_name", "Structure"))), grp_bldgs.size()]
		btn.modulate = hud._active_hud_accent if i == safe_active else Color(0.72, 0.78, 0.84, 0.85)
		var captured_idx: int = i
		btn.pressed.connect(func() -> void:
			if is_instance_valid(hud) and hud._selection_controller != null:
				hud._selection_controller.set_active_building_subgroup(captured_idx)
		)
		hud.subgroup_tabs_row.add_child(btn)

	if b_subgroups.size() > max_tabs:
		var more_tabs: Label = Label.new()
		more_tabs.text = "+%d" % (b_subgroups.size() - max_tabs)
		more_tabs.add_theme_font_size_override("font_size", 10)
		more_tabs.modulate = Color(0.75, 0.85, 0.90, 0.85)
		hud.subgroup_tabs_row.add_child(more_tabs)

	if b_subgroups.size() > 1:
		var k_tab: String = hud._get_compact_action_badge(&"ui_cycle_subgroup", "Tab")
		if not k_tab.is_empty():
			var hint: Label = Label.new()
			hint.text = "[%s]" % k_tab
			hint.add_theme_font_size_override("font_size", 10)
			hint.modulate = hud._active_hud_accent
			hud.subgroup_tabs_row.add_child(hint)


func rebuild_control_group_row(hud: SelectionHUD, summary: Dictionary) -> void:
	if hud.control_group_row == null:
		return
	for child: Node in hud.control_group_row.get_children():
		child.queue_free()

	var rich: Dictionary = hud._selection_controller.get_control_group_summaries() if (hud._selection_controller != null and hud._selection_controller.has_method("get_control_group_summaries")) else {}
	if summary.is_empty() and rich.is_empty():
		hud.control_group_row.visible = false
		return

	hud.control_group_row.visible = true
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
		pill.text = ("[%d] %s ×%d" % [num, shorten_name(label_str), count]) if is_building else ("[%d] ×%d" % [num, count])
		pill.modulate = hud._active_hud_accent if is_active else (Color(0.96, 0.84, 0.44, 0.92) if is_building else Color(0.76, 0.88, 0.94, 0.90))
		var captured_num: int = num
		pill.pressed.connect(func() -> void:
			if is_instance_valid(hud) and hud._selection_controller != null:
				hud._selection_controller.recall_control_group(captured_num, true)
		)
		var kind_label: String = "Structure(s)" if is_building else "Unit(s)"
		hud._attach_tooltip(
			pill,
			"Control Group %d — %s" % [num, label_str],
			str(num),
			"%d %s Assigned" % [count, kind_label],
			"Click or press %d to select. Double-tap to center. Ctrl+%d assign, Shift+%d add, Alt+%d steal." % [num, num, num, num]
		)
		hud.control_group_row.add_child(pill)


func show_wireframe_hover_tooltip(hud: SelectionHUD, entity: Node) -> void:
	if hud.command_tooltip == null or entity == null or not is_instance_valid(entity):
		return
	var title: String = "Entity"
	var badge: String = ""
	var meta_parts: PackedStringArray = PackedStringArray()
	if entity is Unit:
		var u: Unit = entity as Unit
		if u.is_dead:
			return
		title = u.data.display_name if u.data != null else "Unit"
		meta_parts.append("HP %s/%s" % [
			InspectionHelper.format_number(int(round(u.current_hp))),
			InspectionHelper.format_number(int(round(u.get_max_hp()))),
		])
		if u.max_shield > 0.0:
			meta_parts.append("SHD %s/%s" % [
				InspectionHelper.format_number(int(round(u.current_shield))),
				InspectionHelper.format_number(int(round(u.max_shield))),
			])
		if u.veterancy_rank > 0:
			badge = "RANK %d" % u.veterancy_rank
		var t_stacks: int = u.get_optical_tether_stacks()
		if t_stacks > 0:
			meta_parts.append("Lattice x%d" % t_stacks)
		if u.is_deployed():
			meta_parts.append("Deployed")
	elif entity is Building:
		var b: Building = entity as Building
		if b.is_destroyed:
			return
		title = b.display_name
		meta_parts.append("HP %s/%s" % [
			InspectionHelper.format_number(int(round(b.current_hp))),
			InspectionHelper.format_number(int(round(b.max_hp))),
		])
		if b.max_shield > 0.0:
			meta_parts.append("SHD %s/%s" % [
				InspectionHelper.format_number(int(round(b.current_shield))),
				InspectionHelper.format_number(int(round(b.max_shield))),
			])
		if b.is_constructed and b.requires_power_grid and not b.is_powered:
			badge = "UNPOWERED"
			meta_parts.append("Needs Power Lattice")
		elif b.is_overclocked():
			badge = "OVERCLOCK"
		elif b.is_actively_producing():
			meta_parts.append("Producing (%d)" % b.get_training_queue_size())
	hud.command_tooltip.show_tooltip(
		title,
		badge,
		" • ".join(meta_parts),
		"LMB Isolate • Shift Remove • Ctrl / 2xLMB Type • Ctrl+Shift Drop Type"
	)
