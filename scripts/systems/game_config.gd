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

enum GameMode {
	SKIRMISH = 0,
	UPLINK_HOLDOUT = 1,
	MICRO_GAUNTLET = 2,
}

const MAP_SKIRMISH_01: String = "res://scenes/maps/skirmish_arena_01.tscn"
const MAP_SKIRMISH_02: String = "res://scenes/maps/skirmish_arena_02.tscn"
const MAP_SKIRMISH_03: String = "res://scenes/maps/skirmish_arena_03.tscn"
const MAP_SANDBOX_TESTBED: String = "res://scenes/test/milestone_0_test.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"

const MAP_CATALOG: Array = [
	{"path": MAP_SKIRMISH_01, "label": "Skirmish Arena 01 (1v1 Symmetric)", "max_players": 2},
	{"path": MAP_SKIRMISH_02, "label": "Twin Causeway (Skirmish Arena 02)", "max_players": 2},
	{"path": MAP_SKIRMISH_03, "label": "Quad Nexus (2–4P FFA / 2v2)", "max_players": 4},
	{"path": MAP_SANDBOX_TESTBED, "label": "Sandbox Testbed (Milestone 0)", "max_players": 2},
]

const PRESET_STANDARD: StringName = &"standard"
const PRESET_FAST_TECH: StringName = &"fast_tech"

const TEAM_PRESET_1V1: StringName = &"1v1"
const TEAM_PRESET_FFA: StringName = &"ffa"
const TEAM_PRESET_2V2: StringName = &"2v2"
const TEAM_PRESET_1V2: StringName = &"1v2"
const TEAM_PRESET_1V3: StringName = &"1v3"
const TEAM_PRESET_CUSTOM: StringName = &"custom"

const ALLIANCE_LETTERS: Array = ["A", "B", "C", "D"]
const UPLINK_VICTORY_DURATION: float = 180.0

const HOLDOUT_ENEMY_MIXED: StringName = &"mixed"
const DRILL_STUTTER_STEP: StringName = &"stutter_step_bulwarks"
const DRILL_SIEGE_BREACH: StringName = &"siege_line_breach"
const DRILL_OPTIMAL_BOOM: StringName = &"optimal_3min_boom"

const GAUNTLET_DRILLS: Array = [
	{
		"id": DRILL_STUTTER_STEP,
		"title": "Stutter-Step vs. Bulwarks",
		"tag": "60s Tactical Micro",
		"time_limit": 60.0,
		"scene_path": MAP_SANDBOX_TESTBED,
		"fixed_faction": &"genesis_v2",
		"enemy_faction": &"monolith_os",
		"lower_is_better": true,
		"summary": "Kite 5 Bulwarks with Clone Troopers, Adrenal Surge, Symbiotes & Lance-Rigs.",
		"thresholds": "GOLD <=32s (7+ alive) • SILVER <=45s (4+ alive) • BRONZE <=60s",
	},
	{
		"id": DRILL_SIEGE_BREACH,
		"title": "Siege-Line Breach",
		"tag": "90s Assault Micro",
		"time_limit": 90.0,
		"scene_path": MAP_SANDBOX_TESTBED,
		"fixed_faction": &"monolith_os",
		"enemy_faction": &"genesis_v2",
		"lower_is_better": true,
		"summary": "Breach barricades, shield-tank turrets/mortars, deploy Anvils & kill Nexus Vat.",
		"thresholds": "GOLD <=50s (5+ alive) • SILVER <=70s (3+ alive) • BRONZE <=90s",
	},
	{
		"id": DRILL_OPTIMAL_BOOM,
		"title": "Optimal 3-Minute Boom",
		"tag": "180s Macro Economy",
		"time_limit": 180.0,
		"scene_path": MAP_SKIRMISH_01,
		"fixed_faction": &"",
		"enemy_faction": &"monolith_os",
		"lower_is_better": false,
		"summary": "Maximize gathered resources, army value & Tier 2 tech in 3:00 with zero supply block.",
		"thresholds": "GOLD >=4,200 + T2 • SILVER >=3,000 • BRONZE >=1,800",
	},
]

