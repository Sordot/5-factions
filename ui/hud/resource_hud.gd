class_name ResourceHUD
extends CanvasLayer

const TECH_TREE_SCENE_PATH: String = "res://scenes/ui/tech_tree_overlay.tscn"
const CONTROLS_REF_SCENE_PATH: String = "res://scenes/ui/controls_reference_overlay.tscn"

@export var economy_manager_path: NodePath
@export var tracked_team: Unit.Team = Unit.Team.PLAYER

@onready var top_left_spectator_anchor: Control = %TopLeftSpectatorAnchor
@onready var spectator_panel: PanelContainer = %SpectatorPanel
@onready var spec_team0_label: Label = %SpecTeam0Label
@onready var spec_team1_label: Label = %SpecTeam1Label
@onready var btn_spectator_fog: Button = %BtnSpectatorFog
@onready var biomass_value_label: Label = %BiomassValueLabel
@onready var biomass_rate_label: Label = %BiomassRateLabel
@onready var silica_value_label: Label = %SilicaValueLabel
@onready var silica_rate_label: Label = %SilicaRateLabel
@onready var compute_value_label: Label = %ComputeValueLabel
@onready var compute_rate_label: Label = %ComputeRateLabel
@onready var bandwidth_value_label: Label = %BandwidthValueLabel
@onready var match_timer_label: Label = %MatchTimerLabel
@onready var btn_audio_mute: Button = %BtnAudioMute
@onready var btn_idle_workers: Button = %BtnIdleWorkers
@onready var btn_idle_production: Button = %BtnIdleProduction
@onready var btn_select_army: Button = %BtnSelectArmy
@onready var btn_tech_tree: Button = %BtnTechTree
@onready var btn_controls_help: Button = %BtnControlsHelp
@onready var btn_speed_05: Button = %BtnSpeed05
@onready var btn_speed_10: Button = %BtnSpeed10
@onready var btn_speed_15: Button = %BtnSpeed15
@onready var btn_speed_20: Button = %BtnSpeed20
@onready var aggro_paused_badge: Label = %AggroPausedBadge
@onready var uplink_bonus_label: Label = %UplinkBonusLabel
@onready var resource_alert_label: Label = %ResourceAlertLabel

var _economy_manager: EconomyManager = null
var _match_manager: MatchManager = null
var _selection_controller: SelectionController = null
var _tech_tree_instance: CanvasLayer = null
var _controls_ref_instance: CanvasLayer = null
var _flash_timers: Dictionary = {}
var _alert_timer: float = 0.0
var _hud_poll_timer: float = 0.0
var _bandwidth_capped: bool = false
var _bandwidth_near_cap: bool = false
var _bw_near_cap_armed: bool = true
var _bw_near_cap_cooldown: float = 0.0
var _bw_pulse_time: float = 0.0


