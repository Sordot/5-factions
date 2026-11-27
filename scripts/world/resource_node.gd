class_name ResourceNode
extends StaticBody2D

const HARVEST_PULSE_DURATION: float = 0.22
const ASSIGN_GRACE_MSEC: int = 200
const BADGE_REFRESH_INTERVAL: float = 0.12

signal amount_changed(node: ResourceNode, remaining: int, max_amount: int)
signal status_changed(node: ResourceNode)
signal depleted(node: ResourceNode)

@export var resource_type: StringName = &"biomass"
@export var display_name: String = "Biomass Cluster"
@export var max_amount: int = 1500
@export var remaining_amount: int = 1500
@export var collision_radius: float = 22.0
@export var interaction_radius: float = 28.0
@export var max_harvesters: int = 3
@export var is_vent: bool = false
@export var is_high_yield: bool = false
@export var high_yield_multiplier: float = 1.35

@onready var visual_root: Node2D = get_node_or_null("VisualRoot") as Node2D
@onready var highlight_ring: Line2D = get_node_or_null("HighlightRing") as Line2D
@onready var amount_label: Label = get_node_or_null("AmountLabel") as Label

var occupied_by_building: Building = null
var is_inspected: bool = false
var is_hovered: bool = false
var surge_remaining: float = 0.0
var surge_duration_total: float = 45.0
var surge_multiplier: float = 2.0
var _surge_anim_time: float = 0.0
var _last_surge_sec_int: int = -1
var _gleam_anim_time: float = 0.0
var _gleam_redraw_acc: float = 0.0
var _pulse_timer: float = 0.0
var _is_highlighted: bool = false
var _assigned_workers: Array[Unit] = []
var _assigned_timestamps: Dictionary = {}
var _harvest_slots: Dictionary = {} # slot_index: int -> Unit
var _badge_timer: float = 0.0
var _show_saturation_badge: bool = false
var _cached_badge_assigned: int = -1
var _cached_badge_cap: int = -1


func _ready() -> void:
	add_to_group("resource_nodes")
	if SpatialGrid != null:
		SpatialGrid.register_resource(self)
	if is_high_yield and not is_vent:
		var default_max: int = 2500 if resource_type == &"silica" else 1500
		if max_amount <= default_max:
			var old_max: int = max_amount
			max_amount = int(round(float(max_amount) * 1.25))
			if remaining_amount >= old_max or remaining_amount <= 0:
				remaining_amount = max_amount
		if resource_type == &"silica":
			if display_name.is_empty() or display_name == "Silica Vein":
				display_name = "Rich Silica Vein"
		elif resource_type == &"biomass":
			if display_name.is_empty() or display_name == "Biomass Cluster":
				display_name = "Dense Biomass Cluster"
		_apply_high_yield_styling()
	remaining_amount = clampi(remaining_amount, 0, maxi(1, max_amount))
	_update_ring_visual()
	_update_visuals()
	if is_high_yield and not is_vent:
		queue_redraw()


func _apply_high_yield_styling() -> void:
	if amount_label != null:
		var lbl_col: Color = Color(1.0, 0.90, 0.36, 0.98) if resource_type == &"silica" else Color(0.54, 1.0, 0.78, 0.98)
		amount_label.add_theme_color_override("font_color", lbl_col)
	if visual_root != null:
		var rim: Line2D = visual_root.get_node_or_null("RimOutline") as Line2D
		if rim != null:
			rim.width = 2.2
			rim.default_color = Color(1.0, 0.88, 0.32, 0.95) if resource_type == &"silica" else Color(0.46, 1.0, 0.76, 0.95)


func get_effective_carry_capacity(base_capacity: int) -> int:
	if is_high_yield and not is_vent:
		return maxi(base_capacity + 1, int(round(float(base_capacity) * high_yield_multiplier)))
	return base_capacity


func is_surging() -> bool:
	return is_vent and surge_remaining > 0.0


func get_compute_surge_multiplier() -> float:
	return surge_multiplier if is_surging() else 1.0


func start_overpressure_surge(duration: float = 45.0, mult: float = 2.0) -> void:
	if not is_vent:
		return
	surge_duration_total = maxf(1.0, duration)
	surge_remaining = surge_duration_total
	surge_multiplier = maxf(1.0, mult)
	_surge_anim_time = 0.0
	_last_surge_sec_int = int(ceil(surge_remaining))
	queue_redraw()
	status_changed.emit(self)
	if occupied_by_building != null and is_instance_valid(occupied_by_building):
		occupied_by_building.status_changed.emit(occupied_by_building)


