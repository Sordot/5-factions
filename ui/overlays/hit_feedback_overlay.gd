class_name HitFeedbackOverlay
extends Node2D

## Batched, zero-churn diegetic hit feedback pip renderer (Milestone 3.5a).
## Fixed ring-buffer of 96 lightweight pips with per-entity throttling (>= 140 ms)
## visualizing shield absorption, armor-blunted hits, and anti-armor penetrations.

const MAX_PIPS: int = 96
const THROTTLE_MS: int = 140

const KIND_SHIELD_ABSORB: StringName = &"shield_absorb"
const KIND_ARMOR_BLUNTED: StringName = &"armor_blunted"
const KIND_ANTI_ARMOR: StringName = &"anti_armor"

var _pips: Array[Dictionary] = []
var _write_idx: int = 0
var _active_count: int = 0
var _throttle_map: Dictionary = {} # int(key) -> int(last_ticks_msec)
var _throttle_gc_timer: float = 0.0
var _cached_view_rect: Rect2 = Rect2()


func _ready() -> void:
	add_to_group("hit_feedback_overlay")
	z_index = 64
	_pips.resize(MAX_PIPS)
	for i: int in range(MAX_PIPS):
		_pips[i] = {"active": false}


func _refresh_view_rect() -> void:
	if not is_inside_tree():
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var cam: Camera2D = vp.get_camera_2d()
	if cam == null:
		_cached_view_rect = Rect2()
		return
	var vp_sz: Vector2 = vp.get_visible_rect().size / maxf(0.25, cam.zoom.x)
	_cached_view_rect = Rect2(cam.global_position - vp_sz * 0.5, vp_sz).grow(96.0)


func push_hit_pip(world_pos: Vector2, kind: StringName, value: int = 0, entity_id: int = 0) -> void:
	if SettingsManager != null and not SettingsManager.show_combat_hit_feedback:
		return
	if not _cached_view_rect.has_area():
		_refresh_view_rect()
	if _cached_view_rect.has_area() and not _cached_view_rect.has_point(world_pos):
		return

	var now_ms: int = Time.get_ticks_msec()
	var eff_throttle: int = 240 if _active_count >= 64 else (185 if _active_count >= 40 else THROTTLE_MS)
	if entity_id != 0:
		var k_code: int = 1 if kind == KIND_SHIELD_ABSORB else (2 if kind == KIND_ARMOR_BLUNTED else 3)
		var t_key: int = entity_id * 8 + k_code
		var last_ms: int = int(_throttle_map.get(t_key, -99999))
		if (now_ms - last_ms) < eff_throttle:
			return
		_throttle_map[t_key] = now_ms

	var dur: float = 0.38
	var rise: float = 14.0
	if kind == KIND_ARMOR_BLUNTED:
		dur = 0.36
		rise = 12.0
	elif kind == KIND_ANTI_ARMOR:
		dur = 0.42
		rise = 16.0

	# Slight horizontal jitter so simultaneous adjacent hits remain legible
	var jitter_x: float = float((now_ms + _write_idx * 37) % 15 - 7)
	var slot: Dictionary = _pips[_write_idx]
	if not bool(slot.get("active", false)):
		_active_count += 1
	slot["active"] = true
	slot["pos"] = world_pos + Vector2(jitter_x, -10.0)
	slot["kind"] = kind
	slot["value"] = value
	slot["elapsed"] = 0.0
	slot["duration"] = dur
	slot["rise"] = rise
	_write_idx = (_write_idx + 1) % MAX_PIPS
	queue_redraw()


func _process(delta: float) -> void:
	_refresh_view_rect()
	_throttle_gc_timer += delta
	if _throttle_gc_timer >= 4.0:
		_throttle_gc_timer = 0.0
		if _throttle_map.size() > 160:
			_throttle_map.clear()

	if _active_count <= 0:
		return

	var still_active: int = 0
	for i: int in range(MAX_PIPS):
		var p: Dictionary = _pips[i]
		if not bool(p.get("active", false)):
			continue
		var el: float = float(p["elapsed"]) + delta
		if el >= float(p["duration"]):
			p["active"] = false
		else:
			p["elapsed"] = el
			still_active += 1
	_active_count = still_active
	queue_redraw()


func _draw() -> void:
	if _active_count <= 0:
		return

	var cyan: Color = Color(0.220, 0.741, 0.973, 1.0) # #38BDF8
	var slate: Color = Color(0.580, 0.639, 0.722, 1.0) # #94A3B8
	var gold: Color = Color(1.0, 0.745, 0.180, 1.0) # #FFBE2E
	var white: Color = Color(0.96, 0.98, 1.0, 1.0)

	for i: int in range(MAX_PIPS):
		var p: Dictionary = _pips[i]
		if not bool(p.get("active", false)):
			continue
		var t: float = clampf(float(p["elapsed"]) / maxf(0.05, float(p["duration"])), 0.0, 1.0)
		var ease_out: float = 1.0 - (1.0 - t) * (1.0 - t)
		var fade: float = clampf(1.0 - maxf(0.0, (t - 0.35) / 0.65), 0.0, 1.0)
		var center: Vector2 = to_local(p["pos"] as Vector2) + Vector2(0.0, -float(p["rise"]) * ease_out)
		var kind: StringName = p["kind"] as StringName

		if kind == KIND_SHIELD_ABSORB:
			# Crisp cyan diamond shield-deflect glint + tiny '-' pip
			var r: float = lerpf(4.8, 3.6, t)
			var dia: PackedVector2Array = PackedVector2Array([
				center + Vector2(0.0, -r),
				center + Vector2(r, 0.0),
				center + Vector2(0.0, r),
				center + Vector2(-r, 0.0),
				center + Vector2(0.0, -r),
			])
			draw_polyline(dia, Color(cyan.r, cyan.g, cyan.b, 0.95 * fade), 1.7, true)
			draw_line(center + Vector2(-2.2, 0.0), center + Vector2(2.2, 0.0), Color(white.r, white.g, white.b, 0.92 * fade), 1.4, true)
		elif kind == KIND_ARMOR_BLUNTED:
			# Muted steel angled ricochet tick + subtle shield-chevron
			var sc: Color = Color(slate.r, slate.g, slate.b, 0.90 * fade)
			draw_polyline(PackedVector2Array([
				center + Vector2(-4.2, -1.0),
				center + Vector2(0.0, 3.0),
				center + Vector2(4.2, -1.0),
			]), sc, 1.8, true)
			draw_line(center + Vector2(-3.0, -3.5), center + Vector2(3.5, -6.5), Color(0.84, 0.88, 0.94, 0.72 * fade), 1.3, true)
		elif kind == KIND_ANTI_ARMOR:
			# Sharp gold 4-point armor-pierce diamond spark + bold upward chevron
			var gc: Color = Color(gold.r, gold.g, gold.b, 0.98 * fade)
			var sr: float = lerpf(5.8, 4.2, t)
			draw_line(center + Vector2(0.0, -sr), center + Vector2(0.0, sr), gc, 1.9, true)
			draw_line(center + Vector2(-sr, 0.0), center + Vector2(sr, 0.0), gc, 1.9, true)
			draw_polyline(PackedVector2Array([
				center + Vector2(-4.5, -2.5),
				center + Vector2(0.0, -7.2),
				center + Vector2(4.5, -2.5),
			]), Color(white.r, white.g, white.b, 0.95 * fade), 1.8, true)
