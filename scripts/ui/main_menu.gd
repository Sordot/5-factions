class_name MainMenu
extends Control

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")

@onready var btn_audio_mute: Button = %BtnAudioMute
@onready var config_header: Label = %ConfigHeader
@onready var btn_mode_skirmish: Button = %BtnModeSkirmish
@onready var btn_mode_holdout: Button = %BtnModeHoldout
@onready var btn_mode_gauntlet: Button = %BtnModeGauntlet
@onready var skirmish_config_box: VBoxContainer = %SkirmishConfigBox
@onready var holdout_config_box: VBoxContainer = %HoldoutConfigBox
@onready var btn_holdout_fac_gen: Button = %BtnHoldoutFacGen
@onready var btn_holdout_fac_mono: Button = %BtnHoldoutFacMono
@onready var btn_holdout_fac_prisma: Button = %BtnHoldoutFacPrisma
@onready var btn_holdout_fac_mixed: Button = %BtnHoldoutFacMixed
@onready var btn_holdout_diff_relaxed: Button = %BtnHoldoutDiffRelaxed
@onready var btn_holdout_diff_standard: Button = %BtnHoldoutDiffStandard
@onready var btn_holdout_diff_brutal: Button = %BtnHoldoutDiffBrutal
@onready var holdout_record_label: Label = %HoldoutRecordLabel
@onready var gauntlet_config_box: VBoxContainer = %GauntletConfigBox
@onready var gauntlet_drill_scroll: ScrollContainer = %GauntletDrillScroll
@onready var gauntlet_drill_list: VBoxContainer = %GauntletDrillList
@onready var gauntlet_detail_label: Label = %GauntletDetailLabel
@onready var map_option: OptionButton = %MapOption
@onready var proc_map_options_box: VBoxContainer = %ProcMapOptionsBox
@onready var proc_seed_input: LineEdit = %ProcSeedInput
@onready var btn_roll_seed: Button = %BtnRollSeed
@onready var opt_proc_biome: OptionButton = %OptProcBiome
@onready var opt_proc_chokes: OptionButton = %OptProcChokes
@onready var opt_proc_high_ground: OptionButton = %OptProcHighGround
@onready var opt_proc_richness: OptionButton = %OptProcRichness
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
@onready var chk_uplink_victory: CheckBox = %ChkUplinkVictory
@onready var validation_label: Label = %ValidationLabel
@onready var summary_label: Label = %MatchSummaryLabel
@onready var dossier_notice_label: Label = %DossierNoticeLabel
@onready var btn_launch: Button = %BtnLaunch
@onready var btn_settings: Button = %BtnSettings
@onready var btn_quit: Button = %BtnQuit
@onready var faction_section_header: Label = %FactionSectionHeader
@onready var active_faction_card: PanelContainer = %GenesisActiveCard
@onready var faction_color_swatch: ColorRect = %ColorSwatch
@onready var faction_name_label: Label = %FactionName
@onready var faction_tagline_label: Label = %FactionTagline
@onready var faction_active_badge: PanelContainer = %ActiveBadge
@onready var faction_active_badge_label: Label = %Label
@onready var faction_desc_label: Label = %FactionDesc
@onready var faction_badge_row: HFlowContainer = %BadgeRow
@onready var locked_slot_2: Button = %LockedSlot2
@onready var locked_slot_3: Button = %LockedSlot3
@onready var locked_slot_4: Button = %LockedSlot4
@onready var locked_slot_5: Button = %LockedSlot5

const LOCKED_TEASER_DOSSIERS: Array[Dictionary] = [
	{
		"slot_number": 3,
		"button_text": "03 // IRON_CONSENSUS — The Foundry Bloc\nHeavy Automata Armor  •  LOCKED — IN DEVELOPMENT",
		"title": "03 // IRON_CONSENSUS",
		"briefing": "Heavy Automata Armor — Modular siege walkers & kinetic bastion walls engineered to outlast attrition pushes and hold choke points.",
		"accent": Color(1.0, 0.76, 0.42, 1.0),
		"idle": Color(0.84, 0.78, 0.72, 0.78),
		"hi": Color(1.0, 0.84, 0.56, 1.0),
	},
	{
		"slot_number": 4,
		"button_text": "04 // NULL_VECTOR — The Whisper Net\nElectronic Warfare & Disruption  •  LOCKED — IN DEVELOPMENT",
		"title": "04 // NULL_VECTOR",
		"briefing": "Electronic Warfare & Disruption — Signal-spoofing arrays & EMP disruptors designed to sever enemy Compute networks.",
		"accent": Color(0.84, 0.66, 1.0, 1.0),
		"idle": Color(0.80, 0.74, 0.90, 0.78),
		"hi": Color(0.92, 0.78, 1.0, 1.0),
	},
	{
		"slot_number": 5,
		"button_text": "05 // VERDANT_OS — The Canopy Mesh\nAdaptive Bio-Lattice  •  LOCKED — IN DEVELOPMENT",
		"title": "05 // VERDANT_OS",
		"briefing": "Adaptive Bio-Lattice — Living creep networks & regenerative symbiote spires that turn contested territory into self-healing strongholds.",
		"accent": Color(0.42, 0.98, 0.72, 1.0),
		"idle": Color(0.72, 0.86, 0.78, 0.78),
		"hi": Color(0.56, 1.0, 0.80, 1.0),
	},
]

