class_name CommandCardBuilder
extends RefCounted

const COMMAND_ICON_BUTTON_SCRIPT: GDScript = preload("res://ui/hud/command_icon_button.gd")

var unit_cmd_tiles: Dictionary = {}
var ability_buttons: Dictionary = {}
var building_action_buttons: Array[Dictionary] = []
var active_abilities: Array[AbilityData] = []


func clear_command_grid(hud: SelectionHUD) -> void:
	if hud != null and hud.command_grid != null:
		for child: Node in hud.command_grid.get_children():
			child.queue_free()
	building_action_buttons.clear()
	unit_cmd_tiles.clear()
	ability_buttons.clear()
	active_abilities.clear()


func clear_unit_bindings() -> void:
	unit_cmd_tiles.clear()
	ability_buttons.clear()
	active_abilities.clear()


func clear_building_bindings() -> void:
	building_action_buttons.clear()


func apply_theme_to_grid(hud: SelectionHUD) -> void:
	if hud == null or hud.command_grid == null:
		return
	for child: Node in hud.command_grid.get_children():
		if child is CommandIconButton:
			(child as CommandIconButton).apply_faction_theme(hud._active_hud_faction_id, hud._active_hud_accent, hud._active_hud_primary)


func _new_icon_tile(hud: SelectionHUD) -> CommandIconButton:
	var tile: CommandIconButton = COMMAND_ICON_BUTTON_SCRIPT.new() as CommandIconButton
	tile.apply_faction_theme(hud._active_hud_faction_id, hud._active_hud_accent, hud._active_hud_primary)
	return tile


func _populate_12_slot_grid(hud: SelectionHUD, slots: Array) -> void:
	hud.command_grid.columns = 4
	for i: int in range(12):
		var item: Variant = slots[i] if i < slots.size() else null
		if item is CommandIconButton:
			hud.command_grid.add_child(item as CommandIconButton)
		else:
			var empty_tile: CommandIconButton = _new_icon_tile(hud)
			empty_tile.setup_empty_socket()
			hud.command_grid.add_child(empty_tile)


func get_unit_icon_accent(hud: SelectionHUD, u_data: UnitData) -> Color:
	if u_data == null:
		return hud._active_hud_accent
	if u_data.can_staff_compute:
		return Color(0.28, 0.86, 1.0, 1.0)
	if u_data.can_gather and u_data.auto_gather_on_spawn:
		return Color(1.0, 0.76, 0.24, 1.0)
	if u_data.has_tag(&"support") or u_data.heal_aura_rate > 0.0:
		return Color(0.24, 0.96, 0.72, 1.0) if hud._active_hud_faction_id != &"monolith_os" else Color(0.220, 0.741, 0.973, 1.0)
	if u_data.has_tag(&"heavy") or u_data.has_tag(&"siege"):
		return Color(1.0, 0.64, 0.16, 1.0)
	return hud._active_hud_accent


func get_building_icon_accent(hud: SelectionHUD, b_data: BuildingData) -> Color:
	if b_data == null:
		return hud._active_hud_accent
	var bid: StringName = b_data.building_id
	if bid == &"silica_condenser" or bid == &"silica_smelter" or bid == &"alabaster_kiln":
		return Color(1.0, 0.76, 0.26, 1.0)
	if bid == &"wetware_mainframe" or bid == &"logic_monolith" or bid == &"capacitor_pylon" or bid == &"oracle_reliquary":
		return Color(0.28, 0.84, 1.0, 1.0)
	if bid == &"synapse_pylon" or bid == &"halo_spire":
		return Color(0.76, 0.58, 1.0, 1.0)
	if bid == &"defense_turret" or bid == &"bastion_emplacement" or bid == &"solar_obelisk":
		return Color(1.0, 0.46, 0.26, 1.0)
	return hud._active_hud_accent


func build_unit_class_traits_label(u_data: UnitData) -> String:
	if u_data == null:
		return ""
	var tags: PackedStringArray = PackedStringArray()
	if u_data.unit_type_id == &"goliath_frame" or u_data.unit_type_id == &"arc_lancer" or u_data.unit_type_id == &"monolith_dreadnought" or u_data.unit_type_id == &"anvil_siege_walker" or u_data.unit_type_id == &"seraph_cruiser" or u_data.unit_type_id == &"solstice_lance":
		tags.append("Heavy Chassis")
	elif u_data.is_armored:
		tags.append("Armored")
	else:
		tags.append("Light")

	if u_data.can_deploy:
		tags.append("Deployable")
	if u_data.max_shield > 0.0:
		tags.append("Shielded")
	if u_data.is_continuous_beam:
		tags.append("Escalating Beam")
	if u_data.refract_max_bounces > 0:
		tags.append("Refract")
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


# =============================================================================
# BUILDING 4x3 ICON COMMAND CARD
# =============================================================================

