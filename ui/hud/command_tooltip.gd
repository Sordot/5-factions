class_name CommandTooltip
extends PanelContainer

@onready var title_label: Label = %TooltipTitleLabel
@onready var hotkey_label: Label = %TooltipHotkeyLabel
@onready var meta_label: Label = %TooltipMetaLabel
@onready var desc_label: Label = %TooltipDescLabel


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_tooltip(title: String, hotkey: String, meta_line: String, description: String) -> void:
	if title_label != null:
		title_label.text = title
	if hotkey_label != null:
		var hk_clean: String = hotkey.strip_edges()
		hotkey_label.visible = not hk_clean.is_empty()
		hotkey_label.text = "[%s]" % hk_clean
	if meta_label != null:
		meta_label.visible = not meta_line.is_empty()
		meta_label.text = meta_line
	if desc_label != null:
		desc_label.visible = not description.is_empty()
		desc_label.text = description
	visible = true


func hide_tooltip() -> void:
	visible = false