var _featured_faction_id: StringName = &"genesis_v2"
var _dossier_slot_entries: Array[Dictionary] = []
var _selected_mode: int = GameConfig.GameMode.SKIRMISH
var _holdout_enemy_faction_id: StringName = &"monolith_os"
var _holdout_difficulty: int = int(GameConfig.AIDifficulty.STANDARD)
var _selected_drill_id: StringName = GameConfig.DRILL_STUTTER_STEP
var _gauntlet_drill_buttons: Array[Button] = []
var _proc_seed: int = 0
var _proc_chokes: int = 1
var _proc_high_ground: int = 1
var _proc_richness: int = 1
var _proc_biome: StringName = &"auto"
const PROC_BIOME_IDS: Array = [&"auto", &"vat_basin", &"twin_causeway", &"quad_nexus"]

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
var _uplink_victory_enabled: bool = true
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
	_uplink_victory_enabled = GameConfig.uplink_victory_enabled
	_selected_mode = int(GameConfig.active_game_mode)
	_holdout_enemy_faction_id = GameConfig.holdout_enemy_faction_id
	_holdout_difficulty = int(GameConfig.holdout_difficulty)
	_selected_drill_id = GameConfig.selected_gauntlet_drill_id
	_proc_seed = GameConfig.proc_map_seed
	_proc_chokes = GameConfig.proc_map_chokes
	_proc_high_ground = GameConfig.proc_map_high_ground
	_proc_richness = GameConfig.proc_map_richness
	_proc_biome = GameConfig.proc_map_biome

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
	if chk_uplink_victory != null:
		chk_uplink_victory.button_pressed = _uplink_victory_enabled
		chk_uplink_victory.toggled.connect(func(pressed: bool) -> void:
			AudioManager.play_ui_click()
			_uplink_victory_enabled = pressed
			_refresh_ui()
		)

	if btn_audio_mute != null:
		btn_audio_mute.pressed.connect(func() -> void:
			AudioManager.toggle_mute()
			_refresh_audio_button()
		)
	if not AudioManager.mute_changed.is_connected(_on_mute_changed):
		AudioManager.mute_changed.connect(_on_mute_changed)

	if faction_section_header != null:
		faction_section_header.text = "AI LORD FACTION DOSSIERS (%d / 5 ACTIVE)" % maxi(1, _playable_factions.size())

	var slot_btns: Array[Button] = _get_dossier_slot_buttons()
	for si: int in range(slot_btns.size()):
		var sb: Button = slot_btns[si]
		if sb != null:
			var captured_si: int = si
			sb.pressed.connect(func() -> void: _on_dossier_slot_pressed(captured_si))

	if btn_launch != null:
		btn_launch.pressed.connect(_on_launch_pressed)
	if btn_settings != null:
		btn_settings.pressed.connect(_on_settings_pressed)
	if btn_quit != null:
		btn_quit.pressed.connect(_on_quit_pressed)

	# Milestone 3.5b: Mode switcher & Holdout / Gauntlet selectors
	if btn_mode_skirmish != null:
		btn_mode_skirmish.pressed.connect(func() -> void: _set_selected_mode(int(GameConfig.GameMode.SKIRMISH)))
	if btn_mode_holdout != null:
		btn_mode_holdout.pressed.connect(func() -> void: _set_selected_mode(int(GameConfig.GameMode.UPLINK_HOLDOUT)))
	if btn_mode_gauntlet != null:
		btn_mode_gauntlet.pressed.connect(func() -> void: _set_selected_mode(int(GameConfig.GameMode.MICRO_GAUNTLET)))

	if btn_holdout_fac_gen != null:
		btn_holdout_fac_gen.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_holdout_enemy_faction_id = &"genesis_v2"
			_refresh_ui()
		)
	if btn_holdout_fac_mono != null:
		btn_holdout_fac_mono.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_holdout_enemy_faction_id = &"monolith_os"
			_refresh_ui()
		)
	if btn_holdout_fac_prisma != null:
		btn_holdout_fac_prisma.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_holdout_enemy_faction_id = &"prisma_dei"
			_refresh_ui()
		)
	if btn_holdout_fac_mixed != null:
		btn_holdout_fac_mixed.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_holdout_enemy_faction_id = GameConfig.HOLDOUT_ENEMY_MIXED
			_refresh_ui()
		)
	if btn_holdout_diff_relaxed != null:
		btn_holdout_diff_relaxed.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_holdout_difficulty = int(GameConfig.AIDifficulty.RELAXED)
			_refresh_ui()
		)
	if btn_holdout_diff_standard != null:
		btn_holdout_diff_standard.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_holdout_difficulty = int(GameConfig.AIDifficulty.STANDARD)
			_refresh_ui()
		)
	if btn_holdout_diff_brutal != null:
		btn_holdout_diff_brutal.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_holdout_difficulty = int(GameConfig.AIDifficulty.BRUTAL)
			_refresh_ui()
		)
	_build_gauntlet_drill_cards()

	# Milestone 3.6: Procedural Skirmish Map controls
	_init_procedural_map_controls()

	_wire_hover_audio([
		btn_audio_mute, btn_mode_skirmish, btn_mode_holdout, btn_mode_gauntlet,
		btn_holdout_fac_gen, btn_holdout_fac_mono, btn_holdout_fac_prisma, btn_holdout_fac_mixed,
		btn_holdout_diff_relaxed, btn_holdout_diff_standard, btn_holdout_diff_brutal,
		btn_roll_seed,
		opt_proc_biome, opt_proc_chokes, opt_proc_high_ground, opt_proc_richness,
		map_option, btn_players_2, btn_players_3, btn_players_4,
		opt_team_preset, btn_ai_standard, btn_ai_passive, btn_res_standard, btn_res_fast,
		chk_mutator_yield, chk_mutator_no_fog, chk_mutator_fast_build, chk_uplink_victory,
		btn_launch, btn_settings, btn_quit,
		locked_slot_2, locked_slot_3, locked_slot_4, locked_slot_5,
	])
	_wire_hover_audio(_gauntlet_drill_buttons)

	_clamp_player_count_for_map()
	_rebuild_preset_options()
	_featured_faction_id = _get_local_human_faction_id()
	_apply_featured_faction_dossier(_featured_faction_id, true)
	_refresh_audio_button()
	_refresh_ui()


