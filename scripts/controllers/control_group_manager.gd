class_name ControlGroupManager
extends RefCounted

var control_groups: Dictionary = {}
var _last_recall_group: int = -1
var _last_recall_time_ms: int = 0
var _owner_sc: SelectionController = null


func cleanup() -> void:
	_owner_sc = null


func assign(sc: SelectionController, group_num: int) -> void:
	if sc == null or group_num < 1 or group_num > 9:
		return
	_owner_sc = sc
	sc._prune_invalid_units()
	if not sc.selected_units.is_empty():
		control_groups[group_num] = sc.selected_units.duplicate()
		_watch_units(sc, sc.selected_units)
		sc._emit_control_groups_changed()
		return
	if not sc.selected_buildings.is_empty():
		control_groups[group_num] = sc.selected_buildings.duplicate()
		_watch_buildings(sc, sc.selected_buildings)
		sc._emit_control_groups_changed()


func append(sc: SelectionController, group_num: int) -> void:
	if sc == null or group_num < 1 or group_num > 9:
		return
	_owner_sc = sc
	sc._prune_invalid_units()
	if not sc.selected_units.is_empty():
		var group_units: Array[Unit] = get_pruned_units(sc, group_num)
		for unit: Unit in sc.selected_units:
			if not group_units.has(unit):
				group_units.append(unit)
		if not group_units.is_empty():
			control_groups[group_num] = group_units
			_watch_units(sc, group_units)
		sc._emit_control_groups_changed()
		return
	if not sc.selected_buildings.is_empty():
		var group_buildings: Array[Building] = get_pruned_buildings(sc, group_num)
		for b: Building in sc.selected_buildings:
			if not group_buildings.has(b):
				group_buildings.append(b)
		if not group_buildings.is_empty():
			control_groups[group_num] = group_buildings
			_watch_buildings(sc, group_buildings)
		sc._emit_control_groups_changed()


func remove(sc: SelectionController, group_num: int) -> void:
	if sc == null or group_num < 1 or group_num > 9 or not control_groups.has(group_num):
		return
	_owner_sc = sc
	sc._prune_invalid_units()
	var group_units: Array[Unit] = get_pruned_units(sc, group_num)
	if not group_units.is_empty():
		var remaining: Array[Unit] = []
		for unit: Unit in group_units:
			if not sc.selected_units.has(unit):
				remaining.append(unit)
		if remaining.is_empty():
			control_groups.erase(group_num)
		else:
			control_groups[group_num] = remaining
		sc._emit_control_groups_changed()
		return
	var group_buildings: Array[Building] = get_pruned_buildings(sc, group_num)
	if not group_buildings.is_empty():
		var rem_b: Array[Building] = []
		for b: Building in group_buildings:
			if not sc.selected_buildings.has(b):
				rem_b.append(b)
		if rem_b.is_empty():
			control_groups.erase(group_num)
		else:
			control_groups[group_num] = rem_b
		sc._emit_control_groups_changed()


func steal_assign(sc: SelectionController, group_num: int) -> void:
	if sc == null or group_num < 1 or group_num > 9:
		return
	_owner_sc = sc
	sc._prune_invalid_units()
	if not sc.selected_units.is_empty():
		_strip_from_other_groups(sc, group_num, sc.selected_units, [])
		control_groups[group_num] = sc.selected_units.duplicate()
		_watch_units(sc, sc.selected_units)
		sc._emit_control_groups_changed()
		return
	if not sc.selected_buildings.is_empty():
		_strip_from_other_groups(sc, group_num, [], sc.selected_buildings)
		control_groups[group_num] = sc.selected_buildings.duplicate()
		_watch_buildings(sc, sc.selected_buildings)
		sc._emit_control_groups_changed()


func steal_append(sc: SelectionController, group_num: int) -> void:
	if sc == null or group_num < 1 or group_num > 9:
		return
	_owner_sc = sc
	sc._prune_invalid_units()
	if not sc.selected_units.is_empty():
		_strip_from_other_groups(sc, group_num, sc.selected_units, [])
		var group_units: Array[Unit] = get_pruned_units(sc, group_num)
		for unit: Unit in sc.selected_units:
			if not group_units.has(unit):
				group_units.append(unit)
		if not group_units.is_empty():
			control_groups[group_num] = group_units
			_watch_units(sc, group_units)
		sc._emit_control_groups_changed()
		return
	if not sc.selected_buildings.is_empty():
		_strip_from_other_groups(sc, group_num, [], sc.selected_buildings)
		var group_buildings: Array[Building] = get_pruned_buildings(sc, group_num)
		for b: Building in sc.selected_buildings:
			if not group_buildings.has(b):
				group_buildings.append(b)
		if not group_buildings.is_empty():
			control_groups[group_num] = group_buildings
			_watch_buildings(sc, group_buildings)
		sc._emit_control_groups_changed()


