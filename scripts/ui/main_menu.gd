class_name MainMenu
extends Control

const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")

@onready var btn_audio_mute: Button = %BtnAudioMute
@onready var map_option: OptionButton = %MapOption
@onready var btn_mode_pvai: Button = %BtnModePvAI
@onready var btn_mode_aivai: Button = %BtnModeAIvAI
@onready var ai_label: Label = %AILabel
@onready var ai_row: HBoxContainer = %AIRow
@onready var btn_ai_standard: Button = %BtnAIStandard
@onready var btn_ai_passive: Button = %BtnAIPassive
@onready var team0_ai_grid: GridContainer = %Team0AIGrid
@onready var opt_team0_diff: OptionButton = %OptTeam0Diff
@onready var opt_team0_style: OptionButton = %OptTeam0Style
@onready var diff_label: Label = %DiffLabel
@onready var style_label: Label = %StyleLabel
@onready var opt_ai_difficulty: OptionButton = %OptAIDifficulty
@onready var opt_ai_playstyle: OptionButton = %OptAIPlaystyle
@onready var btn_res_standard: Button = %BtnResStandard
@onready var btn_res_fast: Button = %BtnResFast
@onready var chk_mutator_yield: CheckBox = %ChkMutatorYield
@onready var chk_mutator_no_fog: CheckBox = %ChkMutatorNoFog
@onready var chk_mutator_fast_build: CheckBox = %ChkMutatorFastBuild
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
var _match_mode: int = 0
var _aggro_ai_enabled: bool = true
var _team0_difficulty: int = 1
var _team0_playstyle: int = 1
var _ai_difficulty: int = 1
var _ai_playstyle: int = 0
var _resource_preset: StringName = GameConfig.PRESET_STANDARD
var _mutator_high_yield: bool = false
var _mutator_no_fog: bool = false
var _mutator_fast_build: bool = false
var _bg_time: float = 0.0
var _settings_instance: SettingsMenu = null
var _inspected_locked_btn: Button = null