func _build_slot_roster_widgets() -> void:
	if slot_roster_vbox == null:
		return
	for child: Node in slot_roster_vbox.get_children():
		child.queue_free()
	_slot_row_widgets.clear()
	_playable_factions = TeamManager.get_playable_factions() if (TeamManager != null and TeamManager.has_method("get_playable_factions")) else []
	_playable_factions.sort_custom(func(a: FactionData, b: FactionData) -> bool:
		if a.dossier_slot_number != b.dossier_slot_number:
			return a.dossier_slot_number < b.dossier_slot_number
		return String(a.faction_id) < String(b.faction_id)
	)

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
	_featured_faction_id = _get_local_human_faction_id()
	_apply_featured_faction_dossier(_featured_faction_id, true)
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
	var new_fid: StringName = _playable_factions[fac_idx].faction_id
	_slot_configs[slot_idx]["faction_id"] = new_fid
	var human_idx: int = _get_local_human_slot_index()
	if slot_idx == human_idx or (human_idx < 0 and slot_idx == 0):
		_featured_faction_id = new_fid
		_apply_featured_faction_dossier(new_fid, true)
	_refresh_ui()


func _get_local_human_slot_index() -> int:
	for i: int in range(mini(_player_count, _slot_configs.size())):
		if int(_slot_configs[i]["controller_type"]) == 0:
			return i
	return -1


func _get_local_human_faction_id() -> StringName:
	var human_idx: int = _get_local_human_slot_index()
	if human_idx >= 0 and human_idx < _slot_configs.size():
		var h_fid: StringName = _slot_configs[human_idx].get("faction_id", &"genesis_v2") as StringName
		if h_fid != &"":
			return h_fid
	if not _slot_configs.is_empty():
		var s0_fid: StringName = _slot_configs[0].get("faction_id", &"genesis_v2") as StringName
		if s0_fid != &"":
			return s0_fid
	return GameConfig.selected_faction_id if GameConfig != null else &"genesis_v2"


func _get_dossier_slot_buttons() -> Array[Button]:
	return [locked_slot_2, locked_slot_3, locked_slot_4, locked_slot_5]


func _find_faction_data(faction_id: StringName) -> FactionData:
	for fd: FactionData in _playable_factions:
		if fd != null and fd.faction_id == faction_id:
			return fd
	if TeamManager != null and TeamManager.has_method("get_faction_data"):
		var fetched: FactionData = TeamManager.get_faction_data(faction_id) as FactionData
		if fetched != null:
			return fetched
	if not _playable_factions.is_empty():
		return _playable_factions[0]
	return null


func _select_featured_faction(next_fid: StringName) -> void:
	_inspected_locked_btn = null
	_featured_faction_id = next_fid
	var target_slot: int = _get_local_human_slot_index()
	if target_slot < 0:
		target_slot = 0
	if target_slot < _slot_configs.size():
		_slot_configs[target_slot]["faction_id"] = next_fid
	_apply_featured_faction_dossier(next_fid, true)
	_refresh_ui()