func rebuild_building_card(hud: SelectionHUD, building: Building) -> void:
	clear_command_grid(hud)
	var slots: Array = []
	slots.resize(12)

	if not building.is_constructed:
		var cancel_tile: CommandIconButton = _new_icon_tile(hud)
		cancel_tile.setup_tile(&"cancel_build", &"danger", "", Color(1.0, 0.42, 0.30, 1.0))
		cancel_tile.set_tile_state("75%", Color(1.0, 0.74, 0.36, 1.0))
		var captured_b_cancel: Building = building
		cancel_tile.pressed.connect(func() -> void:
			if is_instance_valid(captured_b_cancel):
				captured_b_cancel.cancel_construction()
		)
		hud._attach_tooltip(
			cancel_tile,
			"Cancel %s" % building.display_name,
			"LMB",
			"75%% Refund: %s" % building.get_refund_label(0.75),
			"Immediately cancels this unfinished scaffold, refunds 75% of construction resources, releases workers, and updates pathing."
		)
		slots[11] = cancel_tile
		building_action_buttons.append({
			"kind": "cancel_build",
			"button": cancel_tile,
		})
		_populate_12_slot_grid(hud, slots)
		hud.command_grid.visible = true
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
		var hk_short: String = hud._get_compact_action_badge(t_act, t_fb)
		var train_tile: CommandIconButton = _new_icon_tile(hud)
		train_tile.setup_tile(u_data.unit_type_id, &"unit", hk_short, get_unit_icon_accent(hud, u_data))
		var captured_b: Building = building
		var captured_slot: int = i
		var captured_u: UnitData = u_data
		train_tile.pressed.connect(func() -> void:
			if not is_instance_valid(hud):
				return
			var shift_batch: bool = Input.is_key_pressed(KEY_SHIFT)
			if shift_batch:
				if hud._selection_controller != null:
					hud._selection_controller.queue_unit_distributed_batch(captured_u, 5, captured_b)
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
			elif hud._selection_controller != null and hud._selected_buildings.size() > 1:
				hud._selection_controller.queue_unit_distributed(captured_u)
			elif is_instance_valid(captured_b):
				captured_b.queue_unit_training(captured_slot)
		)
		train_tile.tooltip_text = ""
		train_tile.mouse_entered.connect(func() -> void:
			if not is_instance_valid(hud) or hud.command_tooltip == null or not is_instance_valid(captured_b):
				return
			var hk_full: String = SettingsManager.get_action_display_label(t_act, false) if SettingsManager != null else t_fb
			var b_info: Dictionary = captured_b.get_unit_batch_info(captured_u)
			var b_cnt: int = int(b_info["batch_count"])
			var traits_line: String = build_unit_class_traits_label(captured_u)
			var meta_line: String = "Cost: %s / %d BW  •  %.1fs" % [String(b_info["cost_label"]), int(b_info["bandwidth_cost"]), float(b_info["duration"])]
			if not traits_line.is_empty():
				meta_line = "%s  •  %s" % [traits_line, meta_line]
			var desc: String = "Queues a %s (max 5 in queue). Reserves Bandwidth immediately." % captured_u.display_name
			if b_cnt > 1:
				var mult_val: float = float(b_info["cost_multiplier"])
				var eff_note: String = " (Batch Efficiency Active)" if mult_val <= 1.55 else " (1.75x Batch Cost)"
				desc = "Parallel Batch Cloning: spawns %d %ss simultaneously for %.2fx single-unit cost%s." % [b_cnt, captured_u.display_name, mult_val, eff_note]
			desc += "\n[Shift+%s / Shift+Click: Queue x5]" % hk_full
			hud.command_tooltip.show_tooltip(
				("Clone %s (x%d)" % [captured_u.display_name, b_cnt]) if b_cnt > 1 else ("Train %s" % captured_u.display_name),
				hk_full,
				meta_line,
				desc
			)
		)
		train_tile.mouse_exited.connect(func() -> void:
			if is_instance_valid(hud) and hud.command_tooltip != null:
				hud.command_tooltip.hide_tooltip()
		)
		slots[i] = train_tile
		building_action_buttons.append({
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
		var hk_u: String = hud._get_compact_action_badge(u_act, u_fb)
		var upg_tile: CommandIconButton = _new_icon_tile(hud)
		upg_tile.setup_tile(upg.upgrade_id, &"upgrade", hk_u, Color(1.0, 0.84, 0.34, 1.0))
		var captured_b_u: Building = building
		var captured_upg_idx: int = j
		var captured_upg: UpgradeData = upg
		upg_tile.pressed.connect(func() -> void:
			if not is_instance_valid(hud):
				return
			var started: bool = false
			if hud._selection_controller != null:
				var scoped_u: Array[Building] = hud._selection_controller.get_active_building_subgroup_buildings()
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
			if not is_instance_valid(hud) or hud.command_tooltip == null:
				return
			var hk_uf: String = SettingsManager.get_action_display_label(u_act, false) if SettingsManager != null else u_fb
			var upg_meta: String = "Upgrade  •  Cost: %s  •  %.1fs" % [captured_upg.get_cost_label(), captured_upg.research_time]
			hud.command_tooltip.show_tooltip("Research: %s" % captured_upg.display_name, hk_uf, upg_meta, captured_upg.description)
		)
		upg_tile.mouse_exited.connect(func() -> void:
			if is_instance_valid(hud) and hud.command_tooltip != null:
				hud.command_tooltip.hide_tooltip()
		)
		slots[4 + j] = upg_tile
		building_action_buttons.append({
			"kind": "upgrade",
			"slot": j,
			"action": u_act,
			"fallback": u_fb,
			"data": upg,
			"button": upg_tile,
		})

	# Row 3 Slot 8: Facility Special (F) — Core Overclock or Eject Engineers
	if building.has_overclock_ability():
		var hk_oc: String = hud._get_compact_action_badge(&"cmd_ability_f", "F")
		var oc_tile: CommandIconButton = _new_icon_tile(hud)
		oc_tile.setup_tile(&"overclock", &"special", hk_oc, Color(1.0, 0.624, 0.110, 1.0))
		var captured_b_oc: Building = building
		oc_tile.pressed.connect(func() -> void:
			if is_instance_valid(hud) and hud._selection_controller != null:
				if hud._selection_controller.is_overclock_targeting:
					hud._selection_controller.cancel_overclock_targeting()
				elif not hud._selection_controller.begin_overclock_targeting() and AudioManager != null:
					AudioManager.play_error()
		)
		oc_tile.tooltip_text = ""
		oc_tile.mouse_entered.connect(func() -> void:
			if is_instance_valid(hud) and hud.command_tooltip != null and is_instance_valid(captured_b_oc):
				var hk_oc_full: String = SettingsManager.get_action_display_label(&"cmd_ability_f", false) if SettingsManager != null else "F"
				var spd_m: float = captured_b_oc.get_overclock_config_speed_mult()
				var dur_s: float = captured_b_oc.get_overclock_config_duration()
				var cd_s: float = captured_b_oc.get_overclock_config_cooldown()
				hud.command_tooltip.show_tooltip(
					"Core Overclock",
					hk_oc_full,
					"%.1fx Speed  •  %.0fs Duration  •  %.0fs Cooldown" % [spd_m, dur_s, cd_s],
					"Target any friendly production or research structure to boost its unit training and upgrade speed by %.1fx." % spd_m
				)
		)
		oc_tile.mouse_exited.connect(func() -> void:
			if is_instance_valid(hud) and hud.command_tooltip != null:
				hud.command_tooltip.hide_tooltip()
		)
		slots[8] = oc_tile
		building_action_buttons.append({
			"kind": "overclock",
			"button": oc_tile,
		})
	elif building.max_staff_slots > 0:
		var hk_ej: String = hud._get_compact_action_badge(&"cmd_ability_f", "F")
		var eject_tile: CommandIconButton = _new_icon_tile(hud)
		eject_tile.setup_tile(&"eject_engineers", &"special", hk_ej, Color(0.32, 0.88, 1.0, 1.0))
		var captured_building: Building = building
		eject_tile.pressed.connect(func() -> void:
			if not is_instance_valid(hud):
				return
			if AudioManager != null:
				AudioManager.play_ui_click()
			if hud._selection_controller != null and hud._selected_buildings.size() > 1:
				hud._selection_controller.eject_engineers_from_selected_buildings()
			elif is_instance_valid(captured_building):
				captured_building.eject_engineers()
		)
		hud._attach_dynamic_action_tooltip(
			eject_tile,
			"Eject Engineers",
			&"cmd_ability_f",
			"Instant Release (F or E)",
			"Releases all Engineers / Grid-Techs currently staffed inside this facility back onto the battlefield."
		)
		slots[8] = eject_tile
		building_action_buttons.append({
			"kind": "eject",
			"button": eject_tile,
		})

	# Row 3 Slot 11 (bottom-right): Salvage (click-only)
	var salv_tile: CommandIconButton = _new_icon_tile(hud)
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
		if not is_instance_valid(hud) or hud.command_tooltip == null or not is_instance_valid(captured_b_salv):
			return
		if captured_b_salv.is_salvaging:
			var rem_s: float = maxf(0.0, Building.SALVAGE_DURATION - captured_b_salv.salvage_elapsed)
			hud.command_tooltip.show_tooltip(
				"Cancel Salvage",
				"LMB",
				"%.1fs Remaining" % rem_s,
				"Aborts the salvage timer and restores this building to active service."
			)
		elif not captured_b_salv.can_salvage():
			hud.command_tooltip.show_tooltip(
				"Salvage Locked",
				"",
				"Last Command Hub",
				"Cannot salvage your final Command Hub."
			)
		else:
			hud.command_tooltip.show_tooltip(
				"Salvage %s" % captured_b_salv.display_name,
				"LMB",
				"4.0s Timer  •  50%% Refund: %s" % captured_b_salv.get_refund_label(0.50),
				"Deconstructs this structure over 4.0 seconds (click-only for safety), refunding 50% of its cost and clearing pathing."
			)
	)
	salv_tile.mouse_exited.connect(func() -> void:
		if is_instance_valid(hud) and hud.command_tooltip != null:
			hud.command_tooltip.hide_tooltip()
	)
	slots[11] = salv_tile
	building_action_buttons.append({
		"kind": "salvage",
		"button": salv_tile,
	})

	_populate_12_slot_grid(hud, slots)
	hud.command_grid.visible = true
	refresh_building_card(hud, building)


func refresh_building_card(hud: SelectionHUD, building: Building) -> void:
	if hud == null or building == null or not is_instance_valid(building):
		return
	if hud._economy_manager == null:
		hud._connect_economy_manager()

	for entry: Dictionary in building_action_buttons:
		var kind: String = String(entry["kind"])
		var btn: CommandIconButton = entry["button"] as CommandIconButton
		if btn == null or not is_instance_valid(btn):
			continue
		if kind == "overclock":
			var k_oc: String = hud._get_compact_action_badge(&"cmd_ability_f", "F")
			btn.hotkey_text = k_oc
			var any_ready: bool = false
			var min_cd: float = INF
			var max_cd: float = maxf(1.0, building.get_overclock_config_cooldown())
			var hub_list: Array[Building] = []
			if hud._selection_controller != null and hud._building_subgroups.size() > 1:
				hub_list = hud._selection_controller.get_active_building_subgroup_buildings()
			elif hud._selected_buildings.size() > 1:
				hub_list = hud._selected_buildings
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
				btn.set_tile_state("TGT" if hud._overclock_targeting else "", Color(1.0, 0.84, 0.28, 1.0), hud._overclock_targeting, false, false, 0.0, 0.0)
			else:
				btn.disabled = true
				var cd_rem: float = 0.0 if min_cd == INF else min_cd
				btn.set_tile_state("", Color(1.0, 0.72, 0.24, 1.0), false, false, false, cd_rem, max_cd)
		elif kind == "eject":
			var count: int = building.get_assigned_engineer_count()
			btn.hotkey_text = hud._get_compact_action_badge(&"cmd_ability_f", "F")
			btn.disabled = count <= 0
			btn.set_tile_state(str(count) if count > 0 else "", Color(0.45, 0.96, 1.0, 1.0), false, count <= 0)
		elif kind == "train":
			var slot: int = int(entry["slot"])
			var u_data: UnitData = entry["data"] as UnitData
			btn.hotkey_text = hud._get_compact_action_badge(entry["action"] as StringName, String(entry["fallback"]))
			var b_info: Dictionary = building.get_unit_batch_info(u_data)
			var b_cnt: int = int(b_info["batch_count"])
			var can_train: bool = building.can_train_unit(slot)
			btn.disabled = false
			var b_tag: String = "×%d" % b_cnt if b_cnt > 1 else ""
			btn.set_tile_state(b_tag, Color(0.32, 0.98, 0.84, 1.0), false, not can_train)
		elif kind == "upgrade":
			var u_slot: int = int(entry["slot"])
			var upg: UpgradeData = entry["data"] as UpgradeData
			btn.hotkey_text = hud._get_compact_action_badge(entry["action"] as StringName, String(entry["fallback"]))
			var is_done: bool = hud._economy_manager != null and hud._economy_manager.has_upgrade(building.team, upg.upgrade_id)
			var is_prog: bool = hud._economy_manager != null and hud._economy_manager.is_upgrade_in_progress(building.team, upg.upgrade_id)
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

func _make_std_cmd_tile(hud: SelectionHUD, key_id: StringName) -> CommandIconButton:
	var tile: CommandIconButton = _new_icon_tile(hud)
	match key_id:
		&"move":
			tile.setup_tile(&"cmd_move", &"command", "RMB", Color(0.42, 0.96, 0.88, 1.0))
			tile.disabled = true
			hud._attach_tooltip(tile, "Move", "RMB", "Right-Click Ground", "Orders selected units to navigate to the target location.")
		&"stop":
			tile.setup_tile(&"cmd_stop", &"command", hud._get_compact_action_badge(&"cmd_stop", "S"), Color(0.84, 0.90, 0.96, 1.0))
			tile.pressed.connect(func() -> void:
				if AudioManager != null:
					AudioManager.play_ui_click()
				if is_instance_valid(hud) and hud._selection_controller != null:
					hud._selection_controller.issue_stop_command()
			)
			hud._attach_dynamic_action_tooltip(tile, "Stop", &"cmd_stop", "Immediate", "Cancels current movement, patrol, gathering, construction, or target and flushes command queue.")
		&"hold":
			tile.setup_tile(&"cmd_hold", &"command", hud._get_compact_action_badge(&"cmd_hold", "H"), Color(1.0, 0.84, 0.32, 1.0))
			tile.pressed.connect(func() -> void:
				if AudioManager != null:
					AudioManager.play_ui_click()
				if is_instance_valid(hud) and hud._selection_controller != null:
					hud._selection_controller.issue_hold_command()
			)
			hud._attach_dynamic_action_tooltip(tile, "Hold Position", &"cmd_hold", "Immediate", "Locks unit position while engaging enemies inside attack range.")
		&"defensive":
			tile.setup_tile(&"cmd_defensive", &"command", hud._get_compact_action_badge(&"cmd_defensive_stance", "D"), Color(0.28, 0.98, 0.80, 1.0))
			tile.pressed.connect(func() -> void:
				if AudioManager != null:
					AudioManager.play_ui_click()
				if is_instance_valid(hud) and hud._selection_controller != null:
					hud._selection_controller.issue_defensive_command()
			)
			hud._attach_dynamic_action_tooltip(tile, "Defensive Stance", &"cmd_defensive_stance", "Immediate (260px Leash)", "Auto-acquires nearby enemies and chases up to 260px from anchor before smoothly returning.")
		&"patrol":
			tile.setup_tile(&"cmd_patrol", &"command", hud._get_compact_action_badge(&"cmd_patrol", "P"), Color(0.46, 0.90, 1.0, 1.0))
			tile.pressed.connect(func() -> void:
				if is_instance_valid(hud) and hud._selection_controller != null:
					hud._selection_controller.begin_patrol_targeting()
			)
			hud._attach_dynamic_action_tooltip(tile, "Patrol", &"cmd_patrol", "Click Waypoint (Shift Chains Loop)", "Loops units continuously between waypoints while engaging enemies encountered along the path.")
		&"amove":
			tile.setup_tile(&"cmd_amove", &"command", hud._get_compact_action_badge(&"cmd_attack_move", "A"), Color(1.0, 0.38, 0.44, 1.0))
			tile.pressed.connect(func() -> void:
				if is_instance_valid(hud) and hud._selection_controller != null:
					hud._selection_controller.begin_attack_move_targeting()
			)
			tile.tooltip_text = ""
			tile.mouse_entered.connect(func() -> void:
				if is_instance_valid(hud) and hud.command_tooltip != null:
					var hk: String = SettingsManager.get_action_display_label(&"cmd_attack_move", false) if SettingsManager != null else "A"
					var click_confirm: bool = SettingsManager != null and SettingsManager.attack_move_mode == SettingsManager.AttackMoveMode.CLICK_TO_CONFIRM
					var meta_txt: String = "Click Target (Shift Chains)" if click_confirm else "Quick-Cast at Cursor (Shift Chains)"
					hud.command_tooltip.show_tooltip("Attack-Move", hk, meta_txt, "Moves toward target point and automatically engages hostile targets along the way.")
			)
			tile.mouse_exited.connect(func() -> void:
				if is_instance_valid(hud) and hud.command_tooltip != null:
					hud.command_tooltip.hide_tooltip()
			)
	unit_cmd_tiles[key_id] = tile
	return tile


func _make_ability_tile(hud: SelectionHUD, ability: AbilityData) -> CommandIconButton:
	var tile: CommandIconButton = _new_icon_tile(hud)
	var hk_compact: String = hud._get_ability_hotkey_display(ability.hotkey_label, true)
	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT and ability.building_to_build != null:
		tile.setup_tile(ability.building_to_build.building_id, &"building", hk_compact, get_building_icon_accent(hud, ability.building_to_build))
	else:
		tile.setup_tile(ability.ability_id, &"ability", hk_compact, ability.effect_color)

	var captured_ability: AbilityData = ability
	tile.pressed.connect(func() -> void:
		if is_instance_valid(hud) and hud._selection_controller != null:
			hud._selection_controller.request_ability_slot(captured_ability, Input.is_key_pressed(KEY_SHIFT))
	)
	if ability.allow_autocast:
		tile.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb: InputEventMouseButton = ev as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
					if is_instance_valid(hud):
						toggle_subgroup_autocast(hud, captured_ability.ability_id)
					tile.accept_event()
		)
	tile.tooltip_text = ""
	tile.mouse_entered.connect(func() -> void:
		if is_instance_valid(hud) and hud.command_tooltip != null:
			var dynamic_meta: String = build_ability_tooltip_meta(hud, captured_ability)
			var hk_full: String = hud._get_ability_hotkey_display(captured_ability.hotkey_label, false)
			hud.command_tooltip.show_tooltip(captured_ability.display_name, hk_full, dynamic_meta, captured_ability.description)
	)
	tile.mouse_exited.connect(func() -> void:
		if is_instance_valid(hud) and hud.command_tooltip != null:
			hud.command_tooltip.hide_tooltip()
	)
	ability_buttons[ability.ability_id] = {
		"button": tile,
		"ability": ability,
	}
	return tile


