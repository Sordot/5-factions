class_name SelectionWireframeGrid
extends VBoxContainer

## Pooled 24-slot clickable wireframe selection grid with clean pagination for >24 entities
## (Milestone 4.1). Groups entities deterministically by Tab-subgroup order and instance_id so
## tiles never jump under the cursor mid-fight, refreshing live HP/shield/status at 0.15s.

signal entity_tile_clicked(entity: Node, shift_held: bool, ctrl_held: bool, is_double_click: bool)
signal entity_tile_hovered(entity: Node, tile_global_rect: Rect2)
signal entity_tile_unhovered(entity: Node)

const TILE_SCRIPT: GDScript = preload("res://ui/hud/selection_wireframe_tile.gd")
const SLOTS_PER_PAGE: int = 24
const REDRAW_CADENCE: float = 0.15

var _grid: GridContainer = null
var _tiles: Array[SelectionWireframeTile] = []
var _page_bar: HBoxContainer = null
var _btn_prev: Button = null
var _btn_next: Button = null
var _page_label: Label = null

var _ordered_entries: Array[Dictionary] = [] # { "entity": Node, "is_active": bool }
var _current_page: int = 0
var _redraw_acc: float = 0.0
var _faction_id: StringName = &"genesis_v2"
var _faction_accent: Color = Color(0.20, 0.83, 0.60, 1.0)


func _init() -> void:
	add_theme_constant_override("separation", 3)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	add_to_group("blocks_edge_pan")
	_grid = GridContainer.new()
	_grid.name = "WireframeTilesGrid"
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(_grid)

	# Pre-allocate exactly 24 pooled tiles once (zero runtime instantiate/free churn)
	for i: int in range(SLOTS_PER_PAGE):
		var tile: SelectionWireframeTile = TILE_SCRIPT.new() as SelectionWireframeTile
		tile.name = "WireTile%02d" % i
		tile.visible = false
		tile.tile_clicked.connect(_on_tile_clicked)
		tile.tile_hovered.connect(_on_tile_hovered)
		tile.tile_unhovered.connect(_on_tile_unhovered)
		tile.apply_faction_theme(_faction_id, _faction_accent)
		_grid.add_child(tile)
		_tiles.append(tile)

	# Compact 18px pagination strip (visible only when total selected > 24)
	_page_bar = HBoxContainer.new()
	_page_bar.name = "PaginationBar"
	_page_bar.visible = false
	_page_bar.custom_minimum_size = Vector2(0.0, 18.0)
	_page_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_page_bar.add_theme_constant_override("separation", 6)
	add_child(_page_bar)

	_btn_prev = Button.new()
	_btn_prev.text = "<"
	_btn_prev.focus_mode = Control.FOCUS_NONE
	_btn_prev.custom_minimum_size = Vector2(24.0, 18.0)
	_btn_prev.add_theme_font_size_override("font_size", 10)
	_btn_prev.add_to_group("blocks_edge_pan")
	_btn_prev.pressed.connect(_on_prev_page)
	_page_bar.add_child(_btn_prev)

	_page_label = Label.new()
	_page_label.text = "PAGE 1 / 1"
	_page_label.add_theme_font_size_override("font_size", 10)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_bar.add_child(_page_label)

	_btn_next = Button.new()
	_btn_next.text = ">"
	_btn_next.focus_mode = Control.FOCUS_NONE
	_btn_next.custom_minimum_size = Vector2(24.0, 18.0)
	_btn_next.add_theme_font_size_override("font_size", 10)
	_btn_next.add_to_group("blocks_edge_pan")
	_btn_next.pressed.connect(_on_next_page)
	_page_bar.add_child(_btn_next)


func _process(delta: float) -> void:
	if not visible or _ordered_entries.is_empty():
		return
	_redraw_acc += delta
	if _redraw_acc >= REDRAW_CADENCE:
		_redraw_acc = 0.0
		redraw_visible_tiles()


func apply_faction_theme(faction_id: StringName, accent: Color) -> void:
	_faction_id = faction_id
	_faction_accent = accent
	for tile: SelectionWireframeTile in _tiles:
		if is_instance_valid(tile):
			tile.apply_faction_theme(faction_id, accent)
	if _page_label != null:
		_page_label.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.35))


func set_unit_subgroups(subgroups: Array[Dictionary], active_subgroup_index: int) -> void:
	var entries: Array[Dictionary] = []
	var safe_active: int = clampi(active_subgroup_index, 0, maxi(0, subgroups.size() - 1))
	for gi: int in range(subgroups.size()):
		var grp: Dictionary = subgroups[gi]
		var raw_units: Array = grp.get("units", [])
		var valid_units: Array[Unit] = []
		for item: Variant in raw_units:
			if is_instance_valid(item) and item is Unit:
				var u: Unit = item as Unit
				if not u.is_dead and not u.is_staffed and not u.is_queued_for_deletion():
					valid_units.append(u)
		valid_units.sort_custom(func(a: Unit, b: Unit) -> bool:
			return a.get_instance_id() < b.get_instance_id()
		)
		var is_act: bool = (gi == safe_active)
		for u: Unit in valid_units:
			entries.append({"entity": u, "is_active": is_act})
	_apply_entries(entries)


