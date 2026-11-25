class_name SalvageCore
extends Node2D

const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")
const DEFAULT_LIFETIME: float = 28.0
const FLICKER_WINDOW: float = 6.0
const BASE_EXTRACTION_DURATION: float = 2.5
const ENGINEER_SPEED_MULT: float = 2.5 / 1.8 # 1.8s solo extraction for Systems Engineers

signal status_changed(core: Node)
signal claimed(core: Node, claiming_team: int)
signal expired(core: Node)

@export var display_name: String = "Heavy Salvage Core"
@export var salvage_silica: int = 40
@export var salvage_compute: int = 15
@export var lifetime: float = DEFAULT_LIFETIME
@export var interaction_radius: float = 22.0

var remaining_lifetime: float = DEFAULT_LIFETIME
var extraction_progress: float = 0.0
var is_claimed: bool = false
var is_selected: bool = false
var is_hovered: bool = false
var source_unit_name: String = ""

var _anim_time: float = 0.0
var _hud_tick_timer: float = 0.0


func _ready() -> void:
	z_index = 6
	remaining_lifetime = maxf(2.0, lifetime)
	add_to_group("salvage_cores")
	if SpatialGrid != null:
		SpatialGrid.register_salvage(self)
	queue_redraw()


func _exit_tree() -> void:
	if SpatialGrid != null:
		SpatialGrid.unregister_salvage(self)


func configure_payload(silica_amt: int, compute_amt: int, unit_label: String = "") -> void:
	salvage_silica = maxi(0, silica_amt)
	salvage_compute = maxi(0, compute_amt)
	source_unit_name = unit_label
	if not unit_label.is_empty():
		display_name = "%s Wreckage Core" % unit_label
	queue_redraw()


func _process(delta: float) -> void:
	if is_claimed:
		return
	_anim_time += delta
	remaining_lifetime = maxf(0.0, remaining_lifetime - delta)
	_hud_tick_timer += delta
	if _hud_tick_timer >= 0.25:
		_hud_tick_timer = 0.0
		if is_selected:
			status_changed.emit(self)
	if remaining_lifetime <= 0.0:
		_dissolve()
		return
	queue_redraw()


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	queue_redraw()


func set_hovered(hovered: bool) -> void:
	if is_hovered == hovered:
		return
	is_hovered = hovered
	queue_redraw()


func contains_point(world_pos: Vector2) -> bool:
	if is_claimed:
		return false
	var r: float = interaction_radius + 10.0
	return global_position.distance_squared_to(world_pos) <= r * r


func get_payload_label() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if salvage_silica > 0:
		parts.append("+%d S" % salvage_silica)
	if salvage_compute > 0:
		parts.append("+%d C" % salvage_compute)
	return " / ".join(parts) if not parts.is_empty() else "Salvage"


func advance_extraction(extractor: Node, delta: float) -> bool:
	if is_claimed or delta <= 0.0:
		return true
	var speed_mult: float = 1.0
	if extractor is Unit:
		var u: Unit = extractor as Unit
		if u.data != null and (u.data.can_staff_compute or u.get_unit_type_id() == &"engineer"):
			speed_mult = ENGINEER_SPEED_MULT
	extraction_progress = clampf(extraction_progress + (delta * speed_mult) / BASE_EXTRACTION_DURATION, 0.0, 1.0)
	if is_selected:
		status_changed.emit(self)
	queue_redraw()
	if extraction_progress >= 1.0:
		_complete_extraction(extractor)
		return true
	return false


