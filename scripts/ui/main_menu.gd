class_name MainMenu
extends Control

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")

@onready var btn_audio_mute: Button = %BtnAudioMute
@onready var map_option: OptionButton = %MapOption
@onready var btn_players_2: Button = %BtnPlayers2
@onready var btn_players_3: Button = %BtnPlayers3
@onready var btn_players_4: Button = %BtnPlayers4
@onready var opt_team_preset: OptionButton = %OptTeamPreset
@onready var spectator_badge: Label = %SpectatorBadge
@onready var slot_roster_vbox: VBoxContainer = %SlotRosterVBox
@onready var ai_row: HBoxContainer = %AIRow
@onready var btn_ai_standard: Button = %BtnAIStandard
@onready var btn_ai_passive: Button = %BtnAIPassive
@onready var btn_res_standard: Button = %BtnResStandard
@onready var btn_res_fast: Button = %BtnResFast
@onready var chk_mutator_yield: CheckBox = %ChkMutatorYield
@onready var chk_mutator_no_fog: CheckBox = %ChkMutatorNoFog
@onready var chk_mutator_fast_build: CheckBox = %ChkMutatorFastBuild
@onready var validation_label: Label = %ValidationLabel
@onready var summary_label: Label = %MatchSummaryLabel
@onready var dossier_notice_label: Label = %DossierNoticeLabel
@onready var btn_launch: Button = %BtnLaunch
@onready var btn_settings: Button = %BtnSettings
@onready var btn_quit: Button = %BtnQuit
@onready var locked_slot_2: Button = %LockedSlot2
@onready var locked_slot_3: Button = %LockedSlot3
@onready var locked_slot_4: Button = %LockedSlot4
@onready var locked_slot_5: Button = %LockedSlot5

var _selected_map_path: String = GameConfig.MAP_SKIRMISH_01
var _player_count: int = 2
var _team_preset: StringName = GameConfig.TEAM_PRESET_1V1
var _slot_configs: Array[Dictionary] = []
var _slot_row_widgets: Array[Dictionary] = []
var _playable_factions: Array[FactionData] = []
var _preset_ids: Array[StringName] = []
var _aggro_ai_enabled: bool = true
var _resource_preset: StringName = GameConfig.PRESET_STANDARD
var _mutator_high_yield: bool = false
var _mutator_no_fog: bool = false
var _mutator_fast_build: bool = false
var _bg_time: float = 0.0
var _settings_instance: SettingsMenu = null
var _inspected_locked_btn: Button = null
var _suppress_callbacks: bool = false


