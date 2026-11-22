class_name ResourceHUD
extends CanvasLayer

@export var economy_manager_path: NodePath
@export var tracked_team: Unit.Team = Unit.Team.PLAYER

@onready var biomass_value_label: Label = %BiomassValueLabel
@onready var silica_value_label: Label = %SilicaValueLabel
@onready var compute_value_label: Label = %ComputeValueLabel
@onready var bandwidth_value_label: Label = %BandwidthValueLabel

var _economy_manager: EconomyManager = null


func _ready() -> void:
	_connect_economy_manager()
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


func _refresh_from_economy() -> void:
	if _economy_manager == null:
		return
	_on_resources_changed(tracked_team, _economy_manager.get_resources(tracked_team))
	_on_bandwidth_changed(
		tracked_team,
		_economy_manager.get_bandwidth_used(tracked_team),
		_economy_manager.get_bandwidth_cap(tracked_team)
	)


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