func _exit_tree() -> void:
	_assigned_workers.clear()
	_assigned_timestamps.clear()
	_harvest_slots.clear()
	if SpatialGrid != null:
		SpatialGrid.unregister_resource(self)


func _process(delta: float) -> void:
	if _pulse_timer > 0.0:
		_pulse_timer = maxf(0.0, _pulse_timer - delta)
		var t: float = _pulse_timer / HARVEST_PULSE_DURATION
		if visual_root != null:
			var boost: float = 1.0 + 0.35 * t
			visual_root.modulate = Color(boost, 1.0 + 0.55 * t, boost, 1.0)
		if _pulse_timer <= 0.0 and visual_root != null:
			visual_root.modulate = Color.WHITE

	if is_vent:
		if surge_remaining > 0.0:
			surge_remaining = maxf(0.0, surge_remaining - delta)
			_surge_anim_time += delta
			var sec_now: int = int(ceil(surge_remaining))
			if sec_now != _last_surge_sec_int or surge_remaining <= 0.0:
				_last_surge_sec_int = sec_now
				status_changed.emit(self)
				if occupied_by_building != null and is_instance_valid(occupied_by_building):
					occupied_by_building.status_changed.emit(occupied_by_building)
			queue_redraw()
		return

	if not is_depleted():
		if is_high_yield:
			_gleam_anim_time += delta
			_gleam_redraw_acc += delta
			if _gleam_redraw_acc >= 0.06:
				_gleam_redraw_acc = 0.0
				queue_redraw()
		_badge_timer += delta
		if _badge_timer >= BADGE_REFRESH_INTERVAL:
			_badge_timer = 0.0
			_refresh_saturation_badge_state()


func _refresh_saturation_badge_state() -> void:
	var viewer_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var should_show: bool = is_inspected or _is_highlighted or is_hovered
	if not should_show and is_inside_tree():
		var mouse_world: Vector2 = get_global_mouse_position()
		var hover_r: float = interaction_radius + 10.0
		if global_position.distance_squared_to(mouse_world) <= hover_r * hover_r:
			should_show = true
	if not should_show and is_inside_tree() and viewer_team >= 0:
		var sel: Node = get_tree().get_first_node_in_group("selection_controller")
		if sel != null:
			var sel_units: Variant = sel.get("selected_units")
			if sel_units is Array:
				for item: Variant in (sel_units as Array):
					if is_instance_valid(item) and item is Unit:
						var u: Unit = item as Unit
						if u.can_gather_resource(resource_type):
							should_show = true
							break

	var count_now: int = get_assigned_count(viewer_team if viewer_team >= 0 else -1) if should_show else -1
	var cap_now: int = get_effective_max_harvesters(viewer_team) if should_show else -1
	if should_show != _show_saturation_badge or count_now != _cached_badge_assigned or cap_now != _cached_badge_cap:
		_show_saturation_badge = should_show
		_cached_badge_assigned = count_now
		_cached_badge_cap = cap_now
		queue_redraw()


func set_hovered(hovered: bool) -> void:
	if is_hovered == hovered:
		return
	is_hovered = hovered
	if not is_vent and not is_depleted():
		_refresh_saturation_badge_state()
	queue_redraw()


