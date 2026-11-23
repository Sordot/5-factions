class_name UpgradeData
extends Resource

@export var upgrade_id: StringName = &""
@export var display_name: String = "Upgrade"
@export_multiline var description: String = ""
@export var hotkey_label: String = ""
@export var biomass_cost: int = 0
@export var silica_cost: int = 0
@export var compute_cost: int = 0
@export var research_time: float = 12.0
@export var modifier_key: StringName = &""
@export var modifier_value: float = 0.0


func get_cost_dict() -> Dictionary:
	var costs: Dictionary = {}
	if biomass_cost > 0:
		costs[EconomyManager.RESOURCE_BIOMASS] = biomass_cost
	if silica_cost > 0:
		costs[EconomyManager.RESOURCE_SILICA] = silica_cost
	if compute_cost > 0:
		costs[EconomyManager.RESOURCE_COMPUTE] = compute_cost
	return costs


func get_cost_label() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if biomass_cost > 0:
		parts.append("%dB" % biomass_cost)
	if silica_cost > 0:
		parts.append("%dS" % silica_cost)
	if compute_cost > 0:
		parts.append("%dC" % compute_cost)
	return " / ".join(parts) if not parts.is_empty() else "Free"
