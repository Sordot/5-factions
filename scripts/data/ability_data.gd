class_name AbilityData
extends Resource

enum TargetType {
	POINT_AOE,
	UNIT_TARGET,
	INSTANT,
}

@export var ability_id: StringName = &""
@export var display_name: String = "Ability"
@export var hotkey_label: String = "Q"
@export var cooldown_duration: float = 5.0
@export var cast_range: float = 250.0
@export var target_type: TargetType = TargetType.POINT_AOE
@export var damage_or_value: float = 35.0
@export var aoe_radius: float = 64.0
@export_multiline var description: String = ""
