extends Node

enum ControllerType {
	HUMAN = 0,
	AI = 1,
	NEUTRAL = 2,
}

const TEAM_NEUTRAL: int = -1
const MAX_TEAMS: int = 4

const DEFAULT_TEAM_PALETTES: Array = [
	{
		"primary": Color(0.20, 0.96, 0.86, 1.0),
		"accent": Color(0.28, 0.98, 0.62, 1.0),
		"shell": Color(0.90, 0.95, 0.98, 0.96),
		"shell_hi": Color(0.97, 0.99, 1.0, 0.98),
		"deck": Color(0.14, 0.22, 0.29, 0.98),
		"trim": Color(0.50, 0.64, 0.74, 1.0),
		"outline": Color(0.30, 0.96, 0.92, 0.92),
		"wire": Color(0.28, 0.96, 1.0, 0.88),
	},
	{
		"primary": Color(1.0, 0.32, 0.24, 1.0),
		"accent": Color(1.0, 0.66, 0.24, 1.0),
		"shell": Color(0.84, 0.78, 0.80, 0.96),
		"shell_hi": Color(0.95, 0.88, 0.88, 0.98),
		"deck": Color(0.20, 0.12, 0.14, 0.98),
		"trim": Color(0.54, 0.30, 0.32, 1.0),
		"outline": Color(1.0, 0.42, 0.32, 0.92),
		"wire": Color(1.0, 0.42, 0.32, 0.88),
	},
	{
		"primary": Color(0.76, 0.44, 1.0, 1.0),
		"accent": Color(1.0, 0.42, 0.86, 1.0),
		"shell": Color(0.88, 0.84, 0.95, 0.96),
		"shell_hi": Color(0.96, 0.92, 1.0, 0.98),
		"deck": Color(0.18, 0.13, 0.25, 0.98),
		"trim": Color(0.52, 0.38, 0.68, 1.0),
		"outline": Color(0.82, 0.52, 1.0, 0.92),
		"wire": Color(0.82, 0.52, 1.0, 0.88),
	},
	{
		"primary": Color(1.0, 0.82, 0.24, 1.0),
		"accent": Color(1.0, 0.94, 0.54, 1.0),
		"shell": Color(0.94, 0.91, 0.82, 0.96),
		"shell_hi": Color(1.0, 0.98, 0.90, 0.98),
		"deck": Color(0.22, 0.19, 0.11, 0.98),
		"trim": Color(0.64, 0.54, 0.30, 1.0),
		"outline": Color(1.0, 0.86, 0.36, 0.92),
		"wire": Color(1.0, 0.86, 0.36, 0.88),
	},
]

const FACTION_DIR_PATH: String = "res://resources/factions/"
const FACTION_MANIFEST_PATHS: Array = [
	"res://resources/factions/genesis_v2_faction.tres",
]

signal teams_reconfigured(mode: StringName)

var match_mode: StringName = &"player_vs_ai"
var team_configs: Dictionary = {}
var _factions: Dictionary = {}
var _faction_order: Array[StringName] = []


func _ready() -> void:
	_load_faction_registry()
	_validate_registered_factions()
	_setup_default_1v1()


func _load_faction_registry() -> void:
	_factions.clear()
	_faction_order.clear()
	var paths: Array[String] = []
	for raw_path: Variant in FACTION_MANIFEST_PATHS:
		var ps: String = String(raw_path)
		if not paths.has(ps):
			paths.append(ps)

	# Auto-discover additional FactionData .tres manifests dropped into resources/factions/
	var dir: DirAccess = DirAccess.open(FACTION_DIR_PATH)
	if dir != null:
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while not fname.is_empty():
			if not dir.current_is_dir() and fname.ends_with(".tres"):
				var full_p: String = FACTION_DIR_PATH + fname
				if not paths.has(full_p):
					paths.append(full_p)
			fname = dir.get_next()
		dir.list_dir_end()

	for path_str: String in paths:
		if not ResourceLoader.exists(path_str):
			continue
		var res: Resource = load(path_str)
		if res != null and res.get("faction_id") != null:
			var fid: StringName = res.get("faction_id") as StringName
			if fid != &"" and not _factions.has(fid):
				_factions[fid] = res
				_faction_order.append(fid)


func _validate_registered_factions() -> void:
	for fid: StringName in _faction_order:
		var res: Resource = _factions.get(fid, null) as Resource
		if res != null and res.has_method("validate"):
			var warnings: Array = res.call("validate") as Array
			for w: Variant in warnings:
				push_warning("FactionData.validate(): %s" % String(w))


func get_faction_data(faction_id: StringName) -> Resource:
	if _factions.is_empty():
		_load_faction_registry()
	if _factions.has(faction_id):
		return _factions[faction_id] as Resource
	if _factions.has(&"genesis_v2"):
		return _factions[&"genesis_v2"] as Resource
	if not _faction_order.is_empty():
		return _factions[_faction_order[0]] as Resource
	return null


func get_team_faction_data(team_id: int) -> FactionData:
	var fid: StringName = get_team_faction(team_id)
	return get_faction_data(fid) as FactionData