func _make_auto_repair_tile(hud: SelectionHUD, data: UnitData) -> CommandIconButton:
	var rep_tile: CommandIconButton = _new_icon_tile(hud)
	rep_tile.setup_tile(&"auto_repair", &"special", "", Color(0.38, 1.0, 0.84, 1.0))
	rep_tile.pressed.connect(func() -> void:
		if is_instance_valid(hud):
			toggle_subgroup_auto_repair(hud)
	)
	rep_tile.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				if is_instance_valid(hud):
					toggle_subgroup_auto_repair(hud)
				rep_tile.accept_event()
	)
	rep_tile.tooltip_text = ""
	rep_tile.mouse_entered.connect(func() -> void:
		if is_instance_valid(hud) and hud.command_tooltip != null:
			var is_on: bool = is_subgroup_auto_repair_enabled(hud)
			var state_str: String = "Auto-Cast ON" if is_on else "Auto-Cast OFF"
			var scope_str: String = "damaged friendly buildings & heavy synthetic units within 220px" if data.can_staff_compute else "damaged friendly buildings within 220px"
			hud.command_tooltip.show_tooltip(
				"Auto-Repair",
				"RMB / LMB",
				"Radius: 220 px  •  [Right-Click: %s]" % state_str,
				"When IDLE, automatically repairs %s (~2B/1S per sec)." % scope_str
			)
	)
	rep_tile.mouse_exited.connect(func() -> void:
		if is_instance_valid(hud) and hud.command_tooltip != null:
			hud.command_tooltip.hide_tooltip()
	)
	ability_buttons[&"__auto_repair__"] = {
		"button": rep_tile,
		"ability": null,
	}
	return rep_tile


