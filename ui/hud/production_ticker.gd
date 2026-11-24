class_name ProductionTicker
extends Control

const MAX_VISIBLE_ROWS: int = 5
const REFRESH_INTERVAL: float = 0.20
const DOUBLE_CLICK_MS: int = 350

@onready var ticker_panel: PanelContainer = %TickerPanel
@onready var header_label: Label = %HeaderLabel
@onready var btn_collapse: Button = %BtnCollapse
@onready var rows_container: VBoxContainer = %RowsContainer
@onready var overflow_label: Label = %OverflowLabel

var _selection_controller: SelectionController = null
var _collapsed: bool = false
var _refresh_timer: float = 0.0
var _last_clicked_building_id: int = 0
var _last_click_ms: int = 0
var _row_widgets: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("production_ticker")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ticker_panel != null:
		ticker_panel.add_to_group("blocks_edge_pan")
		ticker_panel.visible = false
	if btn_collapse != null:
		btn_collapse.add_to_group("blocks_edge_pan")
		btn_collapse.pressed.connect(_on_toggle_collapse)
	call_deferred("_resolve_selection_controller")
	call_deferred("_refresh_ticker")


func _resolve_selection_controller() -> void:
	if is_inside_tree():
		_selection_controller = get_tree().get_first_node_in_group("selection_controller") as SelectionController


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	_refresh_ticker()


func _on_toggle_collapse() -> void:
	_collapsed = not _collapsed
	if AudioManager != null:
		AudioManager.play_ui_click()
	if btn_collapse != null:
		btn_collapse.text = "+" if _collapsed else "−"
	if rows_container != null:
		rows_container.visible = not _collapsed
	if overflow_label != null and _collapsed:
		overflow_label.visible = false
	_refresh_ticker()


func _refresh_ticker() -> void:
	if not is_inside_tree() or ticker_panel == null:
		return

	var active_entries: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building) or not is_instance_valid(node):
			continue
		var b: Building = node
		if b.is_destroyed or b.is_queued_for_deletion() or not b.is_constructed or b.team != Unit.Team.PLAYER:
			continue
		if b.production_component == null:
			continue
		var q_size: int = b.production_component.get_queue_size()
		if q_size <= 0:
			continue
		var status: Dictionary = b.get_active_training_status()
		if status.is_empty():
			continue
		active_entries.append({
			"building": b,
			"building_id": b.get_instance_id(),
			"queue_size": q_size,
			"status": status,
		})

	if active_entries.is_empty():
		ticker_panel.visible = false
		return

	active_entries.sort_custom(func(a: Dictionary, b_item: Dictionary) -> bool:
		return int(a["building_id"]) < int(b_item["building_id"])
	)

	ticker_panel.visible = true
	if header_label != null:
		header_label.text = "PRODUCTION (%d)" % active_entries.size()

	if _collapsed:
		if rows_container != null:
			rows_container.visible = false
		if overflow_label != null:
			overflow_label.visible = false
		return

	if rows_container != null:
		rows_container.visible = true

	var display_count: int = mini(active_entries.size(), MAX_VISIBLE_ROWS)
	_ensure_row_count(display_count)

	for i: int in range(display_count):
		var entry: Dictionary = active_entries[i]
		var b: Building = entry["building"] as Building
		var q_size: int = int(entry["queue_size"])
		var st: Dictionary = entry["status"] as Dictionary
		var kind: StringName = st.get("kind", ProductionComponent.KIND_UNIT)
		var is_upgrade: bool = (kind == ProductionComponent.KIND_UPGRADE)
		var raw_name: String = String(st.get("display_name", "Item"))
		var short_name: String = _shorten_name(raw_name)
		var batch_cnt: int = int(st.get("batch_count", 1))
		var progress: float = clampf(float(st.get("progress", 0.0)), 0.0, 1.0)
		var pct: int = int(round(progress * 100.0))

		var widget: Dictionary = _row_widgets[i]
		widget["building"] = b
		var title_lbl: Label = widget["title"] as Label
		var pct_lbl: Label = widget["pct"] as Label
		var bar: ProgressBar = widget["bar"] as ProgressBar
		var fill_style: StyleBoxFlat = widget["fill"] as StyleBoxFlat

		var prefix: String = "[UPG] " if is_upgrade else ""
		var batch_tag: String = (" x%d" % batch_cnt) if (not is_upgrade and batch_cnt > 1) else ""
		var q_tag: String = (" (+%d)" % (q_size - 1)) if q_size > 1 else ""
		title_lbl.text = "%s%s%s%s" % [prefix, short_name, batch_tag, q_tag]
		title_lbl.modulate = Color(1.0, 0.88, 0.42, 1.0) if is_upgrade else Color(0.88, 0.98, 1.0, 1.0)
		pct_lbl.text = "%d%%" % pct
		bar.value = progress * 100.0
		if fill_style != null:
			fill_style.bg_color = Color(1.0, 0.80, 0.28, 1.0) if is_upgrade else Color(0.24, 0.96, 0.86, 1.0)

	if overflow_label != null:
		var hidden_count: int = active_entries.size() - display_count
		overflow_label.visible = hidden_count > 0
		if hidden_count > 0:
			overflow_label.text = "+%d more producing..." % hidden_count


