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

enum MatchMode {
	PLAYER_VS_AI = 0,
	AI_VS_AI = 1,
}

const MAP_SKIRMISH_01: String = "res://scenes/maps/skirmish_arena_01.tscn"
const MAP_SKIRMISH_02: String = "res://scenes/maps/skirmish_arena_02.tscn"
const MAP_SANDBOX_TESTBED: String = "res://scenes/test/milestone_0_test.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"

const PRESET_STANDARD: StringName = &"standard"
const PRESET_FAST_TECH: StringName = &"fast_tech"

var selected_faction_id: StringName = &"genesis_v2"
var selected_map_path: String = MAP_SKIRMISH_01
var match_mode: int = MatchMode.PLAYER_VS_AI
var aggro_ai_enabled: bool = true
var ai_difficulty: AIDifficulty = AIDifficulty.STANDARD
var ai_playstyle: AIPlaystyle = AIPlaystyle.BALANCED
var team0_ai_difficulty: int = AIDifficulty.STANDARD
var team0_ai_playstyle: int = AIPlaystyle.SWARM_RUSH
var team1_ai_difficulty: int = AIDifficulty.STANDARD
var team1_ai_playstyle: int = AIPlaystyle.SYNTHETICS_TECH
var resource_preset: StringName = PRESET_STANDARD
var configured_from_menu: bool = false

# Skirmish Lobby Mutators
var mutator_high_yield: bool = false
var mutator_no_fog: bool = false
var mutator_fast_build: bool = false


func get_yield_multiplier() -> float:
	return 2.0 if mutator_high_yield else 1.0


func get_build_speed_multiplier() -> float:
	return 2.0 if mutator_fast_build else 1.0


func get_active_mutator_labels() -> PackedStringArray:
	var labels: PackedStringArray = PackedStringArray()
	if mutator_high_yield:
		labels.append("2x YIELD")
	if mutator_no_fog:
		labels.append("NO FOG")
	if mutator_fast_build:
		labels.append("FAST BUILD")
	return labels


func get_active_mutators_summary() -> String:
	var labels: PackedStringArray = get_active_mutator_labels()
	return " • ".join(labels) if not labels.is_empty() else "None"


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


func get_map_label(path: String = "") -> String:
	var target: String = selected_map_path if path.is_empty() else path
	if target == MAP_SANDBOX_TESTBED:
		return "Sandbox Testbed"
	if target == MAP_SKIRMISH_02:
		return "Twin Causeway (Skirmish Arena 02)"
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


func is_spectator_mode() -> bool:
	return match_mode == MatchMode.AI_VS_AI


func set_match_config(
	map_path: String,
	aggro_enabled: bool,
	preset: StringName,
	faction_id: StringName = &"genesis_v2",
	difficulty: int = AIDifficulty.STANDARD,
	playstyle: int = AIPlaystyle.BALANCED,
	p_match_mode: int = MatchMode.PLAYER_VS_AI,
	p_team0_diff: int = -1,
	p_team0_style: int = -1,
	p_high_yield: bool = false,
	p_no_fog: bool = false,
	p_fast_build: bool = false
) -> void:
	selected_map_path = map_path if not map_path.is_empty() else MAP_SKIRMISH_01
	match_mode = clampi(p_match_mode, 0, 1)
	aggro_ai_enabled = true if match_mode == MatchMode.AI_VS_AI else aggro_enabled
	resource_preset = preset
	selected_faction_id = faction_id
	ai_difficulty = clampi(difficulty, 0, 2) as AIDifficulty
	ai_playstyle = clampi(playstyle, 0, 2) as AIPlaystyle
	team1_ai_difficulty = int(ai_difficulty)
	team1_ai_playstyle = int(ai_playstyle)
	if p_team0_diff >= 0:
		team0_ai_difficulty = clampi(p_team0_diff, 0, 2)
	if p_team0_style >= 0:
		team0_ai_playstyle = clampi(p_team0_style, 0, 2)
	mutator_high_yield = p_high_yield
	mutator_no_fog = p_no_fog
	mutator_fast_build = p_fast_build
	configured_from_menu = true
	if TeamManager != null:
		TeamManager.configure_from_game_config()