func _make_deploy_tile(hud: SelectionHUD, data: UnitData) -> CommandIconButton:
	var dep_tile: CommandIconButton = _new_icon_tile(hud)
	dep_tile.setup_tile(&"deploy", &"special", hud._get_compact_action_badge(&"cmd_ability_e", "E"), Color(1.0, 0.624, 0.110, 1.0))
	var captured_u_data: UnitData = data
	dep_tile.pressed.connect(func() -> void:
		if is_instance_valid(hud) and hud._selection_controller != null:
			hud._selection_controller.toggle_deploy_active_subgroup()
	)
	dep_tile.tooltip_text = ""
	dep_tile.mouse_entered.connect(func() -> void:
		if is_instance_valid(hud) and hud.command_tooltip != null and captured_u_data != null:
			var hk_dep: String = SettingsManager.get_action_display_label(&"cmd_ability_e", false) if SettingsManager != null else "E"
			var meta_parts: PackedStringArray = PackedStringArray(["Transition: %.1fs" % captured_u_data.deploy_duration])
			if captured_u_data.deployed_attack_range > 0.0:
				meta_parts.append("Range: %dpx" % int(round(captured_u_data.deployed_attack_range)))
			if captured_u_data.deployed_attack_damage > 0.0:
				meta_parts.append("Dmg: %d" % int(round(captured_u_data.deployed_attack_damage)))
			if captured_u_data.deployed_damage_reduction_bonus > 0.0:
				meta_parts.append("+%d%% Armor" % int(round(captured_u_data.deployed_damage_reduction_bonus * 100.0)))
			hud.command_tooltip.show_tooltip(
				"Deploy / Anchor Stance",
				hk_dep,
				"  •  ".join(meta_parts),
				"Anchors the chassis in place to engage heavy deployed weaponry. Move orders will not accidentally undeploy anchored units."
			)
	)
	dep_tile.mouse_exited.connect(func() -> void:
		if is_instance_valid(hud) and hud.command_tooltip != null:
			hud.command_tooltip.hide_tooltip()
	)
	ability_buttons[&"__deploy__"] = {
		"button": dep_tile,
		"ability": null,
	}
	return dep_tile