func _ready() -> void:
	Engine.time_scale = 1.0
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(false)

	_selected_map_path = GameConfig.selected_map_path
	_player_count = GameConfig.player_count
	_team_preset = GameConfig.team_preset
	_aggro_ai_enabled = GameConfig.aggro_ai_enabled
	_resource_preset = GameConfig.resource_preset
	_mutator_high_yield = GameConfig.mutator_high_yield
	_mutator_no_fog = GameConfig.mutator_no_fog
	_mutator_fast_build = GameConfig.mutator_fast_build

	_slot_configs.clear()
	for i: int in range(4):
		if i < GameConfig.slot_configs.size():
			_slot_configs.append((GameConfig.slot_configs[i] as Dictionary).duplicate(true))
		else:
			_slot_configs.append({
				"team_id": i,
				"alliance_id": i,
				"controller_type": 0 if i == 0 else 1,
				"faction_id": GameConfig.selected_faction_id,
				"ai_difficulty": int(GameConfig.AIDifficulty.STANDARD),
				"ai_playstyle": int(GameConfig.AIPlaystyle.BALANCED),
			})

	if map_option != null:
		map_option.clear()
		var selected_idx: int = 0
		for i: int in range(GameConfig.MAP_CATALOG.size()):
			var entry: Dictionary = GameConfig.MAP_CATALOG[i]
			map_option.add_item(String(entry["label"]), i)
			if String(entry["path"]) == _selected_map_path:
				selected_idx = i
		map_option.select(selected_idx)
		map_option.item_selected.connect(_on_map_selected)

	if btn_players_2 != null:
		btn_players_2.pressed.connect(func() -> void: _set_player_count(2))
	if btn_players_3 != null:
		btn_players_3.pressed.connect(func() -> void: _set_player_count(3))
	if btn_players_4 != null:
		btn_players_4.pressed.connect(func() -> void: _set_player_count(4))

	if opt_team_preset != null:
		opt_team_preset.item_selected.connect(_on_team_preset_selected)

	_build_slot_roster_widgets()

	if btn_ai_standard != null:
		btn_ai_standard.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_aggro_ai_enabled = true
			_refresh_ui()
		)
	if btn_ai_passive != null:
		btn_ai_passive.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_aggro_ai_enabled = false
			_refresh_ui()
		)

	if btn_res_standard != null:
		btn_res_standard.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_resource_preset = GameConfig.PRESET_STANDARD
			_refresh_ui()
		)
	if btn_res_fast != null:
		btn_res_fast.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_resource_preset = GameConfig.PRESET_FAST_TECH
			_refresh_ui()
		)

	if chk_mutator_yield != null:
		chk_mutator_yield.button_pressed = _mutator_high_yield
		chk_mutator_yield.toggled.connect(func(pressed: bool) -> void:
			AudioManager.play_ui_click()
			_mutator_high_yield = pressed
			_refresh_ui()
		)
	if chk_mutator_no_fog != null:
		chk_mutator_no_fog.button_pressed = _mutator_no_fog
		chk_mutator_no_fog.toggled.connect(func(pressed: bool) -> void:
			AudioManager.play_ui_click()
			_mutator_no_fog = pressed
			_refresh_ui()
		)
	if chk_mutator_fast_build != null:
		chk_mutator_fast_build.button_pressed = _mutator_fast_build
		chk_mutator_fast_build.toggled.connect(func(pressed: bool) -> void:
			AudioManager.play_ui_click()
			_mutator_fast_build = pressed
			_refresh_ui()
		)

	if btn_audio_mute != null:
		btn_audio_mute.pressed.connect(func() -> void:
			AudioManager.toggle_mute()
			_refresh_audio_button()
		)
	if not AudioManager.mute_changed.is_connected(_on_mute_changed):
		AudioManager.mute_changed.connect(_on_mute_changed)

	_wire_locked_card(
		locked_slot_2,
		"02 // AETHER_PRIME",
		"Solar-Optic Precision — Long-range prism relays & shield-linked beam arrays that punish clustered swarms from elevated sightlines.",
		Color(0.56, 0.90, 1.0, 1.0)
	)
	_wire_locked_card(
		locked_slot_3,
		"03 // IRON_CONSENSUS",
		"Heavy Automata Armor — Modular siege walkers & kinetic bastion walls engineered to outlast attrition pushes and hold choke points.",
		Color(1.0, 0.76, 0.42, 1.0)
	)
	_wire_locked_card(
		locked_slot_4,
		"04 // NULL_VECTOR",
		"Stealth & Algorithmic Subversion — Cloaked infiltrators & sensor-spoofing nodes designed to ambush expansions and disrupt Compute pipelines.",
		Color(0.84, 0.66, 1.0, 1.0)
	)
	_wire_locked_card(
		locked_slot_5,
		"05 // VERDANT_OS",
		"Adaptive Bio-Lattice — Living creep networks & regenerative symbiote spires that turn contested territory into self-healing strongholds.",
		Color(0.42, 0.98, 0.72, 1.0)
	)

	if btn_launch != null:
		btn_launch.pressed.connect(_on_launch_pressed)
	if btn_settings != null:
		btn_settings.pressed.connect(_on_settings_pressed)
	if btn_quit != null:
		btn_quit.pressed.connect(_on_quit_pressed)

	_wire_hover_audio([
		btn_audio_mute, map_option, btn_players_2, btn_players_3, btn_players_4,
		opt_team_preset, btn_ai_standard, btn_ai_passive, btn_res_standard, btn_res_fast,
		chk_mutator_yield, chk_mutator_no_fog, chk_mutator_fast_build,
		btn_launch, btn_settings, btn_quit,
		locked_slot_2, locked_slot_3, locked_slot_4, locked_slot_5,
	])

	if dossier_notice_label != null and TeamManager != null and TeamManager.has_method("get_faction_data"):
		var fac_res: Resource = TeamManager.get_faction_data(GameConfig.selected_faction_id)
		if fac_res != null:
			var fac_name: String = String(fac_res.get("display_name"))
			var fac_tag: String = String(fac_res.get("tagline"))
			var b_roster: Variant = fac_res.get("building_roster")
			var u_roster: Variant = fac_res.get("unit_roster")
			var b_cnt: int = (b_roster as Array).size() if b_roster is Array else 7
			var u_cnt: int = (u_roster as Array).size() if u_roster is Array else 11
			dossier_notice_label.text = "%s (%d Structures • %d Units): %s" % [fac_name, b_cnt, u_cnt, fac_tag]

	_clamp_player_count_for_map()
	_rebuild_preset_options()
	_refresh_audio_button()
	_refresh_ui()


