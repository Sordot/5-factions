class_name ResourceHUD
extends CanvasLayer

@export var economy_manager_path: NodePath
@export var tracked_team: Unit.Team = Unit.Team.PLAYER

@onready var biomass_value_label: Label = %BiomassValueLabel
@onready var silica_value_label: Label = %SilicaValueLabel
@onready var compute_value_label: Label = %ComputeValueLabel
@onready var bandwidth_value_label: Label = %BandwidthValueLabel
@onready var btn_idle_workers: Button = %BtnIdleWorkers
@onready var aggro_paused_badge: Label = %AggroPausedBadge
@onready var uplink_bonus_label: Label = %UplinkBonusLabel
@onready var zone_status_label: Label = %ZoneStatusLabel

var _economy_manager: EconomyManager = null
var _encroaching_zone: EncroachingZone = null
var _match_manager: MatchManager = null
var _selection_controller: SelectionController = null


func _ready() -> void:
	var res_panel: Control = get_node_or_null("RootControl/TopRightAnchor/TopRightVBox/ResourceBarPanel") as Control
	if res_panel != null:
		res_panel.add_to_group("blocks_edge_pan")
	if btn_idle_workers != null:
		btn_idle_workers.add_to_group("blocks_edge_pan")
		btn_idle_workers.pressed.connect(_on_idle_workers_pressed)
	_connect_economy_manager()
	_connect_encroaching_zone()
	_connect_match_manager()
	call_deferred("_connect_selection_controller")
	_refresh_from_economy()
	_refresh_aggro_badge()
	_on_idle_workers_updated(0)


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
	btn_idle_workers.text = "Idle Workers: %d [F1]" % count
	btn_idle_workers.disabled = count <= 0
	if count > 0:
		btn_idle_workers.modulate = Color(1.0, 0.84, 0.28, 1.0)
	else:
		btn_idle_workers.modulate = Color(0.56, 0.64, 0.72, 0.72)


func _connect_match_manager() -> void:
	if not is_inside_tree():
		return
	_match_manager = get_tree().get_first_node_in_group("match_manager") as MatchManager
	if _match_manager != null and not _match_manager.aggro_ai_toggled.is_connected(_on_aggro_ai_toggled):
		_match_manager.aggro_ai_toggled.connect(_on_aggro_ai_toggled)


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
