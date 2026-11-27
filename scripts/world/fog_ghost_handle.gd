class_name FogGhostInspectHandle
extends Node2D

## Lightweight reusable inspection/hover proxy for frozen Fog-of-War building ghosts.
## Lets SelectionController and SelectionHUD inspect last-seen enemy structures without
## exposing or referencing live hostile Building nodes hidden in Fog of War.

signal ghost_invalidated(ghost_id: int)

var ghost_id: int = -1
var is_selected: bool = false
var is_hovered: bool = false

var _fog_system: FogOfWarSystem = null
var _overlay: Node2D = null


func _ready() -> void:
	add_to_group("fog_ghost_handles")


func bind_ghost(id: int, fog_system: FogOfWarSystem, overlay: Node2D) -> void:
	ghost_id = id
	_fog_system = fog_system
	_overlay = overlay
	var snap: Dictionary = get_ghost_snapshot()
	if not snap.is_empty():
		global_position = snap.get("pos", Vector2.ZERO) as Vector2
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_redraw()


func is_ghost_active() -> bool:
	if ghost_id < 0 or _fog_system == null or not is_instance_valid(_fog_system):
		return false
	return not _fog_system.get_building_ghost_by_id(ghost_id).is_empty()


func get_ghost_snapshot() -> Dictionary:
	if ghost_id < 0 or _fog_system == null or not is_instance_valid(_fog_system):
		return {}
	return _fog_system.get_building_ghost_by_id(ghost_id)


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	if not is_selected:
		ghost_id = -1
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_redraw()


func set_hovered(hovered: bool) -> void:
	if is_hovered == hovered:
		return
	is_hovered = hovered
	if not is_hovered and not is_selected:
		ghost_id = -1
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_redraw()


func invalidate() -> void:
	if ghost_id < 0:
		return
	var old_id: int = ghost_id
	ghost_id = -1
	is_selected = false
	is_hovered = false
	ghost_invalidated.emit(old_id)
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_redraw()


func get_inspection_data() -> Dictionary:
	var snap: Dictionary = get_ghost_snapshot()
	if snap.is_empty():
		return {
			"title": "Unknown Structure",
			"subtitle": "LAST SEEN IN FOG",
			"affiliation": &"enemy",
			"accent_color": Color(0.70, 0.50, 0.52, 1.0),
			"ring_color": Color(0.70, 0.50, 0.52, 1.0),
			"show_hp_bar": false,
			"show_primary_bar": false,
			"stats": [],
			"is_commandable": false,
			"readonly_label": "LAST KNOWN INTEL — OUT OF VISION",
		}
	var info: Variant = snap.get("inspection_snapshot", {})
	if info is Dictionary and not (info as Dictionary).is_empty():
		return (info as Dictionary).duplicate(true)
	var time_str: String = String(snap.get("scouted_time_str", "00:00"))
	var disp_name: String = String(snap.get("display_name", "Hostile Structure"))
	return {
		"title": disp_name,
		"subtitle": "LAST SEEN IN FOG (%s)" % time_str,
		"affiliation": &"enemy",
		"accent_color": Color(0.84, 0.44, 0.40, 1.0),
		"ring_color": Color(0.84, 0.44, 0.40, 1.0),
		"show_hp_bar": true,
		"hp": float(snap.get("current_hp", 1.0)),
		"max_hp": float(snap.get("max_hp", 1.0)),
		"shield": float(snap.get("current_shield", 0.0)),
		"max_shield": float(snap.get("max_shield", 0.0)),
		"show_primary_bar": false,
		"stats": [],
		"is_commandable": false,
		"readonly_label": "LAST KNOWN INTEL — OUT OF VISION",
	}
