class_name TechTreeOverlay
extends CanvasLayer

signal closed

@onready var root_control: Control = %RootControl
@onready var subtitle_label: Label = %SubtitleLabel
@onready var btn_close: Button = %BtnClose
@onready var columns_row: HBoxContainer = %ColumnsRow

var _tracked_team: int = 0
var _refresh_timer: float = 0.0


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("tech_tree_overlay")
	if TeamManager != null:
		var human_team: int = TeamManager.get_local_human_team()
		_tracked_team = human_team if human_team >= 0 else 0
	if btn_close != null:
		btn_close.pressed.connect(close_overlay)
	if SettingsManager != null:
		SettingsManager.refresh_mouse_mode()
	_rebuild_tree()


func _exit_tree() -> void:
	if SettingsManager != null:
		SettingsManager.call_deferred("refresh_mouse_mode")


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= 0.5:
		_refresh_timer = 0.0
		_rebuild_tree()


func _input(event: InputEvent) -> void:
	if not visible or event.is_echo():
		return
	if event.is_action_pressed("cmd_cancel") or event.is_action_pressed("ui_toggle_tech_tree"):
		get_viewport().set_input_as_handled()
		close_overlay()


func close_overlay() -> void:
	if AudioManager != null:
		AudioManager.play_ui_click()
	closed.emit()
	queue_free()


func _rebuild_tree() -> void:
	if columns_row == null or not is_inside_tree():
		return
	for child: Node in columns_row.get_children():
		child.queue_free()

	var econ: EconomyManager = get_tree().get_first_node_in_group("economy_manager") as EconomyManager
	var hk: String = SettingsManager.get_action_display_label(&"ui_toggle_tech_tree", true) if SettingsManager != null else "U"
	if btn_close != null:
		btn_close.text = ("Close (%s)" % hk) if not hk.is_empty() else "Close"
	if subtitle_label != null:
		var team_tag: String = TeamManager.get_team_display_name(_tracked_team) if TeamManager != null else "PLAYER // GENESIS_V2"
		subtitle_label.text = "Tracking: %s  •  Owned structures & researched tech highlighted live  •  Press %s or Esc to close" % [team_tag, hk if not hk.is_empty() else "Esc"]

	var tiers: Array = [
		{
			"header": "TIER 0 // CORE & ECONOMY",
			"accent": Color(0.28, 0.96, 0.86, 1.0),
			"nodes": [
				{
					"id": &"nexus_vat",
					"name": "Nexus Vat",
					"cost": "Core Hub  •  +10 BW",
					"prereq": "",
					"units": [
						"Worker Drone (50B) — Biomass Gather / Build / Repair Bldgs",
						"Silica Harvester (75B) — Automated Silica Mining",
						"Systems Engineer (75B/25S) — Staff Mainframe / Repair Heavy",
					],
					"upgrades": [],
				},
				{
					"id": &"synapse_pylon",
					"name": "Synapse Pylon",
					"cost": "100B  •  +10 Bandwidth",
					"prereq": "",
					"units": ["Expands active unit Bandwidth supply cap"],
					"upgrades": [],
				},
				{
					"id": &"silica_condenser",
					"name": "Silica Condenser",
					"cost": "75B  •  Silica Drop-Off",
					"prereq": "",
					"units": ["Trains Silica Harvesters & refines Silica Veins"],
					"upgrades": [],
				},
				{
					"id": &"wetware_mainframe",
					"name": "Wetware Mainframe",
					"cost": "100B / 50S  •  Compute Vent",
					"prereq": "Build on Compute Vent",
					"units": ["Staff up to 2 Engineers (+5 Compute / 3s each)"],
					"upgrades": [],
				},
			],
		},
		{
			"header": "TIER 1 // SWARM & COUNTERS",
			"accent": Color(0.98, 0.78, 0.30, 1.0),
			"nodes": [
				{
					"id": &"cloning_vat",
					"name": "Cloning Vat",
					"cost": "150B / 50S  •  x2 Batch (1.75x Cost)",
					"prereq": "Unlocks Tier-2 Synthetics Fabricator",
					"units": [
						"Clone Trooper x2 [Light] — Pulse Rifle + Adrenal Surge (Q)",
						"Stinger x2 [Light] — Fast Flanker + Acid Cleave",
						"Symbiote x2 [Light] — Passive Heal Aura (+2 HP/s)",
					],
					"upgrades": [
						{"id": &"batch_efficiency", "label": "Batch Efficiency (100B/100S) — Batch cost 1.75x -> 1.50x"},
						{"id": &"adrenal_potency", "label": "Adrenal Potency (120B/80S) — +2s & +15% Atk Spd"},
					],
				},
				{
					"id": &"calibration_foundry",
					"name": "Calibration Foundry",
					"cost": "125B / 75S  •  Tier-1.5 Counter Tech",
					"prereq": "",
					"units": [
						"Lance-Rig [Light] — High-Voltage Rail (+vs Armored / Barricades)",
						"Signal Jammer [Light] — Static Pulse AoE Slow (Q)",
					],
					"upgrades": [],
				},
			],
		},
		{
			"header": "TIER 2 // HEAVY SYNTHETICS",
			"accent": Color(0.42, 0.94, 1.0, 1.0),
			"nodes": [
				{
					"id": &"synthetics_fabricator",
					"name": "Synthetics Fabricator",
					"cost": "150B / 100S / 50C",
					"prereq": "Requires: Cloning Vat",
					"req_id": &"cloning_vat",
					"units": [
						"Goliath Frame [Heavy Synthetic] — Tank Armor + Seismic Slam (Q)",
						"Arc-Lancer [Heavy Synthetic] — Colossus Stride + Line Pierce Beam",
						"Chrysalis Mortar [Armored] — Long-Range AoE Splash (Min Range)",
					],
					"upgrades": [
						{"id": &"compute_overdrive", "label": "Compute Overdrive (100S/100C) — Goliath +20% Spd & +15% DR"},
					],
				},
			],
		},
	]

	for tier: Dictionary in tiers:
		var col_vbox: VBoxContainer = VBoxContainer.new()
		col_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col_vbox.add_theme_constant_override("separation", 8)

		var hdr: Label = Label.new()
		hdr.text = String(tier["header"])
		hdr.add_theme_font_size_override("font_size", 12)
		hdr.add_theme_color_override("font_color", tier["accent"] as Color)
		col_vbox.add_child(hdr)

		for node_def: Dictionary in tier["nodes"]:
			var card: PanelContainer = _build_tech_card(node_def, econ)
			col_vbox.add_child(card)

		columns_row.add_child(col_vbox)


