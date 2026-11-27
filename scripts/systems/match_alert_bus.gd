class_name MatchAlertBus
extends RefCounted

const ALERT_REGION_RADIUS: float = 300.0
const ALERT_DAMAGE_THROTTLE_S: float = 4.0
const MAX_RECENT_ALERTS: int = 3

var recent_alerts: Array[Dictionary] = []
var damage_alert_log: Array[Dictionary] = []
var event_dedupe_times: Dictionary = {}


func reset() -> void:
	recent_alerts.clear()
	damage_alert_log.clear()
	event_dedupe_times.clear()


func emit_tactical_event(
	mm: MatchManager,
	category: StringName,
	message: String,
	world_pos: Vector2,
	accent_color: Color = Color(0.28, 0.96, 0.92, 1.0),
	dedupe_key: String = ""
) -> void:
	if mm == null or mm.is_match_over or message.strip_edges().is_empty():
		return
	if not dedupe_key.is_empty():
		var now_s: float = float(Time.get_ticks_msec()) * 0.001
		if event_dedupe_times.has(dedupe_key) and (now_s - float(event_dedupe_times[dedupe_key])) < 2.2:
			return
		event_dedupe_times[dedupe_key] = now_s
	mm.tactical_event_logged.emit(category, message, world_pos, accent_color)


func push_tactical_alert(mm: MatchManager, world_pos: Vector2, alert_type: StringName, message: String = "") -> void:
	if mm == null or mm.is_match_over:
		return
	var normalized_type: StringName = alert_type
	match alert_type:
		&"damage", &"under_attack":
			normalized_type = &"under_attack"
		&"uplink", &"uplink_contested":
			normalized_type = &"uplink_contested"
		&"construction", &"upgrade", &"tech_complete":
			normalized_type = &"tech_complete"

	var now_s: float = float(Time.get_ticks_msec()) * 0.001
	if normalized_type == &"under_attack" or normalized_type == &"uplink_contested":
		# Spatial + temporal throttling: suppress duplicate alerts of same type within 300px for 4.0s
		var kept: Array[Dictionary] = []
		var r_sq: float = ALERT_REGION_RADIUS * ALERT_REGION_RADIUS
		for item: Dictionary in damage_alert_log:
			if now_s - float(item["time"]) < ALERT_DAMAGE_THROTTLE_S:
				kept.append(item)
				if item.get("type", &"") == normalized_type and (item["pos"] as Vector2).distance_squared_to(world_pos) <= r_sq:
					damage_alert_log = kept
					return
		kept.append({"pos": world_pos, "type": normalized_type, "time": now_s})
		damage_alert_log = kept

	var label: String = message
	if label.is_empty():
		match normalized_type:
			&"under_attack":
				label = "Forces Under Attack"
			&"uplink_contested":
				label = "Hyper-Uplink Alert"
			&"tech_complete":
				label = "Production / Tech Complete"
			_:
				label = "Tactical Alert"

	recent_alerts.push_front({
		"pos": world_pos,
		"category": normalized_type,
		"message": label,
		"time": now_s,
	})
	while recent_alerts.size() > MAX_RECENT_ALERTS:
		recent_alerts.pop_back()

	if AudioManager != null and AudioManager.has_method("play_tactical_alert"):
		AudioManager.play_tactical_alert(normalized_type)
		if normalized_type == &"under_attack" and AudioManager.has_method("notify_combat_activity"):
			AudioManager.call("notify_combat_activity", 0.85)

	mm.tactical_alert_triggered.emit(world_pos, normalized_type, label)
	mm.tactical_alert_recorded.emit(world_pos, label)


func get_recent_alerts() -> Array[Dictionary]:
	return recent_alerts
