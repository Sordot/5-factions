class_name DestructibleBarricade
extends StaticBody2D

const COMBAT_VFX_SCRIPT: GDScript = preload("res://ui/overlays/combat_vfx.gd")
const HIT_FLASH_DURATION: float = 0.08

signal health_changed(barricade: Node, current_hp: float, max_hp: float)
signal status_changed(barricade: Node)
signal destroyed(barricade: Node)

@export var barricade_name: String = "Reinforced Debris Gate"
@export var max_hp: float = 650.0
@export var is_armored: bool = true
@export var footprint_size: Vector2 = Vector2(120.0, 44.0)

var current_hp: float = 650.0
var is_destroyed: bool = false
var is_selected: bool = false

var _hit_flash_timer: float = 0.0
var _collision_shape: CollisionShape2D = null


func _ready() -> void:
	current_hp = maxf(1.0, max_hp)
	collision_layer = 1
	collision_mask = 0
	z_index = 4
	add_to_group("destructible_barricades")
	add_to_group("nav_bake_obstacles")
	if SpatialGrid != null:
		SpatialGrid.register_barricade(self)
	_ensure_collider()
	queue_redraw()


func _exit_tree() -> void:
	if SpatialGrid != null:
		SpatialGrid.unregister_barricade(self)


func _ensure_collider() -> void:
	_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision_shape == null:
		_collision_shape = CollisionShape2D.new()
		_collision_shape.name = "CollisionShape2D"
		add_child(_collision_shape)
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = footprint_size
	_collision_shape.shape = rect_shape


func _process(delta: float) -> void:
	if is_destroyed:
		return
	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		queue_redraw()


func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	queue_redraw()


func get_footprint_radius() -> float:
	return maxf(footprint_size.x, footprint_size.y) * 0.48


func contains_point(world_pos: Vector2) -> bool:
	if is_destroyed:
		return false
	var local_pt: Vector2 = to_local(world_pos)
	var half: Vector2 = footprint_size * 0.5 + Vector2(10.0, 10.0)
	return absf(local_pt.x) <= half.x and absf(local_pt.y) <= half.y


func overlaps_circle(world_pos: Vector2, radius: float) -> bool:
	if is_destroyed:
		return false
	var local_pt: Vector2 = to_local(world_pos)
	var half: Vector2 = footprint_size * 0.5
	var clamped: Vector2 = Vector2(
		clampf(local_pt.x, -half.x, half.x),
		clampf(local_pt.y, -half.y, half.y)
	)
	return local_pt.distance_squared_to(clamped) <= radius * radius


func get_world_polygon() -> PackedVector2Array:
	var half: Vector2 = footprint_size * 0.5
	return PackedVector2Array([
		to_global(Vector2(-half.x, -half.y)),
		to_global(Vector2(half.x, -half.y)),
		to_global(Vector2(half.x, half.y)),
		to_global(Vector2(-half.x, half.y)),
	])


func take_damage(amount: float, _attacker: Node = null) -> void:
	if is_destroyed or amount <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_hit_flash_timer = HIT_FLASH_DURATION
	queue_redraw()
	health_changed.emit(self, current_hp, max_hp)
	status_changed.emit(self)
	if current_hp <= 0.0:
		_destroy()


func _destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
	if is_in_group("nav_bake_obstacles"):
		remove_from_group("nav_bake_obstacles")
	if is_in_group("destructible_barricades"):
		remove_from_group("destructible_barricades")
	if SpatialGrid != null:
		SpatialGrid.unregister_barricade(self)
	set_selected(false)

	if get_parent() != null:
		var fx: Node2D = COMBAT_VFX_SCRIPT.new() as Node2D
		fx.z_index = 54
		get_parent().add_child(fx)
		fx.call("setup_death_burst", global_position, maxf(30.0, get_footprint_radius() * 0.9), Color(1.0, 0.72, 0.28, 1.0), true)

	if AudioManager != null:
		AudioManager.play_sfx(&"entity_destroyed", -2.5, 0.06)

	if is_inside_tree():
		var nav_reg: Node = get_tree().get_first_node_in_group("arena_nav_region")
		if nav_reg != null and nav_reg.has_method("request_rebake"):
			nav_reg.call("request_rebake")
		var fog: Node = get_tree().get_first_node_in_group("fog_of_war")
		if fog != null and fog.has_method("rebuild_blocker_grid"):
			fog.call("rebuild_blocker_grid")
		var cam: Node = get_tree().get_first_node_in_group("rts_camera")
		if cam != null and cam.has_method("add_camera_shake"):
			cam.call("add_camera_shake", 3.2, 0.15, global_position)

	destroyed.emit(self)
	queue_free()


