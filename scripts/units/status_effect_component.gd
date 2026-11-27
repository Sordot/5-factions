class_name StatusEffectComponent
extends Node

## Modular, extensible status effect, gameplay tag, DoT/HoT, and multi-barrier shield container.
## Tracks named timed/permanent gameplay tags, structured stat modifiers with dirty-flag caching,
## composable stacking policies, dispel support, periodic HP ticks, ability-block flags,
## and prioritized damage absorption barriers.

const PERIODIC_TICK_INTERVAL: float = 0.25

var _effects: Dictionary = {} # effect_id: StringName -> Dictionary
var _tags: Dictionary = {} # tag: StringName -> remaining: float (-1.0 = permanent)
var _shields: Array[Dictionary] = [] # [{"id": StringName, "amount": float, "remaining": float, "duration": float, "label": String}]
var _periodic_acc: float = 0.0

# Dirty-flag cached aggregated modifiers (O(1) hot-path reads)
var _modifiers_dirty: bool = true
var _c_move_mult: float = 1.0
var _c_attack_mult: float = 1.0
var _c_dmg_dealt: float = 1.0
var _c_dmg_taken: float = 1.0
var _c_bonus_range: float = 0.0
var _c_beam_ramp_mult: float = 1.0
var _c_bonus_refract: int = 0
var _c_blocks_abilities: bool = false
var _c_armor_delta: float = 0.0
var _c_heal_received_mult: float = 1.0


func apply_adrenal_surge(duration: float, speed_bonus: float, attack_speed_bonus: float) -> void:
	apply_effect(&"adrenal_surge", {
		"duration": duration,
		"label": "Adrenal Surge",
		"category": &"buff",
		"move_speed_mult": 1.0 + maxf(0.0, speed_bonus),
		"attack_speed_mult": 1.0 + maxf(0.0, attack_speed_bonus),
		"damage_dealt_mult": 1.0,
		"damage_taken_mult": 1.0,
	})