func set_building_subgroups(b_subgroups: Array[Dictionary], active_subgroup_index: int, fallback_buildings: Array[Building] = []) -> void:
	var entries: Array[Dictionary] = []
	if not b_subgroups.is_empty():
		var safe_active: int = clampi(active_subgroup_index, 0, maxi(0, b_subgroups.size() - 1))
		for gi: int in range(b_subgroups.size()):
			var grp: Dictionary = b_subgroups[gi]
			var raw_bldgs: Array = grp.get("buildings", [])
			var valid_bldgs: Array[Building] = []
			for item: Variant in raw_bldgs:
				if is_instance_valid(item) and item is Building:
					var b: Building = item as Building
					if not b.is_destroyed and not b.is_queued_for_deletion():
						valid_bldgs.append(b)
			valid_bldgs.sort_custom(func(a: Building, b: Building) -> bool:
				return a.get_instance_id() < b.get_instance_id()
			)
			var is_act: bool = (gi == safe_active)
			for b: Building in valid_bldgs:
				entries.append({"entity": b, "is_active": is_act})
	else:
		var valid_fb: Array[Building] = []
		for b: Building in fallback_buildings:
			if is_instance_valid(b) and not b.is_destroyed and not b.is_queued_for_deletion():
				valid_fb.append(b)
		valid_fb.sort_custom(func(a: Building, b: Building) -> bool:
			return a.get_instance_id() < b.get_instance_id()
		)
		for b: Building in valid_fb:
			entries.append({"entity": b, "is_active": true})
	_apply_entries(entries)


func clear_grid() -> void:
	_ordered_entries.clear()
	_current_page = 0
	for tile: SelectionWireframeTile in _tiles:
		if is_instance_valid(tile):
			tile.clear_slot()
	if _page_bar != null:
		_page_bar.visible = false


func redraw_visible_tiles() -> void:
	for tile: SelectionWireframeTile in _tiles:
		if is_instance_valid(tile) and tile.visible:
			tile.queue_redraw()


func _apply_entries(entries: Array[Dictionary]) -> void:
	_ordered_entries = entries
	var total: int = _ordered_entries.size()
	var total_pages: int = maxi(1, ceili(float(total) / float(SLOTS_PER_PAGE)))
	_current_page = clampi(_current_page, 0, total_pages - 1)
	_redraw_acc = 0.0
	_bind_current_page()


func _bind_current_page() -> void:
	var total: int = _ordered_entries.size()
	var total_pages: int = maxi(1, ceili(float(total) / float(SLOTS_PER_PAGE)))
	_current_page = clampi(_current_page, 0, total_pages - 1)
	var start_idx: int = _current_page * SLOTS_PER_PAGE

	for slot_i: int in range(_tiles.size()):
		var tile: SelectionWireframeTile = _tiles[slot_i]
		var entry_i: int = start_idx + slot_i
		if entry_i < total:
			var entry: Dictionary = _ordered_entries[entry_i]
			tile.bind_entity(entry["entity"] as Node, bool(entry["is_active"]))
		else:
			tile.clear_slot()

	if _page_bar != null:
		var show_pages: bool = total > SLOTS_PER_PAGE
		_page_bar.visible = show_pages
		if show_pages:
			_page_label.text = "PAGE %d / %d  (%d SELECTED)" % [_current_page + 1, total_pages, total]
			_btn_prev.disabled = (_current_page <= 0)
			_btn_next.disabled = (_current_page >= total_pages - 1)


func _on_prev_page() -> void:
	if _current_page > 0:
		_current_page -= 1
		if AudioManager != null:
			AudioManager.play_ui_click()
		_bind_current_page()


func _on_next_page() -> void:
	var total_pages: int = maxi(1, ceili(float(_ordered_entries.size()) / float(SLOTS_PER_PAGE)))
	if _current_page < total_pages - 1:
		_current_page += 1
		if AudioManager != null:
			AudioManager.play_ui_click()
		_bind_current_page()


func _on_tile_clicked(entity: Node, shift_held: bool, ctrl_held: bool, is_double_click: bool) -> void:
	entity_tile_clicked.emit(entity, shift_held, ctrl_held, is_double_click)


func _on_tile_hovered(entity: Node, tile_global_rect: Rect2) -> void:
	entity_tile_hovered.emit(entity, tile_global_rect)


func _on_tile_unhovered(entity: Node) -> void:
	entity_tile_unhovered.emit(entity)