func _build_slot_roster_widgets() -> void:
	if slot_roster_vbox == null:
		return
	for child: Node in slot_roster_vbox.get_children():
		child.queue_free()
	_slot_row_widgets.clear()
	_playable_factions = TeamManager.get_playable_factions() if (TeamManager != null and TeamManager.has_method("get_playable_factions")) else []

	for i: int in range(4):
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)

		var pip: ColorRect = ColorRect.new()
		pip.custom_minimum_size = Vector2(6.0, 22.0)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var pal: Dictionary = TeamManager.DEFAULT_TEAM_PALETTES[i % TeamManager.DEFAULT_TEAM_PALETTES.size()] if TeamManager != null else {"primary": Color(0.24, 0.96, 0.88, 1.0)}
		pip.color = pal["primary"] as Color
		row.add_child(pip)

		var slot_lbl: Label = Label.new()
		slot_lbl.text = "P%d" % (i + 1)
		slot_lbl.custom_minimum_size = Vector2(20.0, 0.0)
		slot_lbl.add_theme_font_size_override("font_size", 11)
		slot_lbl.add_theme_color_override("font_color", pal["primary"] as Color)
		row.add_child(slot_lbl)

		var ctrl_btn: Button = Button.new()
		ctrl_btn.custom_minimum_size = Vector2(48.0, 24.0)
		ctrl_btn.focus_mode = Control.FOCUS_NONE
		ctrl_btn.add_theme_font_size_override("font_size", 10)
		ctrl_btn.tooltip_text = "Click to switch between Human and AI (all AI = Spectator Mode)"
		var captured_i: int = i
		ctrl_btn.pressed.connect(func() -> void:
			_on_slot_controller_toggled(captured_i)
		)
		row.add_child(ctrl_btn)

		var ally_opt: OptionButton = OptionButton.new()
		ally_opt.custom_minimum_size = Vector2(46.0, 24.0)
		ally_opt.clip_text = true
		ally_opt.fit_to_longest_item = false
		ally_opt.focus_mode = Control.FOCUS_NONE
		ally_opt.add_theme_font_size_override("font_size", 10)
		ally_opt.add_item("T-A", 0)
		ally_opt.add_item("T-B", 1)
		ally_opt.add_item("T-C", 2)
		ally_opt.add_item("T-D", 3)
		ally_opt.item_selected.connect(func(idx: int) -> void:
			_on_slot_alliance_changed(captured_i, idx)
		)
		row.add_child(ally_opt)

		var fac_opt: OptionButton = OptionButton.new()
		fac_opt.custom_minimum_size = Vector2(66.0, 24.0)
		fac_opt.clip_text = true
		fac_opt.fit_to_longest_item = false
		fac_opt.focus_mode = Control.FOCUS_NONE
		fac_opt.add_theme_font_size_override("font_size", 10)
		if _playable_factions.is_empty():
			fac_opt.add_item("GEN-V2", 0)
			fac_opt.disabled = true
			fac_opt.tooltip_text = "More factions unlocking in 3.0"
		else:
			for fi: int in range(_playable_factions.size()):
				var fd: FactionData = _playable_factions[fi]
				var f_lbl: String = fd.short_code if not fd.short_code.is_empty() else fd.display_name
				fac_opt.add_item(f_lbl, fi)
			fac_opt.disabled = (_playable_factions.size() <= 1)
			fac_opt.tooltip_text = "More factions unlocking in 3.0" if _playable_factions.size() <= 1 else "Select Faction for slot P%d" % (i + 1)
		fac_opt.item_selected.connect(func(idx: int) -> void:
			_on_slot_faction_changed(captured_i, idx)
		)
		row.add_child(fac_opt)

		var diff_opt: OptionButton = OptionButton.new()
		diff_opt.custom_minimum_size = Vector2(68.0, 24.0)
		diff_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		diff_opt.clip_text = true
		diff_opt.fit_to_longest_item = false
		diff_opt.focus_mode = Control.FOCUS_NONE
		diff_opt.add_theme_font_size_override("font_size", 10)
		diff_opt.add_item("Relaxed", int(GameConfig.AIDifficulty.RELAXED))
		diff_opt.add_item("Standard", int(GameConfig.AIDifficulty.STANDARD))
		diff_opt.add_item("Brutal", int(GameConfig.AIDifficulty.BRUTAL))
		diff_opt.item_selected.connect(func(idx: int) -> void:
			_on_slot_difficulty_changed(captured_i, idx)
		)
		row.add_child(diff_opt)

		var style_opt: OptionButton = OptionButton.new()
		style_opt.custom_minimum_size = Vector2(66.0, 24.0)
		style_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		style_opt.clip_text = true
		style_opt.fit_to_longest_item = false
		style_opt.focus_mode = Control.FOCUS_NONE
		style_opt.add_theme_font_size_override("font_size", 10)
		style_opt.add_item("Balanced", int(GameConfig.AIPlaystyle.BALANCED))
		style_opt.add_item("Swarm", int(GameConfig.AIPlaystyle.SWARM_RUSH))
		style_opt.add_item("Tech", int(GameConfig.AIPlaystyle.SYNTHETICS_TECH))
		style_opt.item_selected.connect(func(idx: int) -> void:
			_on_slot_playstyle_changed(captured_i, idx)
		)
		row.add_child(style_opt)

		var human_tag: Label = Label.new()
		human_tag.text = "LOCAL COMMANDER"
		human_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		human_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		human_tag.add_theme_font_size_override("font_size", 10)
		human_tag.add_theme_color_override("font_color", Color(0.42, 0.96, 0.90, 0.90))
		human_tag.visible = false
		row.add_child(human_tag)

		slot_roster_vbox.add_child(row)
		_slot_row_widgets.append({
			"row": row,
			"ctrl_btn": ctrl_btn,
			"ally_opt": ally_opt,
			"fac_opt": fac_opt,
			"diff_opt": diff_opt,
			"style_opt": style_opt,
			"human_tag": human_tag,
		})


