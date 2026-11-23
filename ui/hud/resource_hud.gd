class_name ResourceHUD
extends CanvasLayer

@export var economy_manager_path: NodePath
@export var tracked_team: Unit.Team = Unit.Team.PLAYER

@onready var biomass_value_label: Label = %BiomassValueLabel
@onready var silica_value_label: Label = %SilicaValueLabel
@onready var compute_value_label: Label = %ComputeValueLabel
@onready var bandwidth_value_label: Label = %BandwidthValueLabel
@onready var btn_audio_mute: Button = %BtnAudioMute
@onready var btn_idle_workers: Button = %BtnIdleWorkers
@onready var aggro_paused_badge: Label = %AggroPausedBadge
@onready var uplink_bonus_label: Label = %UplinkBonusLabel
@onready var zone_status_label: Label = %ZoneStatusLabel
@onready var resource_alert_label: Label = %ResourceAlertLabel

var _economy_manager: EconomyManager = null
var _encroaching_zone: EncroachingZone = null
var _match_manager: MatchManager = null
var _selection_controller: SelectionController = null
var _flash_timers: Dictionary = {}
var _alert_timer: float = 0.0


func _ready() -> void:
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
	if btn_idle_workers != null:
		btn_idle_workers.add_to_group("blocks_edge_pan")
		btn_idle_workers.pressed.connect(_on_idle_workers_pressed)
	_connect_economy_manager()
	_connect_encroaching_zone()
	_connect_match_manager()
	call_deferred("_connect_camera_toasts")
	call_deferred("_connect_selection_controller")
	_refresh_from_economy()
	_refresh_aggro_badge()
	_refresh_audio_button()
	_on_idle_workers_updated(0)


func _connect_camera_toasts() -> void:
	if not is_inside_tree():
		return
	var cam: RTSCamera = get_tree().get_first_node_in_group("rts_camera") as RTSCamera
	if cam != null and not cam.camera_toast.is_connected(_on_hud_toast):
		cam.camera_toast.connect(_on_hud_toast)


func _on_keybind_changed(_action_name: StringName) -> void:
	var count: int = _selection_controller.idle_worker_count if _selection_controller != null else 0
	_on_idle_workers_updated(count)
	_refresh_aggro_badge()


func _on_hud_toast(message: String) -> void:
	_alert_timer = 1.85
	if resource_alert_label != null:
		resource_alert_label.text = message.to_upper()
		resource_alert_label.visible = true
		resource_alert_label.modulate = Color(0.38, 0.98, 0.90, 1.0)


func _process(delta: float) -> void:
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
			resource_alert_label.text = "BANDWIDTH LIMIT REACHED — BUILD SYNAPSE PYLON"
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
	_on_idle_workers_updated(_selection_controller.idle_worker_count)


func _on_idle_workers_pressed() -> void:
	if _selection_controller == null:
		_connect_selection_controller()
	if _selection_controller != null:
		_selection_controller.select_next_idle_worker(true)


func _on_idle_workers_updated(count: int) -> void:
	if btn_idle_workers == null:
		return
	var hk: String = SettingsManager.get_action_key_label(&"cmd_select_idle_worker") if SettingsManager != null else "`"
	btn_idle_workers.text = "Idle Workers: %d [%s]" % [count, hk]
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


func _on_tactical_alert_recorded(_world_pos: Vector2, message: String) -> void:
	var hk: String = SettingsManager.get_action_key_label(&"jump_last_alert") if SettingsManager != null else "Space"
	_alert_timer = 2.2
	if resource_alert_label != null:
		resource_alert_label.text = "%s  [%s]" % [message.to_upper(), hk]
		resource_alert_label.visible = true
		resource_alert_label.modulate = Color(1.0, 0.82, 0.34, 1.0)


func _on_aggro_ai_toggled(_enabled: bool) -> void:
	_refresh_aggro_badge()


func _refresh_aggro_badge() -> void:
	if aggro_paused_badge == null:
		return
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


func _connect_encroaching_zone() -> void:
	if not is_inside_tree():
		return
	_encroaching_zone = get_tree().get_first_node_in_group("encroaching_zone") as EncroachingZone
	if _encroaching_zone == null:
		if zone_status_label != null:
			zone_status_label.visible = false
		return
	if not _encroaching_zone.zone_updated.is_connected(_on_zone_updated):
		_encroaching_zone.zone_updated.connect(_on_zone_updated)


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
	if bandwidth_value_label != null:
		bandwidth_value_label.text = "%d / %d" % [used, cap]
		if cap > 0 and used >= cap:
			bandwidth_value_label.modulate = Color(1.0, 0.48, 0.34, 1.0)
		else:
			bandwidth_value_label.modulate = Color(0.74, 0.96, 1.0, 1.0)


func _on_production_bonus_changed(team: int, multiplier: float) -> void:
	if team != int(tracked_team) or uplink_bonus_label == null:
		return
	var pct: int = int(round((multiplier - 1.0) * 100.0))
	uplink_bonus_label.visible = pct > 0
	uplink_bonus_label.text = "UPLINK: +%d%% SPEED" % pct


func _on_zone_updated(_phase_index: int, state_label: String, time_remaining: float, _current_radius: float) -> void:
	if zone_status_label == null:
		return
	zone_status_label.visible = true
	if state_label == "ZONE OFF":
		zone_status_label.text = "ZONE: OFF"
		zone_status_label.modulate = Color(0.56, 0.64, 0.70, 0.78)
		return
	var mins: int = int(time_remaining) / 60
	var secs: int = int(time_remaining) % 60
	if state_label.begins_with("SHRINK"):
		zone_status_label.text = "%s (%02d:%02d)" % [state_label, mins, secs]
		zone_status_label.modulate = Color(1.0, 0.38, 0.44, 1.0)
	elif state_label.begins_with("ZONE FINAL"):
		zone_status_label.text = "ZONE LOCKED"
		zone_status_label.modulate = Color(1.0, 0.32, 0.36, 1.0)
	else:
		zone_status_label.text = "%s: %02d:%02d" % [state_label, mins, secs]
		zone_status_label.modulate = Color(0.84, 0.72, 0.78, 0.92)
