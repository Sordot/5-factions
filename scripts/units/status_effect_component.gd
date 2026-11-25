class_name StatusEffectComponent
extends Node

## Modular, extensible status effect, gameplay tag, DoT/HoT, and damage-shield container.
## Tracks named timed/permanent gameplay tags, structured stat modifiers, periodic HP ticks,
## ability-block flags, and damage absorption barriers.

const PERIODIC_TICK_INTERVAL: float = 0.25

var _effects: Dictionary = {} # effect_id: StringName -> Dictionary
var _tags: Dictionary = {} # tag: StringName -> remaining: float (-1.0 = permanent)
var _periodic_acc: float = 0.0

var _shield_amount: float = 0.0
var _shield_remaining: float = -1.0
var _shield_label: String = "Barrier"


func apply_adrenal_surge(duration: float, speed_bonus: float, attack_speed_bonus: float) -> void:
	apply_effect(&"adrenal_surge", {
		"duration": duration,
		"label": "Adrenal Surge",
		"move_speed_mult": 1.0 + maxf(0.0, speed_bonus),
		"attack_speed_mult": 1.0 + maxf(0.0, attack_speed_bonus),
		"damage_dealt_mult": 1.0,
		"damage_taken_mult": 1.0,
	})


func apply_slow_debuff(duration: float, move_penalty: float, attack_penalty: float) -> void:
	apply_effect(&"static_slow", {
		"duration": duration,
		"label": "Static Slow",
		"move_speed_mult": clampf(1.0 - maxf(0.0, move_penalty), 0.20, 1.0),
		"attack_speed_mult": clampf(1.0 - maxf(0.0, attack_penalty), 0.25, 1.0),
		"damage_dealt_mult": 1.0,
		"damage_taken_mult": 1.0,
	})


func apply_effect(effect_id: StringName, config: Dictionary) -> void:
	if effect_id == &"":
		return
	var duration: float = float(config.get("duration", 0.0))
	var is_permanent: bool = duration < 0.0
	if not is_permanent and duration <= 0.0:
		return

	var prev_rem: float = 0.0
	if _effects.has(effect_id):
		prev_rem = float((_effects[effect_id] as Dictionary).get("remaining", 0.0))

	var move_mult: float = float(config.get("move_speed_mult", config.get("move_mult", 1.0)))
	var atk_mult: float = float(config.get("attack_speed_mult", config.get("attack_mult", 1.0)))
	var dmg_dealt: float = float(config.get("damage_dealt_mult", 1.0))
	var dmg_taken: float = float(config.get("damage_taken_mult", 1.0))
	var hp_per_sec: float = float(config.get("hp_per_sec", 0.0))
	var blocks_abilities: bool = bool(config.get("blocks_abilities", false))
	var source_attacker: Variant = config.get("source_attacker", null)
	var label_str: String = String(config.get("label", String(effect_id).replace("_", " ").capitalize()))

	_effects[effect_id] = {
		"id": effect_id,
		"label": label_str,
		"remaining": -1.0 if is_permanent else maxf(prev_rem, duration),
		"duration": -1.0 if is_permanent else duration,
		"move_mult": clampf(move_mult, 0.10, 4.0),
		"attack_mult": clampf(atk_mult, 0.10, 4.0),
		"damage_dealt_mult": clampf(dmg_dealt, 0.0, 5.0),
		"damage_taken_mult": clampf(dmg_taken, 0.0, 5.0),
		"hp_per_sec": hp_per_sec,
		"blocks_abilities": blocks_abilities,
		"source_attacker": source_attacker,
	}


func remove_effect(effect_id: StringName) -> void:
	_effects.erase(effect_id)


func add_tag(tag: StringName, duration: float = -1.0) -> void:
	if tag == &"":
		return
	if duration < 0.0:
		_tags[tag] = -1.0
	elif duration > 0.0:
		if _tags.has(tag) and float(_tags[tag]) < 0.0:
			return
		var prev: float = float(_tags.get(tag, 0.0))
		_tags[tag] = maxf(prev, duration)


func remove_tag(tag: StringName) -> void:
	_tags.erase(tag)


func has_tag(tag: StringName) -> bool:
	if tag == &"" or not _tags.has(tag):
		return false
	var rem: float = float(_tags[tag])
	return rem < 0.0 or rem > 0.0


func get_active_tags() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _tags.keys():
		var t: StringName = key as StringName
		if has_tag(t):
			out.append(t)
	return out


func add_damage_shield(amount: float, duration: float = -1.0, label: String = "Barrier") -> void:
	if amount <= 0.0:
		return
	_shield_amount = maxf(_shield_amount, amount)
	if duration < 0.0:
		_shield_remaining = -1.0
	elif duration > 0.0:
		if _shield_remaining >= 0.0:
			_shield_remaining = maxf(_shield_remaining, duration)
		elif _shield_amount <= amount:
			_shield_remaining = duration
	if not label.is_empty():
		_shield_label = label


func get_shield_amount() -> float:
	return maxf(0.0, _shield_amount)


func absorb_damage_shield(amount: float, _damage_type: StringName = &"generic") -> float:
	if amount <= 0.0 or _shield_amount <= 0.0:
		return amount
	var absorbed: float = minf(_shield_amount, amount)
	_shield_amount = maxf(0.0, _shield_amount - absorbed)
	if _shield_amount <= 0.001:
		_shield_amount = 0.0
		_shield_remaining = -1.0
	return maxf(0.0, amount - absorbed)


func clear_all() -> void:
	_effects.clear()
	_tags.clear()
	_shield_amount = 0.0
	_shield_remaining = -1.0
	_periodic_acc = 0.0