func _set_player_count(count: int) -> void:
	var max_p: int = GameConfig.get_map_max_players(_selected_map_path)
	var clamped: int = clampi(count, 2, max_p)
	if clamped == _player_count:
		return
	AudioManager.play_ui_click()
	_player_count = clamped
	# Choose sensible default preset when switching player count
	if _player_count == 2:
		_team_preset = GameConfig.TEAM_PRESET_1V1
	elif _player_count == 3:
		_team_preset = GameConfig.TEAM_PRESET_FFA
	else:
		_team_preset = GameConfig.TEAM_PRESET_FFA
	GameConfig.apply_team_preset(_player_count, _team_preset, _slot_configs)
	_rebuild_preset_options()
	_refresh_ui()


func _clamp_player_count_for_map() -> void:
	var max_p: int = GameConfig.get_map_max_players(_selected_map_path)
	if _player_count > max_p:
		_player_count = max_p
		_team_preset = GameConfig.TEAM_PRESET_1V1 if _player_count == 2 else GameConfig.TEAM_PRESET_FFA
		GameConfig.apply_team_preset(_player_count, _team_preset, _slot_configs)
	# Ensure preset is valid for current player count
	var valid_list: Array[Dictionary] = GameConfig.get_valid_presets_for_count(_player_count)
	var found: bool = false
	for item: Dictionary in valid_list:
		if item["id"] == _team_preset:
			found = true
			break
	if not found and not valid_list.is_empty():
		_team_preset = valid_list[0]["id"] as StringName
		GameConfig.apply_team_preset(_player_count, _team_preset, _slot_configs)


func _rebuild_preset_options() -> void:
	if opt_team_preset == null:
		return
	_suppress_callbacks = true
	opt_team_preset.clear()
	_preset_ids.clear()
	var valid_list: Array[Dictionary] = GameConfig.get_valid_presets_for_count(_player_count)
	var sel_idx: int = 0
	for i: int in range(valid_list.size()):
		var item: Dictionary = valid_list[i]
		var pid: StringName = item["id"] as StringName
		_preset_ids.append(pid)
		opt_team_preset.add_item(String(item["label"]), i)
		if pid == _team_preset:
			sel_idx = i
	opt_team_preset.select(sel_idx)
	_suppress_callbacks = false


