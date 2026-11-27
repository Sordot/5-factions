extends Node

const CELL_SIZE: float = 128.0
const INV_CELL_SIZE: float = 1.0 / CELL_SIZE

var _unit_buckets: Dictionary = {}
var _building_buckets: Dictionary = {}
var _barricade_buckets: Dictionary = {}
var _resource_buckets: Dictionary = {}
var _salvage_buckets: Dictionary = {}

var _unit_cells: Dictionary = {}
var _building_cells: Dictionary = {}
var _barricade_cells: Dictionary = {}
var _resource_cells: Dictionary = {}
var _salvage_cells: Dictionary = {}


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x * INV_CELL_SIZE)), int(floor(pos.y * INV_CELL_SIZE)))


func clear_all() -> void:
	_unit_buckets.clear()
	_building_buckets.clear()
	_barricade_buckets.clear()
	_resource_buckets.clear()
	_salvage_buckets.clear()
	_unit_cells.clear()
	_building_cells.clear()
	_barricade_cells.clear()
	_resource_cells.clear()
	_salvage_cells.clear()


func register_unit(unit: Node2D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var id: int = unit.get_instance_id()
	var cell: Vector2i = world_to_cell(unit.global_position)
	if _unit_cells.has(id):
		var prev_cell: Vector2i = _unit_cells[id]
		if prev_cell == cell:
			return
		_remove_from_bucket(_unit_buckets, prev_cell, unit)
	_add_to_bucket(_unit_buckets, cell, unit)
	_unit_cells[id] = cell


func update_unit(unit: Node2D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var id: int = unit.get_instance_id()
	var cell: Vector2i = world_to_cell(unit.global_position)
	if _unit_cells.has(id):
		var prev_cell: Vector2i = _unit_cells[id]
		if prev_cell == cell:
			return
		_remove_from_bucket(_unit_buckets, prev_cell, unit)
	_add_to_bucket(_unit_buckets, cell, unit)
	_unit_cells[id] = cell


func unregister_unit(unit: Node2D) -> void:
	if unit == null:
		return
	var id: int = unit.get_instance_id()
	if not _unit_cells.has(id):
		return
	var prev_cell: Vector2i = _unit_cells[id]
	_remove_from_bucket(_unit_buckets, prev_cell, unit)
	_unit_cells.erase(id)


func register_building(building: Node2D) -> void:
	_register_static(_building_buckets, _building_cells, building)


func unregister_building(building: Node2D) -> void:
	_unregister_static(_building_buckets, _building_cells, building)


func register_barricade(barricade: Node2D) -> void:
	_register_static(_barricade_buckets, _barricade_cells, barricade)


func unregister_barricade(barricade: Node2D) -> void:
	_unregister_static(_barricade_buckets, _barricade_cells, barricade)


func register_resource(res_node: Node2D) -> void:
	_register_static(_resource_buckets, _resource_cells, res_node)


func unregister_resource(res_node: Node2D) -> void:
	_unregister_static(_resource_buckets, _resource_cells, res_node)


func register_salvage(salvage_node: Node2D) -> void:
	_register_static(_salvage_buckets, _salvage_cells, salvage_node)


func unregister_salvage(salvage_node: Node2D) -> void:
	_unregister_static(_salvage_buckets, _salvage_cells, salvage_node)


func query_units_into(center: Vector2, radius: float, out_results: Array, filter_team: int = -99) -> void:
	out_results.clear()
	var safe_r: float = maxf(0.0, radius)
	# Expand both cell bounds AND distance check by max unit radius slack so edge-to-edge
	# queries across 128px cell borders never miss large units (Goliath / Arc-Lancer).
	var pad_r: float = safe_r + 36.0
	var pad_r_sq: float = pad_r * pad_r
	var min_c: Vector2i = world_to_cell(center - Vector2(pad_r, pad_r))
	var max_c: Vector2i = world_to_cell(center + Vector2(pad_r, pad_r))

	for cy: int in range(min_c.y, max_c.y + 1):
		for cx: int in range(min_c.x, max_c.x + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not _unit_buckets.has(key):
				continue
			var bucket: Array = _unit_buckets[key]
			var i: int = bucket.size() - 1
			while i >= 0:
				var item: Variant = bucket[i]
				if not is_instance_valid(item) or not (item is Unit):
					var last: int = bucket.size() - 1
					if i != last:
						bucket[i] = bucket[last]
					bucket.pop_back()
					i -= 1
					continue
				var u: Unit = item as Unit
				if u.is_dead or u.is_staffed or u.is_queued_for_deletion():
					i -= 1
					continue
				if filter_team != -99 and int(u.team) != filter_team:
					i -= 1
					continue
				if u.global_position.distance_squared_to(center) <= pad_r_sq:
					out_results.append(u)
				i -= 1
			if bucket.is_empty():
				_unit_buckets.erase(key)


func query_units_in_radius(center: Vector2, radius: float, filter_team: int = -99) -> Array[Unit]:
	var results: Array[Unit] = []
	query_units_into(center, radius, results, filter_team)
	return results


func query_buildings_in_radius(center: Vector2, radius: float, filter_team: int = -99) -> Array[Building]:
	var results: Array[Building] = []
	var safe_r: float = maxf(0.0, radius)
	# Buildings can have footprints up to ~64px radius; expand cell search by 1 cell margin.
	var search_r: float = safe_r + 72.0
	var min_c: Vector2i = world_to_cell(center - Vector2(search_r, search_r))
	var max_c: Vector2i = world_to_cell(center + Vector2(search_r, search_r))

	for cy: int in range(min_c.y, max_c.y + 1):
		for cx: int in range(min_c.x, max_c.x + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not _building_buckets.has(key):
				continue
			var bucket: Array = _building_buckets[key]
			var i: int = bucket.size() - 1
			while i >= 0:
				var item: Variant = bucket[i]
				if not is_instance_valid(item) or not (item is Building):
					var last: int = bucket.size() - 1
					if i != last:
						bucket[i] = bucket[last]
					bucket.pop_back()
					i -= 1
					continue
				var b: Building = item as Building
				if b.is_destroyed or b.is_queued_for_deletion():
					i -= 1
					continue
				if filter_team != -99 and int(b.team) != filter_team:
					i -= 1
					continue
				var eff_r: float = safe_r + b.footprint_radius + 16.0
				if b.global_position.distance_squared_to(center) <= eff_r * eff_r:
					results.append(b)
				i -= 1
			if bucket.is_empty():
				_building_buckets.erase(key)
	return results


func query_resources_in_radius(center: Vector2, radius: float, include_vents: bool = false) -> Array[ResourceNode]:
	var results: Array[ResourceNode] = []
	var safe_r: float = maxf(0.0, radius)
	var search_r: float = safe_r + 48.0
	var min_c: Vector2i = world_to_cell(center - Vector2(search_r, search_r))
	var max_c: Vector2i = world_to_cell(center + Vector2(search_r, search_r))

	for cy: int in range(min_c.y, max_c.y + 1):
		for cx: int in range(min_c.x, max_c.x + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not _resource_buckets.has(key):
				continue
			var bucket: Array = _resource_buckets[key]
			var i: int = bucket.size() - 1
			while i >= 0:
				var item: Variant = bucket[i]
				if not is_instance_valid(item) or not (item is ResourceNode):
					var last: int = bucket.size() - 1
					if i != last:
						bucket[i] = bucket[last]
					bucket.pop_back()
					i -= 1
					continue
				var rn: ResourceNode = item as ResourceNode
				if rn.is_depleted() or rn.is_queued_for_deletion():
					i -= 1
					continue
				if not include_vents and rn.is_vent:
					i -= 1
					continue
				var eff_r: float = safe_r + rn.collision_radius + 8.0
				if rn.global_position.distance_squared_to(center) <= eff_r * eff_r:
					results.append(rn)
				i -= 1
			if bucket.is_empty():
				_resource_buckets.erase(key)
	return results


func query_barricades_in_radius(center: Vector2, radius: float) -> Array[Node2D]:
	var results: Array[Node2D] = []
	var safe_r: float = maxf(0.0, radius)
	var search_r: float = safe_r + 84.0
	var min_c: Vector2i = world_to_cell(center - Vector2(search_r, search_r))
	var max_c: Vector2i = world_to_cell(center + Vector2(search_r, search_r))

	for cy: int in range(min_c.y, max_c.y + 1):
		for cx: int in range(min_c.x, max_c.x + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not _barricade_buckets.has(key):
				continue
			var bucket: Array = _barricade_buckets[key]
			var i: int = bucket.size() - 1
			while i >= 0:
				var item: Variant = bucket[i]
				if not is_instance_valid(item) or not (item is Node2D):
					var last: int = bucket.size() - 1
					if i != last:
						bucket[i] = bucket[last]
					bucket.pop_back()
					i -= 1
					continue
				var bar: Node2D = item as Node2D
				if bool(bar.get("is_destroyed")) or bar.is_queued_for_deletion():
					i -= 1
					continue
				var fp_r: float = float(bar.call("get_footprint_radius")) if bar.has_method("get_footprint_radius") else 56.0
				var eff_r: float = safe_r + fp_r + 12.0
				if bar.global_position.distance_squared_to(center) <= eff_r * eff_r:
					results.append(bar)
				i -= 1
			if bucket.is_empty():
				_barricade_buckets.erase(key)
	return results


func query_entities_in_radius(
	center: Vector2,
	radius: float,
	include_buildings: bool = true,
	include_barricades: bool = false
) -> Array[Node2D]:
	var results: Array[Node2D] = []
	for u: Unit in query_units_in_radius(center, radius):
		results.append(u)
	if include_buildings:
		for b: Building in query_buildings_in_radius(center, radius):
			results.append(b)
	if include_barricades:
		for bar: Node2D in query_barricades_in_radius(center, radius):
			results.append(bar)
	return results


func query_salvage_in_radius(center: Vector2, radius: float) -> Array[Node2D]:
	var results: Array[Node2D] = []
	var safe_r: float = maxf(0.0, radius)
	var min_c: Vector2i = world_to_cell(center - Vector2(safe_r, safe_r))
	var max_c: Vector2i = world_to_cell(center + Vector2(safe_r, safe_r))
	var r_sq: float = safe_r * safe_r

	for cy: int in range(min_c.y, max_c.y + 1):
		for cx: int in range(min_c.x, max_c.x + 1):
			var key: Vector2i = Vector2i(cx, cy)
			if not _salvage_buckets.has(key):
				continue
			var bucket: Array = _salvage_buckets[key]
			var i: int = bucket.size() - 1
			while i >= 0:
				var item: Variant = bucket[i]
				if not is_instance_valid(item) or not (item is Node2D):
					var last: int = bucket.size() - 1
					if i != last:
						bucket[i] = bucket[last]
					bucket.pop_back()
					i -= 1
					continue
				var sc: Node2D = item as Node2D
				if bool(sc.get("is_claimed")) or sc.is_queued_for_deletion():
					i -= 1
					continue
				if sc.global_position.distance_squared_to(center) <= r_sq:
					results.append(sc)
				i -= 1
			if bucket.is_empty():
				_salvage_buckets.erase(key)
	return results


func _register_static(buckets: Dictionary, cell_map: Dictionary, entity: Node2D) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var id: int = entity.get_instance_id()
	var cell: Vector2i = world_to_cell(entity.global_position)
	if cell_map.has(id):
		var prev_cell: Vector2i = cell_map[id]
		if prev_cell == cell:
			return
		_remove_from_bucket(buckets, prev_cell, entity)
	_add_to_bucket(buckets, cell, entity)
	cell_map[id] = cell


func _unregister_static(buckets: Dictionary, cell_map: Dictionary, entity: Node2D) -> void:
	if entity == null:
		return
	var id: int = entity.get_instance_id()
	if not cell_map.has(id):
		return
	var prev_cell: Vector2i = cell_map[id]
	_remove_from_bucket(buckets, prev_cell, entity)
	cell_map.erase(id)


func _add_to_bucket(buckets: Dictionary, cell: Vector2i, entity: Node2D) -> void:
	if not buckets.has(cell):
		buckets[cell] = [entity]
	else:
		var arr: Array = buckets[cell]
		if not arr.has(entity):
			arr.append(entity)


func _remove_from_bucket(buckets: Dictionary, cell: Vector2i, entity: Node2D) -> void:
	if not buckets.has(cell):
		return
	var arr: Array = buckets[cell]
	var idx: int = arr.find(entity)
	if idx != -1:
		var last: int = arr.size() - 1
		if idx != last:
			arr[idx] = arr[last]
		arr.pop_back()
	if arr.is_empty():
		buckets.erase(cell)