# Milestone 3.5b: Alternate game mode state
var active_game_mode: GameMode = GameMode.SKIRMISH
var holdout_enemy_faction_id: StringName = &"monolith_os"
var holdout_difficulty: AIDifficulty = AIDifficulty.STANDARD
var selected_gauntlet_drill_id: StringName = DRILL_STUTTER_STEP

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

# Multi-player / team lobby state (Milestone 2.5)
var player_count: int = 2
var team_preset: StringName = TEAM_PRESET_1V1
var slot_configs: Array[Dictionary] = []

# Skirmish Lobby Mutators
var mutator_high_yield: bool = false
var mutator_no_fog: bool = false
var mutator_fast_build: bool = false
var uplink_victory_enabled: bool = true


func _ready() -> void:
	_ensure_default_slots()


func _ensure_default_slots() -> void:
	if slot_configs.size() == 4:
		return
	slot_configs = [
		{
			"team_id": 0,
			"alliance_id": 0,
			"controller_type": 0, # HUMAN
			"faction_id": selected_faction_id,
			"ai_difficulty": int(AIDifficulty.STANDARD),
			"ai_playstyle": int(AIPlaystyle.SWARM_RUSH),
		},
		{
			"team_id": 1,
			"alliance_id": 1,
			"controller_type": 1, # AI
			"faction_id": selected_faction_id,
			"ai_difficulty": int(AIDifficulty.STANDARD),
			"ai_playstyle": int(AIPlaystyle.BALANCED),
		},
		{
			"team_id": 2,
			"alliance_id": 2,
			"controller_type": 1, # AI
			"faction_id": selected_faction_id,
			"ai_difficulty": int(AIDifficulty.STANDARD),
			"ai_playstyle": int(AIPlaystyle.SWARM_RUSH),
		},
		{
			"team_id": 3,
			"alliance_id": 3,
			"controller_type": 1, # AI
			"faction_id": selected_faction_id,
			"ai_difficulty": int(AIDifficulty.STANDARD),
			"ai_playstyle": int(AIPlaystyle.SYNTHETICS_TECH),
		},
	]


func get_map_max_players(path: String = "") -> int:
	var target: String = selected_map_path if path.is_empty() else path
	for item: Dictionary in MAP_CATALOG:
		if String(item["path"]) == target:
			return int(item.get("max_players", 2))
	return 2


func get_valid_presets_for_count(count: int) -> Array[Dictionary]:
	match clampi(count, 2, 4):
		3:
			return [
				{"id": TEAM_PRESET_FFA, "label": "FFA (1v1v1)"},
				{"id": TEAM_PRESET_1V2, "label": "1v2 (Handicap)"},
				{"id": TEAM_PRESET_CUSTOM, "label": "Custom"},
			]
		4:
			return [
				{"id": TEAM_PRESET_FFA, "label": "FFA (4-Way)"},
				{"id": TEAM_PRESET_2V2, "label": "2v2 (Allied)"},
				{"id": TEAM_PRESET_1V3, "label": "1v3 (Boss)"},
				{"id": TEAM_PRESET_CUSTOM, "label": "Custom"},
			]
		_:
			return [
				{"id": TEAM_PRESET_1V1, "label": "1v1 Standard"},
				{"id": TEAM_PRESET_CUSTOM, "label": "Custom"},
			]


func get_preset_display_label(preset: StringName = &"") -> String:
	var p: StringName = team_preset if preset == &"" else preset
	match p:
		TEAM_PRESET_1V1:
			return "1v1"
		TEAM_PRESET_FFA:
			return "FFA (%dP)" % player_count
		TEAM_PRESET_2V2:
			return "2v2"
		TEAM_PRESET_1V2:
			return "1v2"
		TEAM_PRESET_1V3:
			return "1v3"
		_:
			return "Custom (%dP)" % player_count


func get_alliance_letter(alliance_id: int) -> String:
	var idx: int = clampi(alliance_id, 0, ALLIANCE_LETTERS.size() - 1)
	return String(ALLIANCE_LETTERS[idx])