func recall(sc: SelectionController, group_num: int, allow_double_tap_center: bool = true) -> void:
	if sc == null or group_num < 1 or group_num > 9:
		return
	_owner_sc = sc
	var group_units: Array[Unit] = get_pruned_units(sc, group_num)
	if not group_units.is_empty():
		control_groups[group_num] = group_units
		sc.cancel_ability_targeting()
		sc.cancel_attack_move_targeting()
		sc.cancel_patrol_targeting()
		sc._set_selected_buildings([])
		sc._set_inspected_entity(null)
		sc._set_selected_units(group_units)
		sc._emit_control_groups_changed()
		if allow_double_tap_center:
			var now_ms: int = Time.get_ticks_msec()
			if _last_recall_group == group_num and (now_ms - _last_recall_time_ms) <= SelectionController.DOUBLE_TAP_WINDOW_MS:
				sc._center_camera_on_units(group_units)
				_last_recall_group = -1
				_last_recall_time_ms = 0
			else:
				_last_recall_group = group_num
				_last_recall_time_ms = now_ms
		return

	var group_buildings: Array[Building] = get_pruned_buildings(sc, group_num)
	if not group_buildings.is_empty():
		control_groups[group_num] = group_buildings
		sc.cancel_ability_targeting()
		sc.cancel_overclock_targeting()
		sc.cancel_attack_move_targeting()
		sc.cancel_patrol_targeting()
		sc._set_selected_units([])
		sc._set_selected_buildings(group_buildings)
		sc._emit_control_groups_changed()
		if allow_double_tap_center:
			var now_b_ms: int = Time.get_ticks_msec()
			if _last_recall_group == group_num and (now_b_ms - _last_recall_time_ms) <= SelectionController.DOUBLE_TAP_WINDOW_MS:
				sc._center_camera_on_nodes(group_buildings)
				_last_recall_group = -1
				_last_recall_time_ms = 0
			else:
				_last_recall_group = group_num
				_last_recall_time_ms = now_b_ms
		return

	control_groups.erase(group_num)
	sc._emit_control_groups_changed()


func handle_key(sc: SelectionController, group_num: int, key_event: InputEventKey) -> void:
	if key_event.alt_pressed and key_event.shift_pressed:
		steal_append(sc, group_num)
	elif key_event.alt_pressed:
		steal_assign(sc, group_num)
	elif key_event.ctrl_pressed:
		assign(sc, group_num)
	elif key_event.shift_pressed:
		append(sc, group_num)
	else:
		recall(sc, group_num, true)


func get_key_group_num(key_event: InputEventKey) -> int:
	var code: Key = key_event.physical_keycode
	if code < KEY_1 or code > KEY_9:
		code = key_event.keycode
	if code >= KEY_1 and code <= KEY_9:
		return int(code - KEY_1) + 1
	return 0


func get_pruned_units(sc: SelectionController, group_num: int) -> Array[Unit]:
	var valid: Array[Unit] = []
	if sc == null or not control_groups.has(group_num):
		return valid
	var local_t: Unit.Team = sc._get_local_human_team_enum()
	var raw: Variant = control_groups[group_num]
	if raw is Array:
		for item: Variant in raw:
			if is_instance_valid(item) and item is Unit:
				var unit: Unit = item
				if not unit.is_dead and not unit.is_staffed and unit.team == local_t:
					valid.append(unit)
	return valid


func get_pruned_buildings(sc: SelectionController, group_num: int) -> Array[Building]:
	var valid: Array[Building] = []
	if sc == null or not control_groups.has(group_num):
		return valid
	var local_t: Unit.Team = sc._get_local_human_team_enum()
	var raw: Variant = control_groups[group_num]
	if raw is Array:
		for item: Variant in raw:
			if is_instance_valid(item) and item is Building:
				var b: Building = item
				if not b.is_destroyed and not b.is_queued_for_deletion() and b.team == local_t:
					valid.append(b)
	return valid