func apply_slow_debuff(duration: float, move_penalty: float, attack_penalty: float) -> void:
	apply_effect(&"static_slow", {
		"duration": duration,
		"label": "Static Slow",
		"category": &"debuff",
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

	var move_mult: float = clampf(float(config.get("move_speed_mult", config.get("move_mult", 1.0))), 0.10, 4.0)
	var atk_mult: float = clampf(float(config.get("attack_speed_mult", config.get("attack_mult", 1.0))), 0.10, 4.0)
	var dmg_dealt: float = clampf(float(config.get("damage_dealt_mult", 1.0)), 0.0, 5.0)
	var dmg_taken: float = clampf(float(config.get("damage_taken_mult", 1.0)), 0.0, 5.0)
	var hp_per_sec: float = float(config.get("hp_per_sec", 0.0))
	var blocks_abilities: bool = bool(config.get("blocks_abilities", false))
	var source_attacker: Variant = config.get("source_attacker", null)
	var bonus_attack_range: float = maxf(0.0, float(config.get("bonus_attack_range", 0.0)))
	var beam_ramp_speed_mult: float = clampf(float(config.get("beam_ramp_speed_mult", 1.0)), 0.25, 4.0)
	var bonus_refract_bounces: int = maxi(0, int(config.get("bonus_refract_bounces", 0)))
	var tether_stacks: int = maxi(0, int(config.get("tether_stacks", 0)))
	var armor_delta: float = clampf(float(config.get("armor_delta", 0.0)), -0.75, 0.75)
	var heal_received_mult: float = clampf(float(config.get("heal_received_mult", 1.0)), 0.0, 4.0)
	var label_str: String = String(config.get("label", String(effect_id).replace("_", " ").capitalize()))
	var stack_policy: StringName = config.get("stack_policy", &"refresh") as StringName
	var max_stacks: int = maxi(1, int(config.get("max_stacks", 1)))

	var category: StringName = config.get("category", &"") as StringName
	if category == &"":
		if effect_id == &"optical_tether":
			category = &"aura"
		elif (
			move_mult < 0.999
			or atk_mult < 0.999
			or dmg_dealt < 0.999
			or dmg_taken > 1.001
			or hp_per_sec < -0.001
			or blocks_abilities
			or armor_delta < -0.001
			or heal_received_mult < 0.999
		):
			category = &"debuff"
		else:
			category = &"buff"

	var prev_rem: float = 0.0
	var stacks: int = 1
	if _effects.has(effect_id):
		var existing: Dictionary = _effects[effect_id] as Dictionary
		prev_rem = float(existing.get("remaining", 0.0))
		if stack_policy == &"strongest":
			var new_mag: float = _compute_effect_magnitude(move_mult, atk_mult, dmg_dealt, dmg_taken, hp_per_sec, bonus_attack_range, armor_delta, heal_received_mult)
			var old_mag: float = _compute_effect_magnitude(
				float(existing.get("move_mult", 1.0)),
				float(existing.get("attack_mult", 1.0)),
				float(existing.get("damage_dealt_mult", 1.0)),
				float(existing.get("damage_taken_mult", 1.0)),
				float(existing.get("hp_per_sec", 0.0)),
				float(existing.get("bonus_attack_range", 0.0)),
				float(existing.get("armor_delta", 0.0)),
				float(existing.get("heal_received_mult", 1.0))
			)
			if old_mag > new_mag + 0.001:
				existing["remaining"] = -1.0 if (is_permanent or prev_rem < 0.0) else maxf(prev_rem, duration)
				return
		elif stack_policy == &"stack":
			stacks = mini(max_stacks, maxi(1, int(existing.get("stacks", 1))) + 1)

	_effects[effect_id] = {
		"id": effect_id,
		"label": label_str,
		"category": category,
		"stack_policy": stack_policy,
		"stacks": stacks,
		"max_stacks": max_stacks,
		"remaining": -1.0 if is_permanent else maxf(prev_rem, duration),
		"duration": -1.0 if is_permanent else duration,
		"move_mult": move_mult,
		"attack_mult": atk_mult,
		"damage_dealt_mult": dmg_dealt,
		"damage_taken_mult": dmg_taken,
		"hp_per_sec": hp_per_sec,
		"blocks_abilities": blocks_abilities,
		"source_attacker": source_attacker,
		"bonus_attack_range": bonus_attack_range,
		"beam_ramp_speed_mult": beam_ramp_speed_mult,
		"bonus_refract_bounces": bonus_refract_bounces,
		"tether_stacks": tether_stacks,
		"armor_delta": armor_delta,
		"heal_received_mult": heal_received_mult,
	}
	_modifiers_dirty = true


func remove_effect(effect_id: StringName) -> void:
	if _effects.erase(effect_id):
		_modifiers_dirty = true


func dispel(category: StringName, max_count: int = 99) -> int:
	if category == &"" or max_count <= 0 or _effects.is_empty():
		return 0
	var to_remove: Array[StringName] = []
	for key: Variant in _effects.keys():
		if to_remove.size() >= max_count:
			break
		var eff: Dictionary = _effects[key] as Dictionary
		var eff_cat: StringName = eff.get("category", &"buff") as StringName
		if eff_cat == &"aura":
			continue
		if eff_cat == category or category == &"any":
			to_remove.append(key as StringName)
	for key_rm: StringName in to_remove:
		_effects.erase(key_rm)
	if not to_remove.is_empty():
		_modifiers_dirty = true
	return to_remove.size()


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


func add_damage_shield(amount: float, duration: float = -1.0, label: String = "Barrier", source_id: StringName = &"") -> void:
	if amount <= 0.0:
		return
	var lbl: String = label if not label.is_empty() else "Barrier"
	var sid: StringName = source_id if source_id != &"" else StringName(lbl.to_lower().replace(" ", "_"))
	var is_perm: bool = duration < 0.0
	for entry: Dictionary in _shields:
		if entry.get("id", &"") == sid:
			entry["amount"] = maxf(float(entry.get("amount", 0.0)), amount)
			if is_perm:
				entry["remaining"] = -1.0
				entry["duration"] = -1.0
			else:
				var prev_r: float = float(entry.get("remaining", 0.0))
				if prev_r >= 0.0:
					entry["remaining"] = maxf(prev_r, duration)
				entry["duration"] = maxf(float(entry.get("duration", duration)), duration)
			entry["label"] = lbl
			return
	_shields.append({
		"id": sid,
		"amount": amount,
		"remaining": -1.0 if is_perm else duration,
		"duration": -1.0 if is_perm else duration,
		"label": lbl,
	})


func get_shield_amount() -> float:
	var total: float = 0.0
	for entry: Dictionary in _shields:
		total += maxf(0.0, float(entry.get("amount", 0.0)))
	return total


func absorb_damage_shield(amount: float, _damage_type: StringName = &"generic") -> float:
	if amount <= 0.0 or _shields.is_empty():
		return amount
	# Shortest remaining timed barrier absorbs first; permanent barriers (< 0.0) absorb last.
	if _shields.size() > 1:
		_shields.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ra: float = float(a.get("remaining", -1.0))
			var rb: float = float(b.get("remaining", -1.0))
			var a_perm: bool = ra < 0.0
			var b_perm: bool = rb < 0.0
			if a_perm != b_perm:
				return not a_perm
			return ra < rb
		)
	var rem_dmg: float = amount
	var idx: int = 0
	while idx < _shields.size() and rem_dmg > 0.0:
		var entry: Dictionary = _shields[idx]
		var cur_amt: float = float(entry.get("amount", 0.0))
		if cur_amt <= 0.001:
			_shields.remove_at(idx)
			continue
		var absorbed: float = minf(cur_amt, rem_dmg)
		cur_amt -= absorbed
		rem_dmg = maxf(0.0, rem_dmg - absorbed)
		if cur_amt <= 0.001:
			_shields.remove_at(idx)
		else:
			entry["amount"] = cur_amt
			idx += 1
	return rem_dmg


func clear_all() -> void:
	_effects.clear()
	_tags.clear()
	_shields.clear()
	_periodic_acc = 0.0
	_modifiers_dirty = true


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
		if not expired.is_empty():
			_modifiers_dirty = true

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

	# 3. Tick timed damage barriers
	if not _shields.is_empty():
		var si: int = _shields.size() - 1
		while si >= 0:
			var s_entry: Dictionary = _shields[si]
			var s_rem: float = float(s_entry.get("remaining", -1.0))
			if s_rem >= 0.0:
				s_rem -= delta
				s_entry["remaining"] = s_rem
				if s_rem <= 0.0:
					_shields.remove_at(si)
					changed = true
			si -= 1

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
		var stacks: int = maxi(1, int(eff.get("stacks", 1)))
		var delta_hp: float = rate * float(stacks) * tick_dt
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
	return not _effects.is_empty() or not _tags.is_empty() or not _shields.is_empty()


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


func _recompute_modifiers_if_dirty() -> void:
	if not _modifiers_dirty:
		return
	_modifiers_dirty = false
	var mv: float = 1.0
	var atk: float = 1.0
	var dealt: float = 1.0
	var taken: float = 1.0
	var rng: float = 0.0
	var ramp: float = 1.0
	var refract: int = 0
	var blocked: bool = false
	var arm_d: float = 0.0
	var heal_m: float = 1.0

	for eff_val: Variant in _effects.values():
		var eff: Dictionary = eff_val as Dictionary
		var st: int = maxi(1, int(eff.get("stacks", 1)))
		var e_mv: float = float(eff.get("move_mult", 1.0))
		var e_atk: float = float(eff.get("attack_mult", 1.0))
		var e_dealt: float = float(eff.get("damage_dealt_mult", 1.0))
		var e_taken: float = float(eff.get("damage_taken_mult", 1.0))
		var e_ramp: float = float(eff.get("beam_ramp_speed_mult", 1.0))
		var e_heal: float = float(eff.get("heal_received_mult", 1.0))
		if st > 1:
			mv *= pow(e_mv, float(st))
			atk *= pow(e_atk, float(st))
			dealt *= pow(e_dealt, float(st))
			taken *= pow(e_taken, float(st))
			ramp *= pow(e_ramp, float(st))
			heal_m *= pow(e_heal, float(st))
		else:
			mv *= e_mv
			atk *= e_atk
			dealt *= e_dealt
			taken *= e_taken
			ramp *= e_ramp
			heal_m *= e_heal
		rng += maxf(0.0, float(eff.get("bonus_attack_range", 0.0))) * float(st)
		refract += maxi(0, int(eff.get("bonus_refract_bounces", 0))) * st
		arm_d += float(eff.get("armor_delta", 0.0)) * float(st)
		if bool(eff.get("blocks_abilities", false)):
			blocked = true

	_c_move_mult = clampf(mv, 0.25, 2.5)
	_c_attack_mult = clampf(atk, 0.25, 2.5)
	_c_dmg_dealt = clampf(dealt, 0.0, 5.0)
	_c_dmg_taken = clampf(taken, 0.25, 2.5)
	_c_bonus_range = rng
	_c_beam_ramp_mult = clampf(ramp, 0.25, 4.0)
	_c_bonus_refract = refract
	_c_blocks_abilities = blocked
	_c_armor_delta = clampf(arm_d, -0.75, 0.75)
	_c_heal_received_mult = clampf(heal_m, 0.0, 4.0)


func _compute_effect_magnitude(
	move_mult: float,
	atk_mult: float,
	dmg_dealt: float,
	dmg_taken: float,
	hp_per_sec: float,
	bonus_range: float,
	armor_delta: float,
	heal_mult: float
) -> float:
	return (
		absf(move_mult - 1.0)
		+ absf(atk_mult - 1.0)
		+ absf(dmg_dealt - 1.0)
		+ absf(dmg_taken - 1.0)
		+ absf(hp_per_sec) * 0.05
		+ bonus_range * 0.01
		+ absf(armor_delta)
		+ absf(heal_mult - 1.0)
	)


func get_move_speed_multiplier() -> float:
	_recompute_modifiers_if_dirty()
	return _c_move_mult


func get_attack_speed_multiplier() -> float:
	_recompute_modifiers_if_dirty()
	return _c_attack_mult


func get_damage_dealt_multiplier() -> float:
	_recompute_modifiers_if_dirty()
	return _c_dmg_dealt


func get_damage_taken_multiplier() -> float:
	_recompute_modifiers_if_dirty()
	return _c_dmg_taken


func get_bonus_attack_range() -> float:
	_recompute_modifiers_if_dirty()
	return _c_bonus_range


func get_beam_ramp_speed_multiplier() -> float:
	_recompute_modifiers_if_dirty()
	return _c_beam_ramp_mult


func get_bonus_refract_bounces() -> int:
	_recompute_modifiers_if_dirty()
	return _c_bonus_refract


func get_armor_delta() -> float:
	_recompute_modifiers_if_dirty()
	return _c_armor_delta


func get_heal_received_multiplier() -> float:
	_recompute_modifiers_if_dirty()
	return _c_heal_received_mult


func get_optical_tether_stacks() -> int:
	if not _effects.has(&"optical_tether"):
		return 0
	var eff: Dictionary = _effects[&"optical_tether"] as Dictionary
	var rem: float = float(eff.get("remaining", 0.0))
	if rem >= 0.0 and rem <= 0.0:
		return 0
	return maxi(0, int(eff.get("tether_stacks", 0)))


func is_abilities_blocked() -> bool:
	_recompute_modifiers_if_dirty()
	return _c_blocks_abilities


func get_active_effects_summary() -> Array[Dictionary]:
	var summary: Array[Dictionary] = []
	for key: Variant in _effects.keys():
		var eff: Dictionary = _effects[key]
		var rem: float = float(eff.get("remaining", 0.0))
		if rem < 0.0 or rem > 0.0:
			var st: int = maxi(1, int(eff.get("stacks", 1)))
			var base_lbl: String = String(eff.get("label", String(key)))
			var lbl: String = "%s x%d" % [base_lbl, st] if (st > 1 and not base_lbl.contains("x%d" % st)) else base_lbl
			summary.append({
				"id": eff.get("id", key),
				"label": lbl,
				"remaining": rem,
				"duration": float(eff.get("duration", 1.0)),
			})
	for s_entry: Dictionary in _shields:
		var amt: float = float(s_entry.get("amount", 0.0))
		if amt > 0.001:
			var s_rem: float = float(s_entry.get("remaining", -1.0))
			var s_dur: float = float(s_entry.get("duration", -1.0))
			summary.append({
				"id": s_entry.get("id", &"damage_shield"),
				"label": "%s (%d)" % [String(s_entry.get("label", "Barrier")), int(round(amt))],
				"remaining": s_rem,
				"duration": maxf(1.0, s_dur if s_dur > 0.0 else s_rem),
			})
	return summary