func apply_team_preset(count: int, preset: StringName, target_slots: Array = []) -> void:
	_ensure_default_slots()
	var slots: Array = slot_configs if target_slots.is_empty() else target_slots
	var clamped_count: int = clampi(count, 2, 4)
	if target_slots.is_empty():
		player_count = clamped_count
		team_preset = preset
	if preset == TEAM_PRESET_CUSTOM:
		return
	match preset:
		TEAM_PRESET_1V1:
			if slots.size() >= 2:
				(slots[0] as Dictionary)["alliance_id"] = 0
				(slots[1] as Dictionary)["alliance_id"] = 1
		TEAM_PRESET_FFA:
			for i: int in range(mini(4, slots.size())):
				(slots[i] as Dictionary)["alliance_id"] = i
		TEAM_PRESET_2V2:
			# On Quad Nexus: Slots 0 (BL) & 2 (TL) share West flank (Team A); Slots 1 (TR) & 3 (BR) share East flank (Team B).
			if slots.size() >= 4:
				(slots[0] as Dictionary)["alliance_id"] = 0
				(slots[1] as Dictionary)["alliance_id"] = 1
				(slots[2] as Dictionary)["alliance_id"] = 0
				(slots[3] as Dictionary)["alliance_id"] = 1
		TEAM_PRESET_1V2:
			if slots.size() >= 3:
				(slots[0] as Dictionary)["alliance_id"] = 0
				(slots[1] as Dictionary)["alliance_id"] = 1
				(slots[2] as Dictionary)["alliance_id"] = 1
		TEAM_PRESET_1V3:
			if slots.size() >= 4:
				(slots[0] as Dictionary)["alliance_id"] = 0
				(slots[1] as Dictionary)["alliance_id"] = 1
				(slots[2] as Dictionary)["alliance_id"] = 1
				(slots[3] as Dictionary)["alliance_id"] = 1


func get_active_slot_configs() -> Array[Dictionary]:
	_ensure_default_slots()
	var max_p: int = get_map_max_players(selected_map_path)
	var count: int = clampi(player_count, 2, max_p)
	var out: Array[Dictionary] = []
	for i: int in range(count):
		var copy: Dictionary = (slot_configs[i] as Dictionary).duplicate(true)
		copy["team_id"] = i
		var slot_fac: StringName = copy.get("faction_id", selected_faction_id) as StringName
		copy["faction_id"] = slot_fac if slot_fac != &"" else selected_faction_id
		out.append(copy)
	return out


func has_opposing_alliances(slots: Array = [], count: int = -1) -> bool:
	_ensure_default_slots()
	var source: Array = slot_configs if slots.is_empty() else slots
	var limit: int = player_count if count < 0 else count
	limit = clampi(limit, 2, mini(4, source.size()))
	var alliances: Dictionary = {}
	for i: int in range(limit):
		var cfg: Dictionary = source[i] as Dictionary
		alliances[int(cfg.get("alliance_id", i))] = true
	return alliances.size() >= 2


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
	if uplink_victory_enabled:
		labels.append("UPLINK WIN (3m)")
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
	for item: Dictionary in MAP_CATALOG:
		if String(item["path"]) == target:
			return String(item["label"])
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