func _complete_extraction(extractor: Node) -> void:
	if is_claimed:
		return
	is_claimed = true
	var claim_team: int = 0
	if extractor is Unit:
		claim_team = int((extractor as Unit).team)

	if is_inside_tree():
		var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
		if econ != null:
			if salvage_silica > 0:
				econ.add_resource(claim_team, EconomyManager.RESOURCE_SILICA, salvage_silica, false)
			if salvage_compute > 0:
				econ.add_resource(claim_team, EconomyManager.RESOURCE_COMPUTE, salvage_compute, false)

	if get_parent() != null:
		var fx: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
		fx.z_index = 62
		get_parent().add_child(fx)
		fx.call("setup_floating_text", global_position + Vector2(0.0, -14.0), get_payload_label(), Color(1.0, 0.84, 0.34, 1.0))

		var burst: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
		burst.z_index = 55
		get_parent().add_child(burst)
		burst.call("setup_death_burst", global_position, 22.0, Color(0.32, 0.96, 1.0, 1.0), false)

	var is_local: bool = TeamManager.is_team_controlled_by_local_human(claim_team) if TeamManager != null else (claim_team == 0)
	if AudioManager != null and (is_local or visible):
		AudioManager.play_sfx(&"salvage_claimed", -2.5, 0.04, global_position, not is_local)

	if is_inside_tree():
		var scars: Node = get_tree().get_first_node_in_group("battle_scars")
		if scars != null and scars.has_method("add_scar"):
			scars.call("add_scar", &"wreck_splatter", global_position, 20.0, Color(1.0, 0.80, 0.28, 1.0))
		var viewer_s: int = TeamManager.get_local_human_team() if TeamManager != null else 0
		var show_feed: bool = viewer_s < 0 or (TeamManager.are_allies(viewer_s, claim_team) if TeamManager != null else (claim_team == 0))
		if show_feed:
			var mm: Node = get_tree().get_first_node_in_group("match_manager")
			if mm != null and mm.has_method("emit_tactical_event"):
				var tag: String = TeamManager.get_team_short_label(claim_team, false) if (TeamManager != null and TeamManager.has_method("get_team_short_label")) else ("P%d" % (claim_team + 1))
				mm.call("emit_tactical_event", &"economy", "%s Salvage Claimed (%s)" % [tag, get_payload_label()], global_position, Color(0.28, 0.98, 0.78, 1.0))

	if SpatialGrid != null:
		SpatialGrid.unregister_salvage(self)
	if is_in_group("salvage_cores"):
		remove_from_group("salvage_cores")
	claimed.emit(self, claim_team)
	queue_free()


func _dissolve() -> void:
	if is_claimed:
		return
	is_claimed = true
	if is_inside_tree():
		var scars: Node = get_tree().get_first_node_in_group("battle_scars")
		if scars != null and scars.has_method("add_scar"):
			scars.call("add_scar", &"wreck_splatter", global_position, 18.0, Color(0.68, 0.76, 0.82, 1.0))
	if SpatialGrid != null:
		SpatialGrid.unregister_salvage(self)
	if is_in_group("salvage_cores"):
		remove_from_group("salvage_cores")
	expired.emit(self)
	queue_free()


func get_inspection_data() -> Dictionary:
	var stats: Array[Dictionary] = [
		{"label": "Silica", "value": "+%d Silica" % salvage_silica},
		{"label": "Compute", "value": "+%d Compute" % salvage_compute},
		{"label": "Decay", "value": "%.1fs Left" % remaining_lifetime},
		{"label": "Extract", "value": "Worker 2.5s / Eng 1.8s"},
	]
	return {
		"title": display_name,
		"subtitle": "NEUTRAL SALVAGE CORE  —  TIMED PICKUP",
		"affiliation": &"neutral",
		"accent_color": Color(1.0, 0.80, 0.30, 1.0),
		"ring_color": Color(0.32, 0.96, 1.0, 1.0),
		"show_hp_bar": false,
		"show_primary_bar": true,
		"primary_bar_label": ("Extracting: %d%%" % int(round(extraction_progress * 100.0))) if extraction_progress > 0.01 else ("Core Integrity: %.1fs Remaining" % remaining_lifetime),
		"primary_bar_value": (extraction_progress * 100.0) if extraction_progress > 0.01 else remaining_lifetime,
		"primary_bar_max": 100.0 if extraction_progress > 0.01 else maxf(1.0, lifetime),
		"primary_bar_color": Color(0.30, 0.96, 1.0, 1.0) if extraction_progress > 0.01 else Color(1.0, 0.78, 0.28, 1.0),
		"stats": stats,
		"is_commandable": false,
		"readonly_label": "RIGHT-CLICK WITH WORKER OR ENGINEER TO EXTRACT",
	}


