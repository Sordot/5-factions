class_name EntityVisuals
extends Node2D

## Slim procedural visual coordinator for units and structures.
## Dispatches faction-specific silhouettes and upgrade telltales to pluggable
## FactionVisualRenderer modules (O(1) cached lookup) while owning shared engine
## overlays: hover rings, marquee highlights, blueprint construction fill,
## completion flashes, hub saturation pills, and low-HP damage states.

enum Mode {
	UNIT,
	BUILDING,
}

static var _renderers: Array[FactionVisualRenderer] = []
static var _renderers_initialized: bool = false

var mode: Mode = Mode.UNIT
var entity_type_id: StringName = &""
var team: int = 0
var _owner_unit: Unit = null
var _owner_building: Building = null
var _anim_time: float = 0.0
var _economy_manager: EconomyManager = null
var _researched_upgrades: Dictionary = {}
var _upgrade_cache_team: int = -999
var _cached_renderer: FactionVisualRenderer = null
var _cached_renderer_type_id: StringName = &""
var _cached_renderer_mode: Mode = Mode.UNIT
var _upgrade_callable: Callable = Callable()
var _draw_ctx: Dictionary = {}


static func _ensure_renderers() -> void:
	if _renderers_initialized:
		return
	_renderers_initialized = true
	_renderers = [
		GenesisVisualRenderer.new(),
		MonolithVisualRenderer.new(),
	]


static func register_renderer(renderer: FactionVisualRenderer) -> void:
	_ensure_renderers()
	if renderer != null and not _renderers.has(renderer):
		_renderers.append(renderer)


static func _resolve_renderer(type_id: StringName, is_building: bool) -> FactionVisualRenderer:
	_ensure_renderers()
	for r: FactionVisualRenderer in _renderers:
		if is_building:
			if r.handles_building(type_id):
				return r
		else:
			if r.handles_unit(type_id):
				return r
	return null


func _ready() -> void:
	_upgrade_callable = Callable(self, "_has_team_upgrade")
	call_deferred("_bind_economy_manager")


func _exit_tree() -> void:
	if _economy_manager != null and is_instance_valid(_economy_manager):
		if _economy_manager.tech_changed.is_connected(_on_economy_tech_changed):
			_economy_manager.tech_changed.disconnect(_on_economy_tech_changed)
		if _economy_manager.upgrade_completed.is_connected(_on_economy_upgrade_completed):
			_economy_manager.upgrade_completed.disconnect(_on_economy_upgrade_completed)
	_economy_manager = null


func bind_unit(unit: Unit) -> void:
	mode = Mode.UNIT
	_owner_unit = unit
	entity_type_id = unit.get_unit_type_id()
	team = int(unit.team)
	_refresh_cached_renderer()
	_sync_upgrade_cache()
	queue_redraw()


func bind_building(building: Building) -> void:
	mode = Mode.BUILDING
	_owner_building = building
	entity_type_id = building.building_type_id
	team = int(building.team)
	_refresh_cached_renderer()
	_sync_upgrade_cache()
	queue_redraw()


func _refresh_cached_renderer() -> void:
	if _cached_renderer_type_id == entity_type_id and _cached_renderer_mode == mode and _cached_renderer != null:
		return
	_cached_renderer_type_id = entity_type_id
	_cached_renderer_mode = mode
	_cached_renderer = _resolve_renderer(entity_type_id, mode == Mode.BUILDING)


func _bind_economy_manager() -> void:
	if _economy_manager != null and is_instance_valid(_economy_manager):
		return
	if not is_inside_tree():
		return
	_economy_manager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	if _economy_manager != null:
		if not _economy_manager.tech_changed.is_connected(_on_economy_tech_changed):
			_economy_manager.tech_changed.connect(_on_economy_tech_changed)
		if not _economy_manager.upgrade_completed.is_connected(_on_economy_upgrade_completed):
			_economy_manager.upgrade_completed.connect(_on_economy_upgrade_completed)
		_sync_upgrade_cache()
		queue_redraw()