func set_lobby_config(
	map_path: String,
	p_player_count: int,
	p_team_preset: StringName,
	p_slot_configs: Array,
	p_aggro_enabled: bool,
	p_resource_preset: StringName,
	faction_id: StringName = &"genesis_v2",
	p_high_yield: bool = false,
	p_no_fog: bool = false,
	p_fast_build: bool = false,
	p_uplink_victory: bool = true
) -> void:
	_ensure_default_slots()
	selected_map_path = map_path if not map_path.is_empty() else MAP_SKIRMISH_01
	var max_p: int = get_map_max_players(selected_map_path)
	player_count = clampi(p_player_count, 2, max_p)
	team_preset = p_team_preset
	selected_faction_id = faction_id
	resource_preset = p_resource_preset

	var normalized: Array[Dictionary] = []
	for i: int in range(4):
		var src: Dictionary = (p_slot_configs[i] as Dictionary) if (i < p_slot_configs.size() and p_slot_configs[i] is Dictionary) else (slot_configs[i] as Dictionary)
		var slot_fac: StringName = src.get("faction_id", faction_id) as StringName
		if slot_fac == &"":
			slot_fac = faction_id
		normalized.append({
			"team_id": i,
			"alliance_id": clampi(int(src.get("alliance_id", i)), 0, 3),
			"controller_type": clampi(int(src.get("controller_type", 1)), 0, 1),
			"faction_id": slot_fac,
			"ai_difficulty": clampi(int(src.get("ai_difficulty", int(AIDifficulty.STANDARD))), 0, 2),
			"ai_playstyle": clampi(int(src.get("ai_playstyle", int(AIPlaystyle.BALANCED))), 0, 2),
		})
	slot_configs = normalized

	# Determine if any active slot is HUMAN; if none, auto-enter Spectator (AI vs AI) mode.
	var has_human: bool = false
	for i: int in range(player_count):
		if int(slot_configs[i]["controller_type"]) == 0:
			has_human = true
			break
	match_mode = MatchMode.PLAYER_VS_AI if has_human else MatchMode.AI_VS_AI
	aggro_ai_enabled = true if not has_human else p_aggro_enabled

	# Sync legacy convenience fields for backward compatibility
	team0_ai_difficulty = int(slot_configs[0]["ai_difficulty"])
	team0_ai_playstyle = int(slot_configs[0]["ai_playstyle"])
	team1_ai_difficulty = int(slot_configs[1]["ai_difficulty"])
	team1_ai_playstyle = int(slot_configs[1]["ai_playstyle"])
	ai_difficulty = team1_ai_difficulty as AIDifficulty
	ai_playstyle = team1_ai_playstyle as AIPlaystyle

	mutator_high_yield = p_high_yield
	mutator_no_fog = p_no_fog
	mutator_fast_build = p_fast_build
	uplink_victory_enabled = p_uplink_victory
	active_game_mode = GameMode.SKIRMISH
	configured_from_menu = true
	if TeamManager != null:
		TeamManager.configure_from_game_config()


func is_holdout_mode() -> bool:
	return active_game_mode == GameMode.UPLINK_HOLDOUT


func is_gauntlet_mode() -> bool:
	return active_game_mode == GameMode.MICRO_GAUNTLET


func is_special_mode() -> bool:
	return active_game_mode != GameMode.SKIRMISH


func get_gauntlet_drill_info(drill_id: StringName = &"") -> Dictionary:
	var target: StringName = selected_gauntlet_drill_id if drill_id == &"" else drill_id
	for entry: Dictionary in GAUNTLET_DRILLS:
		if (entry["id"] as StringName) == target:
			return entry
	return GAUNTLET_DRILLS[0] as Dictionary


func get_next_gauntlet_drill_id(drill_id: StringName = &"") -> StringName:
	var target: StringName = selected_gauntlet_drill_id if drill_id == &"" else drill_id
	for i: int in range(GAUNTLET_DRILLS.size()):
		if ((GAUNTLET_DRILLS[i] as Dictionary)["id"] as StringName) == target:
			var next_idx: int = (i + 1) % GAUNTLET_DRILLS.size()
			return (GAUNTLET_DRILLS[next_idx] as Dictionary)["id"] as StringName
	return DRILL_STUTTER_STEP


func set_holdout_config(
	player_faction_id: StringName,
	enemy_faction_id: StringName,
	difficulty: int = AIDifficulty.STANDARD
) -> void:
	_ensure_default_slots()
	active_game_mode = GameMode.UPLINK_HOLDOUT
	selected_map_path = MAP_SKIRMISH_01
	selected_faction_id = player_faction_id if player_faction_id != &"" else &"genesis_v2"
	holdout_enemy_faction_id = enemy_faction_id if enemy_faction_id != &"" else &"monolith_os"
	holdout_difficulty = clampi(difficulty, 0, 2) as AIDifficulty
	player_count = 2
	team_preset = TEAM_PRESET_1V1
	match_mode = MatchMode.PLAYER_VS_AI
	aggro_ai_enabled = false
	resource_preset = PRESET_STANDARD
	mutator_high_yield = false
	mutator_no_fog = false
	mutator_fast_build = false
	uplink_victory_enabled = false

	var resolved_enemy_fac: StringName = holdout_enemy_faction_id
	if resolved_enemy_fac == HOLDOUT_ENEMY_MIXED:
		resolved_enemy_fac = &"monolith_os" if selected_faction_id == &"genesis_v2" else &"genesis_v2"
	slot_configs[0] = {
		"team_id": 0,
		"alliance_id": 0,
		"controller_type": 0,
		"faction_id": selected_faction_id,
		"ai_difficulty": int(holdout_difficulty),
		"ai_playstyle": int(AIPlaystyle.BALANCED),
	}
	slot_configs[1] = {
		"team_id": 1,
		"alliance_id": 1,
		"controller_type": 1,
		"faction_id": resolved_enemy_fac,
		"ai_difficulty": int(holdout_difficulty),
		"ai_playstyle": int(AIPlaystyle.BALANCED),
	}
	configured_from_menu = true
	if TeamManager != null:
		TeamManager.configure_from_game_config()