func _on_team_preset_selected(index: int) -> void:
	if _suppress_callbacks or index < 0 or index >= _preset_ids.size():
		return
	AudioManager.play_ui_click()
	_team_preset = _preset_ids[index]
	GameConfig.apply_team_preset(_player_count, _team_preset, _slot_configs)
	_refresh_ui()


func _on_slot_controller_toggled(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _slot_configs.size():
		return
	AudioManager.play_ui_click()
	var cur_ctrl: int = int(_slot_configs[slot_idx]["controller_type"])
	if cur_ctrl == 0:
		# Switch Human -> AI (Spectator Mode if no Human remains)
		_slot_configs[slot_idx]["controller_type"] = 1
	else:
		# Switch AI -> Human; enforce at most 1 local Human across all slots
		for i: int in range(_slot_configs.size()):
			_slot_configs[i]["controller_type"] = 0 if i == slot_idx else 1
	_refresh_ui()


func _on_slot_alliance_changed(slot_idx: int, alliance_idx: int) -> void:
	if _suppress_callbacks or slot_idx < 0 or slot_idx >= _slot_configs.size():
		return
	AudioManager.play_ui_click()
	_slot_configs[slot_idx]["alliance_id"] = clampi(alliance_idx, 0, 3)
	_team_preset = GameConfig.TEAM_PRESET_CUSTOM
	_rebuild_preset_options()
	_refresh_ui()


func _on_slot_difficulty_changed(slot_idx: int, diff_idx: int) -> void:
	if _suppress_callbacks or slot_idx < 0 or slot_idx >= _slot_configs.size():
		return
	AudioManager.play_ui_click()
	_slot_configs[slot_idx]["ai_difficulty"] = clampi(diff_idx, 0, 2)
	_refresh_ui()


func _on_slot_playstyle_changed(slot_idx: int, style_idx: int) -> void:
	if _suppress_callbacks or slot_idx < 0 or slot_idx >= _slot_configs.size():
		return
	AudioManager.play_ui_click()
	_slot_configs[slot_idx]["ai_playstyle"] = clampi(style_idx, 0, 2)
	_refresh_ui()


func _on_slot_faction_changed(slot_idx: int, fac_idx: int) -> void:
	if _suppress_callbacks or slot_idx < 0 or slot_idx >= _slot_configs.size():
		return
	if fac_idx < 0 or fac_idx >= _playable_factions.size():
		return
	AudioManager.play_ui_click()
	_slot_configs[slot_idx]["faction_id"] = _playable_factions[fac_idx].faction_id
	_refresh_ui()


func _has_active_human() -> bool:
	for i: int in range(mini(_player_count, _slot_configs.size())):
		if int(_slot_configs[i]["controller_type"]) == 0:
			return true
	return false


func _wire_hover_audio(controls: Array) -> void:
	for item: Variant in controls:
		if item is BaseButton:
			var btn: BaseButton = item as BaseButton
			btn.mouse_entered.connect(func() -> void:
				if not btn.disabled and AudioManager != null:
					AudioManager.play_sfx(&"ui_click", -12.0, 0.05)
			)


func _process(delta: float) -> void:
	_bg_time += delta
	queue_redraw()


func _draw() -> void:
	var sz: Vector2 = size
	# Deep Technozen terminal backdrop
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.032, 0.048, 0.068, 1.0), true)

	# Subtle radial cyan/emerald bloom behind active dossier
	var glow_center: Vector2 = Vector2(sz.x * 0.30, sz.y * 0.42)
	for i: int in range(5):
		var r: float = (120.0 + float(i) * 95.0) + sin(_bg_time * 0.8 + float(i)) * 12.0
		var a: float = 0.035 - float(i) * 0.005
		draw_circle(glow_center, r, Color(0.12, 0.88, 0.84, maxf(0.005, a)))

	# Subtle animated Y2K orthogonal grid with drifting intersection pulses
	var grid_step: float = 48.0
	var drift_y: float = fmod(_bg_time * 10.0, grid_step)
	var grid_col: Color = Color(0.14, 0.42, 0.50, 0.12)
	var x: float = 0.0
	while x <= sz.x:
		draw_line(Vector2(x, 0.0), Vector2(x, sz.y), grid_col, 1.0)
		x += grid_step
	var y: float = drift_y - grid_step
	while y <= sz.y:
		draw_line(Vector2(0.0, y), Vector2(sz.x, y), grid_col, 1.0)
		y += grid_step

	# Drifting translucent scanline bar
	var scan_y: float = fmod(_bg_time * 42.0, sz.y + 120.0) - 60.0
	draw_rect(Rect2(0.0, scan_y, sz.x, 36.0), Color(0.20, 0.92, 0.88, 0.03), true)
	draw_line(Vector2(0.0, scan_y + 18.0), Vector2(sz.x, scan_y + 18.0), Color(0.24, 0.96, 0.92, 0.10), 1.0)

	# Subtle pulsing diagonal telemetry nodes near the scanline
	var node_x: float = grid_step * 2.0
	while node_x < sz.x - grid_step:
		var pulse_y: float = floorf((scan_y + 18.0) / grid_step) * grid_step + drift_y
		if pulse_y >= 16.0 and pulse_y <= sz.y - 16.0:
			draw_circle(Vector2(node_x, pulse_y), 2.0, Color(0.26, 0.96, 0.90, 0.22))
		node_x += grid_step * 4.0

	# Corner Y2K framing brackets
	var m: float = 14.0
	var b: float = 22.0
	var frame_col: Color = Color(0.22, 0.88, 0.92, 0.45)
	draw_line(Vector2(m, m), Vector2(m + b, m), frame_col, 2.0)
	draw_line(Vector2(m, m), Vector2(m, m + b), frame_col, 2.0)
	draw_line(Vector2(sz.x - m, m), Vector2(sz.x - m - b, m), frame_col, 2.0)
	draw_line(Vector2(sz.x - m, m), Vector2(sz.x - m, m + b), frame_col, 2.0)
	draw_line(Vector2(m, sz.y - m), Vector2(m + b, sz.y - m), frame_col, 2.0)
	draw_line(Vector2(m, sz.y - m), Vector2(m, sz.y - m - b), frame_col, 2.0)
	draw_line(Vector2(sz.x - m, sz.y - m), Vector2(sz.x - m - b, sz.y - m), frame_col, 2.0)
	draw_line(Vector2(sz.x - m, sz.y - m), Vector2(sz.x - m, sz.y - m - b), frame_col, 2.0)