func _ready() -> void:
	Engine.time_scale = 1.0
	if SettingsManager != null:
		SettingsManager.set_gameplay_cursor_active(false)
	_selected_map_path = GameConfig.selected_map_path
	_match_mode = int(GameConfig.match_mode)
	_aggro_ai_enabled = GameConfig.aggro_ai_enabled
	_team0_difficulty = int(GameConfig.team0_ai_difficulty)
	_team0_playstyle = int(GameConfig.team0_ai_playstyle)
	_ai_difficulty = int(GameConfig.ai_difficulty)
	_ai_playstyle = int(GameConfig.ai_playstyle)
	_resource_preset = GameConfig.resource_preset
	_mutator_high_yield = GameConfig.mutator_high_yield
	_mutator_no_fog = GameConfig.mutator_no_fog
	_mutator_fast_build = GameConfig.mutator_fast_build

	if map_option != null:
		map_option.clear()
		map_option.add_item("Skirmish Arena 01 (1v1 Symmetric)", 0)
		map_option.add_item("Twin Causeway (Skirmish Arena 02)", 1)
		map_option.add_item("Sandbox Testbed (Milestone 0)", 2)
		var map_idx: int = 0
		if _selected_map_path == GameConfig.MAP_SKIRMISH_02:
			map_idx = 1
		elif _selected_map_path == GameConfig.MAP_SANDBOX_TESTBED:
			map_idx = 2
		map_option.select(map_idx)
		map_option.item_selected.connect(_on_map_selected)

	if btn_mode_pvai != null:
		btn_mode_pvai.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_match_mode = 0
			_refresh_ui()
		)
	if btn_mode_aivai != null:
		btn_mode_aivai.pressed.connect(func() -> void:
			AudioManager.play_ui_click()
			_match_mode = 1
			_refresh_ui()
		)

	if opt_team0_diff != null:
		opt_team0_diff.clear()
		opt_team0_diff.add_item("Relaxed", int(GameConfig.AIDifficulty.RELAXED))
		opt_team0_diff.add_item("Standard", int(GameConfig.AIDifficulty.STANDARD))
		opt_team0_diff.add_item("Brutal", int(GameConfig.AIDifficulty.BRUTAL))
		opt_team0_diff.select(_team0_difficulty)
		opt_team0_diff.item_selected.connect(func(idx: int) -> void:
			AudioManager.play_ui_click()
			_team0_difficulty = clampi(idx, 0, 2)
			_refresh_ui()
		)

	if opt_team0_style != null:
		opt_team0_style.clear()
		opt_team0_style.add_item("Balanced", int(GameConfig.AIPlaystyle.BALANCED))
		opt_team0_style.add_item("Swarm Rush", int(GameConfig.AIPlaystyle.SWARM_RUSH))
		opt_team0_style.add_item("Synthetics Tech", int(GameConfig.AIPlaystyle.SYNTHETICS_TECH))
		opt_team0_style.select(_team0_playstyle)
		opt_team0_style.item_selected.connect(func(idx: int) -> void:
			AudioManager.play_ui_click()
			_team0_playstyle = clampi(idx, 0, 2)
			_refresh_ui()
		)

	if opt_ai_difficulty != null:
		opt_ai_difficulty.clear()
		opt_ai_difficulty.add_item("Relaxed", int(GameConfig.AIDifficulty.RELAXED))
		opt_ai_difficulty.add_item("Standard", int(GameConfig.AIDifficulty.STANDARD))
		opt_ai_difficulty.add_item("Brutal", int(GameConfig.AIDifficulty.BRUTAL))
		opt_ai_difficulty.select(int(_ai_difficulty))
		opt_ai_difficulty.item_selected.connect(_on_ai_difficulty_selected)

	if opt_ai_playstyle != null:
		opt_ai_playstyle.clear()
		opt_ai_playstyle.add_item("Balanced", int(GameConfig.AIPlaystyle.BALANCED))
		opt_ai_playstyle.add_item("Swarm Rush", int(GameConfig.AIPlaystyle.SWARM_RUSH))
		opt_ai_playstyle.add_item("Synthetics Tech", int(GameConfig.AIPlaystyle.SYNTHETICS_TECH))
		opt_ai_playstyle.select(int(_ai_playstyle))
		opt_ai_playstyle.item_selected.connect(_on_ai_playstyle_selected)

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
		btn_audio_mute, map_option, btn_mode_pvai, btn_mode_aivai,
		btn_ai_standard, btn_ai_passive, opt_team0_diff, opt_team0_style,
		opt_ai_difficulty, opt_ai_playstyle, btn_res_standard, btn_res_fast,
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

	_refresh_audio_button()
	_refresh_ui()


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
			dossier_notice_label.text = "[CLASSIFIED PREVIEW] %s — %s (Locked; GENESIS_V2 remains selected for launch.)" % [dossier_name, briefing]
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
	if index == 1:
		_selected_map_path = GameConfig.MAP_SKIRMISH_02
	elif index == 2:
		_selected_map_path = GameConfig.MAP_SANDBOX_TESTBED
	else:
		_selected_map_path = GameConfig.MAP_SKIRMISH_01
	_refresh_ui()


func _on_ai_difficulty_selected(index: int) -> void:
	AudioManager.play_ui_click()
	_ai_difficulty = clampi(index, 0, 2)
	_refresh_ui()


