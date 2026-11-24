extends Node

enum AIDifficulty {
	RELAXED,
	STANDARD,
	BRUTAL,
}

enum AIPlaystyle {
	BALANCED,
	SWARM_RUSH,
	SYNTHETICS_TECH,
}

const MAP_SKIRMISH_01: String = "res://scenes/maps/skirmish_arena_01.tscn"
const MAP_SANDBOX_TESTBED: String = "res://scenes/test/milestone_0_test.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"

const PRESET_STANDARD: StringName = &"standard"
const PRESET_FAST_TECH: StringName = &"fast_tech"

var selected_faction_id: StringName = &"genesis_v2"
var selected_map_path: String = MAP_SKIRMISH_01
var aggro_ai_enabled: bool = true
var ai_difficulty: AIDifficulty = AIDifficulty.STANDARD
var ai_playstyle: AIPlaystyle = AIPlaystyle.BALANCED
var resource_preset: StringName = PRESET_STANDARD
var configured_from_menu: bool = false


func get_starting_resources() -> Dictionary:
	if resource_preset == PRESET_FAST_TECH:
		return {
			"biomass": 1000,
			"silica": 500,
			"compute": 200,
		}
	return {
		"biomass": 200,
		"silica": 50,
		"compute": 0,
	}


func get_preset_label() -> String:
	if resource_preset == PRESET_FAST_TECH:
		return "Fast-Tech Test (1000 B / 500 S / 200 C)"
	return "Standard (200 B / 50 S)"


func get_map_label() -> String:
	if selected_map_path == MAP_SANDBOX_TESTBED:
		return "Sandbox Testbed"
	return "Skirmish Arena 01 (1v1 Symmetric)"


func get_difficulty_label(diff: int = -1) -> String:
	var resolved: int = int(ai_difficulty) if diff < 0 else diff
	match resolved:
		int(AIDifficulty.RELAXED):
			return "Relaxed"
		int(AIDifficulty.BRUTAL):
			return "Brutal"
		_:
			return "Standard"


func get_playstyle_label(style: int = -1) -> String:
	var resolved: int = int(ai_playstyle) if style < 0 else style
	match resolved:
		int(AIPlaystyle.SWARM_RUSH):
			return "Swarm Rush"
		int(AIPlaystyle.SYNTHETICS_TECH):
			return "Synthetics Tech"
		_:
			return "Balanced"


func set_match_config(
	map_path: String,
	aggro_enabled: bool,
	preset: StringName,
	faction_id: StringName = &"genesis_v2",
	difficulty: int = AIDifficulty.STANDARD,
	playstyle: int = AIPlaystyle.BALANCED
) -> void:
	selected_map_path = map_path if not map_path.is_empty() else MAP_SKIRMISH_01
	aggro_ai_enabled = aggro_enabled
	resource_preset = preset
	selected_faction_id = faction_id
	ai_difficulty = clampi(difficulty, 0, 2) as AIDifficulty
	ai_playstyle = clampi(playstyle, 0, 2) as AIPlaystyle
	configured_from_menu = true