func rebuild_unit_card(hud: SelectionHUD, active_group: Dictionary) -> void:
	clear_command_grid(hud)
	var data: UnitData = active_group.get("data", null) as UnitData
	var slots: Array = []
	slots.resize(12)

	var valid_abilities: Array[AbilityData] = []
	var build_ability_count: int = 0
	if data != null:
		for ab: AbilityData in data.abilities:
			if ab != null:
				valid_abilities.append(ab)
				active_abilities.append(ab)
				if ab.target_type == AbilityData.TargetType.BUILD_PLACEMENT:
					build_ability_count += 1

	var supports_auto_repair: bool = data != null and (data.can_gather or data.can_staff_compute or data.unit_type_id == &"worker" or data.unit_type_id == &"engineer")
	var supports_deploy: bool = data != null and data.can_deploy

	if build_ability_count >= 5:
		# Builder layout (Worker Drone / Servo-Drone / Acolyte): 12 exact slots in 4x3 grid!
		# Row 1: Move, Stop, Hold, Auto-Repair
		# Row 2..3: All 8 build abilities neatly aligned
		slots[0] = _make_std_cmd_tile(hud, &"move")
		slots[1] = _make_std_cmd_tile(hud, &"stop")
		slots[2] = _make_std_cmd_tile(hud, &"hold")
		if supports_auto_repair:
			slots[3] = _make_auto_repair_tile(hud, data)
		var cursor_b: int = 4
		for ab: AbilityData in valid_abilities:
			if cursor_b >= 12:
				break
			slots[cursor_b] = _make_ability_tile(hud, ab)
			cursor_b += 1
	else:
		# Standard / Combat / Specialist layout
		# Row 1: Move, Stop, Hold, Defend
		# Row 2: Patrol, Atk-Move, Abilities...
		# Row 3: Remaining Abilities, Deploy, Auto-Repair
		slots[0] = _make_std_cmd_tile(hud, &"move")
		slots[1] = _make_std_cmd_tile(hud, &"stop")
		slots[2] = _make_std_cmd_tile(hud, &"hold")
		slots[3] = _make_std_cmd_tile(hud, &"defensive")
		slots[4] = _make_std_cmd_tile(hud, &"patrol")
		slots[5] = _make_std_cmd_tile(hud, &"amove")
		var cursor_u: int = 6
		for ab: AbilityData in valid_abilities:
			if cursor_u >= 12:
				break
			slots[cursor_u] = _make_ability_tile(hud, ab)
			cursor_u += 1
		if supports_deploy and cursor_u < 12:
			slots[cursor_u] = _make_deploy_tile(hud, data)
			cursor_u += 1
		if supports_auto_repair and cursor_u < 12:
			slots[cursor_u] = _make_auto_repair_tile(hud, data)
			cursor_u += 1

	_populate_12_slot_grid(hud, slots)
	hud.command_grid.visible = true