func _on_economy_tech_changed(changed_team: int) -> void:
	if changed_team == team:
		_sync_upgrade_cache()
		queue_redraw()


func _on_economy_upgrade_completed(changed_team: int, _upgrade_id: StringName) -> void:
	if changed_team == team:
		_sync_upgrade_cache()
		queue_redraw()


func _sync_upgrade_cache() -> void:
	if _economy_manager == null or not is_instance_valid(_economy_manager):
		if is_inside_tree():
			_economy_manager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
			if _economy_manager != null:
				if not _economy_manager.tech_changed.is_connected(_on_economy_tech_changed):
					_economy_manager.tech_changed.connect(_on_economy_tech_changed)
				if not _economy_manager.upgrade_completed.is_connected(_on_economy_upgrade_completed):
					_economy_manager.upgrade_completed.connect(_on_economy_upgrade_completed)
	_upgrade_cache_team = team
	_researched_upgrades.clear()
	if _economy_manager == null or not is_instance_valid(_economy_manager) or _economy_manager.upgrade_manager == null:
		return
	for upg_id: StringName in _economy_manager.upgrade_manager.get_researched_upgrades(team):
		_researched_upgrades[upg_id] = true


func _has_team_upgrade(upgrade_id: StringName) -> bool:
	if _upgrade_cache_team != team or (_economy_manager == null and is_inside_tree()):
		_sync_upgrade_cache()
	return _researched_upgrades.has(upgrade_id)


func _process(delta: float) -> void:
	_anim_time += delta
	if mode == Mode.UNIT:
		if _owner_unit == null or not is_instance_valid(_owner_unit) or _owner_unit.is_dead:
			return
		var next_id: StringName = _owner_unit.get_unit_type_id()
		if next_id != entity_type_id:
			entity_type_id = next_id
			_refresh_cached_renderer()
		team = int(_owner_unit.team)
		_draw_ctx["upgrades"] = _upgrade_callable
		var renderer_wants_anim: bool = _cached_renderer != null and _cached_renderer.needs_unit_animation(entity_type_id, _draw_ctx)
		if (
			_owner_unit.is_hovered
			or _owner_unit.spawn_anim_timer > 0.0
			or renderer_wants_anim
			or _owner_unit.has_status_effect(&"adrenal_surge")
			or (_owner_unit.current_hp / maxf(1.0, _owner_unit.get_max_hp())) <= 0.40
		):
			queue_redraw()
	else:
		if _owner_building == null or not is_instance_valid(_owner_building) or _owner_building.is_destroyed:
			return
		var next_bid: StringName = _owner_building.building_type_id
		if next_bid != entity_type_id:
			entity_type_id = next_bid
			_refresh_cached_renderer()
		team = int(_owner_building.team)
		queue_redraw()


func _get_palette() -> Dictionary:
	if TeamManager != null:
		return TeamManager.get_team_palette(team)
	var is_enemy: bool = (team == int(Unit.Team.ENEMY))
	if is_enemy:
		return {
			"shell": Color(0.84, 0.78, 0.80, 0.96),
			"shell_hi": Color(0.95, 0.88, 0.88, 0.98),
			"deck": Color(0.20, 0.12, 0.14, 0.98),
			"trim": Color(0.54, 0.30, 0.32, 1.0),
			"core": Color(1.0, 0.32, 0.24, 1.0),
			"core_alt": Color(1.0, 0.66, 0.24, 1.0),
			"outline": Color(1.0, 0.42, 0.32, 0.92),
			"wire": Color(1.0, 0.42, 0.32, 0.88),
		}
	return {
		"shell": Color(0.90, 0.95, 0.98, 0.96),
		"shell_hi": Color(0.97, 0.99, 1.0, 0.98),
		"deck": Color(0.14, 0.22, 0.29, 0.98),
		"trim": Color(0.50, 0.64, 0.74, 1.0),
		"core": Color(0.20, 0.96, 0.86, 1.0),
		"core_alt": Color(0.28, 0.98, 0.62, 1.0),
		"outline": Color(0.30, 0.96, 0.92, 0.92),
		"wire": Color(0.28, 0.96, 1.0, 0.88),
	}