func _build_tech_card(node_def: Dictionary, econ: EconomyManager) -> PanelContainer:
	var b_id: StringName = node_def["id"] as StringName
	var owned: bool = econ != null and econ.has_constructed_building(_tracked_team, b_id)
	var req_id: StringName = node_def.get("req_id", &"") as StringName
	var req_met: bool = req_id == &"" or (econ != null and econ.has_constructed_building(_tracked_team, req_id))

	var panel: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(2 if owned else 1)
	if owned:
		sb.bg_color = Color(0.06, 0.16, 0.19, 0.96)
		sb.border_color = Color(0.24, 0.98, 0.84, 0.95)
	elif not req_met:
		sb.bg_color = Color(0.08, 0.07, 0.09, 0.92)
		sb.border_color = Color(0.62, 0.36, 0.34, 0.72)
	else:
		sb.bg_color = Color(0.05, 0.09, 0.13, 0.94)
		sb.border_color = Color(0.26, 0.56, 0.68, 0.72)
	panel.add_theme_stylebox_override("panel", sb)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)

	var top: HBoxContainer = HBoxContainer.new()
	var name_lbl: Label = Label.new()
	name_lbl.text = String(node_def["name"])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.32, 1.0, 0.88, 1.0) if owned else Color(0.92, 0.98, 1.0, 1.0))
	top.add_child(name_lbl)

	var status_lbl: Label = Label.new()
	status_lbl.add_theme_font_size_override("font_size", 10)
	if owned:
		status_lbl.text = "[ONLINE]"
		status_lbl.add_theme_color_override("font_color", Color(0.28, 1.0, 0.68, 1.0))
	elif not req_met:
		status_lbl.text = "[LOCKED]"
		status_lbl.add_theme_color_override("font_color", Color(1.0, 0.46, 0.36, 0.95))
	else:
		status_lbl.text = "[AVAILABLE]"
		status_lbl.add_theme_color_override("font_color", Color(0.62, 0.82, 0.90, 0.85))
	top.add_child(status_lbl)
	vbox.add_child(top)

	var cost_lbl: Label = Label.new()
	cost_lbl.text = String(node_def["cost"])
	cost_lbl.add_theme_font_size_override("font_size", 10)
	cost_lbl.add_theme_color_override("font_color", Color(0.96, 0.82, 0.40, 0.95))
	vbox.add_child(cost_lbl)

	var prereq_str: String = String(node_def.get("prereq", ""))
	if not prereq_str.is_empty():
		var pr_lbl: Label = Label.new()
		pr_lbl.text = prereq_str
		pr_lbl.add_theme_font_size_override("font_size", 10)
		pr_lbl.add_theme_color_override("font_color", Color(0.46, 0.92, 0.96, 0.90) if req_met else Color(1.0, 0.56, 0.38, 0.95))
		vbox.add_child(pr_lbl)

	for u_line: Variant in node_def.get("units", []):
		var ul: Label = Label.new()
		ul.text = "• %s" % String(u_line)
		ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ul.add_theme_font_size_override("font_size", 10)
		ul.add_theme_color_override("font_color", Color(0.84, 0.93, 0.97, 0.94))
		vbox.add_child(ul)

	for upg_raw: Variant in node_def.get("upgrades", []):
		if not (upg_raw is Dictionary):
			continue
		var upg: Dictionary = upg_raw
		var u_id: StringName = upg["id"] as StringName
		var done: bool = econ != null and econ.has_upgrade(_tracked_team, u_id)
		var prog: bool = econ != null and econ.is_upgrade_in_progress(_tracked_team, u_id)
		var tag: String = "[DONE] " if done else ("[RESEARCHING] " if prog else "[UPG] ")
		var upg_lbl: Label = Label.new()
		upg_lbl.text = "%s%s" % [tag, String(upg["label"])]
		upg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		upg_lbl.add_theme_font_size_override("font_size", 10)
		if done:
			upg_lbl.add_theme_color_override("font_color", Color(0.32, 1.0, 0.72, 1.0))
		elif prog:
			upg_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.34, 1.0))
		else:
			upg_lbl.add_theme_color_override("font_color", Color(0.96, 0.84, 0.50, 0.92))
		vbox.add_child(upg_lbl)

	panel.add_child(vbox)
	return panel