# =============================================================================
# DYNAMIC COMMAND CARD REFRESH & AUTOCAST HELPERS
# =============================================================================

func refresh_dynamic_command_labels(hud: SelectionHUD) -> void:
	if hud == null:
		return
	var k_stop: String = hud._get_compact_action_badge(&"cmd_stop", "S")
	var k_patrol: String = hud._get_compact_action_badge(&"cmd_patrol", "P")
	var k_amove: String = hud._get_compact_action_badge(&"cmd_attack_move", "A")
	var btn_stop: CommandIconButton = unit_cmd_tiles.get(&"stop", null) as CommandIconButton
	if btn_stop != null and is_instance_valid(btn_stop):
		btn_stop.hotkey_text = k_stop
		btn_stop.queue_redraw()
	var btn_patrol: CommandIconButton = unit_cmd_tiles.get(&"patrol", null) as CommandIconButton
	if btn_patrol != null and is_instance_valid(btn_patrol):
		btn_patrol.hotkey_text = k_patrol
		btn_patrol.set_tile_state("TGT" if hud._patrol_targeting else "", Color(1.0, 0.86, 0.30, 1.0), hud._patrol_targeting)
	var btn_amove: CommandIconButton = unit_cmd_tiles.get(&"amove", null) as CommandIconButton
	if btn_amove != null and is_instance_valid(btn_amove):
		btn_amove.hotkey_text = k_amove
		btn_amove.set_tile_state("TGT" if hud._amove_targeting else "", Color(1.0, 0.36, 0.44, 1.0), hud._amove_targeting)