func _ensure_row_count(target_count: int) -> void:
	if rows_container == null:
		return
	while _row_widgets.size() < target_count:
		var idx: int = _row_widgets.size()
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(204.0, 32.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_to_group("blocks_edge_pan")

		var margin: MarginContainer = MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 6)
		margin.add_theme_constant_override("margin_right", 6)
		margin.add_theme_constant_override("margin_top", 3)
		margin.add_theme_constant_override("margin_bottom", 3)
		btn.add_child(margin)

		var vb: VBoxContainer = VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 3)
		margin.add_child(vb)

		var top_row: HBoxContainer = HBoxContainer.new()
		top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_row.add_theme_constant_override("separation", 4)
		vb.add_child(top_row)

		var title_lbl: Label = Label.new()
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_lbl.clip_text = true
		title_lbl.add_theme_font_size_override("font_size", 11)
		top_row.add_child(title_lbl)

		var pct_lbl: Label = Label.new()
		pct_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pct_lbl.add_theme_font_size_override("font_size", 10)
		pct_lbl.add_theme_color_override("font_color", Color(0.56, 0.90, 0.96, 0.95))
		top_row.add_child(pct_lbl)

		var bar: ProgressBar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(0.0, 5.0)
		bar.max_value = 100.0
		bar.value = 0.0
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var bg_style: StyleBoxFlat = StyleBoxFlat.new()
		bg_style.bg_color = Color(0.05, 0.09, 0.13, 0.95)
		bg_style.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", bg_style)

		var fill_style: StyleBoxFlat = StyleBoxFlat.new()
		fill_style.bg_color = Color(0.24, 0.96, 0.86, 1.0)
		fill_style.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", fill_style)
		vb.add_child(bar)

		var captured_idx: int = idx
		btn.pressed.connect(func() -> void:
			_on_row_clicked(captured_idx)
		)

		rows_container.add_child(btn)
		_row_widgets.append({
			"button": btn,
			"title": title_lbl,
			"pct": pct_lbl,
			"bar": bar,
			"fill": fill_style,
			"building": null,
		})

	for i: int in range(_row_widgets.size()):
		var btn_item: Button = _row_widgets[i]["button"] as Button
		if btn_item != null:
			btn_item.visible = (i < target_count)


func _on_row_clicked(row_index: int) -> void:
	if row_index < 0 or row_index >= _row_widgets.size():
		return
	var b: Building = _row_widgets[row_index].get("building", null) as Building
	if b == null or not is_instance_valid(b) or b.is_destroyed:
		return
	if _selection_controller == null:
		_resolve_selection_controller()
	if _selection_controller == null:
		return

	var now_ms: int = Time.get_ticks_msec()
	var b_id: int = b.get_instance_id()
	var is_double: bool = (_last_clicked_building_id == b_id and (now_ms - _last_click_ms) <= DOUBLE_CLICK_MS)
	_last_clicked_building_id = b_id
	_last_click_ms = now_ms

	_selection_controller.select_single_entity(b, is_double)


func _shorten_name(full_name: String) -> String:
	return (
		full_name
		.replace("Worker Drone", "Worker")
		.replace("Systems Engineer", "Engineer")
		.replace("Silica Harvester", "Harvester")
		.replace("Clone Trooper", "Clone")
		.replace("Signal Jammer", "Jammer")
		.replace("Goliath Frame", "Goliath")
		.replace("Chrysalis Mortar", "Mortar")
		.replace("Batch Efficiency", "Batch Eff.")
		.replace("Adrenal Potency", "Adrenal Pot.")
		.replace("Compute Overdrive", "Overdrive")
	)
