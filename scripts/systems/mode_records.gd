class_name ModeRecords
extends RefCounted

const RECORDS_PATH: String = "user://mode_records.cfg"

enum Medal {
	NONE = 0,
	BRONZE = 1,
	SILVER = 2,
	GOLD = 3,
}

static var _loaded: bool = false
static var _cfg: ConfigFile = null


static func _ensure_loaded() -> void:
	if _loaded and _cfg != null:
		return
	_cfg = ConfigFile.new()
	_cfg.load(RECORDS_PATH)
	_loaded = true


static func _save() -> void:
	if _cfg != null:
		_cfg.save(RECORDS_PATH)


static func _holdout_key(faction_id: StringName, difficulty: int) -> String:
	return "%s_d%d" % [String(faction_id), clampi(difficulty, 0, 2)]


static func get_holdout_best_wave(faction_id: StringName, difficulty: int) -> int:
	_ensure_loaded()
	return int(_cfg.get_value("holdout", _holdout_key(faction_id, difficulty), 0))


static func get_holdout_overall_best_wave(faction_id: StringName) -> int:
	_ensure_loaded()
	var best: int = 0
	for d: int in range(3):
		best = maxi(best, get_holdout_best_wave(faction_id, d))
	return best


static func record_holdout_wave(faction_id: StringName, difficulty: int, wave_cleared: int) -> bool:
	_ensure_loaded()
	var clamped_w: int = maxi(0, wave_cleared)
	if clamped_w <= 0:
		return false
	var key: String = _holdout_key(faction_id, difficulty)
	var prev: int = int(_cfg.get_value("holdout", key, 0))
	if clamped_w > prev:
		_cfg.set_value("holdout", key, clamped_w)
		_save()
		return true
	return false


static func get_gauntlet_record(drill_id: StringName) -> Dictionary:
	_ensure_loaded()
	var section: String = "gauntlet_" + String(drill_id)
	var medal: int = clampi(int(_cfg.get_value(section, "medal", Medal.NONE)), Medal.NONE, Medal.GOLD)
	var best_val: float = float(_cfg.get_value(section, "best_value", -1.0))
	return {
		"medal": medal,
		"best_value": best_val,
		"has_record": medal > Medal.NONE or best_val >= 0.0,
	}


static func record_gauntlet_result(
	drill_id: StringName,
	medal: int,
	score_or_time: float,
	lower_is_better: bool = true
) -> bool:
	_ensure_loaded()
	var section: String = "gauntlet_" + String(drill_id)
	var clamped_medal: int = clampi(medal, Medal.NONE, Medal.GOLD)
	if clamped_medal <= Medal.NONE:
		return false

	var prev_medal: int = clampi(int(_cfg.get_value(section, "medal", Medal.NONE)), Medal.NONE, Medal.GOLD)
	var prev_val: float = float(_cfg.get_value(section, "best_value", -1.0))

	var is_new_best: bool = false
	if clamped_medal > prev_medal:
		is_new_best = true
		_cfg.set_value(section, "medal", clamped_medal)
		_cfg.set_value(section, "best_value", score_or_time)
	elif clamped_medal == prev_medal:
		var better_val: bool = false
		if prev_val < 0.0:
			better_val = true
		elif lower_is_better:
			better_val = score_or_time < (prev_val - 0.01)
		else:
			better_val = score_or_time > (prev_val + 0.5)
		if better_val:
			is_new_best = true
			_cfg.set_value(section, "best_value", score_or_time)

	if is_new_best:
		_save()
	return is_new_best


static func get_medal_label(medal: int) -> String:
	match clampi(medal, Medal.NONE, Medal.GOLD):
		Medal.GOLD:
			return "GOLD"
		Medal.SILVER:
			return "SILVER"
		Medal.BRONZE:
			return "BRONZE"
		_:
			return "UNRATED"


static func get_medal_color(medal: int) -> Color:
	match clampi(medal, Medal.NONE, Medal.GOLD):
		Medal.GOLD:
			return Color(1.0, 0.84, 0.24, 1.0)
		Medal.SILVER:
			return Color(0.82, 0.90, 0.96, 1.0)
		Medal.BRONZE:
			return Color(0.88, 0.58, 0.34, 1.0)
		_:
			return Color(0.56, 0.66, 0.74, 0.85)