func refresh_stance_button(hud: SelectionHUD) -> void:
	if hud == null or hud._selection_controller == null:
		return
	var btn_hold: CommandIconButton = unit_cmd_tiles.get(&"hold", null) as CommandIconButton
	var btn_def: CommandIconButton = unit_cmd_tiles.get(&"defensive", null) as CommandIconButton
	if btn_hold == null and btn_def == null:
		return
	var living_count: int = 0
	var hold_count: int = 0
	var defensive_count: int = 0
	for item: Variant in hud._selection_controller.selected_units:
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
		btn_hold.hotkey_text = hud._get_compact_action_badge(&"cmd_hold", "H")
		if living_count > 0 and hold_count == living_count:
			btn_hold.set_tile_state("ON", Color(1.0, 0.84, 0.32, 1.0), true)
		elif hold_count > 0:
			btn_hold.set_tile_state("*", Color(1.0, 0.90, 0.56, 1.0), true)
		else:
			btn_hold.set_tile_state("", Color(1.0, 0.84, 0.32, 1.0), false)

	if btn_def != null and is_instance_valid(btn_def):
		btn_def.hotkey_text = hud._get_compact_action_badge(&"cmd_defensive_stance", "D")
		if living_count > 0 and defensive_count == living_count:
			btn_def.set_tile_state("ON", Color(0.28, 0.98, 0.80, 1.0), true)
		elif defensive_count > 0:
			btn_def.set_tile_state("*", Color(0.56, 0.98, 0.88, 1.0), true)
		else:
			btn_def.set_tile_state("", Color(0.28, 0.98, 0.80, 1.0), false)


func toggle_subgroup_autocast(hud: SelectionHUD, ability_id: StringName) -> void:
	var any_on: bool = is_subgroup_autocast_enabled(hud, ability_id)
	var next_state: bool = not any_on
	for item: Variant in hud._active_subgroup_units:
		if is_instance_valid(item) and item is Unit:
			var u: Unit = item as Unit
			if not u.is_dead and u.ability_component != null:
				u.ability_component.set_autocast_enabled(ability_id, next_state)
	if AudioManager != null:
		AudioManager.play_sfx(&"autocast_toggle", -3.0, 0.03)
	refresh_single_ability_button(hud, ability_id)


func is_subgroup_autocast_enabled(hud: SelectionHUD, ability_id: StringName) -> bool:
	for item: Variant in hud._active_subgroup_units:
		if is_instance_valid(item) and item is Unit:
			var u: Unit = item as Unit
			if not u.is_dead and u.ability_component != null and u.ability_component.is_autocast_enabled(ability_id):
				return true
	return false


func toggle_subgroup_auto_repair(hud: SelectionHUD) -> void:
	var next_state: bool = not is_subgroup_auto_repair_enabled(hud)
	for item: Variant in hud._active_subgroup_units:
		if is_instance_valid(item) and item is Unit:
			var u: Unit = item as Unit
			if not u.is_dead and u.repair_component != null and u.repair_component.has_method("set_auto_repair_enabled"):
				u.repair_component.call("set_auto_repair_enabled", next_state)
	if AudioManager != null:
		AudioManager.play_sfx(&"autocast_toggle", -3.0, 0.03)
	refresh_auto_repair_button(hud)