func _fill_draw_ctx(p: Dictionary) -> Dictionary:
	var team_col: Color = TeamManager.get_team_color(team) if TeamManager != null else (p["core"] as Color)
	_draw_ctx["palette"] = p
	_draw_ctx["team"] = team
	_draw_ctx["team_color"] = team_col
	_draw_ctx["anim_time"] = _anim_time
	_draw_ctx["pulse"] = 0.5 + 0.5 * sin(_anim_time * (4.5 if mode == Mode.UNIT else 3.4))
	_draw_ctx["active_pulse"] = 0.5 + 0.5 * sin(_anim_time * TAU * 2.2)
	_draw_ctx["upgrades"] = _upgrade_callable
	return _draw_ctx


func _draw() -> void:
	var p: Dictionary = _get_palette()
	var ctx: Dictionary = _fill_draw_ctx(p)
	_refresh_cached_renderer()
	_draw_hover_ring()
	_draw_marquee_preview_ring()
	if mode == Mode.UNIT:
		if _cached_renderer != null:
			_cached_renderer.draw_unit(self, entity_type_id, _owner_unit, ctx)
			if _owner_unit != null and is_instance_valid(_owner_unit) and not _owner_unit.is_dead:
				_cached_renderer.draw_unit_upgrade_telltales(self, entity_type_id, _owner_unit, ctx)
		else:
			_draw_fallback_unit(p)
		_draw_unit_damage_overlay()
		_draw_unit_spawn_flash(p)
	else:
		_draw_building_silhouette(p, ctx)
		if _cached_renderer != null and _owner_building != null and is_instance_valid(_owner_building) and not _owner_building.is_destroyed and _owner_building.is_constructed:
			_cached_renderer.draw_building_upgrade_telltales(self, entity_type_id, _owner_building, ctx)
		_draw_building_damage_overlay()


func _draw_fallback_unit(p: Dictionary) -> void:
	var r: float = _owner_unit.data.collision_radius if (_owner_unit != null and _owner_unit.data != null) else 15.0
	var fallback_poly: PackedVector2Array = PackedVector2Array([
		Vector2(r, 0), Vector2(-r * 0.5, -r * 0.8), Vector2(-r * 0.8, 0), Vector2(-r * 0.5, r * 0.8),
	])
	FactionVisualRenderer.poly_outlined(self, fallback_poly, p["shell"], p["outline"], 1.6)
	draw_circle(Vector2.ZERO, r * 0.35, p["core"])


func _get_zoom_invariant_width(base_px: float) -> float:
	if is_inside_tree():
		var cam: Camera2D = get_viewport().get_camera_2d()
		if cam != null:
			return base_px / maxf(0.25, cam.zoom.x)
	return base_px


func _is_entity_hostile(entity_team: int) -> bool:
	var viewer: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	if viewer < 0:
		return false
	if TeamManager != null:
		return TeamManager.are_enemies(viewer, entity_team)
	return entity_team != int(Unit.Team.PLAYER)


