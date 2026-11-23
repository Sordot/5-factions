class_name SubgroupHelper
extends RefCounted


static func build_subgroups(selected_units: Array[Unit]) -> Array[Dictionary]:
	var buckets: Dictionary = {}
	var order: Array[StringName] = []

	for item: Variant in selected_units:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item
		if unit.is_dead:
			continue
		var type_id: StringName = unit.get_unit_type_id()
		if not buckets.has(type_id):
			var empty_list: Array[Unit] = []
			buckets[type_id] = {
				"unit_type_id": type_id,
				"display_name": unit.data.display_name if unit.data != null else String(type_id),
				"data": unit.data,
				"units": empty_list,
			}
			order.append(type_id)
		var group_units: Array[Unit] = buckets[type_id]["units"]
		group_units.append(unit)

	# Deterministic priority order: clone_trooper / test_unit first, then alphabetical by unit_type_id.
	order.sort_custom(func(a: StringName, b: StringName) -> bool:
		var a_pri: bool = (a == &"clone_trooper" or a == &"test_unit")
		var b_pri: bool = (b == &"clone_trooper" or b == &"test_unit")
		if a_pri and not b_pri:
			return true
		if b_pri and not a_pri:
			return false
		return String(a) < String(b)
	)

	var result: Array[Dictionary] = []
	for type_id: StringName in order:
		result.append(buckets[type_id])
	return result


static func find_ability_by_hotkey(subgroup: Dictionary, hotkey: String) -> AbilityData:
	var data: UnitData = subgroup.get("data", null) as UnitData
	if data == null:
		return null
	var upper_key: String = hotkey.to_upper()
	for ability: AbilityData in data.abilities:
		if ability != null and ability.hotkey_label.to_upper() == upper_key:
			return ability
	return null


static func find_closest_ready_caster(subgroup_units: Array[Unit], ability: AbilityData, target_pos: Vector2) -> Unit:
	var best: Unit = null
	var best_dist_sq: float = INF
	for item: Variant in subgroup_units:
		if not is_instance_valid(item) or not (item is Unit):
			continue
		var unit: Unit = item
		if unit.is_dead or not unit.is_ability_ready(ability):
			continue
		var d_sq: float = unit.global_position.distance_squared_to(target_pos)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = unit
	return best


static func has_any_ready_caster(subgroup_units: Array[Unit], ability: AbilityData) -> bool:
	for item: Variant in subgroup_units:
		if is_instance_valid(item) and item is Unit:
			var unit: Unit = item
			if not unit.is_dead and unit.is_ability_ready(ability):
				return true
	return false