func get_inspection_data() -> Dictionary:
	var hp_pct: int = int(round((current_hp / maxf(1.0, max_hp)) * 100.0))
	var integrity_str: String = "Intact"
	if hp_pct <= 33:
		integrity_str = "Critical Fracture"
	elif hp_pct <= 66:
		integrity_str = "Damaged"
	var stats: Array[Dictionary] = [
		{"label": "Class", "value": "Armored Obstacle"},
		{"label": "Integrity", "value": "%s (%d%%)" % [integrity_str, hp_pct]},
		{"label": "Counter", "value": "Lance-Rig / Mortar"},
		{"label": "Effect", "value": "Opens Route on Breach"},
	]
	return {
		"title": barricade_name,
		"subtitle": "DESTRUCTIBLE OBSTACLE — ARMORED",
		"affiliation": &"neutral",
		"accent_color": Color(1.0, 0.74, 0.28, 1.0),
		"ring_color": Color(1.0, 0.74, 0.28, 1.0),
		"show_hp_bar": true,
		"hp_current": current_hp,
		"hp_max": max_hp,
		"show_primary_bar": false,
		"stats": stats,
		"is_commandable": false,
		"readonly_label": "RIGHT-CLICK WITH UNITS TO BREACH",
	}


func _draw() -> void:
	var half: Vector2 = footprint_size * 0.5
	var rect: Rect2 = Rect2(-half, footprint_size)
	var hp_ratio: float = clampf(current_hp / maxf(1.0, max_hp), 0.0, 1.0)
	var flash: bool = _hit_flash_timer > 0.0

	# Drop shadow
	draw_rect(Rect2(-half + Vector2(4.0, 5.0), footprint_size), Color(0.02, 0.03, 0.05, 0.48), true)

	# Selection outline
	if is_selected:
		draw_rect(rect.grow(5.0), Color(1.0, 0.78, 0.30, 0.16), true)
		draw_rect(rect.grow(5.0), Color(1.0, 0.80, 0.30, 0.92), false, 1.8)

	# Reinforced slate armor plating
	var base_col: Color = Color(0.95, 0.96, 1.0, 1.0) if flash else Color(0.28, 0.34, 0.40, 0.98)
	var inner_col: Color = Color(0.85, 0.90, 0.95, 1.0) if flash else Color(0.18, 0.22, 0.27, 0.98)
	var border_col: Color = Color(1.0, 0.82, 0.34, 0.95) if hp_ratio > 0.33 else Color(1.0, 0.42, 0.24, 0.98)

	draw_rect(rect, base_col, true)
	draw_rect(rect.grow(-5.0), inner_col, true)
	draw_rect(rect, border_col, false, 2.2)

	# Diagonal hazard chevrons along the gate
	var stripe_col: Color = Color(1.0, 0.74, 0.24, 0.72) if hp_ratio > 0.33 else Color(1.0, 0.38, 0.22, 0.85)
	var step_x: float = 22.0
	var sx: float = -half.x + 12.0
	while sx < half.x - 10.0:
		var x0: float = sx
		var x1: float = minf(half.x - 5.0, sx + 10.0)
		draw_line(Vector2(x0, -half.y + 6.0), Vector2(x1, half.y - 6.0), stripe_col, 2.4, true)
		sx += step_x

	# Progressive structural damage cracks (< 66% and < 33%)
	if hp_ratio < 0.66:
		var crack_col: Color = Color(0.05, 0.06, 0.08, 0.94)
		var glow_col: Color = Color(1.0, 0.56, 0.22, 0.78)
		var c1: PackedVector2Array = PackedVector2Array([
			Vector2(-half.x * 0.45, -half.y + 2.0),
			Vector2(-half.x * 0.30, -2.0),
			Vector2(-half.x * 0.18, half.y - 3.0),
		])
		draw_polyline(c1, glow_col, 3.2, true)
		draw_polyline(c1, crack_col, 1.6, true)

		var c2: PackedVector2Array = PackedVector2Array([
			Vector2(half.x * 0.25, -half.y + 3.0),
			Vector2(half.x * 0.34, 3.0),
			Vector2(half.x * 0.20, half.y - 2.0),
		])
		draw_polyline(c2, glow_col, 2.8, true)
		draw_polyline(c2, crack_col, 1.4, true)

	if hp_ratio < 0.33:
		# Deep glowing breach fractures
		var crit_glow: Color = Color(1.0, 0.36, 0.20, 0.92)
		var c3: PackedVector2Array = PackedVector2Array([
			Vector2(-half.x * 0.10, -half.y + 2.0),
			Vector2(0.0, 0.0),
			Vector2(half.x * 0.08, half.y - 2.0),
		])
		draw_polyline(c3, crit_glow, 4.6, true)
		draw_polyline(c3, Color(0.04, 0.04, 0.06, 0.98), 2.2, true)
		draw_circle(Vector2.ZERO, 6.5, Color(1.0, 0.46, 0.20, 0.42))

	# World HP bar when damaged or selected (counter-rotated horizontal)
	if is_selected or hp_ratio < 0.999:
		draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
		var bar_w: float = 64.0
		var bar_h: float = 5.0
		var bar_pos: Vector2 = Vector2(-bar_w * 0.5, -maxf(half.x, half.y) * 0.5 - 16.0)
		draw_rect(Rect2(bar_pos - Vector2(1.0, 1.0), Vector2(bar_w + 2.0, bar_h + 2.0)), Color(0.03, 0.05, 0.08, 0.92), true)
		var fill_col: Color = Color(1.0, 0.78, 0.28, 1.0) if hp_ratio > 0.35 else Color(1.0, 0.34, 0.24, 1.0)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * hp_ratio, bar_h)), fill_col, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