func _draw_hover_ring() -> void:
	var pulse_a: float = 0.86 + 0.14 * sin(_anim_time * 5.2)
	var line_w: float = _get_zoom_invariant_width(1.4)
	if mode == Mode.UNIT:
		if _owner_unit == null or not is_instance_valid(_owner_unit) or _owner_unit.is_dead:
			return
		if not _owner_unit.is_hovered or _owner_unit.is_marquee_highlighted:
			return
		var is_hostile: bool = _is_entity_hostile(int(_owner_unit.team))
		var base_col: Color = Color(1.0, 0.302, 0.427, 0.65) if is_hostile else Color(0.220, 0.741, 0.973, 0.55)
		var r: float = _owner_unit.get_selection_radius() + (4.5 if _owner_unit.is_selected else 1.5)
		var alpha: float = (base_col.a * 0.58 if _owner_unit.is_selected else base_col.a) * pulse_a
		if not _owner_unit.is_selected:
			draw_circle(Vector2.ZERO, r, Color(base_col.r, base_col.g, base_col.b, 0.08 * pulse_a))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(base_col.r, base_col.g, base_col.b, alpha), line_w, true)
	else:
		if _owner_building == null or not is_instance_valid(_owner_building) or _owner_building.is_destroyed:
			return
		if not _owner_building.is_hovered or _owner_building.is_marquee_highlighted:
			return
		var is_hostile_b: bool = _is_entity_hostile(int(_owner_building.team))
		var base_col_b: Color = Color(1.0, 0.302, 0.427, 0.65) if is_hostile_b else Color(0.220, 0.741, 0.973, 0.55)
		var r_b: float = maxf(_owner_building.selection_radius, _owner_building.footprint_radius + 6.0) + (5.0 if _owner_building.is_selected else 0.0)
		var alpha_b: float = (base_col_b.a * 0.58 if _owner_building.is_selected else base_col_b.a) * pulse_a
		if not _owner_building.is_selected:
			draw_circle(Vector2.ZERO, r_b, Color(base_col_b.r, base_col_b.g, base_col_b.b, 0.07 * pulse_a))
		draw_arc(Vector2.ZERO, r_b, 0.0, TAU, 36, Color(base_col_b.r, base_col_b.g, base_col_b.b, alpha_b), line_w, true)


func _draw_unit_spawn_flash(p: Dictionary) -> void:
	if _owner_unit == null or not is_instance_valid(_owner_unit) or _owner_unit.spawn_anim_timer <= 0.0:
		return
	var frac: float = clampf(_owner_unit.spawn_anim_timer / Unit.SPAWN_ANIM_DURATION, 0.0, 1.0)
	var base_r: float = _owner_unit.data.collision_radius if _owner_unit.data != null else 15.0
	var rim_r: float = base_r * lerpf(1.38, 0.92, frac)
	var flash_col: Color = p["core"] if team != 0 else Color(0.24, 0.98, 0.88, 1.0)
	draw_circle(Vector2.ZERO, base_r * 1.05, Color(flash_col.r, flash_col.g, flash_col.b, frac * 0.34))
	draw_arc(Vector2.ZERO, rim_r, 0.0, TAU, 24, Color(0.86, 1.0, 0.98, frac * 0.85), 2.4 * frac + 0.8, true)


func _draw_marquee_preview_ring() -> void:
	var smart_mode: bool = SettingsManager != null and SettingsManager.smart_box_select_enabled
	var ring_col: Color = Color(0.961, 0.620, 0.043, 0.92) if smart_mode else Color(0.220, 0.741, 0.973, 0.92)
	if mode == Mode.UNIT:
		if _owner_unit == null or not is_instance_valid(_owner_unit) or _owner_unit.is_dead:
			return
		if not _owner_unit.is_marquee_highlighted or _owner_unit.is_selected:
			return
		var r: float = _owner_unit.get_selection_radius() + 2.0
		draw_circle(Vector2.ZERO, r, Color(ring_col.r, ring_col.g, ring_col.b, 0.14))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, ring_col, 1.8, true)
	else:
		if _owner_building == null or not is_instance_valid(_owner_building) or _owner_building.is_destroyed:
			return
		if not _owner_building.is_marquee_highlighted or _owner_building.is_selected:
			return
		var r_b: float = maxf(_owner_building.selection_radius, _owner_building.footprint_radius + 6.0)
		draw_circle(Vector2.ZERO, r_b, Color(ring_col.r, ring_col.g, ring_col.b, 0.11))
		draw_arc(Vector2.ZERO, r_b, 0.0, TAU, 36, ring_col, 2.0, true)