func _wire_locked_card(btn: Button, dossier_name: String, briefing: String, accent: Color) -> void:
	if btn == null:
		return
	btn.pressed.connect(func() -> void:
		AudioManager.play_ui_click()
		_inspected_locked_btn = btn
		_refresh_locked_card_highlights()
		if dossier_notice_label != null:
			var active_name: String = "GENESIS_V2"
			if TeamManager != null and TeamManager.has_method("get_faction_data"):
				var active_fac: FactionData = TeamManager.get_faction_data(GameConfig.selected_faction_id)
				if active_fac != null:
					active_name = active_fac.short_code if not active_fac.short_code.is_empty() else active_fac.display_name
			dossier_notice_label.text = "[CLASSIFIED PREVIEW] %s — %s (Locked; %s remains selected for launch.)" % [dossier_name, briefing, active_name]
			dossier_notice_label.modulate = accent
	)


func _refresh_locked_card_highlights() -> void:
	var cards: Array = [
		{"btn": locked_slot_2, "idle": Color(0.76, 0.82, 0.90, 0.78), "hi": Color(0.68, 0.96, 1.0, 1.0)},
		{"btn": locked_slot_3, "idle": Color(0.84, 0.78, 0.72, 0.78), "hi": Color(1.0, 0.84, 0.56, 1.0)},
		{"btn": locked_slot_4, "idle": Color(0.80, 0.74, 0.90, 0.78), "hi": Color(0.92, 0.78, 1.0, 1.0)},
		{"btn": locked_slot_5, "idle": Color(0.72, 0.86, 0.78, 0.78), "hi": Color(0.56, 1.0, 0.80, 1.0)},
	]
	for item: Dictionary in cards:
		var b: Button = item["btn"] as Button
		if b != null:
			b.modulate = (item["hi"] as Color) if b == _inspected_locked_btn else (item["idle"] as Color)