func tick(delta: float, owner_unit: Node = null) -> bool:
	var changed: bool = false

	# 1. Tick structured timed effects
	if not _effects.is_empty():
		var expired: Array[StringName] = []
		for key: Variant in _effects.keys():
			var eff: Dictionary = _effects[key]
			var rem: float = float(eff.get("remaining", 0.0))
			if rem >= 0.0:
				rem -= delta
				eff["remaining"] = rem
				if rem <= 0.0:
					expired.append(key as StringName)
		for key: StringName in expired:
			_effects.erase(key)
			changed = true

	# 2. Tick timed gameplay tags
	if not _tags.is_empty():
		var expired_tags: Array[StringName] = []
		for key: Variant in _tags.keys():
			var rem_t: float = float(_tags[key])
			if rem_t >= 0.0:
				rem_t -= delta
				_tags[key] = rem_t
				if rem_t <= 0.0:
					expired_tags.append(key as StringName)
		for t_key: StringName in expired_tags:
			_tags.erase(t_key)
			changed = true

	# 3. Tick timed damage shield
	if _shield_amount > 0.0 and _shield_remaining >= 0.0:
		_shield_remaining -= delta
		if _shield_remaining <= 0.0:
			_shield_amount = 0.0
			_shield_remaining = -1.0
			changed = true

	# 4. Tick periodic DoT / HoT effects at clean 0.25s intervals
	if owner_unit != null and is_instance_valid(owner_unit) and not _effects.is_empty():
		var has_periodic: bool = false
		for eff_val: Variant in _effects.values():
			if absf(float((eff_val as Dictionary).get("hp_per_sec", 0.0))) > 0.001:
				has_periodic = true
				break
		if has_periodic:
			_periodic_acc += delta
			while _periodic_acc >= PERIODIC_TICK_INTERVAL:
				_periodic_acc -= PERIODIC_TICK_INTERVAL
				_apply_periodic_hp_tick(owner_unit, PERIODIC_TICK_INTERVAL)
		else:
			_periodic_acc = 0.0
	else:
		_periodic_acc = 0.0

	return changed


func _apply_periodic_hp_tick(owner_unit: Node, tick_dt: float) -> void:
	if owner_unit == null or not is_instance_valid(owner_unit):
		return
	if owner_unit.has_method("is_alive") and not bool(owner_unit.call("is_alive")):
		return
	for eff_val: Variant in _effects.values():
		var eff: Dictionary = eff_val as Dictionary
		var rate: float = float(eff.get("hp_per_sec", 0.0))
		if absf(rate) <= 0.001:
			continue
		var delta_hp: float = rate * tick_dt
		if delta_hp > 0.0:
			if owner_unit.has_method("heal"):
				owner_unit.call("heal", delta_hp)
		else:
			if owner_unit.has_method("take_damage"):
				var raw_src: Variant = eff.get("source_attacker", null)
				var src_node: Node = raw_src as Node if (raw_src != null and is_instance_valid(raw_src) and raw_src is Node) else null
				owner_unit.call("take_damage", absf(delta_hp), src_node)
		if owner_unit.has_method("is_alive") and not bool(owner_unit.call("is_alive")):
			return


func has_any_active() -> bool:
	return not _effects.is_empty() or not _tags.is_empty() or _shield_amount > 0.0


func has_effect(effect_id: StringName) -> bool:
	if not _effects.has(effect_id):
		return false
	var rem: float = float((_effects[effect_id] as Dictionary).get("remaining", 0.0))
	return rem < 0.0 or rem > 0.0


func get_remaining_duration(effect_id: StringName) -> float:
	if not _effects.has(effect_id):
		return 0.0
	var rem: float = float((_effects[effect_id] as Dictionary).get("remaining", 0.0))
	return -1.0 if rem < 0.0 else maxf(0.0, rem)


func get_move_speed_multiplier() -> float:
	var mult: float = 1.0
	for eff: Variant in _effects.values():
		mult *= float((eff as Dictionary).get("move_mult", 1.0))
	return clampf(mult, 0.25, 2.5)


func get_attack_speed_multiplier() -> float:
	var mult: float = 1.0
	for eff: Variant in _effects.values():
		mult *= float((eff as Dictionary).get("attack_mult", 1.0))
	return clampf(mult, 0.25, 2.5)


func get_damage_dealt_multiplier() -> float:
	var mult: float = 1.0
	for eff: Variant in _effects.values():
		mult *= float((eff as Dictionary).get("damage_dealt_mult", 1.0))
	return clampf(mult, 0.0, 5.0)


func get_damage_taken_multiplier() -> float:
	var mult: float = 1.0
	for eff: Variant in _effects.values():
		mult *= float((eff as Dictionary).get("damage_taken_mult", 1.0))
	return clampf(mult, 0.25, 2.5)


func is_abilities_blocked() -> bool:
	for eff: Variant in _effects.values():
		if bool((eff as Dictionary).get("blocks_abilities", false)):
			return true
	return false


func get_active_effects_summary() -> Array[Dictionary]:
	var summary: Array[Dictionary] = []
	for key: Variant in _effects.keys():
		var eff: Dictionary = _effects[key]
		var rem: float = float(eff.get("remaining", 0.0))
		if rem < 0.0 or rem > 0.0:
			summary.append({
				"id": eff.get("id", key),
				"label": String(eff.get("label", String(key))),
				"remaining": rem,
				"duration": float(eff.get("duration", 1.0)),
			})
	if _shield_amount > 0.0:
		summary.append({
			"id": &"damage_shield",
			"label": "%s (%d)" % [_shield_label, int(round(_shield_amount))],
			"remaining": _shield_remaining,
			"duration": maxf(1.0, _shield_remaining),
		})
	return summary
