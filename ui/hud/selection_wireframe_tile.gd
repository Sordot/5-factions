class_name SelectionWireframeTile
extends Control

## Pooled 34x32 procedural vector wireframe tile for SelectionWireframeGrid (Milestone 4.1).
## Renders faction-themed frame, HP-colorized CommandIconGlyphs silhouette, live HP & Shield
## micro-bars, and crisp 2-3px corner status pips with zero runtime node churn.

signal tile_clicked(entity: Node, shift_held: bool, ctrl_held: bool, is_double_click: bool)
signal tile_right_clicked(entity: Node)
signal tile_hovered(entity: Node, tile_global_rect: Rect2)
signal tile_unhovered(entity: Node)

const HP_HEALTHY: Color = Color(0.22, 0.92, 0.56, 0.96)
const HP_DAMAGED: Color = Color(0.98, 0.78, 0.16, 0.98)
const HP_CRITICAL: Color = Color(1.0, 0.28, 0.38, 1.0)
const SHIELD_CYAN: Color = Color(0.220, 0.741, 0.973, 1.0)
const VET_GOLD: Color = Color(0.980, 0.800, 0.082, 1.0)
const TETHER_MAGENTA: Color = Color(0.851, 0.275, 0.937, 1.0)
const DEPLOY_AMBER: Color = Color(1.0, 0.624, 0.110, 1.0)
const UNPOWERED_CRIMSON: Color = Color(1.0, 0.24, 0.34, 0.88)

var entity_ref: Node = null
var is_active_subgroup: bool = false
var is_hovered: bool = false

var _faction_id: StringName = &"genesis_v2"
var _faction_accent: Color = Color(0.20, 0.83, 0.60, 1.0)
var _bg_color: Color = Color(0.06, 0.09, 0.13, 0.92)


func _init() -> void:
	custom_minimum_size = Vector2(34.0, 32.0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	add_to_group("blocks_edge_pan")
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)


func bind_entity(entity: Node, active_subgroup: bool) -> void:
	entity_ref = entity
	is_active_subgroup = active_subgroup
	visible = (entity != null and is_instance_valid(entity))
	if not visible and is_hovered:
		is_hovered = false
		tile_unhovered.emit(null)
	queue_redraw()


func clear_slot() -> void:
	var prev: Node = entity_ref
	entity_ref = null
	is_active_subgroup = false
	if is_hovered:
		is_hovered = false
		tile_unhovered.emit(prev)
	visible = false


func apply_faction_theme(faction_id: StringName, accent: Color) -> void:
	_faction_id = faction_id
	_faction_accent = accent
	var pal: Dictionary = FactionHudTheme.get_palette(faction_id)
	var base_bg: Color = pal.get("bg", Color(0.06, 0.09, 0.13, 0.92)) as Color
	_bg_color = Color(base_bg.r * 0.85, base_bg.g * 0.85, base_bg.b * 0.85, 0.94)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible or entity_ref == null or not is_instance_valid(entity_ref):
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if mb.pressed:
				var shift_held: bool = mb.shift_pressed or Input.is_key_pressed(KEY_SHIFT)
				var ctrl_held: bool = mb.ctrl_pressed or mb.meta_pressed or Input.is_key_pressed(KEY_CTRL)
				tile_clicked.emit(entity_ref, shift_held, ctrl_held, mb.double_click)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			if mb.pressed:
				tile_right_clicked.emit(entity_ref)


func _on_mouse_entered() -> void:
	if not visible or entity_ref == null or not is_instance_valid(entity_ref):
		return
	is_hovered = true
	queue_redraw()
	tile_hovered.emit(entity_ref, get_global_rect())


func _on_mouse_exited() -> void:
	if is_hovered:
		is_hovered = false
		queue_redraw()
		tile_unhovered.emit(entity_ref)


func _get_hp_tier_color(hp_ratio: float) -> Color:
	if hp_ratio > 0.66:
		return HP_HEALTHY
	if hp_ratio > 0.33:
		return HP_DAMAGED
	return HP_CRITICAL