func _on_map_selected(index: int) -> void:
	AudioManager.play_ui_click()
	if index >= 0 and index < GameConfig.MAP_CATALOG.size():
		_selected_map_path = String((GameConfig.MAP_CATALOG[index] as Dictionary)["path"])
	else:
		_selected_map_path = GameConfig.MAP_SKIRMISH_01
	_clamp_player_count_for_map()
	_rebuild_preset_options()
	_refresh_ui()


func _on_mute_changed(_muted: bool) -> void:
	_refresh_audio_button()


func _refresh_audio_button() -> void:
	if btn_audio_mute == null:
		return
	if AudioManager.is_muted:
		btn_audio_mute.text = "SFX: MUTED"
		btn_audio_mute.modulate = Color(1.0, 0.56, 0.42, 0.92)
	else:
		btn_audio_mute.text = "SFX: ON"
		btn_audio_mute.modulate = Color(0.45, 0.98, 0.90, 1.0)


func _refresh_ui() -> void:
	_suppress_callbacks = true
	var max_p: int = GameConfig.get_map_max_players(_selected_map_path)
	var is_spec: bool = not _has_active_human()
	var valid_teams: bool = GameConfig.has_opposing_alliances(_slot_configs, _player_count)

	if btn_players_2 != null:
		btn_players_2.disabled = false
		btn_players_2.modulate = Color(0.36, 1.0, 0.88, 1.0) if _player_count == 2 else Color(0.66, 0.74, 0.80, 0.78)
	if btn_players_3 != null:
		btn_players_3.disabled = (max_p < 3)
		btn_players_3.tooltip_text = "Requires a 4-player map (Quad Nexus)" if max_p < 3 else "3-Player Skirmish"
		btn_players_3.modulate = Color(0.36, 1.0, 0.88, 1.0) if _player_count == 3 else (Color(0.42, 0.48, 0.54, 0.50) if max_p < 3 else Color(0.66, 0.74, 0.80, 0.78))
	if btn_players_4 != null:
		btn_players_4.disabled = (max_p < 4)
		btn_players_4.tooltip_text = "Requires a 4-player map (Quad Nexus)" if max_p < 4 else "4-Player Skirmish"
		btn_players_4.modulate = Color(0.36, 1.0, 0.88, 1.0) if _player_count == 4 else (Color(0.42, 0.48, 0.54, 0.50) if max_p < 4 else Color(0.66, 0.74, 0.80, 0.78))

	if spectator_badge != null:
		spectator_badge.visible = is_spec

	for i: int in range(_slot_row_widgets.size()):
		var w: Dictionary = _slot_row_widgets[i]
		var row: Control = w["row"] as Control
		row.visible = (i < _player_count)
		if i >= _player_count:
			continue
		var cfg: Dictionary = _slot_configs[i]
		var is_human: bool = int(cfg["controller_type"]) == 0
		var ctrl_btn: Button = w["ctrl_btn"] as Button
		var ally_opt: OptionButton = w["ally_opt"] as OptionButton
		var fac_opt: OptionButton = w["fac_opt"] as OptionButton
		var diff_opt: OptionButton = w["diff_opt"] as OptionButton
		var style_opt: OptionButton = w["style_opt"] as OptionButton
		var human_tag: Label = w["human_tag"] as Label

		ctrl_btn.text = "Human" if is_human else "AI"
		ctrl_btn.modulate = Color(0.36, 1.0, 0.88, 1.0) if is_human else Color(0.84, 0.90, 0.96, 0.92)
		ally_opt.select(clampi(int(cfg["alliance_id"]), 0, 3))
		if fac_opt != null and not _playable_factions.is_empty():
			var slot_fid: StringName = cfg.get("faction_id", &"genesis_v2") as StringName
			var f_sel: int = 0
			for fi: int in range(_playable_factions.size()):
				if _playable_factions[fi].faction_id == slot_fid:
					f_sel = fi
					break
			fac_opt.select(f_sel)
		diff_opt.select(clampi(int(cfg["ai_difficulty"]), 0, 2))
		style_opt.select(clampi(int(cfg["ai_playstyle"]), 0, 2))
		diff_opt.visible = not is_human
		style_opt.visible = not is_human
		diff_opt.disabled = (not is_spec and not _aggro_ai_enabled)
		style_opt.disabled = (not is_spec and not _aggro_ai_enabled)
		human_tag.visible = is_human

	if ai_row != null:
		ai_row.visible = not is_spec
	if btn_ai_standard != null:
		btn_ai_standard.modulate = Color(0.42, 1.0, 0.88, 1.0) if _aggro_ai_enabled else Color(0.66, 0.74, 0.80, 0.78)
	if btn_ai_passive != null:
		btn_ai_passive.modulate = Color(1.0, 0.78, 0.34, 1.0) if not _aggro_ai_enabled else Color(0.66, 0.74, 0.80, 0.78)

	var is_fast: bool = (_resource_preset == GameConfig.PRESET_FAST_TECH)
	if btn_res_standard != null:
		btn_res_standard.modulate = Color(0.42, 1.0, 0.88, 1.0) if not is_fast else Color(0.66, 0.74, 0.80, 0.78)
	if btn_res_fast != null:
		btn_res_fast.modulate = Color(0.36, 0.92, 1.0, 1.0) if is_fast else Color(0.66, 0.74, 0.80, 0.78)

	if validation_label != null:
		validation_label.visible = not valid_teams

	if btn_launch != null:
		btn_launch.disabled = not valid_teams
		if not valid_teams:
			btn_launch.text = "ASSIGN 2+ OPPOSING TEAMS"
		elif is_spec:
			btn_launch.text = "LAUNCH AI SPECTATOR (%dP)" % _player_count
		else:
			btn_launch.text = "LAUNCH %s SKIRMISH" % GameConfig.get_preset_display_label(_team_preset).to_upper()

	if summary_label != null:
		var map_name: String = GameConfig.get_map_label(_selected_map_path)
		var res_str: String = "1000B/500S/200C" if is_fast else "200B/50S"
		var mut_parts: PackedStringArray = PackedStringArray()
		if _mutator_high_yield:
			mut_parts.append("2x Yield")
		if _mutator_no_fog:
			mut_parts.append("No Fog")
		if _mutator_fast_build:
			mut_parts.append("Fast Build")
		var mut_suffix: String = ("  •  " + ", ".join(mut_parts)) if not mut_parts.is_empty() else ""
		var matchup_str: String = _build_alliance_summary_text()
		var mode_tag: String = "AI SPECTATOR" if is_spec else ("PASSIVE SANDBOX" if not _aggro_ai_enabled else "GENESIS_V2")
		summary_label.text = "%s  •  %s\nTEAMS: %s\nRES: %s%s" % [mode_tag, map_name, matchup_str, res_str, mut_suffix]
	_suppress_callbacks = false


