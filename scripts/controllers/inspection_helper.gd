class_name InspectionHelper
extends RefCounted


static func get_inspection_data(entity: Node) -> Dictionary:
	var base: Dictionary = _default_schema()
	if entity == null or not is_instance_valid(entity):
		return base
	if entity.has_method("get_inspection_data"):
		var raw: Variant = entity.call("get_inspection_data")
		if raw is Dictionary:
			var payload: Dictionary = raw
			for key: Variant in payload.keys():
				base[key] = payload[key]
			return base
	base["title"] = entity.name
	return base


static func format_number(value: int) -> String:
	var sign_prefix: String = "-" if value < 0 else ""
	var digits: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i: int in range(digits.length() - 1, -1, -1):
		if count > 0 and (count % 3) == 0:
			out = "," + out
		out = digits[i] + out
		count += 1
	return sign_prefix + out


static func _default_schema() -> Dictionary:
	var empty_stats: Array[Dictionary] = []
	var empty_lines: Array[String] = []
	return {
		"title": "Unknown Entity",
		"subtitle": "TELEMETRY",
		"affiliation": &"neutral",
		"accent_color": Color(0.32, 0.86, 0.94, 1.0),
		"ring_color": Color(0.32, 0.86, 0.94, 1.0),
		"show_hp_bar": false,
		"hp_current": 0.0,
		"hp_max": 0.0,
		"show_shield_bar": false,
		"shield_current": 0.0,
		"shield_max": 0.0,
		"show_primary_bar": false,
		"primary_bar_label": "",
		"primary_bar_value": 0.0,
		"primary_bar_max": 100.0,
		"primary_bar_color": Color(0.24, 0.94, 0.74, 1.0),
		"stats": empty_stats,
		"status_lines": empty_lines,
		"is_commandable": false,
		"readonly_label": "READ-ONLY TELEMETRY",
	}
