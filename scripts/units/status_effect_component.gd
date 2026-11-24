class_name StatusEffectComponent
extends Node

const EFFECT_ADRENAL_SURGE: StringName = &"adrenal_surge"
const EFFECT_STATIC_SLOW: StringName = &"static_slow"

signal effects_changed

var _effects: Dictionary = {}


func apply_adrenal_surge(duration: float, speed_bonus: float, attack_speed_bonus: float) -> void:
	if duration <= 0.0:
		return
	var existing: Dictionary = _effects.get(EFFECT_ADRENAL_SURGE, {})
	var next_dur: float = maxf(float(existing.get("remaining", 0.0)), duration)
	var next_spd: float = maxf(float(existing.get("move_speed_bonus", 0.0)), speed_bonus)
	var next_atk: float = maxf(float(existing.get("attack_speed_bonus", 0.0)), attack_speed_bonus)
	_effects[EFFECT_ADRENAL_SURGE] = {
		"id": EFFECT_ADRENAL_SURGE,
		"label": "Adrenal Surge",
		"is_buff": true,
		"remaining": next_dur,
		"duration": maxf(float(existing.get("duration", duration)), duration),
		"move_speed_bonus": next_spd,
		"attack_speed_bonus": next_atk,
		"damage_taken_mult": 1.0,
		"color": Color(0.28, 1.0, 0.72, 1.0),
	}
	effects_changed.emit()


func apply_slow_debuff(duration: float, move_penalty: float, attack_penalty: float) -> void:
	if duration <= 0.0:
		return
	var existing: Dictionary = _effects.get(EFFECT_STATIC_SLOW, {})
	var next_dur: float = maxf(float(existing.get("remaining", 0.0)), duration)
	var next_mv: float = clampf(maxf(float(existing.get("move_speed_penalty", 0.0)), move_penalty), 0.0, 0.75)
	var next_atk: float = clampf(maxf(float(existing.get("attack_speed_penalty", 0.0)), attack_penalty), 0.0, 0.75)
	_effects[EFFECT_STATIC_SLOW] = {
		"id": EFFECT_STATIC_SLOW,
		"label": "Static Disruption",
		"is_buff": false,
		"remaining": next_dur,
		"duration": maxf(float(existing.get("duration", duration)), duration),
		"move_speed_penalty": next_mv,
		"attack_speed_penalty": next_atk,
		"damage_taken_mult": 1.0,
		"color": Color(0.72, 0.44, 1.0, 1.0),
	}
	effects_changed.emit()


func apply_custom_effect(effect_id: StringName, duration: float, params: Dictionary = {}) -> void:
	if effect_id == &"" or duration <= 0.0:
		return
	var entry: Dictionary = params.duplicate()
	entry["id"] = effect_id
	entry["remaining"] = maxf(float((_effects.get(effect_id, {}) as Dictionary).get("remaining", 0.0)), duration)
	entry["duration"] = maxf(float((_effects.get(effect_id, {}) as Dictionary).get("duration", duration)), duration)
	if not entry.has("label"):
		entry["label"] = String(effect_id).capitalize()
	if not entry.has("is_buff"):
		entry["is_buff"] = true
	if not entry.has("damage_taken_mult"):
		entry["damage_taken_mult"] = 1.0
	_effects[effect_id] = entry
	effects_changed.emit()


func remove_effect(effect_id: StringName) -> void:
	if _effects.erase(effect_id):
		effects_changed.emit()


func clear_all() -> void:
	if not _effects.is_empty():
		_effects.clear()
		effects_changed.emit()


func tick(delta: float) -> bool:
	if _effects.is_empty():
		return false
	var expired: Array[StringName] = []
	for raw_id: Variant in _effects.keys():
		var eff_id: StringName = raw_id as StringName
		var entry: Dictionary = _effects[eff_id]
		var rem: float = maxf(0.0, float(entry.get("remaining", 0.0)) - delta)
		entry["remaining"] = rem
		if rem <= 0.0:
			expired.append(eff_id)
	if expired.is_empty():
		return false
	for eff_id: StringName in expired:
		_effects.erase(eff_id)
	effects_changed.emit()
	return true


func has_any_active() -> bool:
	return not _effects.is_empty()


func has_effect(effect_id: StringName) -> bool:
	return _effects.has(effect_id) and float((_effects[effect_id] as Dictionary).get("remaining", 0.0)) > 0.0


func get_effect_remaining(effect_id: StringName) -> float:
	if not _effects.has(effect_id):
		return 0.0
	return maxf(0.0, float((_effects[effect_id] as Dictionary).get("remaining", 0.0)))


func get_move_speed_multiplier() -> float:
	var mult: float = 1.0
	for raw_id: Variant in _effects.keys():
		var entry: Dictionary = _effects[raw_id]
		var bonus: float = float(entry.get("move_speed_bonus", 0.0))
		if bonus > 0.0:
			mult *= (1.0 + bonus)
		var penalty: float = float(entry.get("move_speed_penalty", 0.0))
		if penalty > 0.0:
			mult *= maxf(0.25, 1.0 - penalty)
	return clampf(mult, 0.25, 2.5)


func get_attack_speed_multiplier() -> float:
	var mult: float = 1.0
	for raw_id: Variant in _effects.keys():
		var entry: Dictionary = _effects[raw_id]
		var bonus: float = float(entry.get("attack_speed_bonus", 0.0))
		if bonus > 0.0:
			mult *= (1.0 + bonus)
		var penalty: float = float(entry.get("attack_speed_penalty", 0.0))
		if penalty > 0.0:
			mult *= maxf(0.35, 1.0 - penalty)
	return clampf(mult, 0.25, 2.5)


func get_damage_taken_multiplier() -> float:
	var mult: float = 1.0
	for raw_id: Variant in _effects.keys():
		var entry: Dictionary = _effects[raw_id]
		var dtm: float = float(entry.get("damage_taken_mult", 1.0))
		if not is_equal_approx(dtm, 1.0):
			mult *= dtm
	return clampf(mult, 0.2, 2.5)


func get_active_effects_summary() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw_id: Variant in _effects.keys():
		var entry: Dictionary = _effects[raw_id]
		out.append({
			"id": entry.get("id", raw_id),
			"label": String(entry.get("label", String(raw_id).capitalize())),
			"is_buff": bool(entry.get("is_buff", true)),
			"remaining": float(entry.get("remaining", 0.0)),
			"color": entry.get("color", Color(0.42, 0.96, 1.0, 1.0)),
		})
	return out