func _get_building_outer_poly(type_id: StringName, radius: float) -> PackedVector2Array:
	if _cached_renderer != null:
		return _cached_renderer.get_building_outer_poly(type_id, radius)
	var r: float = maxf(22.0, radius)
	var c: float = r * 0.42
	var e: float = r * 0.96
	return PackedVector2Array([
		Vector2(e, -c), Vector2(e, c), Vector2(c, e), Vector2(-c, e),
		Vector2(-e, c), Vector2(-e, -c), Vector2(-c, -e), Vector2(c, -e),
	])


func _draw_building_silhouette(p: Dictionary, ctx: Dictionary) -> void:
	if _owner_building == null:
		return
	var is_built: bool = _owner_building.is_constructed
	var progress: float = clampf(_owner_building.construction_progress, 0.0, 1.0)
	var hull_poly: PackedVector2Array = _get_building_outer_poly(entity_type_id, _owner_building.footprint_radius)

	if not is_built:
		_draw_building_blueprint(hull_poly, progress, p)
		return

	if _cached_renderer != null:
		_cached_renderer.draw_building(self, entity_type_id, _owner_building, hull_poly, ctx)
	else:
		FactionVisualRenderer.poly_outlined(self, hull_poly, p["shell"], p["outline"], 2.2)
		draw_colored_polygon(FactionVisualRenderer.scale_poly(hull_poly, 0.65), p["deck"])
		draw_circle(Vector2.ZERO, _owner_building.footprint_radius * 0.32, p["core"])

	if _owner_building.has_turret:
		var handled: bool = _cached_renderer != null and _cached_renderer.draw_building_turret(self, _owner_building, ctx)
		if not handled:
			_draw_default_building_turret_overlay(p)

	if _owner_building.completion_flash_timer > 0.0:
		var cf: float = clampf(_owner_building.completion_flash_timer / Building.COMPLETION_FLASH_DURATION, 0.0, 1.0)
		var fcol: Color = _cached_renderer.get_completion_flash_color(entity_type_id) if _cached_renderer != null else Color(0.90, 1.0, 0.98, 1.0)
		FactionVisualRenderer.draw_closed_outline(
			self,
			FactionVisualRenderer.scale_poly(hull_poly, 1.0 + (1.0 - cf) * 0.10),
			Color(fcol.r, fcol.g, fcol.b, cf * 0.95),
			3.0
		)

	_draw_hub_saturation_badge()