func get_playable_factions() -> Array[FactionData]:
	if _factions.is_empty():
		_load_faction_registry()
	var out: Array[FactionData] = []
	for fid: StringName in _faction_order:
		var res: Resource = _factions[fid] as Resource
		if res is FactionData and (res as FactionData).is_playable:
			out.append(res as FactionData)
	out.sort_custom(func(a: FactionData, b: FactionData) -> bool:
		return a.dossier_slot_number < b.dossier_slot_number
	)
	return out


func _setup_default_1v1() -> void:
	configure_match(&"player_vs_ai", [
		{
			"team_id": 0,
			"alliance_id": 0,
			"faction_id": &"genesis_v2",
			"controller_type": ControllerType.HUMAN,
			"display_name": "PLAYER // GENESIS_V2",
		},
		{
			"team_id": 1,
			"alliance_id": 1,
			"faction_id": &"genesis_v2",
			"controller_type": ControllerType.AI,
			"display_name": "AI-01 // GENESIS_V2",
		},
	])


func configure_match(mode: StringName, slot_configs: Array) -> void:
	match_mode = mode
	team_configs.clear()
	for raw_slot: Variant in slot_configs:
		if not (raw_slot is Dictionary):
			continue
		var cfg: Dictionary = raw_slot
		var tid: int = int(cfg.get("team_id", 0))
		if tid < 0 or tid >= MAX_TEAMS:
			continue
		var pal: Dictionary = DEFAULT_TEAM_PALETTES[tid % DEFAULT_TEAM_PALETTES.size()]
		var primary_col: Color = cfg.get("primary_color", pal["primary"]) as Color
		var accent_col: Color = cfg.get("accent_color", pal["accent"]) as Color
		var ctrl_type: int = int(cfg.get("controller_type", ControllerType.AI))
		var faction_id: StringName = cfg.get("faction_id", &"genesis_v2") as StringName
		var default_name: String = ("PLAYER // %s" % String(faction_id).to_upper()) if ctrl_type == ControllerType.HUMAN else ("AI-%02d // %s" % [tid + 1, String(faction_id).to_upper()])
		team_configs[tid] = {
			"team_id": tid,
			"alliance_id": int(cfg.get("alliance_id", tid)),
			"faction_id": faction_id,
			"controller_type": ctrl_type,
			"display_name": String(cfg.get("display_name", default_name)),
			"primary_color": primary_col,
			"accent_color": accent_col,
			"ai_difficulty": int(cfg.get("ai_difficulty", 1)),
			"ai_playstyle": int(cfg.get("ai_playstyle", 0)),
		}
	teams_reconfigured.emit(match_mode)


func configure_from_game_config() -> void:
	if GameConfig == null:
		_setup_default_1v1()
		return
	var faction_id: StringName = GameConfig.selected_faction_id
	var active_slots: Array[Dictionary] = GameConfig.get_active_slot_configs()
	if active_slots.is_empty():
		_setup_default_1v1()
		return

	var has_human: bool = false
	for slot: Dictionary in active_slots:
		if int(slot.get("controller_type", ControllerType.AI)) == ControllerType.HUMAN:
			has_human = true
			break

	var mode: StringName = &"player_vs_ai" if has_human else &"ai_vs_ai"
	var show_alliance: bool = active_slots.size() > 2
	var built: Array = []
	for slot: Dictionary in active_slots:
		var tid: int = int(slot.get("team_id", 0))
		var ally_id: int = int(slot.get("alliance_id", tid))
		var ctrl_type: int = int(slot.get("controller_type", ControllerType.AI))
		var slot_faction: StringName = slot.get("faction_id", faction_id) as StringName
		if slot_faction == &"":
			slot_faction = faction_id
		var fac_data: FactionData = get_faction_data(slot_faction) as FactionData
		var fac_tag: String = fac_data.short_code if (fac_data != null and not fac_data.short_code.is_empty()) else String(slot_faction).to_upper()
		var diff: int = int(slot.get("ai_difficulty", 1))
		var style: int = int(slot.get("ai_playstyle", 0))
		var ally_tag: String = " [%s]" % GameConfig.get_alliance_letter(ally_id) if show_alliance else ""
		var disp: String = ""
		if ctrl_type == ControllerType.HUMAN:
			disp = "PLAYER%s // %s" % [ally_tag, fac_tag]
		else:
			disp = "AI-%02d%s (%s • %s)" % [
				tid + 1,
				ally_tag,
				GameConfig.get_difficulty_label(diff),
				GameConfig.get_playstyle_label(style),
			]
		built.append({
			"team_id": tid,
			"alliance_id": ally_id,
			"faction_id": slot_faction,
			"controller_type": ctrl_type,
			"display_name": disp,
			"ai_difficulty": diff,
			"ai_playstyle": style,
		})
	configure_match(mode, built)


func get_alliance_letter(alliance_id: int) -> String:
	if GameConfig != null and GameConfig.has_method("get_alliance_letter"):
		return GameConfig.get_alliance_letter(alliance_id)
	const LETTERS: Array = ["A", "B", "C", "D"]
	return String(LETTERS[clampi(alliance_id, 0, LETTERS.size() - 1)])