func _on_ai_playstyle_selected(index: int) -> void:
	AudioManager.play_ui_click()
	_ai_playstyle = clampi(index, 0, 2)
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
	var is_spec: bool = (_match_mode == 1)
	if btn_mode_pvai != null:
		btn_mode_pvai.modulate = Color(0.42, 1.0, 0.88, 1.0) if not is_spec else Color(0.66, 0.74, 0.80, 0.78)
	if btn_mode_aivai != null:
		btn_mode_aivai.modulate = Color(1.0, 0.82, 0.32, 1.0) if is_spec else Color(0.66, 0.74, 0.80, 0.78)

	if ai_label != null:
		ai_label.visible = not is_spec
	if ai_row != null:
		ai_row.visible = not is_spec
	if team0_ai_grid != null:
		team0_ai_grid.visible = is_spec
	if diff_label != null:
		diff_label.text = "TEAM 2 AI DIFFICULTY" if is_spec else "AI DIFFICULTY"
		diff_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.36, 0.95) if is_spec else Color(0.62, 0.84, 0.92, 0.95))
	if style_label != null:
		style_label.text = "TEAM 2 AI PLAYSTYLE" if is_spec else "AI PLAYSTYLE"
		style_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.36, 0.95) if is_spec else Color(0.62, 0.84, 0.92, 0.95))

	if btn_ai_standard != null:
		btn_ai_standard.modulate = Color(0.42, 1.0, 0.88, 1.0) if _aggro_ai_enabled else Color(0.66, 0.74, 0.80, 0.78)
	if btn_ai_passive != null:
		btn_ai_passive.modulate = Color(1.0, 0.78, 0.34, 1.0) if not _aggro_ai_enabled else Color(0.66, 0.74, 0.80, 0.78)

	if opt_ai_difficulty != null:
		opt_ai_difficulty.disabled = (not is_spec and not _aggro_ai_enabled)
	if opt_ai_playstyle != null:
		opt_ai_playstyle.disabled = (not is_spec and not _aggro_ai_enabled)

	var is_fast: bool = (_resource_preset == GameConfig.PRESET_FAST_TECH)
	if btn_res_standard != null:
		btn_res_standard.modulate = Color(0.42, 1.0, 0.88, 1.0) if not is_fast else Color(0.66, 0.74, 0.80, 0.78)
	if btn_res_fast != null:
		btn_res_fast.modulate = Color(0.36, 0.92, 1.0, 1.0) if is_fast else Color(0.66, 0.74, 0.80, 0.78)

	if btn_launch != null:
		btn_launch.text = "LAUNCH AI SPECTATOR MATCH" if is_spec else "LAUNCH SKIRMISH"

	if summary_label != null:
		var map_name: String = GameConfig.get_map_label(_selected_map_path)
		var res_str: String = "1000 B / 500 S / 200 C" if is_fast else "200 B / 50 S / 0 C"
		var mut_parts: PackedStringArray = PackedStringArray()
		if _mutator_high_yield:
			mut_parts.append("2x Yield")
		if _mutator_no_fog:
			mut_parts.append("No Fog")
		if _mutator_fast_build:
			mut_parts.append("Fast Build")
		var mut_line: String = ("\nMUTATORS: %s" % " • ".join(mut_parts)) if not mut_parts.is_empty() else ""
		if is_spec:
			var t0_str: String = "%s (%s)" % [GameConfig.get_playstyle_label(_team0_playstyle), GameConfig.get_difficulty_label(_team0_difficulty)]
			var t1_str: String = "%s (%s)" % [GameConfig.get_playstyle_label(_ai_playstyle), GameConfig.get_difficulty_label(_ai_difficulty)]
			summary_label.text = "MODE: AI vs AI SPECTATOR\nMAP: %s\nMATCHUP: %s vs %s\nRESOURCES: %s%s" % [map_name, t0_str, t1_str, res_str, mut_line]
		else:
			var ai_str: String = "Passive / Sandbox (Aggro OFF)"
			if _aggro_ai_enabled:
				ai_str = "%s AI  •  %s" % [GameConfig.get_difficulty_label(_ai_difficulty), GameConfig.get_playstyle_label(_ai_playstyle)]
			summary_label.text = "FACTION: GENESIS_V2 (The Vat-Born)\nMAP: %s\nOPPONENT: %s\nRESOURCES: %s%s" % [map_name, ai_str, res_str, mut_line]


func _on_launch_pressed() -> void:
	AudioManager.play_sfx(&"build_complete", -3.0, 0.0)
	GameConfig.set_match_config(
		_selected_map_path,
		_aggro_ai_enabled,
		_resource_preset,
		&"genesis_v2",
		_ai_difficulty,
		_ai_playstyle,
		_match_mode,
		_team0_difficulty,
		_team0_playstyle,
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