func _on_dossier_slot_pressed(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _dossier_slot_entries.size():
		return
	AudioManager.play_ui_click()
	var entry: Dictionary = _dossier_slot_entries[slot_idx]
	var kind: StringName = entry.get("kind", &"locked") as StringName
	if kind == &"playable":
		var next_fid: StringName = entry.get("faction_id", &"genesis_v2") as StringName
		_select_featured_faction(next_fid)
		return
	var btns: Array[Button] = _get_dossier_slot_buttons()
	_inspected_locked_btn = btns[slot_idx] if slot_idx < btns.size() else null
	_refresh_dossier_slot_highlights()
	if dossier_notice_label != null:
		var active_fid: StringName = _get_local_human_faction_id()
		var active_fac: FactionData = _find_faction_data(active_fid)
		var active_name: String = active_fac.short_code if (active_fac != null and not active_fac.short_code.is_empty()) else String(active_fid).to_upper()
		dossier_notice_label.text = "[CLASSIFIED PREVIEW] %s — %s (Locked; %s remains selected for launch.)" % [
			String(entry.get("title", "CLASSIFIED")),
			String(entry.get("briefing", "")),
			active_name,
		]
		dossier_notice_label.modulate = entry.get("accent", Color(0.84, 0.88, 0.96, 1.0)) as Color


func _refresh_dossier_grid(featured_id: StringName) -> void:
	_dossier_slot_entries.clear()
	var occupied_slots: Dictionary = {}
	var alternate_factions: Array[FactionData] = []
	for fd: FactionData in _playable_factions:
		if fd == null:
			continue
		occupied_slots[fd.dossier_slot_number] = true
		if fd.faction_id != featured_id:
			alternate_factions.append(fd)

	for fd: FactionData in alternate_factions:
		var pal: Dictionary = FactionHudTheme.get_palette(fd.faction_id)
		var accent: Color = pal.get("accent", fd.hud_accent_color) as Color
		var sub_raw: String = fd.dossier_subtitle if not fd.dossier_subtitle.is_empty() else fd.tagline
		var short_sub: String = sub_raw.split("•")[0].strip_edges()
		if short_sub.is_empty():
			short_sub = fd.short_code
		var btn_txt: String = "%02d // %s\n%s  •  PLAYABLE — CLICK TO SELECT" % [fd.dossier_slot_number, fd.display_name, short_sub]
		_dossier_slot_entries.append({
			"kind": &"playable",
			"faction_id": fd.faction_id,
			"button_text": btn_txt,
			"accent": accent,
			"idle": accent.lerp(Color.WHITE, 0.16),
			"hi": accent.lerp(Color.WHITE, 0.28),
		})

	for teaser: Dictionary in LOCKED_TEASER_DOSSIERS:
		if _dossier_slot_entries.size() >= 4:
			break
		var s_num: int = int(teaser.get("slot_number", 0))
		if occupied_slots.has(s_num):
			continue
		var t_entry: Dictionary = teaser.duplicate(true)
		t_entry["kind"] = &"locked"
		_dossier_slot_entries.append(t_entry)

	var btns: Array[Button] = _get_dossier_slot_buttons()
	for i: int in range(btns.size()):
		var b: Button = btns[i]
		if b == null:
			continue
		if i < _dossier_slot_entries.size():
			b.visible = true
			b.text = String(_dossier_slot_entries[i].get("button_text", ""))
		else:
			b.visible = false
	_refresh_dossier_slot_highlights()


func _refresh_dossier_slot_highlights() -> void:
	var btns: Array[Button] = _get_dossier_slot_buttons()
	for i: int in range(mini(btns.size(), _dossier_slot_entries.size())):
		var b: Button = btns[i]
		if b == null:
			continue
		var entry: Dictionary = _dossier_slot_entries[i]
		var idle_c: Color = entry.get("idle", Color(0.80, 0.84, 0.90, 0.80)) as Color
		var hi_c: Color = entry.get("hi", Color.WHITE) as Color
		b.modulate = hi_c if (b == _inspected_locked_btn) else idle_c


func _apply_featured_faction_dossier(faction_id: StringName, update_notice: bool = true) -> void:
	var fdata: FactionData = _find_faction_data(faction_id)
	var key: StringName = fdata.faction_id if fdata != null else &"genesis_v2"
	var pal: Dictionary = FactionHudTheme.get_palette(key)
	var accent: Color = pal.get("accent", fdata.hud_accent_color if fdata != null else Color(0.20, 0.96, 0.86, 1.0)) as Color
	var tag_col: Color = accent.lerp(Color.WHITE, 0.22)
	tag_col.a = 0.96
	var is_brutal: bool = (pal.get("style", &"technozen") == &"brutalist")
	var bg_col: Color = Color(0.11, 0.095, 0.075, 0.95) if is_brutal else Color(0.06, 0.12, 0.16, 0.94).lerp(Color(accent.r * 0.16, accent.g * 0.16, accent.b * 0.16, 0.94), 0.35)
	var badge_bg: Color = Color(0.16, 0.125, 0.085, 0.92) if is_brutal else bg_col.lightened(0.06)
	var badge_border: Color = Color(accent.r, accent.g, accent.b, 0.76)

	var slot_num: int = fdata.dossier_slot_number if fdata != null else 1
	var title_txt: String = "%02d // %s" % [slot_num, fdata.display_name] if fdata != null else "01 // GENESIS_V2 — The Vat-Born"
	var tagline_txt: String = (fdata.dossier_subtitle if not fdata.dossier_subtitle.is_empty() else fdata.tagline) if fdata != null else ""
	var desc_txt: String = (fdata.dossier_description if not fdata.dossier_description.is_empty() else fdata.tagline) if fdata != null else ""

	if active_faction_card != null:
		var card_sb: StyleBoxFlat = StyleBoxFlat.new()
		card_sb.content_margin_left = 14.0
		card_sb.content_margin_top = 12.0
		card_sb.content_margin_right = 14.0
		card_sb.content_margin_bottom = 12.0
		card_sb.bg_color = bg_col
		card_sb.border_width_left = 2
		card_sb.border_width_top = 2
		card_sb.border_width_right = 2
		card_sb.border_width_bottom = 2
		card_sb.border_color = accent
		card_sb.corner_radius_top_left = 0 if is_brutal else 6
		card_sb.corner_radius_top_right = 0 if is_brutal else 6
		card_sb.corner_radius_bottom_right = 0 if is_brutal else 6
		card_sb.corner_radius_bottom_left = 0 if is_brutal else 6
		active_faction_card.add_theme_stylebox_override("panel", card_sb)

	if faction_color_swatch != null:
		faction_color_swatch.color = accent
	if faction_name_label != null:
		faction_name_label.text = title_txt
	if faction_tagline_label != null:
		faction_tagline_label.text = tagline_txt
		faction_tagline_label.add_theme_color_override("font_color", tag_col)
	if faction_desc_label != null:
		faction_desc_label.text = desc_txt

	var pill_sb: StyleBoxFlat = StyleBoxFlat.new()
	pill_sb.content_margin_left = 7.0
	pill_sb.content_margin_top = 3.0
	pill_sb.content_margin_right = 7.0
	pill_sb.content_margin_bottom = 3.0
	pill_sb.bg_color = badge_bg
	pill_sb.border_width_left = 1
	pill_sb.border_width_top = 1
	pill_sb.border_width_right = 1
	pill_sb.border_width_bottom = 1
	pill_sb.border_color = badge_border
	pill_sb.corner_radius_top_left = 0 if is_brutal else 3
	pill_sb.corner_radius_top_right = 0 if is_brutal else 3
	pill_sb.corner_radius_bottom_right = 0 if is_brutal else 3
	pill_sb.corner_radius_bottom_left = 0 if is_brutal else 3

	if faction_active_badge != null:
		faction_active_badge.add_theme_stylebox_override("panel", pill_sb)
	if faction_active_badge_label != null:
		faction_active_badge_label.add_theme_color_override("font_color", accent)

	if faction_badge_row != null:
		for child: Node in faction_badge_row.get_children():
			child.queue_free()
		var badges: PackedStringArray = fdata.signature_badges if fdata != null else PackedStringArray()
		for b_txt: String in badges:
			var p: PanelContainer = PanelContainer.new()
			p.add_theme_stylebox_override("panel", pill_sb)
			var l: Label = Label.new()
			l.add_theme_font_size_override("font_size", 11)
			l.text = b_txt
			p.add_child(l)
			faction_badge_row.add_child(p)

	_refresh_dossier_grid(key)

	if update_notice and dossier_notice_label != null:
		if fdata != null:
			dossier_notice_label.text = "%s (%d Structures • %d Units): %s" % [
				fdata.display_name,
				fdata.building_roster.size(),
				fdata.unit_roster.size(),
				fdata.tagline,
			]
		else:
			dossier_notice_label.text = "%s selected for deployment." % title_txt
		dossier_notice_label.modulate = tag_col


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

	# Subtle radial bloom behind active dossier (tinted to active featured faction)
	var pal_bloom: Dictionary = FactionHudTheme.get_palette(_featured_faction_id)
	var bloom_col: Color = pal_bloom.get("accent", Color(0.12, 0.88, 0.84, 1.0)) as Color
	var glow_center: Vector2 = Vector2(sz.x * 0.30, sz.y * 0.42)
	for i: int in range(5):
		var r: float = (120.0 + float(i) * 95.0) + sin(_bg_time * 0.8 + float(i)) * 12.0
		var a: float = 0.035 - float(i) * 0.005
		draw_circle(glow_center, r, Color(bloom_col.r, bloom_col.g, bloom_col.b, maxf(0.005, a)))

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


func _init_procedural_map_controls() -> void:
	if proc_seed_input != null:
		proc_seed_input.text = str(_proc_seed) if _proc_seed > 0 else ""
		proc_seed_input.text_changed.connect(_on_proc_seed_text_changed)
	if btn_roll_seed != null:
		btn_roll_seed.pressed.connect(_on_roll_proc_seed_pressed)
	if opt_proc_biome != null:
		opt_proc_biome.clear()
		opt_proc_biome.add_item("Auto Biome", 0)
		opt_proc_biome.add_item("Vat Basin", 1)
		opt_proc_biome.add_item("Causeway", 2)
		opt_proc_biome.add_item("Quad Nexus", 3)
		var b_idx: int = maxi(0, PROC_BIOME_IDS.find(_proc_biome))
		opt_proc_biome.select(b_idx)
		opt_proc_biome.item_selected.connect(func(idx: int) -> void:
			if _suppress_callbacks or idx < 0 or idx >= PROC_BIOME_IDS.size():
				return
			AudioManager.play_ui_click()
			_proc_biome = PROC_BIOME_IDS[idx] as StringName
			_refresh_ui()
		)
	if opt_proc_chokes != null:
		opt_proc_chokes.clear()
		opt_proc_chokes.add_item("Open Lanes", 0)
		opt_proc_chokes.add_item("Balanced", 1)
		opt_proc_chokes.add_item("Tight Chokes", 2)
		opt_proc_chokes.select(clampi(_proc_chokes, 0, 2))
		opt_proc_chokes.item_selected.connect(func(idx: int) -> void:
			if _suppress_callbacks:
				return
			AudioManager.play_ui_click()
			_proc_chokes = clampi(idx, 0, 2)
			_refresh_ui()
		)
	if opt_proc_high_ground != null:
		opt_proc_high_ground.clear()
		opt_proc_high_ground.add_item("Flat Ground", 0)
		opt_proc_high_ground.add_item("Mid Plateaus", 1)
		opt_proc_high_ground.add_item("High Ground+", 2)
		opt_proc_high_ground.select(clampi(_proc_high_ground, 0, 2))
		opt_proc_high_ground.item_selected.connect(func(idx: int) -> void:
			if _suppress_callbacks:
				return
			AudioManager.play_ui_click()
			_proc_high_ground = clampi(idx, 0, 2)
			_refresh_ui()
		)
	if opt_proc_richness != null:
		opt_proc_richness.clear()
		opt_proc_richness.add_item("Std Yield", 0)
		opt_proc_richness.add_item("Rich Yield", 1)
		opt_proc_richness.add_item("Abundant", 2)
		opt_proc_richness.select(clampi(_proc_richness, 0, 2))
		opt_proc_richness.item_selected.connect(func(idx: int) -> void:
			if _suppress_callbacks:
				return
			AudioManager.play_ui_click()
			_proc_richness = clampi(idx, 0, 2)
			_refresh_ui()
		)


func _on_proc_seed_text_changed(new_text: String) -> void:
	if _suppress_callbacks:
		return
	var cleaned: String = ""
	for i: int in range(new_text.length()):
		var ch: String = new_text.substr(i, 1)
		if ch >= "0" and ch <= "9":
			cleaned += ch
	if cleaned != new_text and proc_seed_input != null:
		_suppress_callbacks = true
		proc_seed_input.text = cleaned
		proc_seed_input.caret_column = cleaned.length()
		_suppress_callbacks = false
	_proc_seed = int(cleaned) if not cleaned.is_empty() else 0
	_refresh_ui()


func _on_roll_proc_seed_pressed() -> void:
	AudioManager.play_ui_click()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	_proc_seed = rng.randi_range(100000, 999999)
	if proc_seed_input != null:
		_suppress_callbacks = true
		proc_seed_input.text = str(_proc_seed)
		_suppress_callbacks = false
	_refresh_ui()


func _set_selected_mode(mode_val: int) -> void:
	if _selected_mode == mode_val:
		return
	AudioManager.play_ui_click()
	_selected_mode = clampi(mode_val, int(GameConfig.GameMode.SKIRMISH), int(GameConfig.GameMode.MICRO_GAUNTLET))
	_refresh_ui()


func _refresh_mode_tabs_and_panels() -> void:
	var is_skirmish: bool = (_selected_mode == int(GameConfig.GameMode.SKIRMISH))
	var is_holdout: bool = (_selected_mode == int(GameConfig.GameMode.UPLINK_HOLDOUT))
	var is_gauntlet: bool = (_selected_mode == int(GameConfig.GameMode.MICRO_GAUNTLET))

	if config_header != null:
		if is_holdout:
			config_header.text = "UPLINK HOLDOUT — WAVE DEFENSE"
		elif is_gauntlet:
			config_header.text = "MICRO GAUNTLET — TACTICAL DRILLS"
		else:
			config_header.text = "SKIRMISH MATCH SETUP"

	if btn_mode_skirmish != null:
		btn_mode_skirmish.modulate = Color(0.32, 1.0, 0.90, 1.0) if is_skirmish else Color(0.66, 0.76, 0.84, 0.78)
	if btn_mode_holdout != null:
		btn_mode_holdout.modulate = Color(1.0, 0.78, 0.30, 1.0) if is_holdout else Color(0.66, 0.76, 0.84, 0.78)
	if btn_mode_gauntlet != null:
		btn_mode_gauntlet.modulate = Color(0.46, 0.88, 1.0, 1.0) if is_gauntlet else Color(0.66, 0.76, 0.84, 0.78)

	if skirmish_config_box != null:
		skirmish_config_box.visible = is_skirmish
	if holdout_config_box != null:
		holdout_config_box.visible = is_holdout
	if gauntlet_config_box != null:
		gauntlet_config_box.visible = is_gauntlet

	if is_holdout:
		_refresh_holdout_panel()
	elif is_gauntlet:
		_refresh_gauntlet_panel()


func _build_gauntlet_drill_cards() -> void:
	_gauntlet_drill_buttons.clear()
	if gauntlet_drill_list == null:
		return
	for child: Node in gauntlet_drill_list.get_children():
		child.queue_free()
	for i: int in range(GameConfig.GAUNTLET_DRILLS.size()):
		var info: Dictionary = GameConfig.GAUNTLET_DRILLS[i] as Dictionary
		var did: StringName = info["id"] as StringName
		var btn: Button = Button.new()
		btn.name = "BtnDrill%d" % i
		btn.custom_minimum_size = Vector2(0.0, 56.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", 10)
		var captured_id: StringName = did
		btn.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_selected_drill_id = captured_id
			GameConfig.selected_gauntlet_drill_id = captured_id
			_refresh_ui()
		)
		gauntlet_drill_list.add_child(btn)
		_gauntlet_drill_buttons.append(btn)


func _refresh_holdout_panel() -> void:
	if btn_holdout_fac_gen != null:
		btn_holdout_fac_gen.modulate = Color(0.32, 1.0, 0.88, 1.0) if _holdout_enemy_faction_id == &"genesis_v2" else Color(0.66, 0.74, 0.80, 0.78)
	if btn_holdout_fac_mono != null:
		btn_holdout_fac_mono.modulate = Color(1.0, 0.68, 0.24, 1.0) if _holdout_enemy_faction_id == &"monolith_os" else Color(0.66, 0.74, 0.80, 0.78)
	if btn_holdout_fac_prisma != null:
		btn_holdout_fac_prisma.modulate = Color(0.98, 0.80, 0.14, 1.0) if _holdout_enemy_faction_id == &"prisma_dei" else Color(0.66, 0.74, 0.80, 0.78)
	if btn_holdout_fac_mixed != null:
		btn_holdout_fac_mixed.modulate = Color(0.96, 0.44, 0.88, 1.0) if _holdout_enemy_faction_id == GameConfig.HOLDOUT_ENEMY_MIXED else Color(0.66, 0.74, 0.80, 0.78)

	if btn_holdout_diff_relaxed != null:
		btn_holdout_diff_relaxed.modulate = Color(0.42, 0.98, 0.72, 1.0) if _holdout_difficulty == int(GameConfig.AIDifficulty.RELAXED) else Color(0.66, 0.74, 0.80, 0.78)
	if btn_holdout_diff_standard != null:
		btn_holdout_diff_standard.modulate = Color(0.36, 0.94, 1.0, 1.0) if _holdout_difficulty == int(GameConfig.AIDifficulty.STANDARD) else Color(0.66, 0.74, 0.80, 0.78)
	if btn_holdout_diff_brutal != null:
		btn_holdout_diff_brutal.modulate = Color(1.0, 0.38, 0.30, 1.0) if _holdout_difficulty == int(GameConfig.AIDifficulty.BRUTAL) else Color(0.66, 0.74, 0.80, 0.78)

	if holdout_record_label != null:
		var player_fd: FactionData = _find_faction_data(_featured_faction_id)
		var player_fac_code: String = player_fd.short_code if (player_fd != null and not player_fd.short_code.is_empty()) else String(_featured_faction_id).to_upper()
		var enemy_code: String = "MIXED ASSAULT (3-FACTION)"
		if _holdout_enemy_faction_id != GameConfig.HOLDOUT_ENEMY_MIXED:
			var enemy_fd: FactionData = _find_faction_data(_holdout_enemy_faction_id)
			enemy_code = enemy_fd.short_code if (enemy_fd != null and not enemy_fd.short_code.is_empty()) else String(_holdout_enemy_faction_id).to_upper()
		var diff_str: String = GameConfig.get_difficulty_label(_holdout_difficulty)
		var best_w: int = ModeRecords.get_holdout_best_wave(_featured_faction_id, _holdout_difficulty)
		var overall_w: int = ModeRecords.get_holdout_overall_best_wave(_featured_faction_id)
		var best_str: String = ("Wave %d" % best_w) if best_w > 0 else "None Yet"
		if best_w >= 10:
			best_str = "Wave %d (CLEARED)" % best_w
		holdout_record_label.text = "COMMANDER: %s  vs.  %s (%s)\nARENA: Skirmish Arena 01  •  10 Waves + Endless\nPERSONAL BEST (%s): %s   •   FACTION BEST: %d" % [
			player_fac_code,
			enemy_code,
			diff_str,
			diff_str,
			best_str,
			overall_w,
		]


func _refresh_gauntlet_panel() -> void:
	for i: int in range(mini(_gauntlet_drill_buttons.size(), GameConfig.GAUNTLET_DRILLS.size())):
		var btn: Button = _gauntlet_drill_buttons[i]
		if btn == null or not is_instance_valid(btn):
			continue
		var info: Dictionary = GameConfig.GAUNTLET_DRILLS[i] as Dictionary
		var did: StringName = info["id"] as StringName
		var rec: Dictionary = ModeRecords.get_gauntlet_record(did)
		var medal: int = int(rec.get("medal", ModeRecords.Medal.NONE))
		var medal_tag: String = ModeRecords.get_medal_label(medal)
		var best_str: String = ""
		if bool(rec.get("has_record", false)) and float(rec.get("best_value", -1.0)) >= 0.0:
			if bool(info.get("lower_is_better", true)):
				best_str = " %.1fs" % float(rec["best_value"])
			else:
				best_str = " %s" % InspectionHelper.format_number(int(round(float(rec["best_value"]))))
		var fac_badge: String = String(info.get("faction_badge", "[ANY]"))
		var gold_hint: String = String(info.get("gold_hint", ""))
		btn.text = "%d. %s %s  [%s%s]\n%s  •  %s" % [
			i + 1,
			String(info["title"]),
			fac_badge,
			medal_tag,
			best_str,
			String(info["tag"]),
			gold_hint,
		]
		var is_sel: bool = (did == _selected_drill_id)
		if is_sel:
			btn.modulate = Color(0.98, 0.84, 0.28, 1.0) if fac_badge == "[PRIS]" else Color(0.42, 1.0, 0.92, 1.0)
		elif medal > ModeRecords.Medal.NONE:
			btn.modulate = ModeRecords.get_medal_color(medal).lerp(Color.WHITE, 0.25)
		else:
			btn.modulate = Color(0.76, 0.84, 0.90, 0.86)

	if gauntlet_detail_label != null:
		var sel_info: Dictionary = GameConfig.get_gauntlet_drill_info(_selected_drill_id)
		var fixed_f: StringName = sel_info.get("fixed_faction", &"") as StringName
		var fac_note: String = ""
		if fixed_f == &"":
			var p_fd: FactionData = _find_faction_data(_featured_faction_id)
			var pcode: String = p_fd.display_name.split("—")[0].strip_edges() if p_fd != null else String(_featured_faction_id).to_upper()
			fac_note = "ACTIVE FACTION: %s (change on left)" % pcode
		else:
			fac_note = "PRESET SQUAD: %s" % String(fixed_f).to_upper()
		var retry_hint: String = "[Ctrl+R]" if _selected_drill_id == GameConfig.DRILL_OPTIMAL_BOOM else "[R]"
		gauntlet_detail_label.text = "%s\n%s\n%s  •  Retry: %s" % [
			String(sel_info["summary"]),
			String(sel_info["thresholds"]),
			fac_note,
			retry_hint,
		]


func _refresh_ui() -> void:
	_suppress_callbacks = true
	_refresh_mode_tabs_and_panels()
	var is_proc_map: bool = GameConfig.is_procedural_map_selected(_selected_map_path)
	if proc_map_options_box != null:
		proc_map_options_box.visible = is_proc_map
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
		if _selected_mode == int(GameConfig.GameMode.UPLINK_HOLDOUT):
			btn_launch.disabled = false
			btn_launch.text = "LAUNCH UPLINK HOLDOUT"
		elif _selected_mode == int(GameConfig.GameMode.MICRO_GAUNTLET):
			btn_launch.disabled = false
			btn_launch.text = "LAUNCH DRILL"
		else:
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
		var win_tag: String = "Domination + Uplink (3:00)" if _uplink_victory_enabled else "Domination Only"
		var mut_suffix: String = ("  •  " + ", ".join(mut_parts)) if not mut_parts.is_empty() else ""
		var matchup_str: String = _build_alliance_summary_text()
		var local_fid: StringName = _get_local_human_faction_id()
		var local_fac_label: String = String(local_fid).to_upper()
		if TeamManager != null and TeamManager.has_method("get_faction_data"):
			var lf_data: FactionData = TeamManager.get_faction_data(local_fid) as FactionData
			if lf_data != null and not lf_data.short_code.is_empty():
				local_fac_label = lf_data.short_code
		var mode_tag: String = "AI SPECTATOR" if is_spec else ("PASSIVE SANDBOX (%s)" % local_fac_label if not _aggro_ai_enabled else local_fac_label)
		var proc_tag: String = ""
		if GameConfig.is_procedural_map_selected(_selected_map_path):
			var seed_str: String = ("SEED %d" % _proc_seed) if _proc_seed > 0 else "SEED RANDOM"
			proc_tag = " [%s]" % seed_str
		summary_label.text = "%s  •  %s%s\nTEAMS: %s\nWIN: %s  •  RES: %s%s" % [mode_tag, map_name, proc_tag, matchup_str, win_tag, res_str, mut_suffix]
	_suppress_callbacks = false


func _build_alliance_summary_text() -> String:
	var groups: Dictionary = {}
	for i: int in range(_player_count):
		var cfg: Dictionary = _slot_configs[i]
		var ally: int = int(cfg["alliance_id"])
		if not groups.has(ally):
			groups[ally] = PackedStringArray()
		var base_tag: String = ("P%d" % (i + 1)) if int(cfg["controller_type"]) == 0 else ("AI%d" % (i + 1))
		var sfid: StringName = cfg.get("faction_id", &"genesis_v2") as StringName
		var f_short: String = String(sfid).to_upper()
		if TeamManager != null and TeamManager.has_method("get_faction_data"):
			var fd: FactionData = TeamManager.get_faction_data(sfid) as FactionData
			if fd != null and not fd.short_code.is_empty():
				f_short = fd.short_code
		(groups[ally] as PackedStringArray).append("%s:%s" % [base_tag, f_short])
	var keys: Array = groups.keys()
	keys.sort()
	var sides: PackedStringArray = PackedStringArray()
	for k: Variant in keys:
		var members: PackedStringArray = groups[k] as PackedStringArray
		sides.append("[%s: %s]" % [GameConfig.get_alliance_letter(int(k)), "+".join(members)])
	return " vs ".join(sides)


func _on_launch_pressed() -> void:
	if _selected_mode == int(GameConfig.GameMode.UPLINK_HOLDOUT):
		AudioManager.play_sfx(&"build_complete", -3.0, 0.0)
		GameConfig.set_holdout_config(_featured_faction_id, _holdout_enemy_faction_id, _holdout_difficulty)
		get_tree().change_scene_to_file(GameConfig.selected_map_path)
		return
	if _selected_mode == int(GameConfig.GameMode.MICRO_GAUNTLET):
		AudioManager.play_sfx(&"build_complete", -3.0, 0.0)
		GameConfig.set_gauntlet_config(_selected_drill_id, _featured_faction_id)
		get_tree().change_scene_to_file(GameConfig.selected_map_path)
		return
	if not GameConfig.has_opposing_alliances(_slot_configs, _player_count):
		AudioManager.play_error()
		return
	AudioManager.play_sfx(&"build_complete", -3.0, 0.0)
	var primary_faction_id: StringName = _get_local_human_faction_id()
	GameConfig.proc_map_seed = _proc_seed
	GameConfig.proc_map_chokes = _proc_chokes
	GameConfig.proc_map_high_ground = _proc_high_ground
	GameConfig.proc_map_richness = _proc_richness
	GameConfig.proc_map_biome = _proc_biome
	if GameConfig.is_procedural_map_selected(_selected_map_path):
		GameConfig.resolve_procedural_seed()
	GameConfig.set_lobby_config(
		_selected_map_path,
		_player_count,
		_team_preset,
		_slot_configs,
		_aggro_ai_enabled,
		_resource_preset,
		primary_faction_id,
		_mutator_high_yield,
		_mutator_no_fog,
		_mutator_fast_build,
		_uplink_victory_enabled
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