func get_summary(sc: SelectionController) -> Dictionary:
	var summary: Dictionary = {}
	for num: int in range(1, 10):
		if not control_groups.has(num):
			continue
		var group_units: Array[Unit] = get_pruned_units(sc, num)
		if not group_units.is_empty():
			control_groups[num] = group_units
			summary[num] = group_units.size()
			continue
		var group_buildings: Array[Building] = get_pruned_buildings(sc, num)
		if not group_buildings.is_empty():
			control_groups[num] = group_buildings
			summary[num] = group_buildings.size()
		else:
			control_groups.erase(num)
	return summary


func get_rich_summaries(sc: SelectionController) -> Dictionary:
	var out: Dictionary = {}
	if sc == null:
		return out
	for num: int in range(1, 10):
		if not control_groups.has(num):
			continue
		var group_units: Array[Unit] = get_pruned_units(sc, num)
		if not group_units.is_empty():
			control_groups[num] = group_units
			var lead_name: String = group_units[0].data.display_name if group_units[0].data != null else "Units"
			var active_u: bool = (sc.selected_units.size() == group_units.size() and not sc.selected_units.is_empty())
			if active_u:
				for gu: Unit in group_units:
					if not sc.selected_units.has(gu):
						active_u = false
						break
			out[num] = {
				"count": group_units.size(),
				"label": lead_name,
				"is_active": active_u,
				"is_building": false,
			}
			continue
		var group_buildings: Array[Building] = get_pruned_buildings(sc, num)
		if not group_buildings.is_empty():
			control_groups[num] = group_buildings
			var active_b: bool = (sc.selected_buildings.size() == group_buildings.size() and not sc.selected_buildings.is_empty())
			if active_b:
				for gb: Building in group_buildings:
					if not sc.selected_buildings.has(gb):
						active_b = false
						break
			out[num] = {
				"count": group_buildings.size(),
				"label": group_buildings[0].display_name,
				"is_active": active_b,
				"is_building": true,
			}
		else:
			control_groups.erase(num)
	return out


func clear(sc: SelectionController) -> void:
	control_groups.clear()
	if sc != null:
		sc._emit_control_groups_changed()


func _strip_from_other_groups(sc: SelectionController, exclude_group: int, units_to_strip: Array[Unit], buildings_to_strip: Array[Building]) -> void:
	for num: int in range(1, 10):
		if num == exclude_group or not control_groups.has(num):
			continue
		if not units_to_strip.is_empty():
			var group_units: Array[Unit] = get_pruned_units(sc, num)
			if not group_units.is_empty():
				var remaining: Array[Unit] = []
				for u: Unit in group_units:
					if not units_to_strip.has(u):
						remaining.append(u)
				if remaining.is_empty():
					control_groups.erase(num)
				else:
					control_groups[num] = remaining
		if not buildings_to_strip.is_empty():
			var group_buildings: Array[Building] = get_pruned_buildings(sc, num)
			if not group_buildings.is_empty():
				var rem_b: Array[Building] = []
				for b: Building in group_buildings:
					if not buildings_to_strip.has(b):
						rem_b.append(b)
				if rem_b.is_empty():
					control_groups.erase(num)
				else:
					control_groups[num] = rem_b


func _watch_units(sc: SelectionController, units: Array[Unit]) -> void:
	_owner_sc = sc
	for u: Unit in units:
		if is_instance_valid(u) and not u.is_dead:
			if not u.died.is_connected(_on_unit_removed):
				u.died.connect(_on_unit_removed)


func _watch_buildings(sc: SelectionController, buildings: Array[Building]) -> void:
	_owner_sc = sc
	for b: Building in buildings:
		if is_instance_valid(b) and not b.is_destroyed:
			if not b.destroyed.is_connected(_on_building_removed):
				b.destroyed.connect(_on_building_removed)


func _on_unit_removed(_unit: Unit) -> void:
	if _owner_sc != null and is_instance_valid(_owner_sc):
		_owner_sc._emit_control_groups_changed()


func _on_building_removed(_building: Building) -> void:
	if _owner_sc != null and is_instance_valid(_owner_sc):
		_owner_sc._emit_control_groups_changed()