func _draw() -> void:
	if is_claimed:
		return
	var life_ratio: float = clampf(remaining_lifetime / maxf(1.0, lifetime), 0.0, 1.0)
	var flicker_alpha: float = 1.0
	if remaining_lifetime < FLICKER_WINDOW:
		var urgent: float = 1.0 - (remaining_lifetime / FLICKER_WINDOW)
		var wave: float = 0.5 + 0.5 * sin(_anim_time * lerpf(10.0, 26.0, urgent))
		flicker_alpha = lerpf(0.28, 1.0, wave) * clampf(remaining_lifetime / 1.8, 0.2, 1.0)

	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 4.5)
	var amber: Color = Color(1.0, 0.78, 0.26, flicker_alpha)
	var cyan: Color = Color(0.28, 0.96, 1.0, flicker_alpha)
	var r: float = 13.5

	# Soft ground aura
	draw_circle(Vector2.ZERO, r + 9.0 + pulse * 2.5, Color(amber.r, amber.g, amber.b, 0.10 * flicker_alpha))
	draw_circle(Vector2.ZERO, r + 4.0, Color(cyan.r, cyan.g, cyan.b, 0.14 * flicker_alpha))

	if is_selected:
		draw_arc(Vector2.ZERO, r + 11.0, 0.0, TAU, 28, Color(0.32, 0.98, 1.0, 0.92), 1.8, true)
	if is_hovered:
		var zoom_x: float = 1.0
		if is_inside_tree():
			var cam: Camera2D = get_viewport().get_camera_2d()
			if cam != null:
				zoom_x = maxf(0.25, cam.zoom.x)
		var h_r: float = r + (14.5 if is_selected else 11.0)
		var h_col: Color = Color(0.961, 0.620, 0.043, 0.42 if is_selected else 0.68)
		if not is_selected:
			draw_circle(Vector2.ZERO, h_r, Color(h_col.r, h_col.g, h_col.b, 0.08))
		draw_arc(Vector2.ZERO, h_r, 0.0, TAU, 28, h_col, 1.4 / zoom_x, true)

	# Radial decay ring
	draw_arc(Vector2.ZERO, r + 6.5, -PI * 0.5, -PI * 0.5 + TAU * life_ratio, 28, Color(amber.r, amber.g, amber.b, 0.78 * flicker_alpha), 2.0, true)

	# Fractured hexagonal salvage core
	var hex: PackedVector2Array = PackedVector2Array()
	var rot: float = _anim_time * 0.45
	for i: int in range(6):
		var ang: float = rot + TAU * float(i) / 6.0
		hex.append(Vector2.RIGHT.rotated(ang) * r)
	draw_colored_polygon(hex, Color(0.14, 0.20, 0.27, 0.94 * flicker_alpha))
	var outline: PackedVector2Array = hex.duplicate()
	outline.append(hex[0])
	draw_polyline(outline, cyan, 2.0, true)

	# Inner split amber/cyan core prism
	var inner_hex: PackedVector2Array = PackedVector2Array()
	for i: int in range(6):
		var ang2: float = -rot * 1.4 + TAU * float(i) / 6.0
		inner_hex.append(Vector2.RIGHT.rotated(ang2) * (r * 0.54))
	draw_colored_polygon(inner_hex, Color(amber.r, amber.g, amber.b, (0.72 + pulse * 0.24) * flicker_alpha))
	draw_circle(Vector2.ZERO, 3.6 + pulse * 1.0, Color(0.95, 1.0, 1.0, 0.92 * flicker_alpha))

	# Extraction progress ring when workers are channeling
	if extraction_progress > 0.01:
		draw_arc(Vector2.ZERO, r + 10.0, -PI * 0.5, -PI * 0.5 + TAU * extraction_progress, 28, Color(0.28, 1.0, 0.76, 0.96), 2.8, true)

	# Compact payload hint when selected or actively being extracted
	if is_selected or extraction_progress > 0.01:
		var font: Font = ThemeDB.fallback_font
		var hint: String = get_payload_label()
		var sz: Vector2 = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
		var pill_pos: Vector2 = Vector2(-sz.x * 0.5 - 6.0, -r - 24.0)
		draw_rect(Rect2(pill_pos, Vector2(sz.x + 12.0, 15.0)), Color(0.03, 0.06, 0.10, 0.84), true)
		draw_rect(Rect2(pill_pos, Vector2(sz.x + 12.0, 15.0)), Color(amber.r, amber.g, amber.b, 0.78), false, 1.0)
		draw_string(font, pill_pos + Vector2(6.0, 11.5), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.92, 0.56, 0.96))