func _draw_building_blueprint(hull_poly: PackedVector2Array, progress: float, p: Dictionary) -> void:
	var wire: Color = p["wire"]
	var shell: Color = p["shell"]
	var deck: Color = p["deck"]
	var core: Color = p["core"]

	var min_y: float = 9999.0
	var max_y: float = -9999.0
	var min_x: float = 9999.0
	var max_x: float = -9999.0
	for pt: Vector2 in hull_poly:
		min_y = minf(min_y, pt.y)
		max_y = maxf(max_y, pt.y)
		min_x = minf(min_x, pt.x)
		max_x = maxf(max_x, pt.x)

	draw_colored_polygon(hull_poly, Color(wire.r, wire.g, wire.b, 0.11))
	var step: float = 12.0
	var gx: float = min_x + step
	while gx < max_x:
		draw_line(Vector2(gx, min_y + 4.0), Vector2(gx, max_y - 4.0), Color(wire.r, wire.g, wire.b, 0.16), 1.0)
		gx += step
	var gy: float = min_y + step
	while gy < max_y:
		draw_line(Vector2(min_x + 4.0, gy), Vector2(max_x - 4.0, gy), Color(wire.r, wire.g, wire.b, 0.16), 1.0)
		gy += step

	var fill_top_y: float = lerpf(max_y, min_y, progress)
	if progress > 0.01:
		var clip_rect: PackedVector2Array = PackedVector2Array([
			Vector2(min_x - 4.0, fill_top_y),
			Vector2(max_x + 4.0, fill_top_y),
			Vector2(max_x + 4.0, max_y + 4.0),
			Vector2(min_x - 4.0, max_y + 4.0),
		])
		var clipped_list: Array[PackedVector2Array] = Geometry2D.intersect_polygons(hull_poly, clip_rect)
		for part: PackedVector2Array in clipped_list:
			if part.size() >= 3:
				draw_colored_polygon(part, Color(shell.r, shell.g, shell.b, 0.68))
		var inner_poly: PackedVector2Array = FactionVisualRenderer.scale_poly(hull_poly, 0.72)
		var inner_clips: Array[PackedVector2Array] = Geometry2D.intersect_polygons(inner_poly, clip_rect)
		for part_i: PackedVector2Array in inner_clips:
			if part_i.size() >= 3:
				draw_colored_polygon(part_i, Color(deck.r, deck.g, deck.b, 0.72))
		var scan_w: float = (max_x - min_x) * 0.48
		draw_line(Vector2(-scan_w, fill_top_y), Vector2(scan_w, fill_top_y), Color(core.r, core.g, core.b, 0.96), 2.4, true)

	FactionVisualRenderer.draw_closed_outline(self, hull_poly, wire, 2.0)
	FactionVisualRenderer.draw_closed_outline(self, FactionVisualRenderer.scale_poly(hull_poly, 0.72), Color(wire.r, wire.g, wire.b, 0.45), 1.2)
	var corners: PackedVector2Array = PackedVector2Array([
		Vector2(min_x, min_y), Vector2(max_x, min_y), Vector2(max_x, max_y), Vector2(min_x, max_y),
	])
	for c: Vector2 in corners:
		var toward: Vector2 = -c.normalized() * 7.0
		draw_line(c, c + Vector2(toward.x, 0.0), wire, 2.0)
		draw_line(c, c + Vector2(0.0, toward.y), wire, 2.0)


func _draw_default_building_turret_overlay(p: Dictionary) -> void:
	if _owner_building == null or not _owner_building.is_constructed:
		return
	var shell_hi: Color = p["shell_hi"]
	var deck: Color = p["deck"]
	var trim: Color = p["trim"]
	var core: Color = p["core"]
	var core_alt: Color = p["core_alt"]
	var ang: float = _owner_building.get_turret_angle()
	var recoil: float = _owner_building.get_turret_recoil()
	var dir: Vector2 = Vector2.RIGHT.rotated(ang)
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var style: StringName = _owner_building.turret_tracer_style
	var accent: Color = Color(1.0, 0.82, 0.32, 1.0) if (style == &"rail" and team == 0) else core
	if style == &"mortar" and team == 0:
		accent = core_alt

	var base_pts: PackedVector2Array = PackedVector2Array([
		dir * 12.0 + perp * -6.5,
		dir * 12.0 + perp * 6.5,
		dir * -8.0 + perp * 9.5,
		dir * -12.0 + perp * 4.5,
		dir * -12.0 + perp * -4.5,
		dir * -8.0 + perp * -9.5,
	])
	FactionVisualRenderer.poly_outlined(self, base_pts, shell_hi, accent, 1.6)

	var b_start: Vector2 = dir * (6.0 - recoil)
	var b_end: Vector2 = dir * (26.0 - recoil)
	if style == &"heavy":
		draw_line(b_start + perp * -4.0, b_end + perp * -4.0, deck, 4.2, true)
		draw_line(b_start + perp * 4.0, b_end + perp * 4.0, deck, 4.2, true)
		draw_line(b_start + perp * -4.0, b_end + perp * -4.0, accent, 1.6, true)
		draw_line(b_start + perp * 4.0, b_end + perp * 4.0, accent, 1.6, true)
	elif style == &"mortar":
		draw_line(b_start, dir * (21.0 - recoil), trim, 9.0, true)
		draw_circle(dir * (20.0 - recoil), 4.2, deck)
		draw_circle(dir * (20.0 - recoil), 2.4, accent)
	else:
		draw_line(b_start + perp * -3.2, b_end + perp * -2.6, trim, 2.8, true)
		draw_line(b_start + perp * 3.2, b_end + perp * 2.6, trim, 2.8, true)
		draw_line(dir * (4.0 - recoil), dir * (27.5 - recoil), accent, 2.2, true)

	draw_circle(Vector2.ZERO, 6.2, deck)
	draw_circle(dir * 1.5, 3.2, accent)