func _build_alliance_summary_text() -> String:
	var groups: Dictionary = {}
	for i: int in range(_player_count):
		var cfg: Dictionary = _slot_configs[i]
		var ally: int = int(cfg["alliance_id"])
		if not groups.has(ally):
			groups[ally] = PackedStringArray()
		var tag: String = ("P%d" % (i + 1)) if int(cfg["controller_type"]) == 0 else ("AI%d" % (i + 1))
		(groups[ally] as PackedStringArray).append(tag)
	var keys: Array = groups.keys()
	keys.sort()
	var sides: PackedStringArray = PackedStringArray()
	for k: Variant in keys:
		var members: PackedStringArray = groups[k] as PackedStringArray
		sides.append("[%s: %s]" % [GameConfig.get_alliance_letter(int(k)), "+".join(members)])
	return " vs ".join(sides)


func _on_launch_pressed() -> void:
	if not GameConfig.has_opposing_alliances(_slot_configs, _player_count):
		AudioManager.play_error()
		return
	AudioManager.play_sfx(&"build_complete", -3.0, 0.0)
	GameConfig.set_lobby_config(
		_selected_map_path,
		_player_count,
		_team_preset,
		_slot_configs,
		_aggro_ai_enabled,
		_resource_preset,
		&"genesis_v2",
		_mutator_high_yield,
		_mutator_no_fog,
		_mutator_fast_build
	)
	get_tree().change_scene_to_file(_selected_map_path)


func _on_settings_pressed() -> void:
	if _settings_instance != null and is_instance_valid(_settings_instance):
		return
	AudioManager.play_ui_click()
	_settings_instance = SETTINGS_MENU_SCENE.instantiate() as SettingsMenu
	if _settings_instance != null:
		_settings_instance.closed.connect(func() -> void:
			_settings_instance = null
			_refresh_audio_button()
		)
		add_child(_settings_instance)


func _on_quit_pressed() -> void:
	AudioManager.play_ui_click()
	get_tree().quit()