func is_subgroup_auto_repair_enabled(hud: SelectionHUD) -> bool:
	for item: Variant in hud._active_subgroup_units:
		if is_instance_valid(item) and item is Unit:
			var u: Unit = item as Unit
			if not u.is_dead and u.repair_component != null and bool(u.repair_component.get("auto_repair_enabled")):
				return true
	return false


func refresh_auto_repair_button(hud: SelectionHUD) -> void:
	if not ability_buttons.has(&"__auto_repair__"):
		return
	var entry: Dictionary = ability_buttons[&"__auto_repair__"]
	var btn: CommandIconButton = entry["button"] as CommandIconButton
	if btn == null or not is_instance_valid(btn):
		return
	var is_on: bool = is_subgroup_auto_repair_enabled(hud)
	btn.set_autocast_active(is_on)
	btn.set_tile_state("ON" if is_on else "OFF", Color(0.38, 1.0, 0.84, 1.0) if is_on else Color(0.68, 0.74, 0.80, 0.85), is_on)


func build_ability_tooltip_meta(hud: SelectionHUD, ability: AbilityData) -> String:
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
			var has_req: bool = hud._economy_manager != null and hud._economy_manager.has_constructed_building(check_t_tt, b.required_building_id)
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
		var ac_on: bool = is_subgroup_autocast_enabled(hud, ability.ability_id)
		ab_parts.append("[Right-Click: Auto-Cast %s]" % ("ON" if ac_on else "OFF"))
	return "  •  ".join(ab_parts)


func refresh_deploy_button(hud: SelectionHUD) -> void:
	if not ability_buttons.has(&"__deploy__"):
		return
	var entry: Dictionary = ability_buttons[&"__deploy__"]
	var btn: CommandIconButton = entry["button"] as CommandIconButton
	if btn == null or not is_instance_valid(btn):
		return
	btn.hotkey_text = hud._get_compact_action_badge(&"cmd_ability_e", "E")
	var has_mobile: bool = false
	var has_deploying: bool = false
	var has_undeploying: bool = false
	var has_deployed: bool = false
	for item: Variant in hud._active_subgroup_units:
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


func refresh_all_ability_states(hud: SelectionHUD) -> void:
	for ability: AbilityData in active_abilities:
		refresh_single_ability_button(hud, ability.ability_id)
	refresh_auto_repair_button(hud)
	refresh_deploy_button(hud)


func refresh_single_ability_button(hud: SelectionHUD, ability_id: StringName) -> void:
	if not ability_buttons.has(ability_id):
		return
	var entry: Dictionary = ability_buttons[ability_id]
	var btn: CommandIconButton = entry["button"] as CommandIconButton
	var ability: AbilityData = entry["ability"] as AbilityData
	if btn == null or not is_instance_valid(btn) or ability == null:
		return

	var ac_on: bool = ability.allow_autocast and is_subgroup_autocast_enabled(hud, ability_id)
	btn.set_autocast_active(ac_on)
	btn.hotkey_text = hud._get_ability_hotkey_display(ability.hotkey_label, true)

	var is_targeting: bool = (hud._targeting_ability != null and hud._targeting_ability.ability_id == ability_id)

	if ability.target_type == AbilityData.TargetType.BUILD_PLACEMENT and ability.building_to_build != null:
		var b_data: BuildingData = ability.building_to_build
		var can_afford: bool = true
		var has_prereq: bool = true
		if hud._economy_manager == null:
			hud._connect_economy_manager()
		if hud._economy_manager != null:
			var local_t_b: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
			var check_t_b: int = local_t_b if local_t_b >= 0 else int(Unit.Team.PLAYER)
			can_afford = hud._economy_manager.can_afford(check_t_b, b_data.get_cost_dict())
			if b_data.required_building_id != &"":
				has_prereq = hud._economy_manager.has_constructed_building(check_t_b, b_data.required_building_id)

		btn.disabled = false
		if not has_prereq:
			btn.set_tile_state("LOCK", Color(0.95, 0.42, 0.42, 0.96), false, false, true)
		elif is_targeting:
			btn.set_tile_state("PLC", Color(1.0, 0.85, 0.32, 1.0), true, false, false)
		elif can_afford:
			btn.set_tile_state("", hud._active_hud_accent, false, false, false)
		else:
			btn.set_tile_state("", Color(0.56, 0.60, 0.66, 0.80), false, true, false)
		return

	var min_cd: float = INF
	var ready_count: int = 0
	for item: Variant in hud._active_subgroup_units:
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
		btn.set_tile_state(badge, Color(1.0, 0.85, 0.32, 1.0) if is_targeting else hud._active_hud_accent, is_targeting, false, false, 0.0, 0.0)
	else:
		var display_cd: float = 0.0 if min_cd == INF else min_cd
		btn.disabled = false if ability.allow_autocast else true
		btn.set_tile_state("A" if ac_on else "", hud._active_hud_accent, false, false, false, display_cd, maxf(0.1, ability.cooldown_duration))