func _draw_hub_saturation_badge() -> void:
	if _owner_building == null or not is_instance_valid(_owner_building) or not _owner_building.is_constructed or _owner_building.is_destroyed:
		return
	var is_silica_dropoff: bool = entity_type_id == &"silica_condenser" or (not _owner_building.is_command_hub() and _owner_building.is_resource_dropoff and _owner_building.accepts_resource(&"silica"))
	var is_hub: bool = _owner_building.is_command_hub() or is_silica_dropoff
	if not is_hub:
		return
	var is_local: bool = TeamManager.is_team_controlled_by_local_human(int(_owner_building.team)) if TeamManager != null else (_owner_building.team == Unit.Team.PLAYER)
	if not is_local:
		return

	var should_show: bool = _owner_building.is_selected
	if not should_show and _owner_building.is_inside_tree():
		var mouse_world: Vector2 = _owner_building.get_global_mouse_position()
		var hover_r: float = _owner_building.selection_radius + 8.0
		if _owner_building.global_position.distance_squared_to(mouse_world) <= hover_r * hover_r:
			should_show = true
	if not should_show and _owner_building.is_inside_tree():
		var want_res: StringName = &"silica" if is_silica_dropoff else &"biomass"
		var sel: Node = _owner_building.get_tree().get_first_node_in_group("selection_controller")
		if sel != null:
			var sel_units: Variant = sel.get("selected_units")
			if sel_units is Array:
				for item: Variant in (sel_units as Array):
					if is_instance_valid(item) and item is Unit and (item as Unit).can_gather_resource(want_res):
						should_show = true
						break
	if not should_show:
		return

	var sat: Dictionary = _owner_building.get_cluster_saturation()
	if not bool(sat.get("has_nodes", false)):
		return
	var assigned: int = int(sat.get("assigned", 0))
	var cap: int = maxi(1, int(sat.get("capacity", 0)))
	var text_str: String = "%d/%d" % [assigned, cap]
	var col: Color = ResourceNode.get_saturation_color(assigned, cap)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 11
	var txt_sz: Vector2 = font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pill_w: float = txt_sz.x + 14.0
	var pill_h: float = 17.0
	var pill_pos: Vector2 = Vector2(-pill_w * 0.5, -_owner_building.footprint_radius - pill_h - 14.0)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(0.03, 0.06, 0.10, 0.88), true)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(col.r, col.g, col.b, 0.90), false, 1.3)
	draw_string(font, pill_pos + Vector2(7.0, pill_h - 4.0), text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _draw_unit_damage_overlay() -> void:
	if _owner_unit == null or not is_instance_valid(_owner_unit) or _owner_unit.is_dead:
		return
	var max_hp_v: float = maxf(1.0, _owner_unit.get_max_hp())
	var hp_ratio: float = clampf(_owner_unit.current_hp / max_hp_v, 0.0, 1.0)
	if hp_ratio > 0.40:
		return
	var rad: float = _owner_unit.data.collision_radius if _owner_unit.data != null else 16.0
	var is_mech: bool = (_cached_renderer != null and _cached_renderer.is_mechanical_damage_style(entity_type_id, false)) or (
		_owner_unit.data != null and (
			_owner_unit.data.has_tag(&"mechanical")
			or _owner_unit.data.has_tag(&"synthetic")
			or _owner_unit.data.has_tag(&"heavy")
		)
	)
	var up_dir: Vector2 = Vector2(0.0, -1.0).rotated(-_owner_unit.body_visual.rotation) if _owner_unit.body_visual != null else Vector2(0.0, -1.0)
	_draw_damage_state(hp_ratio, rad, is_mech, up_dir)


func _draw_building_damage_overlay() -> void:
	if _owner_building == null or not is_instance_valid(_owner_building) or _owner_building.is_destroyed or not _owner_building.is_constructed:
		return
	var max_hp_v: float = maxf(1.0, _owner_building.max_hp)
	var hp_ratio: float = clampf(_owner_building.current_hp / max_hp_v, 0.0, 1.0)
	if hp_ratio > 0.40:
		return
	var is_mech_b: bool = _cached_renderer.is_mechanical_damage_style(entity_type_id, true) if _cached_renderer != null else true
	_draw_damage_state(hp_ratio, _owner_building.footprint_radius, is_mech_b, Vector2(0.0, -1.0))


func _draw_damage_state(hp_ratio: float, radius: float, is_mechanical: bool, up_dir: Vector2) -> void:
	var is_critical: bool = hp_ratio <= 0.20
	var side_dir: Vector2 = Vector2(-up_dir.y, up_dir.x)
	var puff_count: int = 3 if is_critical else 2
	var rise_scale: float = clampf(radius * 0.72, 12.0, 32.0)

	for i: int in range(puff_count):
		var phase: float = fmod(_anim_time * (0.95 if is_critical else 0.65) + float(i) / float(puff_count), 1.0)
		var puff_a: float = sin(phase * PI) * (0.52 if is_critical else 0.36)
		if puff_a <= 0.04:
			continue
		var lateral: float = (float(i) - float(puff_count - 1) * 0.5) * (radius * 0.34) + sin(_anim_time * 3.0 + float(i) * 2.1) * 2.2
		var pos: Vector2 = side_dir * lateral + up_dir * (radius * 0.12 + phase * rise_scale)
		var pr: float = lerpf(2.4, clampf(radius * 0.24, 4.0, 8.5), phase)
		var puff_col: Color = Color(0.08, 0.09, 0.11, puff_a) if is_mechanical else Color(0.76, 0.94, 0.86, puff_a * 0.85)
		draw_circle(pos, pr, puff_col)

	var spark_freq: float = 11.0 if is_critical else 6.0
	var spark_wave: float = sin(_anim_time * spark_freq + radius * 0.3)
	if spark_wave > (0.15 if is_critical else 0.55):
		var spark_col: Color = Color(1.0, 0.84, 0.34, 0.95) if is_mechanical else Color(1.0, 0.44, 0.36, 0.88)
		var anchor: Vector2 = side_dir * (radius * 0.28) + up_dir * (radius * 0.18)
		var tip: Vector2 = anchor + (up_dir * 0.75 + side_dir * 0.65) * clampf(radius * 0.35, 5.5, 11.0)
		var mid: Vector2 = anchor.lerp(tip, 0.5) + side_dir * (-2.6)
		draw_polyline(PackedVector2Array([anchor, mid, tip]), spark_col, 1.6, true)

	if is_critical:
		var flare: float = 0.5 + 0.5 * sin(_anim_time * 16.0)
		var flare_col: Color = Color(1.0, 0.36, 0.22, 0.42 + flare * 0.48) if is_mechanical else Color(1.0, 0.32, 0.38, 0.38 + flare * 0.42)
		draw_circle(Vector2.ZERO, clampf(radius * 0.22, 3.0, 7.0), flare_col)
		if is_mechanical and sin(_anim_time * 13.5 + 1.4) > 0.25:
			var a2: Vector2 = -side_dir * (radius * 0.30) + up_dir * (radius * 0.12)
			var t2: Vector2 = a2 + (up_dir * 0.6 - side_dir * 0.8) * clampf(radius * 0.34, 5.5, 10.5)
			draw_line(a2, t2, Color(0.95, 0.96, 1.0, 0.92), 1.4, true)