func _ready() -> void:
	if TeamManager != null and TeamManager.get_local_human_team() >= 0:
		tracked_team = TeamManager.get_local_human_team() as Unit.Team
	var res_panel: Control = get_node_or_null("RootControl/TopRightAnchor/TopRightVBox/ResourceBarPanel") as Control
	if res_panel != null:
		res_panel.add_to_group("blocks_edge_pan")
	if btn_audio_mute != null:
		btn_audio_mute.add_to_group("blocks_edge_pan")
		btn_audio_mute.pressed.connect(func() -> void:
			if AudioManager != null:
				AudioManager.toggle_mute()
			_refresh_audio_button()
		)
	if AudioManager != null and not AudioManager.mute_changed.is_connected(_on_audio_mute_changed):
		AudioManager.mute_changed.connect(_on_audio_mute_changed)
	if SettingsManager != null and not SettingsManager.keybind_changed.is_connected(_on_keybind_changed):
		SettingsManager.keybind_changed.connect(_on_keybind_changed)
	if SettingsManager != null and not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)
	if btn_idle_workers != null:
		btn_idle_workers.add_to_group("blocks_edge_pan")
		btn_idle_workers.pressed.connect(_on_idle_workers_pressed)
	if btn_idle_production != null:
		btn_idle_production.add_to_group("blocks_edge_pan")
		btn_idle_production.pressed.connect(_on_idle_production_pressed)
		btn_idle_production.tooltip_text = "Click: Cycle Idle Production • Double-Click: Center • Shift+Click: Select All"
	if btn_select_army != null:
		btn_select_army.add_to_group("blocks_edge_pan")
		btn_select_army.pressed.connect(_on_select_army_pressed)
	if btn_tech_tree != null:
		btn_tech_tree.add_to_group("blocks_edge_pan")
		btn_tech_tree.pressed.connect(toggle_tech_tree)
	if btn_controls_help != null:
		btn_controls_help.add_to_group("blocks_edge_pan")
		btn_controls_help.pressed.connect(toggle_controls_help)
		_refresh_controls_help_button_label()
	if spectator_panel != null:
		spectator_panel.add_to_group("blocks_edge_pan")
	if btn_spectator_fog != null:
		btn_spectator_fog.add_to_group("blocks_edge_pan")
		btn_spectator_fog.pressed.connect(_on_spectator_fog_pressed)

	if TeamManager != null and TeamManager.has_signal("teams_reconfigured") and not TeamManager.teams_reconfigured.is_connected(_apply_faction_hud_theme):
		TeamManager.teams_reconfigured.connect(_apply_faction_hud_theme)
	_apply_faction_hud_theme()

	_wire_speed_button(btn_speed_05, 0.5)
	_wire_speed_button(btn_speed_10, 1.0)
	_wire_speed_button(btn_speed_15, 1.5)
	_wire_speed_button(btn_speed_20, 2.0)

	_connect_economy_manager()
	_connect_match_manager()
	call_deferred("_connect_camera_toasts")
	call_deferred("_connect_selection_controller")
	_apply_spectator_layout()
	_refresh_from_economy()
	_refresh_aggro_badge()
	_refresh_audio_button()
	_refresh_speed_buttons()
	_on_idle_workers_updated(0)
	_on_idle_production_updated(0)
	_on_army_count_updated(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	var settings_node: Node = get_tree().get_first_node_in_group("settings_menu") if is_inside_tree() else null
	if settings_node != null and is_instance_valid(settings_node) and settings_node.has_method("is_capturing_key"):
		if bool(settings_node.call("is_capturing_key")):
			return
	if event.is_action_pressed("ui_toggle_tech_tree"):
		toggle_tech_tree()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_toggle_controls_help"):
		toggle_controls_help()
		get_viewport().set_input_as_handled()


func _wire_speed_button(btn: Button, speed_val: float) -> void:
	if btn == null:
		return
	btn.add_to_group("blocks_edge_pan")
	btn.pressed.connect(func() -> void:
		if AudioManager != null:
			AudioManager.play_ui_click()
		if _match_manager == null:
			_connect_match_manager()
		if _match_manager != null and _match_manager.has_method("set_game_speed"):
			_match_manager.call("set_game_speed", speed_val)
		_refresh_speed_buttons()
	)


func _refresh_speed_buttons() -> void:
	var spd: float = float(_match_manager.get("current_game_speed")) if _match_manager != null else Engine.time_scale
	var pairs: Array = [
		{"btn": btn_speed_05, "val": 0.5},
		{"btn": btn_speed_10, "val": 1.0},
		{"btn": btn_speed_15, "val": 1.5},
		{"btn": btn_speed_20, "val": 2.0},
	]
	for item: Dictionary in pairs:
		var b: Button = item["btn"] as Button
		if b == null:
			continue
		var active: bool = absf(spd - float(item["val"])) < 0.05
		b.modulate = Color(0.32, 1.0, 0.90, 1.0) if active else Color(0.68, 0.78, 0.84, 0.78)


func toggle_tech_tree() -> void:
	if _tech_tree_instance != null and is_instance_valid(_tech_tree_instance):
		if _tech_tree_instance.has_method("close_overlay"):
			_tech_tree_instance.call("close_overlay")
		else:
			_tech_tree_instance.queue_free()
		_tech_tree_instance = null
		return
	if _controls_ref_instance != null and is_instance_valid(_controls_ref_instance):
		if _controls_ref_instance.has_method("close_overlay"):
			_controls_ref_instance.call("close_overlay")
		else:
			_controls_ref_instance.queue_free()
		_controls_ref_instance = null
	if AudioManager != null:
		AudioManager.play_ui_click()
	var tech_scene: PackedScene = load(TECH_TREE_SCENE_PATH) as PackedScene
	if tech_scene == null:
		return
	_tech_tree_instance = tech_scene.instantiate() as CanvasLayer
	if _tech_tree_instance != null:
		if _tech_tree_instance.has_signal("closed"):
			_tech_tree_instance.connect("closed", func() -> void:
				_tech_tree_instance = null
			)
		get_tree().root.add_child(_tech_tree_instance)


func toggle_controls_help() -> void:
	if _controls_ref_instance != null and is_instance_valid(_controls_ref_instance):
		if _controls_ref_instance.has_method("close_overlay"):
			_controls_ref_instance.call("close_overlay")
		else:
			_controls_ref_instance.queue_free()
		_controls_ref_instance = null
		return
	if _tech_tree_instance != null and is_instance_valid(_tech_tree_instance):
		if _tech_tree_instance.has_method("close_overlay"):
			_tech_tree_instance.call("close_overlay")
		else:
			_tech_tree_instance.queue_free()
		_tech_tree_instance = null
	if AudioManager != null:
		AudioManager.play_ui_click()
	var ref_scene: PackedScene = load(CONTROLS_REF_SCENE_PATH) as PackedScene
	if ref_scene == null:
		return
	_controls_ref_instance = ref_scene.instantiate() as CanvasLayer
	if _controls_ref_instance != null:
		if _controls_ref_instance.has_signal("closed"):
			_controls_ref_instance.connect("closed", func() -> void:
				_controls_ref_instance = null
			)
		get_tree().root.add_child(_controls_ref_instance)


func _apply_spectator_layout() -> void:
	var is_spec: bool = TeamManager != null and TeamManager.is_spectator_mode()
	var res_panel: Control = get_node_or_null("RootControl/TopRightAnchor/TopRightVBox/ResourceBarPanel") as Control
	if res_panel != null:
		res_panel.visible = not is_spec
	if top_left_spectator_anchor != null:
		top_left_spectator_anchor.visible = is_spec
	if btn_idle_workers != null:
		btn_idle_workers.visible = not is_spec
	if btn_idle_production != null and is_spec:
		btn_idle_production.visible = false
	if btn_select_army != null:
		btn_select_army.visible = not is_spec
	_refresh_spectator_fog_button()


func _on_spectator_fog_pressed() -> void:
	if not is_inside_tree():
		return
	if AudioManager != null:
		AudioManager.play_ui_click()
	var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	if fog != null:
		fog.set_fog_enabled(not fog.fog_enabled)
	_refresh_spectator_fog_button()


func _refresh_spectator_fog_button() -> void:
	if btn_spectator_fog == null or not is_inside_tree():
		return
	var fog: FogOfWarSystem = get_tree().get_first_node_in_group("fog_of_war") as FogOfWarSystem
	var is_on: bool = fog != null and fog.fog_enabled
	btn_spectator_fog.text = "Fog: ON" if is_on else "Fog: OFF"
	btn_spectator_fog.modulate = Color(1.0, 0.78, 0.34, 1.0) if is_on else Color(0.32, 1.0, 0.88, 1.0)


func _connect_camera_toasts() -> void:
	if not is_inside_tree():
		return
	var cam: RTSCamera = get_tree().get_first_node_in_group("rts_camera") as RTSCamera
	if cam != null and not cam.camera_toast.is_connected(_on_hud_toast):
		cam.camera_toast.connect(_on_hud_toast)


func _on_settings_changed(category: StringName) -> void:
	if category == &"controls" or category == &"all":
		_on_keybind_changed(&"")


func _on_keybind_changed(_action_name: StringName) -> void:
	var count: int = _selection_controller.idle_worker_count if _selection_controller != null else 0
	var prod_c: int = _selection_controller.idle_production_count if _selection_controller != null else 0
	var army_c: int = _selection_controller.army_unit_count if _selection_controller != null else 0
	_on_idle_workers_updated(count)
	_on_idle_production_updated(prod_c)
	_on_army_count_updated(army_c)
	_refresh_tech_button_label()
	_refresh_controls_help_button_label()
	_refresh_aggro_badge()


func _apply_faction_hud_theme() -> void:
	if TeamManager != null and TeamManager.get_local_human_team() >= 0:
		tracked_team = TeamManager.get_local_human_team() as Unit.Team
	var fid: StringName = FactionHudTheme.resolve_local_faction_id()
	var pal: Dictionary = FactionHudTheme.get_palette(fid)
	var accent: Color = pal["accent"] as Color
	var is_brutal: bool = (pal["style"] == &"brutalist")

	var res_panel: PanelContainer = get_node_or_null("RootControl/TopRightAnchor/TopRightVBox/ResourceBarPanel") as PanelContainer
	if res_panel != null:
		res_panel.add_theme_stylebox_override("panel", FactionHudTheme.make_panel_style(fid, true))
		FactionHudTheme.attach_frame_overlay(res_panel, fid, &"top_bar")
		var hbox: Node = res_panel.get_node_or_null("HBox")
		if hbox != null:
			for child: Node in hbox.get_children():
				if child is VSeparator:
					(child as VSeparator).modulate = Color(accent.r, accent.g, accent.b, 0.85) if is_brutal else Color.WHITE

	if spectator_panel != null:
		spectator_panel.add_theme_stylebox_override("panel", FactionHudTheme.make_panel_style(&"spectator", true))
		FactionHudTheme.attach_frame_overlay(spectator_panel, &"spectator", &"top_bar")

	if btn_tech_tree != null:
		FactionHudTheme.style_utility_button(btn_tech_tree, fid)
		btn_tech_tree.modulate = accent.lightened(0.20)
	if btn_controls_help != null:
		FactionHudTheme.style_utility_button(btn_controls_help, fid)
		btn_controls_help.modulate = (pal["primary"] as Color) if is_brutal else Color(0.76, 0.96, 1.0, 1.0)
	if btn_audio_mute != null:
		FactionHudTheme.style_utility_button(btn_audio_mute, fid)
	if btn_idle_workers != null:
		FactionHudTheme.style_utility_button(btn_idle_workers, fid)
	if btn_idle_production != null:
		FactionHudTheme.style_utility_button(btn_idle_production, fid)
	if btn_select_army != null:
		FactionHudTheme.style_utility_button(btn_select_army, fid)


func _apply_faction_hud_accent() -> void:
	_apply_faction_hud_theme()


func _refresh_tech_button_label() -> void:
	if btn_tech_tree == null:
		return
	var hk: String = SettingsManager.get_action_short_label(&"ui_toggle_tech_tree") if SettingsManager != null else "U"
	btn_tech_tree.text = ("Tech [%s]" % hk) if not hk.is_empty() else "Tech"


func _refresh_controls_help_button_label() -> void:
	if btn_controls_help == null:
		return
	var hk: String = SettingsManager.get_action_short_label(&"ui_toggle_controls_help") if SettingsManager != null else "?"
	btn_controls_help.text = hk if not hk.is_empty() else "?"
	btn_controls_help.tooltip_text = ("Controls Quick-Reference (%s)" % hk) if not hk.is_empty() else "Controls Quick-Reference"


func _on_hud_toast(message: String) -> void:
	if SettingsManager != null and not SettingsManager.show_alert_toasts:
		return
	_alert_timer = 1.85
	if resource_alert_label != null:
		resource_alert_label.text = message.to_upper()
		resource_alert_label.visible = true
		resource_alert_label.modulate = Color(0.38, 0.98, 0.90, 1.0)


func _process(delta: float) -> void:
	_hud_poll_timer += delta
	if _hud_poll_timer >= 0.30:
		_hud_poll_timer = 0.0
		_refresh_income_rates_and_timer()

	if _bw_near_cap_cooldown > 0.0:
		_bw_near_cap_cooldown = maxf(0.0, _bw_near_cap_cooldown - delta)

	if (_bandwidth_capped or _bandwidth_near_cap) and bandwidth_value_label != null and not _flash_timers.has(&"bandwidth"):
		_bw_pulse_time += delta
		if _bandwidth_capped:
			var pulse_c: float = 0.5 + 0.5 * sin(_bw_pulse_time * 5.2)
			bandwidth_value_label.modulate = Color(1.0, 0.72, 0.28, 1.0).lerp(Color(1.0, 0.30, 0.34, 1.0), pulse_c)
		else:
			var pulse_n: float = 0.5 + 0.5 * sin(_bw_pulse_time * 3.4)
			bandwidth_value_label.modulate = Color(0.98, 0.86, 0.52, 1.0).lerp(Color(0.961, 0.620, 0.043, 1.0), pulse_n)

	if _alert_timer > 0.0:
		_alert_timer = maxf(0.0, _alert_timer - delta)
		if resource_alert_label != null:
			resource_alert_label.visible = _alert_timer > 0.0
			resource_alert_label.modulate.a = clampf(_alert_timer / 0.45, 0.0, 1.0)
	if not _flash_timers.is_empty():
		var done_keys: Array[StringName] = []
		for key: Variant in _flash_timers.keys():
			var k: StringName = key as StringName
			var rem: float = maxf(0.0, float(_flash_timers[k]) - delta)
			_flash_timers[k] = rem
			var lbl: Label = _get_resource_label(k)
			if lbl != null:
				if rem <= 0.0:
					lbl.modulate = Color.WHITE
					if k == &"bandwidth" and _economy_manager != null:
						_on_bandwidth_changed(tracked_team, _economy_manager.get_bandwidth_used(tracked_team), _economy_manager.get_bandwidth_cap(tracked_team))
					done_keys.append(k)
				else:
					var pulse: float = 0.5 + 0.5 * sin(rem * 28.0)
					lbl.modulate = Color.WHITE.lerp(Color(1.0, 0.34, 0.24, 1.0), 0.55 + pulse * 0.45)
		for dk: StringName in done_keys:
			_flash_timers.erase(dk)


func _refresh_income_rates_and_timer() -> void:
	if _match_manager == null and is_inside_tree():
		_connect_match_manager()
	if match_timer_label != null and _match_manager != null and _match_manager.has_method("get_match_elapsed_formatted"):
		match_timer_label.text = String(_match_manager.call("get_match_elapsed_formatted"))

	if _economy_manager == null:
		return
	var b_rate: int = _economy_manager.get_income_rate_per_minute(tracked_team, EconomyManager.RESOURCE_BIOMASS)
	var s_rate: int = _economy_manager.get_income_rate_per_minute(tracked_team, EconomyManager.RESOURCE_SILICA)
	var c_rate: int = _economy_manager.get_income_rate_per_minute(tracked_team, EconomyManager.RESOURCE_COMPUTE)
	if biomass_rate_label != null:
		biomass_rate_label.text = ("(+%d/m)" % b_rate) if b_rate > 0 else ""
	if silica_rate_label != null:
		silica_rate_label.text = ("(+%d/m)" % s_rate) if s_rate > 0 else ""
	if compute_rate_label != null:
		compute_rate_label.text = ("(+%d/m)" % c_rate) if c_rate > 0 else ""

	if TeamManager != null and TeamManager.is_spectator_mode():
		_refresh_spectator_telemetry()
		_refresh_spectator_fog_button()


func _refresh_spectator_telemetry() -> void:
	if _economy_manager == null:
		return
	if spec_team0_label != null:
		var r0: Dictionary = _economy_manager.get_resources(0)
		spec_team0_label.text = "AI-01: %dB %dS %dC | %d/%d BW" % [
			int(r0.get(EconomyManager.RESOURCE_BIOMASS, 0)),
			int(r0.get(EconomyManager.RESOURCE_SILICA, 0)),
			int(r0.get(EconomyManager.RESOURCE_COMPUTE, 0)),
			_economy_manager.get_bandwidth_used(0),
			_economy_manager.get_bandwidth_cap(0),
		]
	if spec_team1_label != null:
		var r1: Dictionary = _economy_manager.get_resources(1)
		spec_team1_label.text = "AI-02: %dB %dS %dC | %d/%d BW" % [
			int(r1.get(EconomyManager.RESOURCE_BIOMASS, 0)),
			int(r1.get(EconomyManager.RESOURCE_SILICA, 0)),
			int(r1.get(EconomyManager.RESOURCE_COMPUTE, 0)),
			_economy_manager.get_bandwidth_used(1),
			_economy_manager.get_bandwidth_cap(1),
		]


func _on_audio_mute_changed(_muted: bool) -> void:
	_refresh_audio_button()


func _refresh_audio_button() -> void:
	if btn_audio_mute == null:
		return
	var muted: bool = AudioManager != null and AudioManager.is_muted
	btn_audio_mute.text = "SFX: MUTE" if muted else "SFX: ON"
	btn_audio_mute.modulate = Color(1.0, 0.52, 0.42, 0.92) if muted else Color(0.46, 0.98, 0.90, 1.0)


func _get_resource_label(key: StringName) -> Label:
	match key:
		EconomyManager.RESOURCE_BIOMASS:
			return biomass_value_label
		EconomyManager.RESOURCE_SILICA:
			return silica_value_label
		EconomyManager.RESOURCE_COMPUTE:
			return compute_value_label
		&"bandwidth":
			return bandwidth_value_label
	return null


func _on_resource_insufficient(team: int, missing_key: StringName) -> void:
	if team != int(tracked_team):
		return
	_flash_timers[missing_key] = 0.75
	_alert_timer = 1.35
	if resource_alert_label != null:
		if missing_key == &"bandwidth":
			var supply_name: String = "SUPPLY STRUCTURE"
			if TeamManager != null and TeamManager.has_method("get_team_faction_data"):
				var fac: FactionData = TeamManager.get_team_faction_data(team)
				if fac != null:
					var sup_b: BuildingData = fac.get_ai_building_for_role(&"supply")
					if sup_b != null and not sup_b.display_name.is_empty():
						supply_name = sup_b.display_name.to_upper()
			resource_alert_label.text = "BANDWIDTH LIMIT REACHED — BUILD %s" % supply_name
		else:
			resource_alert_label.text = "INSUFFICIENT %s" % String(missing_key).to_upper()
		resource_alert_label.visible = true
		resource_alert_label.modulate = Color(1.0, 0.44, 0.34, 1.0)


func _connect_selection_controller() -> void:
	if not is_inside_tree():
		return
	_selection_controller = get_tree().get_first_node_in_group("selection_controller") as SelectionController
	if _selection_controller == null:
		return
	if not _selection_controller.idle_workers_updated.is_connected(_on_idle_workers_updated):
		_selection_controller.idle_workers_updated.connect(_on_idle_workers_updated)
	if _selection_controller.has_signal("idle_production_updated") and not _selection_controller.idle_production_updated.is_connected(_on_idle_production_updated):
		_selection_controller.idle_production_updated.connect(_on_idle_production_updated)
	if not _selection_controller.army_count_updated.is_connected(_on_army_count_updated):
		_selection_controller.army_count_updated.connect(_on_army_count_updated)
	if _selection_controller.has_signal("hud_toast_requested") and not _selection_controller.hud_toast_requested.is_connected(_on_hud_toast):
		_selection_controller.hud_toast_requested.connect(_on_hud_toast)
	_on_idle_workers_updated(_selection_controller.idle_worker_count)
	_on_idle_production_updated(_selection_controller.idle_production_count)
	_on_army_count_updated(_selection_controller.army_unit_count)
	_refresh_tech_button_label()


func _on_select_army_pressed() -> void:
	if _selection_controller == null:
		_connect_selection_controller()
	if _selection_controller != null:
		_selection_controller.select_all_army(true)


func _on_army_count_updated(count: int) -> void:
	if btn_select_army == null:
		return
	var hk: String = SettingsManager.get_action_short_label(&"cmd_select_all_army") if SettingsManager != null else "F9"
	btn_select_army.text = ("Army: %d [%s]" % [count, hk]) if not hk.is_empty() else ("Army: %d" % count)
	btn_select_army.disabled = count <= 0
	btn_select_army.modulate = Color(0.32, 0.98, 0.92, 1.0) if count > 0 else Color(0.56, 0.64, 0.72, 0.72)


func _on_idle_workers_pressed() -> void:
	if _selection_controller == null:
		_connect_selection_controller()
	if _selection_controller != null:
		_selection_controller.select_next_idle_worker(true)


func _on_idle_production_pressed() -> void:
	if _selection_controller == null:
		_connect_selection_controller()
	if _selection_controller != null:
		_selection_controller.select_next_idle_production(true, Input.is_key_pressed(KEY_SHIFT))


func _on_idle_production_updated(count: int) -> void:
	if btn_idle_production == null:
		return
	var is_spec: bool = TeamManager != null and TeamManager.is_spectator_mode()
	btn_idle_production.visible = (count > 0 and not is_spec)
	if count <= 0:
		return
	var hk: String = SettingsManager.get_action_short_label(&"cmd_select_idle_production") if SettingsManager != null else ";"
	btn_idle_production.text = ("IDLE PROD: %d [%s]" % [count, hk]) if not hk.is_empty() else ("IDLE PROD: %d" % count)
	btn_idle_production.modulate = Color(0.98, 0.78, 0.30, 1.0)


func _on_idle_workers_updated(count: int) -> void:
	if btn_idle_workers == null:
		return
	var hk: String = SettingsManager.get_action_short_label(&"cmd_select_idle_worker") if SettingsManager != null else "`"
	btn_idle_workers.text = ("Idle Workers: %d [%s]" % [count, hk]) if not hk.is_empty() else ("Idle Workers: %d" % count)
	btn_idle_workers.disabled = count <= 0
	if count > 0:
		btn_idle_workers.modulate = Color(1.0, 0.84, 0.28, 1.0)
	else:
		btn_idle_workers.modulate = Color(0.56, 0.64, 0.72, 0.72)


func _connect_match_manager() -> void:
	if not is_inside_tree():
		return
	_match_manager = get_tree().get_first_node_in_group("match_manager") as MatchManager
	if _match_manager != null:
		if not _match_manager.aggro_ai_toggled.is_connected(_on_aggro_ai_toggled):
			_match_manager.aggro_ai_toggled.connect(_on_aggro_ai_toggled)
		if not _match_manager.tactical_alert_recorded.is_connected(_on_tactical_alert_recorded):
			_match_manager.tactical_alert_recorded.connect(_on_tactical_alert_recorded)
		if _match_manager.has_signal("game_speed_changed") and not _match_manager.is_connected("game_speed_changed", _on_game_speed_changed):
			_match_manager.connect("game_speed_changed", _on_game_speed_changed)


func _on_game_speed_changed(_speed_scale: float) -> void:
	_refresh_speed_buttons()


func _on_tactical_alert_recorded(_world_pos: Vector2, message: String) -> void:
	if SettingsManager != null and not SettingsManager.show_alert_toasts:
		return
	var hk: String = SettingsManager.get_action_short_label(&"jump_last_alert") if SettingsManager != null else "SPC"
	_alert_timer = 2.2
	if resource_alert_label != null:
		resource_alert_label.text = ("%s  [%s]" % [message.to_upper(), hk]) if not hk.is_empty() else message.to_upper()
		resource_alert_label.visible = true
		resource_alert_label.modulate = Color(1.0, 0.82, 0.34, 1.0)


func _on_aggro_ai_toggled(_enabled: bool) -> void:
	_refresh_aggro_badge()


func _refresh_aggro_badge() -> void:
	if aggro_paused_badge == null:
		return
	var hk: String = SettingsManager.get_action_short_label(&"debug_toggle_aggro_ai") if SettingsManager != null else "F10"
	aggro_paused_badge.text = ("AGGRO AI: PAUSED (%s)" % hk) if not hk.is_empty() else "AGGRO AI: PAUSED"
	aggro_paused_badge.visible = not MatchManager.is_aggro_ai_enabled(get_tree() if is_inside_tree() else null)


func _connect_economy_manager() -> void:
	if not economy_manager_path.is_empty():
		_economy_manager = get_node_or_null(economy_manager_path) as EconomyManager
	if _economy_manager == null and is_inside_tree():
		_economy_manager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if _economy_manager == null:
		return
	if not _economy_manager.resources_changed.is_connected(_on_resources_changed):
		_economy_manager.resources_changed.connect(_on_resources_changed)
	if not _economy_manager.bandwidth_changed.is_connected(_on_bandwidth_changed):
		_economy_manager.bandwidth_changed.connect(_on_bandwidth_changed)
	if not _economy_manager.production_bonus_changed.is_connected(_on_production_bonus_changed):
		_economy_manager.production_bonus_changed.connect(_on_production_bonus_changed)
	if not _economy_manager.resource_insufficient.is_connected(_on_resource_insufficient):
		_economy_manager.resource_insufficient.connect(_on_resource_insufficient)


func _refresh_from_economy() -> void:
	if _economy_manager == null:
		return
	_on_resources_changed(tracked_team, _economy_manager.get_resources(tracked_team))
	_on_bandwidth_changed(
		tracked_team,
		_economy_manager.get_bandwidth_used(tracked_team),
		_economy_manager.get_bandwidth_cap(tracked_team)
	)
	_on_production_bonus_changed(tracked_team, _economy_manager.get_production_speed_multiplier(tracked_team))


func _on_resources_changed(team: int, resources: Dictionary) -> void:
	if team != int(tracked_team):
		return
	if biomass_value_label != null:
		biomass_value_label.text = str(int(resources.get(EconomyManager.RESOURCE_BIOMASS, 0)))
	if silica_value_label != null:
		silica_value_label.text = str(int(resources.get(EconomyManager.RESOURCE_SILICA, 0)))
	if compute_value_label != null:
		compute_value_label.text = str(int(resources.get(EconomyManager.RESOURCE_COMPUTE, 0)))


func _on_bandwidth_changed(team: int, used: int, cap: int) -> void:
	if team != int(tracked_team):
		return
	var is_capped: bool = (cap > 0 and used >= cap)
	var is_near_cap: bool = (cap > 0 and used >= cap - 2 and used < cap)
	_bandwidth_capped = is_capped
	_bandwidth_near_cap = is_near_cap

	if is_near_cap:
		if _bw_near_cap_armed and _bw_near_cap_cooldown <= 0.0:
			if AudioManager != null and AudioManager.has_method("play_bandwidth_near_cap_warning"):
				AudioManager.play_bandwidth_near_cap_warning()
			_bw_near_cap_cooldown = 20.0
		_bw_near_cap_armed = false
	elif is_capped:
		_bw_near_cap_armed = false
	else:
		_bw_near_cap_armed = true

	if bandwidth_value_label != null:
		bandwidth_value_label.text = "%d / %d" % [used, cap]
		if _bandwidth_capped:
			bandwidth_value_label.modulate = Color(1.0, 0.34, 0.34, 1.0)
		elif _bandwidth_near_cap:
			bandwidth_value_label.modulate = Color(0.961, 0.620, 0.043, 1.0)
		else:
			_bw_pulse_time = 0.0
			bandwidth_value_label.modulate = Color(0.74, 0.96, 1.0, 1.0)


func _on_production_bonus_changed(team: int, multiplier: float) -> void:
	if team != int(tracked_team) or uplink_bonus_label == null:
		return
	var pct: int = int(round((multiplier - 1.0) * 100.0))
	uplink_bonus_label.visible = pct > 0
	uplink_bonus_label.text = "UPLINK: +%d%% SPEED" % pct