func get_team_short_label(team_id: int, include_alliance: bool = true) -> String:
	if team_id == TEAM_NEUTRAL:
		return "NEUTRAL"
	var base: String = "P%d" % (team_id + 1)
	if team_configs.has(team_id):
		var ctrl: int = int((team_configs[team_id] as Dictionary).get("controller_type", ControllerType.AI))
		base = ("P%d" % (team_id + 1)) if ctrl == ControllerType.HUMAN else ("AI-%d" % (team_id + 1))
	if include_alliance and get_active_teams().size() > 2:
		return "%s [%s]" % [base, get_alliance_letter(get_team_alliance(team_id))]
	return base


func get_active_teams() -> Array[int]:
	var out: Array[int] = []
	for key: Variant in team_configs.keys():
		out.append(int(key))
	out.sort()
	if out.is_empty():
		out = [0, 1]
	return out


func is_active_team(team_id: int) -> bool:
	return team_id >= 0 and team_configs.has(team_id)


func get_team_alliance(team_id: int) -> int:
	if team_configs.has(team_id):
		return int((team_configs[team_id] as Dictionary).get("alliance_id", team_id))
	return team_id


func are_allies(team_a: int, team_b: int) -> bool:
	if team_a == TEAM_NEUTRAL or team_b == TEAM_NEUTRAL:
		return false
	if team_a == team_b:
		return true
	var a_ally: int = get_team_alliance(team_a)
	var b_ally: int = get_team_alliance(team_b)
	return a_ally >= 0 and a_ally == b_ally


func are_enemies(team_a: int, team_b: int) -> bool:
	if team_a == TEAM_NEUTRAL or team_b == TEAM_NEUTRAL:
		return false
	if team_a == team_b:
		return false
	return not are_allies(team_a, team_b)


func get_local_human_team() -> int:
	if match_mode == &"ai_vs_ai":
		return TEAM_NEUTRAL
	for tid: int in get_active_teams():
		var cfg: Dictionary = team_configs[tid]
		if int(cfg.get("controller_type", ControllerType.AI)) == ControllerType.HUMAN:
			return tid
	return TEAM_NEUTRAL


func is_spectator_mode() -> bool:
	return get_local_human_team() == TEAM_NEUTRAL


func is_team_controlled_by_local_human(team_id: int) -> bool:
	var human_team: int = get_local_human_team()
	return human_team >= 0 and team_id == human_team


func get_team_controller_type(team_id: int) -> int:
	if team_configs.has(team_id):
		return int((team_configs[team_id] as Dictionary).get("controller_type", ControllerType.AI))
	return ControllerType.NEUTRAL


func get_team_faction(team_id: int) -> StringName:
	if team_configs.has(team_id):
		return (team_configs[team_id] as Dictionary).get("faction_id", &"genesis_v2") as StringName
	return &"genesis_v2"


func get_team_display_name(team_id: int) -> String:
	if team_configs.has(team_id):
		return String((team_configs[team_id] as Dictionary).get("display_name", "TEAM %d" % team_id))
	if team_id == TEAM_NEUTRAL:
		return "NEUTRAL"
	return "TEAM %d" % team_id


func get_team_ai_difficulty(team_id: int) -> int:
	if team_configs.has(team_id):
		return int((team_configs[team_id] as Dictionary).get("ai_difficulty", 1))
	return 1


func get_team_ai_playstyle(team_id: int) -> int:
	if team_configs.has(team_id):
		return int((team_configs[team_id] as Dictionary).get("ai_playstyle", 0))
	return 0


func get_team_color(team_id: int) -> Color:
	if team_configs.has(team_id):
		return (team_configs[team_id] as Dictionary).get("primary_color", Color(0.20, 0.96, 0.86, 1.0)) as Color
	if team_id >= 0:
		var pal: Dictionary = DEFAULT_TEAM_PALETTES[team_id % DEFAULT_TEAM_PALETTES.size()]
		return pal["primary"] as Color
	return Color(0.68, 0.74, 0.80, 1.0)


func get_team_accent(team_id: int) -> Color:
	if team_configs.has(team_id):
		return (team_configs[team_id] as Dictionary).get("accent_color", Color(0.28, 0.98, 0.62, 1.0)) as Color
	if team_id >= 0:
		var pal: Dictionary = DEFAULT_TEAM_PALETTES[team_id % DEFAULT_TEAM_PALETTES.size()]
		return pal["accent"] as Color
	return Color(0.84, 0.88, 0.92, 1.0)


func get_team_palette(team_id: int) -> Dictionary:
	var idx: int = maxi(0, team_id) % DEFAULT_TEAM_PALETTES.size()
	var base: Dictionary = DEFAULT_TEAM_PALETTES[idx]
	return {
		"shell": base["shell"],
		"shell_hi": base["shell_hi"],
		"deck": base["deck"],
		"trim": base["trim"],
		"core": get_team_color(team_id),
		"core_alt": get_team_accent(team_id),
		"outline": base["outline"],
		"wire": base["wire"],
	}