func _draw() -> void:
	if entity_ref == null or not is_instance_valid(entity_ref):
		return

	var w: float = size.x
	var h: float = size.y
	var rect: Rect2 = Rect2(Vector2.ZERO, size)

	# 1. Resolve live entity state
	var cur_hp: float = 1.0
	var max_hp: float = 1.0
	var cur_shd: float = 0.0
	var max_shd: float = 0.0
	var barrier: float = 0.0
	var icon_id: StringName = &""
	var icon_cat: StringName = &"unit"
	var vet_rank: int = 0
	var tether_stacks: int = 0
	var is_deployed: bool = false
	var is_unpowered: bool = false
	var is_producing: bool = false
	var is_overclocked: bool = false

	if entity_ref is Unit:
		var u: Unit = entity_ref as Unit
		if u.is_dead:
			return
		cur_hp = maxf(0.0, u.current_hp)
		max_hp = maxf(1.0, u.get_max_hp())
		cur_shd = maxf(0.0, u.current_shield)
		max_shd = maxf(0.0, u.max_shield)
		if u.status_effect_component != null and u.status_effect_component.has_method("get_shield_amount"):
			barrier = maxf(0.0, float(u.status_effect_component.call("get_shield_amount")))
		icon_id = u.get_unit_type_id()
		icon_cat = &"unit"
		vet_rank = clampi(u.veterancy_rank, 0, 3)
		tether_stacks = u.get_optical_tether_stacks()
		is_deployed = u.is_deployed()
	elif entity_ref is Building:
		var b: Building = entity_ref as Building
		if b.is_destroyed:
			return
		cur_hp = maxf(0.0, b.current_hp)
		max_hp = maxf(1.0, b.max_hp)
		cur_shd = maxf(0.0, b.current_shield)
		max_shd = maxf(0.0, b.max_shield)
		icon_id = b.building_type_id
		icon_cat = &"building"
		is_unpowered = b.is_constructed and b.requires_power_grid and not b.is_powered
		is_producing = b.is_actively_producing()
		is_overclocked = b.is_overclocked()
	else:
		return

	var hp_ratio: float = clampf(cur_hp / max_hp, 0.0, 1.0)
	var hp_col: Color = _get_hp_tier_color(hp_ratio)

	# 2. Faction-themed background & active-subgroup frame
	var is_monolith: bool = (_faction_id == &"monolith_os")
	var is_prisma: bool = (_faction_id == &"prisma_dei")
	var bg_col: Color = _bg_color.lightened(0.08) if is_hovered else _bg_color

	if is_monolith:
		draw_rect(rect, bg_col, true)
	elif is_prisma:
		var ch_p: float = 2.0
		var poly_p: PackedVector2Array = PackedVector2Array([
			Vector2(ch_p, 0.0), Vector2(w - ch_p, 0.0), Vector2(w, ch_p), Vector2(w, h - ch_p),
			Vector2(w - ch_p, h), Vector2(ch_p, h), Vector2(0.0, h - ch_p), Vector2(0.0, ch_p),
		])
		draw_colored_polygon(poly_p, bg_col)
	else:
		var ch_g: float = 3.0
		var poly_g: PackedVector2Array = PackedVector2Array([
			Vector2(ch_g, 0.0), Vector2(w - ch_g, 0.0), Vector2(w, ch_g), Vector2(w, h - ch_g),
			Vector2(w - ch_g, h), Vector2(ch_g, h), Vector2(0.0, h - ch_g), Vector2(0.0, ch_g),
		])
		draw_colored_polygon(poly_g, bg_col)

	if is_active_subgroup:
		draw_rect(Rect2(1.0, 1.0, w - 2.0, h - 2.0), Color(_faction_accent.r, _faction_accent.g, _faction_accent.b, 0.12), true)

	var border_col: Color
	var border_w: float = 1.0
	if is_active_subgroup:
		border_col = _faction_accent.lightened(0.18) if is_hovered else _faction_accent
		border_w = 1.6
	else:
		var muted_base: Color = Color(0.98, 0.80, 0.082, 0.44) if is_prisma else Color(0.45, 0.56, 0.66, 0.48)
		border_col = muted_base.lightened(0.32) if is_hovered else muted_base
		border_w = 1.2 if is_hovered else 1.0

	draw_rect(Rect2(0.5, 0.5, w - 1.0, h - 1.0), border_col, false, border_w)
	if is_monolith and is_active_subgroup:
		draw_line(Vector2(1.0, 1.0), Vector2(6.0, 1.0), _faction_accent, 2.0)
		draw_line(Vector2(1.0, 1.0), Vector2(1.0, 6.0), _faction_accent, 2.0)
	elif is_prisma and is_active_subgroup:
		draw_line(Vector2(2.0, 2.0), Vector2(5.5, 2.0), VET_GOLD, 1.2)
		draw_line(Vector2(w - 5.5, 2.0), Vector2(w - 2.0, 2.0), VET_GOLD, 1.2)

	# 3. HP-colorized vector wireframe icon (20x20 centered inset via scaled transform)
	var hi_col: Color = hp_col.lightened(0.30)
	var dark_col: Color = Color(hp_col.r * 0.18, hp_col.g * 0.18, hp_col.b * 0.18, 0.78)
	var has_shd_bar: bool = (max_shd > 0.0 or barrier > 0.0)
	var icon_center_y: float = 11.5 if has_shd_bar else 13.0
	draw_set_transform(Vector2(w * 0.5, icon_center_y), 0.0, Vector2(0.74, 0.74))
	CommandIconGlyphs.draw_icon(self, icon_id, icon_cat, Vector2.ZERO, hp_col, hi_col, dark_col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4. Bottom micro-bars (HP + optional Shield)
	var bar_x: float = 3.0
	var bar_w: float = maxf(8.0, w - 6.0)
	var hp_y: float = h - 4.5
	draw_rect(Rect2(bar_x, hp_y, bar_w, 2.5), Color(0.03, 0.05, 0.08, 0.92), true)
	draw_rect(Rect2(bar_x, hp_y, bar_w * hp_ratio, 2.5), hp_col, true)

	if has_shd_bar:
		var total_shd_max: float = maxf(1.0, max_shd + barrier)
		var shd_ratio: float = clampf((cur_shd + barrier) / total_shd_max, 0.0, 1.0)
		var shd_y: float = hp_y - 3.0
		draw_rect(Rect2(bar_x, shd_y, bar_w, 2.0), Color(0.03, 0.06, 0.10, 0.90), true)
		draw_rect(Rect2(bar_x, shd_y, bar_w * shd_ratio, 2.0), SHIELD_CYAN, true)

	# 5. Crisp corner status micro-pips (max 2-3 px)
	if vet_rank > 0:
		for vi: int in range(vet_rank):
			draw_rect(Rect2(2.5 + float(vi) * 3.0, 2.5, 2.0, 2.0), VET_GOLD, true)

	if tether_stacks > 0:
		var tp: Vector2 = Vector2(w - 4.5, 4.5)
		var d_pts: PackedVector2Array = PackedVector2Array([
			tp + Vector2(0.0, -2.6), tp + Vector2(2.6, 0.0),
			tp + Vector2(0.0, 2.6), tp + Vector2(-2.6, 0.0),
		])
		draw_colored_polygon(d_pts, TETHER_MAGENTA if tether_stacks == 1 else VET_GOLD)
	elif is_deployed:
		draw_rect(Rect2(w - 5.5, 2.5, 3.0, 3.0), DEPLOY_AMBER, true)
	elif is_unpowered:
		var pulse_u: float = 0.62 + 0.38 * sin(float(Time.get_ticks_msec()) * 0.007)
		var slash_col: Color = Color(UNPOWERED_CRIMSON.r, UNPOWERED_CRIMSON.g, UNPOWERED_CRIMSON.b, pulse_u)
		draw_line(Vector2(4.0, h - 7.0), Vector2(w - 4.0, 4.0), slash_col, 1.8, true)
	elif is_overclocked:
		draw_circle(Vector2(w - 4.5, 4.5), 2.2, DEPLOY_AMBER)
	elif is_producing:
		draw_circle(Vector2(w - 4.5, 4.5), 2.0, SHIELD_CYAN)
