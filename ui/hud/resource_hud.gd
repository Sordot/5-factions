class_name ResourceHUD
extends CanvasLayer

@export var economy_manager_path: NodePath
@export var tracked_team: Unit.Team = Unit.Team.PLAYER

@onready var biomass_value_label: Label = %BiomassValueLabel
@onready var silica_value_label: Label = %SilicaValueLabel
@onready var compute_value_label: Label = %ComputeValueLabel
@onready var bandwidth_value_label: Label = %BandwidthValueLabel
@onready var uplink_bonus_label: Label = %UplinkBonusLabel
@onready var zone_status_label: Label = %ZoneStatusLabel

var _economy_manager: EconomyManager = null
var _encroaching_zone: EncroachingZone = null


func _ready() -> void:
	_connect_economy_manager()
	_connect_encroaching_zone()
	_refresh_from_economy()


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
	uplink_bonus_label.text = "UPLINK: +%d%% PROD" % pct


func _on_zone_updated(_phase_index: int, state_label: String, time_remaining: float, _current_radius: float) -> void:
	if zone_status_label == null:
		return
	zone_status_label.visible = true
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