func set_gauntlet_config(
	drill_id: StringName,
	player_faction_id: StringName = &"genesis_v2"
) -> void:
	_ensure_default_slots()
	var info: Dictionary = get_gauntlet_drill_info(drill_id)
	active_game_mode = GameMode.MICRO_GAUNTLET
	selected_gauntlet_drill_id = info["id"] as StringName
	selected_map_path = String(info["scene_path"])

	var fixed_fac: StringName = info.get("fixed_faction", &"") as StringName
	var resolved_player_fac: StringName = fixed_fac if fixed_fac != &"" else (player_faction_id if player_faction_id != &"" else &"genesis_v2")
	var resolved_enemy_fac: StringName = info.get("enemy_faction", &"monolith_os") as StringName
	if selected_gauntlet_drill_id == DRILL_OPTIMAL_BOOM:
		resolved_enemy_fac = &"monolith_os" if resolved_player_fac == &"genesis_v2" else &"genesis_v2"

	selected_faction_id = resolved_player_fac
	player_count = 2
	team_preset = TEAM_PRESET_1V1
	match_mode = MatchMode.PLAYER_VS_AI
	aggro_ai_enabled = false
	resource_preset = PRESET_STANDARD
	mutator_high_yield = false
	mutator_no_fog = (selected_gauntlet_drill_id != DRILL_OPTIMAL_BOOM)
	mutator_fast_build = false
	uplink_victory_enabled = false

	slot_configs[0] = {
		"team_id": 0,
		"alliance_id": 0,
		"controller_type": 0,
		"faction_id": resolved_player_fac,
		"ai_difficulty": int(AIDifficulty.STANDARD),
		"ai_playstyle": int(AIPlaystyle.BALANCED),
	}
	slot_configs[1] = {
		"team_id": 1,
		"alliance_id": 1,
		"controller_type": 1,
		"faction_id": resolved_enemy_fac,
		"ai_difficulty": int(AIDifficulty.STANDARD),
		"ai_playstyle": int(AIPlaystyle.BALANCED),
	}
	configured_from_menu = true
	if TeamManager != null:
		TeamManager.configure_from_game_config()


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
	p_fast_build: bool = false,
	p_uplink_victory: bool = true
) -> void:
	_ensure_default_slots()
	var is_spec: bool = (clampi(p_match_mode, 0, 1) == MatchMode.AI_VS_AI)
	var t0_d: int = clampi(p_team0_diff, 0, 2) if p_team0_diff >= 0 else team0_ai_difficulty
	var t0_s: int = clampi(p_team0_style, 0, 2) if p_team0_style >= 0 else team0_ai_playstyle
	var slots: Array[Dictionary] = []
	for i: int in range(4):
		slots.append((slot_configs[i] as Dictionary).duplicate(true))
	slots[0]["controller_type"] = 1 if is_spec else 0
	slots[0]["alliance_id"] = 0
	slots[0]["ai_difficulty"] = t0_d
	slots[0]["ai_playstyle"] = t0_s
	slots[1]["controller_type"] = 1
	slots[1]["alliance_id"] = 1
	slots[1]["ai_difficulty"] = clampi(difficulty, 0, 2)
	slots[1]["ai_playstyle"] = clampi(playstyle, 0, 2)
	set_lobby_config(
		map_path,
		2,
		TEAM_PRESET_1V1,
		slots,
		aggro_enabled,
		preset,
		faction_id,
		p_high_yield,
		p_no_fog,
		p_fast_build,
		p_uplink_victory
	)