func _draw() -> void:
	if is_surging():
		var s_pulse: float = 0.5 + 0.5 * sin(_surge_anim_time * 5.2)
		var ring_phase_a: float = fmod(_surge_anim_time * 0.85, 1.0)
		var ring_phase_b: float = fmod(_surge_anim_time * 0.85 + 0.5, 1.0)
		var base_r: float = maxf(interaction_radius + 8.0, 44.0)
		var r_a: float = lerpf(base_r, base_r + 28.0, ring_phase_a)
		var r_b: float = lerpf(base_r, base_r + 28.0, ring_phase_b)
		var cyan_col: Color = Color(0.28, 0.96, 1.0, (1.0 - ring_phase_a) * 0.88)
		var gold_col: Color = Color(1.0, 0.84, 0.24, (1.0 - ring_phase_b) * 0.78)
		draw_circle(Vector2.ZERO, base_r + 4.0, Color(0.22, 0.92, 1.0, 0.06 + s_pulse * 0.05))
		draw_arc(Vector2.ZERO, r_a, 0.0, TAU, 40, cyan_col, 2.2, true)
		draw_arc(Vector2.ZERO, r_b, 0.0, TAU, 40, gold_col, 1.8, true)
		# Crisp 45s radial countdown arc around vent perimeter (remains clearly visible around occupying Compute facility)
		var arc_r: float = base_r + 5.0
		var frac: float = clampf(surge_remaining / maxf(1.0, surge_duration_total), 0.0, 1.0)
		draw_arc(Vector2.ZERO, arc_r, 0.0, TAU, 44, Color(0.06, 0.14, 0.20, 0.55), 3.6, true)
		draw_arc(Vector2.ZERO, arc_r, -PI * 0.5, -PI * 0.5 + TAU * frac, 44, Color(0.32, 0.98, 1.0, 0.92), 2.8, true)
		# Small "2x" badge above arc
		var s_font: Font = ThemeDB.fallback_font
		if s_font != null:
			var s_txt: String = "2x SURGE %ds" % int(ceil(surge_remaining))
			var s_sz: Vector2 = s_font.get_string_size(s_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
			var s_pos: Vector2 = Vector2(-s_sz.x * 0.5, -arc_r - 7.0)
			draw_rect(Rect2(s_pos + Vector2(-4.0, -s_sz.y + 1.0), s_sz + Vector2(8.0, 4.0)), Color(0.03, 0.08, 0.14, 0.86), true)
			draw_string(s_font, s_pos, s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.38, 0.98, 1.0, 0.98))

	if is_high_yield and not is_vent and not is_depleted():
		var g_pulse: float = 0.5 + 0.5 * sin(_gleam_anim_time * 3.4 + global_position.x * 0.02)
		if resource_type == &"silica":
			# Rich Silica: molten solar-gold / amber faceted crystal prism + shimmering warm gold halo + specular facets
			var halo_r: float = collision_radius + 6.0 + g_pulse * 2.5
			draw_circle(Vector2.ZERO, halo_r, Color(1.0, 0.78, 0.16, 0.10 + g_pulse * 0.08))
			draw_arc(Vector2.ZERO, halo_r, 0.0, TAU, 32, Color(1.0, 0.84, 0.24, 0.56 + g_pulse * 0.30), 1.7, true)
			var prism: PackedVector2Array = PackedVector2Array([
				Vector2(0.0, -15.0),
				Vector2(9.0, -4.0),
				Vector2(5.5, 11.0),
				Vector2(-5.5, 11.0),
				Vector2(-9.0, -4.0),
			])
			draw_colored_polygon(prism, Color(1.0, 0.86, 0.34, 0.34 + g_pulse * 0.18))
			draw_polyline(prism + PackedVector2Array([prism[0]]), Color(1.0, 0.96, 0.68, 0.88), 1.4, true)
			# Specular highlight facets
			draw_line(Vector2(-3.0, -9.0), Vector2(4.0, -2.0), Color(1.0, 0.99, 0.85, 0.90), 1.5, true)
			draw_line(Vector2(0.0, -14.0), Vector2(0.0, 6.0), Color(1.0, 0.96, 0.74, 0.55), 1.1, true)
		else:
			# Dense Biomass: radiant mint-emerald crystal veins + pulsing golden-emerald aura ring + 3 crisp diamond glint ticks
			var aura_r: float = collision_radius + 5.5 + g_pulse * 2.4
			draw_circle(Vector2.ZERO, aura_r, Color(0.28, 1.0, 0.66, 0.09 + g_pulse * 0.07))
			draw_arc(Vector2.ZERO, aura_r, 0.0, TAU, 32, Color(0.56, 1.0, 0.68, 0.52 + g_pulse * 0.28), 1.7, true)
			draw_arc(Vector2.ZERO, aura_r + 3.2, 0.0, TAU, 32, Color(0.98, 0.88, 0.34, 0.26 + g_pulse * 0.20), 1.0, true)
			# Radiant mint-emerald veins
			var vein_col: Color = Color(0.68, 1.0, 0.86, 0.82)
			draw_line(Vector2(0.0, -12.0), Vector2(0.0, 10.0), vein_col, 1.4, true)
			draw_line(Vector2(0.0, -3.0), Vector2(-9.0, 5.0), vein_col, 1.3, true)
			draw_line(Vector2(0.0, -1.0), Vector2(9.0, 4.0), vein_col, 1.3, true)
			# 3 crisp diamond glint ticks spaced at 120° around perimeter
			for gi: int in range(3):
				var ga: float = _gleam_anim_time * 0.55 + float(gi) * (TAU / 3.0)
				var gp: Vector2 = Vector2.from_angle(ga) * (aura_r + 2.0)
				var gs: float = 3.2 + g_pulse * 1.1
				var g_dia: PackedVector2Array = PackedVector2Array([
					gp + Vector2(0.0, -gs),
					gp + Vector2(gs * 0.75, 0.0),
					gp + Vector2(0.0, gs),
					gp + Vector2(-gs * 0.75, 0.0),
				])
				draw_colored_polygon(g_dia, Color(0.94, 1.0, 0.76, 0.88))

	if is_hovered and not is_depleted():
		var zoom_x: float = 1.0
		if is_inside_tree():
			var cam: Camera2D = get_viewport().get_camera_2d()
			if cam != null:
				zoom_x = maxf(0.25, cam.zoom.x)
		var ring_r: float = interaction_radius + (5.0 if is_inspected else 2.5)
		var h_col: Color = Color(0.204, 0.827, 0.600, 0.36 if is_inspected else 0.62)
		if not is_inspected:
			draw_circle(Vector2.ZERO, ring_r, Color(h_col.r, h_col.g, h_col.b, 0.08))
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32, h_col, 1.4 / zoom_x, true)

	if not _show_saturation_badge or is_vent or is_depleted():
		return
	var viewer_team: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var assigned: int = maxi(0, _cached_badge_assigned)
	var cap: int = get_effective_max_harvesters(viewer_team)
	var label_txt: String = "%d/%d" % [assigned, cap]
	var col: Color = get_saturation_color(assigned, cap)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 11
	var txt_sz: Vector2 = font.get_string_size(label_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pill_w: float = txt_sz.x + 12.0
	var pill_h: float = 16.0
	var pill_pos: Vector2 = Vector2(-pill_w * 0.5, -interaction_radius - pill_h - 4.0)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(0.03, 0.06, 0.10, 0.88), true)
	draw_rect(Rect2(pill_pos, Vector2(pill_w, pill_h)), Color(col.r, col.g, col.b, 0.90), false, 1.2)
	draw_string(font, pill_pos + Vector2(6.0, pill_h - 4.0), label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


static func get_saturation_color(assigned: int, cap: int) -> Color:
	if assigned > cap:
		return Color(1.0, 0.34, 0.28, 0.98) # Crimson: over-saturated
	if assigned == cap and cap > 0:
		return Color(1.0, 0.78, 0.24, 0.98) # Amber/Gold: optimal cap
	return Color(0.32, 0.96, 1.0, 0.96) # Cyan: under-saturated


func prune_assigned_workers() -> void:
	var now_ms: int = Time.get_ticks_msec()
	var kept: Array[Unit] = []
	for u: Unit in _assigned_workers:
		if not is_instance_valid(u) or u.is_dead or u.is_staffed or u.is_queued_for_deletion():
			continue
		var uid: int = u.get_instance_id()
		var within_grace: bool = (now_ms - int(_assigned_timestamps.get(uid, -99999))) <= ASSIGN_GRACE_MSEC
		var actively_on_self: bool = (
			u.gather_component != null
			and u.gather_component.is_active()
			and u.gather_component.target_node == self
		)
		var queued_for_self: bool = _has_queued_gather_for_self(u)
		if actively_on_self or queued_for_self or within_grace:
			kept.append(u)
		else:
			_assigned_timestamps.erase(uid)
	_assigned_workers = kept

	# Prune stale harvest slot holders
	var stale_slots: Array = []
	for slot_key: Variant in _harvest_slots.keys():
		var holder: Unit = _harvest_slots[slot_key] as Unit
		if holder == null or not is_instance_valid(holder) or holder.is_dead or holder.is_staffed or holder.is_queued_for_deletion():
			stale_slots.append(slot_key)
			continue
		if holder.gather_component == null or holder.gather_component.target_node != self:
			stale_slots.append(slot_key)
			continue
		var st: GatherComponent.GatherState = holder.gather_component.state
		if st != GatherComponent.GatherState.GATHERING and st != GatherComponent.GatherState.GATHER_MOVING_TO_NODE:
			stale_slots.append(slot_key)
	for k: Variant in stale_slots:
		_harvest_slots.erase(k)


func _has_queued_gather_for_self(u: Unit) -> bool:
	for cmd: Dictionary in u.command_queue:
		if cmd.get("type", &"") == &"gather" and cmd.get("target", null) == self:
			return true
	return false


func get_assigned_count(team_filter: int = -1) -> int:
	prune_assigned_workers()
	if team_filter < 0:
		return _assigned_workers.size()
	var count: int = 0
	for u: Unit in _assigned_workers:
		if int(u.team) == team_filter:
			count += 1
	return count


func get_effective_max_harvesters(team_filter: int = -1) -> int:
	var cap: int = maxi(1, max_harvesters)
	if team_filter >= 0 and TeamManager != null and TeamManager.has_method("get_team_faction_data"):
		var faction: FactionData = TeamManager.get_team_faction_data(team_filter)
		if faction != null and faction.has_method("get_bonus_harvesters"):
			cap += faction.get_bonus_harvesters(resource_type)
	return cap


func has_free_slot(team_filter: int = -1) -> bool:
	if is_depleted() or is_vent:
		return false
	return get_assigned_count(team_filter) < get_effective_max_harvesters(team_filter)


func assign_worker(worker: Unit) -> void:
	if worker == null or not is_instance_valid(worker) or worker.is_dead:
		return
	if not _assigned_workers.has(worker):
		_assigned_workers.append(worker)
	_assigned_timestamps[worker.get_instance_id()] = Time.get_ticks_msec()


func release_worker(worker: Unit) -> void:
	if worker == null:
		return
	_assigned_workers.erase(worker)
	if is_instance_valid(worker):
		_assigned_timestamps.erase(worker.get_instance_id())
	release_harvest_slot(worker)


func release_harvest_slot(worker: Unit) -> void:
	if worker == null:
		return
	var to_erase: Array = []
	for k: Variant in _harvest_slots.keys():
		if _harvest_slots[k] == worker:
			to_erase.append(k)
	for k: Variant in to_erase:
		_harvest_slots.erase(k)


func claim_harvest_slot(worker: Unit, dropoff_pos: Vector2 = Vector2.INF) -> Vector2:
	prune_assigned_workers()
	var unit_r: float = worker.data.collision_radius if (worker != null and worker.data != null) else 13.0
	var stand_r: float = collision_radius + unit_r + 6.0

	var hub_dir: Vector2 = Vector2.ZERO
	if dropoff_pos != Vector2.INF and dropoff_pos.distance_squared_to(global_position) > 16.0:
		hub_dir = (dropoff_pos - global_position).normalized()
	elif global_position.length_squared() > 16.0:
		hub_dir = (-global_position).normalized()
	else:
		hub_dir = Vector2.RIGHT
	var hub_angle: float = hub_dir.angle()

	# Hub-facing primary perimeter arc + overflow fallback angles
	var cap: int = get_effective_max_harvesters(int(worker.team) if worker != null else -1)
	var offsets: PackedFloat32Array
	if cap <= 2:
		offsets = PackedFloat32Array([-0.5585, 0.5585, 0.0, -1.6057, 1.6057, PI])
	else:
		offsets = PackedFloat32Array([0.0, -0.8378, 0.8378, -1.6755, 1.6755, PI])

	# Keep existing claimed slot if this worker already holds one
	for k: Variant in _harvest_slots.keys():
		if _harvest_slots[k] == worker:
			var idx_existing: int = clampi(int(k), 0, offsets.size() - 1)
			return global_position + Vector2.RIGHT.rotated(hub_angle + offsets[idx_existing]) * stand_r

	# Prefer unclaimed primary slots (0 .. cap - 1) closest to the worker
	var primary_count: int = mini(maxi(1, cap), offsets.size())
	var best_idx: int = -1
	var best_d_sq: float = INF
	var worker_pos: Vector2 = worker.global_position if (worker != null and is_instance_valid(worker)) else global_position

	for i: int in range(primary_count):
		if _harvest_slots.has(i):
			continue
		var pt: Vector2 = global_position + Vector2.RIGHT.rotated(hub_angle + offsets[i]) * stand_r
		var d_sq: float = worker_pos.distance_squared_to(pt)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best_idx = i

	# Spill to overflow perimeter slots if all primary slots are currently occupied
	if best_idx < 0:
		for i: int in range(primary_count, offsets.size()):
			if _harvest_slots.has(i):
				continue
			var pt2: Vector2 = global_position + Vector2.RIGHT.rotated(hub_angle + offsets[i]) * stand_r
			var d_sq2: float = worker_pos.distance_squared_to(pt2)
			if d_sq2 < best_d_sq:
				best_d_sq = d_sq2
				best_idx = i

	if best_idx >= 0:
		_harvest_slots[best_idx] = worker
		return global_position + Vector2.RIGHT.rotated(hub_angle + offsets[best_idx]) * stand_r

	# All slots occupied (extreme overflow): deterministically angle around perimeter by instance id
	var fallback_ang: float = hub_angle + fmod(float(worker.get_instance_id() % 12) * (TAU / 12.0), TAU)
	return global_position + Vector2.RIGHT.rotated(fallback_ang) * (stand_r + 3.0)


static func pick_best_cluster_node(
	anchor_node: ResourceNode,
	worker: Unit,
	team: int,
	cluster_radius: float = 420.0,
	overflow_radius: float = 950.0,
	exclude_node: ResourceNode = null
) -> ResourceNode:
	if anchor_node == null or not is_instance_valid(anchor_node) or not anchor_node.is_inside_tree():
		return null
	return pick_best_cluster_node_from_pos(
		anchor_node.get_tree(),
		anchor_node.global_position,
		anchor_node.resource_type,
		worker,
		team,
		cluster_radius,
		overflow_radius,
		anchor_node,
		exclude_node
	)


static func pick_best_cluster_node_from_pos(
	tree: SceneTree,
	origin: Vector2,
	res_type: StringName,
	worker: Unit,
	team: int,
	cluster_radius: float = 420.0,
	overflow_radius: float = 950.0,
	anchor_node: ResourceNode = null,
	exclude_node: ResourceNode = null
) -> ResourceNode:
	if tree == null or res_type == &"":
		return null

	var local_candidates: Array[ResourceNode] = []
	var overflow_candidates: Array[ResourceNode] = []
	var cluster_r_sq: float = cluster_radius * cluster_radius
	var overflow_r_sq: float = overflow_radius * overflow_radius

	for node: Node in tree.get_nodes_in_group("resource_nodes"):
		if not (node is ResourceNode) or not is_instance_valid(node):
			continue
		var rn: ResourceNode = node as ResourceNode
		if rn == exclude_node or rn.is_depleted() or rn.is_vent or rn.resource_type != res_type:
			continue
		var d_sq: float = origin.distance_squared_to(rn.global_position)
		if d_sq <= cluster_r_sq:
			local_candidates.append(rn)
		elif d_sq <= overflow_r_sq:
			overflow_candidates.append(rn)

	# 1. Pick best unsaturated node in local cluster
	var best_local: ResourceNode = null
	var best_local_score: float = INF
	for rn: ResourceNode in local_candidates:
		if not rn.has_free_slot(team):
			continue
		var assigned: int = rn.get_assigned_count(team)
		var dist: float = origin.distance_to(rn.global_position)
		var anchor_bonus: float = -12.0 if (rn == anchor_node and assigned == 0) else 0.0
		var worker_bias: float = (worker.global_position.distance_to(rn.global_position) * 0.08) if (worker != null and is_instance_valid(worker)) else 0.0
		var score: float = float(assigned) * 1000.0 + dist + worker_bias + anchor_bonus
		if score < best_local_score:
			best_local_score = score
			best_local = rn
	if best_local != null:
		return best_local

	# 2. Local cluster full -> spill over to nearest unsaturated node within overflow_radius
	var fog: Node = tree.get_first_node_in_group("fog_of_war")
	var is_local_human: bool = TeamManager != null and TeamManager.is_team_controlled_by_local_human(team)
	var check_fog: bool = is_local_human and fog != null and bool(fog.get("fog_enabled")) and fog.has_method("is_world_pos_explored")

	var best_overflow: ResourceNode = null
	var best_overflow_score: float = INF
	for rn: ResourceNode in overflow_candidates:
		if not rn.has_free_slot(team):
			continue
		if check_fog and not bool(fog.call("is_world_pos_explored", rn.global_position)):
			continue
		var assigned_o: int = rn.get_assigned_count(team)
		var score_o: float = float(assigned_o) * 1000.0 + origin.distance_to(rn.global_position)
		if score_o < best_overflow_score:
			best_overflow_score = score_o
			best_overflow = rn
	if best_overflow != null:
		return best_overflow

	# 3. Fallback: least-assigned node in local cluster so overflow workers distribute evenly
	var fallback: ResourceNode = null
	var fallback_score: float = INF
	for rn: ResourceNode in local_candidates:
		var assigned_f: int = rn.get_assigned_count(team)
		var score_f: float = float(assigned_f) * 1000.0 + origin.distance_to(rn.global_position)
		if score_f < fallback_score:
			fallback_score = score_f
			fallback = rn
	if fallback != null:
		return fallback

	# 4. Last resort: nearest valid node in overflow_candidates (even if saturated)
	var last_best: ResourceNode = null
	var last_score: float = INF
	for rn: ResourceNode in overflow_candidates:
		var assigned_l: int = rn.get_assigned_count(team)
		var score_l: float = float(assigned_l) * 1000.0 + origin.distance_to(rn.global_position)
		if score_l < last_score:
			last_score = score_l
			last_best = rn
	return last_best


func is_depleted() -> bool:
	if is_vent:
		return false
	return remaining_amount <= 0


func is_occupied() -> bool:
	return occupied_by_building != null and is_instance_valid(occupied_by_building) and not occupied_by_building.is_destroyed


func claim_by_building(building: Building) -> void:
	occupied_by_building = building
	if amount_label != null and is_vent:
		amount_label.visible = false
	status_changed.emit(self)


func release_building(building: Building) -> void:
	if occupied_by_building == building:
		occupied_by_building = null
		if amount_label != null and is_vent:
			amount_label.visible = true
		status_changed.emit(self)


func contains_point(world_point: Vector2) -> bool:
	if is_depleted():
		return false
	return global_position.distance_squared_to(world_point) <= interaction_radius * interaction_radius


func set_highlighted(highlighted: bool) -> void:
	_is_highlighted = highlighted
	_update_ring_visual()
	_refresh_saturation_badge_state()


func set_inspected(inspected: bool) -> void:
	if is_inspected == inspected:
		return
	is_inspected = inspected
	_update_ring_visual()
	_refresh_saturation_badge_state()


func _update_ring_visual() -> void:
	if highlight_ring == null:
		return
	highlight_ring.visible = is_inspected or _is_highlighted
	if is_inspected:
		if is_vent:
			highlight_ring.default_color = Color(0.28, 0.92, 1.0, 0.96)
		else:
			highlight_ring.default_color = Color(1.0, 0.84, 0.28, 0.96)
		highlight_ring.width = 2.6
	else:
		highlight_ring.width = 2.0


func pulse_harvest_feedback() -> void:
	_pulse_timer = HARVEST_PULSE_DURATION


func extract(amount: int) -> int:
	if is_vent or amount <= 0 or remaining_amount <= 0:
		return 0
	var extracted: int = mini(amount, remaining_amount)
	remaining_amount -= extracted
	_update_visuals()
	amount_changed.emit(self, remaining_amount, max_amount)
	status_changed.emit(self)
	if remaining_amount <= 0:
		if is_in_group("nav_bake_obstacles"):
			remove_from_group("nav_bake_obstacles")
		if SpatialGrid != null:
			SpatialGrid.unregister_resource(self)
		collision_layer = 0
		for child: Node in get_children():
			if child is CollisionShape2D:
				(child as CollisionShape2D).set_deferred("disabled", true)
		if is_inside_tree():
			var nav_reg: Node = get_tree().get_first_node_in_group("arena_nav_region")
			if nav_reg != null and nav_reg.has_method("request_rebake"):
				nav_reg.call("request_rebake")
		depleted.emit(self)
		queue_free()
	return extracted


func get_inspection_data() -> Dictionary:
	if is_vent:
		var status_text: String = "CAPPED — Compute Node" if is_occupied() else "UNOCCUPIED — Ready"
		var surging_now: bool = is_surging()
		var yield_str: String = "+%d Compute / 3.0s / Eng (2x)" % int(round(5.0 * surge_multiplier)) if surging_now else "+5 Compute / 3.0s / Eng"
		var vent_stats: Array[Dictionary] = [
			{"label": "Status", "value": status_text},
			{"label": "Yield Rate", "value": yield_str},
			{"label": "Capacity", "value": "Infinite Geothermal"},
			{"label": "Structure", "value": "Compute Node [E]"},
		]
		if surging_now:
			vent_stats.append({
				"label": "Thermal State",
				"value": "OVERPRESSURE SURGE (%dx) — %ds" % [int(round(surge_multiplier)), int(ceil(surge_remaining))],
				"color": Color(0.28, 0.96, 1.0, 1.0),
			})
		return {
			"title": "Thermal Data Vent",
			"subtitle": "OVERPRESSURE COMPUTE VENT (2x)" if surging_now else "COMPUTE VENT",
			"affiliation": &"neutral",
			"accent_color": Color(0.28, 0.98, 1.0, 1.0) if surging_now else Color(0.32, 0.86, 1.0, 1.0),
			"ring_color": Color(0.28, 0.92, 1.0, 0.96),
			"show_hp_bar": false,
			"show_primary_bar": false,
			"stats": vent_stats,
			"is_commandable": false,
			"readonly_label": "READ-ONLY TELEMETRY  —  BUILD COMPUTE NODE [E]",
		}

	var is_silica: bool = (resource_type == &"silica")
	var accent: Color = Color(0.98, 0.78, 0.28, 1.0) if is_silica else Color(0.26, 0.94, 0.56, 1.0)
	if is_high_yield:
		accent = Color(1.0, 0.86, 0.26, 1.0) if is_silica else Color(0.40, 1.0, 0.74, 1.0)
	var pct: int = int(round((float(remaining_amount) / float(maxi(1, max_amount))) * 100.0))
	var fmt_rem: String = InspectionHelper.format_number(remaining_amount)
	var fmt_max: String = InspectionHelper.format_number(max_amount)
	var viewer_t: int = TeamManager.get_local_human_team() if TeamManager != null else int(Unit.Team.PLAYER)
	var active_gatherers: int = get_assigned_count(viewer_t if viewer_t >= 0 else -1)
	var cap: int = get_effective_max_harvesters(viewer_t)
	var sat_col: Color = get_saturation_color(active_gatherers, cap)
	var deposit_stats: Array[Dictionary] = [
		{"label": "Resource", "value": "Rich Silica" if (is_silica and is_high_yield) else ("Dense Biomass" if is_high_yield else ("Silica" if is_silica else "Biomass"))},
		{"label": "Remaining", "value": "%s / %s (%d%%)" % [fmt_rem, fmt_max, pct]},
		{"label": "Harvest", "value": "Automated Harvester" if is_silica else "Direct Worker Gather"},
		{"label": "Saturation", "value": "%d / %d Harvesters" % [active_gatherers, cap], "color": sat_col},
	]
	if is_high_yield:
		var bonus_pct: int = int(round((high_yield_multiplier - 1.0) * 100.0))
		deposit_stats.append({
			"label": "Yield Rate",
			"value": "+%d%% Load / Trip" % bonus_pct,
			"color": accent,
		})
	var sub_text: String = "HIGH-YIELD RESOURCE (+%d%%)" % int(round((high_yield_multiplier - 1.0) * 100.0)) if is_high_yield else ("SILICA VEIN" if is_silica else "BIOMASS DEPOSIT")
	return {
		"title": display_name,
		"subtitle": sub_text,
		"affiliation": &"neutral",
		"accent_color": accent,
		"ring_color": Color(1.0, 0.84, 0.28, 0.96),
		"show_hp_bar": false,
		"show_primary_bar": true,
		"primary_bar_label": "Remaining: %s / %s" % [fmt_rem, fmt_max],
		"primary_bar_value": float(remaining_amount),
		"primary_bar_max": float(maxi(1, max_amount)),
		"primary_bar_color": accent,
		"stats": deposit_stats,
		"is_commandable": false,
		"readonly_label": "READ-ONLY TELEMETRY",
	}


func _update_visuals() -> void:
	if is_vent:
		if amount_label != null:
			amount_label.visible = not is_occupied()
		return
	var ratio: float = clampf(float(remaining_amount) / float(maxi(1, max_amount)), 0.0, 1.0)
	if visual_root != null:
		var scale_factor: float = lerpf(0.65, 1.0, ratio)
		visual_root.scale = Vector2(scale_factor, scale_factor)
	if amount_label != null:
		amount_label.text = str(remaining_amount)
