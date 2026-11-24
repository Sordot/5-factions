class_name AbilityData
extends Resource

enum TargetType {
	POINT_AOE,
	UNIT_TARGET,
	INSTANT,
	BUILD_PLACEMENT,
}

@export var ability_id: StringName = &""
@export var display_name: String = "Ability"
@export var hotkey_label: String = "Q"
@export var cooldown_duration: float = 5.0
@export var cast_range: float = 250.0
@export var target_type: TargetType = TargetType.POINT_AOE
@export var damage_or_value: float = 35.0
@export var aoe_radius: float = 64.0
@export var effect_duration: float = 0.0
@export var move_speed_modifier: float = 0.0
@export var attack_speed_modifier: float = 0.0
@export var effect_color: Color = Color(0.42, 0.88, 1.0, 0.95)
@export var cast_on_all_ready: bool = false
@export var allow_autocast: bool = false
@export var default_autocast: bool = false
@export_multiline var description: String = ""
@export var building_to_build: BuildingData = null
