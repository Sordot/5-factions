class_name AIBuildPlanner
extends RefCounted

## Faction-driven macro, prerequisite, counter-unit, and upgrade planner for SkirmishAICommander.
## Eliminates hardcoded faction IDs so any FactionData resource works automatically with AI commanders.

var faction: FactionData = null


func bind_faction(faction_data: FactionData) -> void:
	faction = faction_data


func get_building_for_role(role: StringName) -> BuildingData:
	if faction == null:
		return null
	var direct: BuildingData = faction.get_ai_building_for_role(role)
	if direct != null:
		return direct

	# Semantic fallback scan across faction.building_roster
	var primary_t1: BuildingData = null
	if role == &"counter_foundry":
		primary_t1 = get_building_for_role(&"barracks_t1")
	for b: BuildingData in faction.building_roster:
		if b == null:
			continue
		match role:
			&"hub":
				if b.is_hub():
					return b
			&"supply":
				if b.is_supply_provider and not b.is_hub():
					return b
			&"refinery":
				if b.is_dropoff and not b.is_hub():
					return b
			&"compute_hub":
				if b.requires_vent or b.max_staff_slots > 0:
					return b
			&"barracks_t1":
				if b.is_military_production and b.tech_tier == 1:
					return b
			&"counter_foundry":
				if b != primary_t1 and b.is_military_production and b.tech_tier == 1:
					return b
			&"heavy_t2":
				if b.is_military_production and b.tech_tier >= 2:
					return b
	return null


func get_power_provider_building() -> BuildingData:
	if faction == null:
		return null
	for b: BuildingData in faction.building_roster:
		if b != null and b.provides_power_grid and b.power_radius > 0.0:
			return b
	return null


func get_unit_for_role(role_tag: StringName) -> UnitData:
	if faction == null:
		return null
	for u: UnitData in faction.unit_roster:
		if u != null and u.has_tag(role_tag):
			return u
	for u: UnitData in faction.unit_roster:
		if u == null:
			continue
		if role_tag == &"worker" and u.can_gather and not u.auto_gather_on_spawn:
			return u
		if role_tag == &"harvester" and u.can_gather and u.auto_gather_on_spawn:
			return u
		if role_tag == &"engineer" and u.can_staff_compute:
			return u
	return null


func get_scout_unit_id() -> StringName:
	if faction != null and faction.ai_scout_unit_id != &"":
		return faction.ai_scout_unit_id
	var by_tag: UnitData = get_unit_for_role(&"scout")
	if by_tag != null:
		return by_tag.unit_type_id
	var flanker: UnitData = get_unit_for_role(&"flanker")
	return flanker.unit_type_id if flanker != null else &""


func get_salvage_unit_ids() -> Array[StringName]:
	if faction != null and not faction.ai_salvage_unit_ids.is_empty():
		return faction.ai_salvage_unit_ids
	var out: Array[StringName] = []
	var eng: UnitData = get_unit_for_role(&"engineer")
	if eng != null:
		out.append(eng.unit_type_id)
	var wrk: UnitData = get_unit_for_role(&"worker")
	if wrk != null:
		out.append(wrk.unit_type_id)
	return out


func is_breach_capable(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit) or unit.is_dead or unit.data == null:
		return false
	if faction != null and faction.ai_counter_units.has(&"BREACH"):
		var breach_list: Variant = faction.ai_counter_units[&"BREACH"]
		if breach_list is Array and (breach_list as Array).has(unit.get_unit_type_id()):
			return true
	return (
		unit.data.has_tag(&"anti_armor")
		or unit.data.has_tag(&"heavy")
		or unit.data.has_tag(&"siege")
		or unit.data.bonus_vs_armored > 0.0
		or unit.data.aoe_attack_radius > 0.0
	)


func are_prerequisites_met(bdata: BuildingData, econ: EconomyManager, team_id: int) -> bool:
	if bdata == null:
		return false
	var prereqs: Array[StringName] = bdata.get_prerequisite_ids()
	if prereqs.is_empty():
		return true
	if econ == null:
		return false
	for pid: StringName in prereqs:
		if not econ.has_constructed_building(team_id, pid):
			return false
	return true


func get_playstyle_key(playstyle_idx: int) -> StringName:
	if GameConfig != null:
		if playstyle_idx == int(GameConfig.AIPlaystyle.SWARM_RUSH):
			return &"swarm_rush"
		if playstyle_idx == int(GameConfig.AIPlaystyle.SYNTHETICS_TECH):
			return &"synthetics_tech"
	return &"balanced"


func choose_unit_for_building(
	bldg: Building,
	playstyle_idx: int,
	counter_posture: StringName,
	counter_strength: float,
	prod_counter: int
) -> UnitData:
	if bldg == null or bldg.trainable_unit_data.is_empty():
		return null

	var candidates: Array[UnitData] = []
	var weights: PackedFloat32Array = PackedFloat32Array()
	var total_weight: float = 0.0

	var style_key: StringName = get_playstyle_key(playstyle_idx)
	var style_map: Dictionary = {}
	if faction != null and faction.ai_playstyle_weights.has(style_key):
		var raw_style: Variant = faction.ai_playstyle_weights[style_key]
		if raw_style is Dictionary:
			style_map = raw_style as Dictionary

	var counter_list: Array = []
	if faction != null and counter_posture != &"NONE" and faction.ai_counter_units.has(counter_posture):
		var raw_cnt: Variant = faction.ai_counter_units[counter_posture]
		if raw_cnt is Array:
			counter_list = raw_cnt as Array

	for udata: UnitData in bldg.trainable_unit_data:
		if udata == null or not bldg.can_train_unit_data(udata):
			continue
		var uid: StringName = udata.unit_type_id
		var w: float = float(style_map.get(uid, 1.0))
		if w <= 0.0:
			w = 0.5
		if not counter_list.is_empty() and counter_strength > 0.0:
			var c_idx: int = counter_list.find(uid)
			if c_idx == 0:
				w += 2.6 * counter_strength
			elif c_idx == 1:
				w += 1.4 * counter_strength
			elif c_idx >= 2:
				w += 0.7 * counter_strength
		candidates.append(udata)
		weights.append(w)
		total_weight += w

	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]

	# Deterministic low-discrepancy selection across weights using golden-ratio fraction of prod_counter
	var frac: float = fposmod(float(prod_counter) * 0.61803398875, 1.0)
	var target_w: float = frac * total_weight
	var acc: float = 0.0
	for i: int in range(candidates.size()):
		acc += weights[i]
		if target_w <= acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


func choose_next_upgrade_for_building(bldg: Building) -> UpgradeData:
	if bldg == null or bldg.production_component == null:
		return null
	for upg: UpgradeData in bldg.researchable_upgrades:
		if upg != null and bldg.production_component.can_queue_upgrade(bldg, upg):
			return upg
	return null


func is_role_building(bldg: Building, role: StringName) -> bool:
	if bldg == null or bldg.is_destroyed:
		return false
	var expected: BuildingData = get_building_for_role(role)
	if expected != null:
		return bldg.building_type_id == expected.building_id
	match role:
		&"hub":
			return bldg.is_command_hub()
		&"supply":
			return bldg.bandwidth_provided > 0 and not bldg.is_command_hub()
		&"refinery":
			return bldg.is_resource_dropoff and not bldg.is_command_hub()
		&"compute_hub":
			return bldg.max_staff_slots > 0
		&"barracks_t1":
			return bldg.is_military_production_building() and bldg.get_tech_tier() == 1
		&"heavy_t2":
			return bldg.is_military_production_building() and bldg.get_tech_tier() >= 2
	return false
