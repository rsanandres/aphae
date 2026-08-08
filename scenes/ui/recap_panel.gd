class_name RecapPanel
extends BasePanel
## Viewer for the episode recap, with export to user://recaps/.

var _scroll: ScrollContainer
var _body: RichTextLabel
var _status: Label


func _ready() -> void:
	_setup_chrome("Episode Recap")
	_build_ui()


func _on_opened() -> void:
	refresh()


func refresh() -> void:
	_body.text = EpisodeRecap.build_display()
	_status.text = ""
	_scroll.call_deferred("set_v_scroll", 0)


func _build_ui() -> void:
	var export_btn := Button.new()
	export_btn.text = "Export"
	export_btn.tooltip_text = "Write this recap to user://recaps/ as Markdown"
	export_btn.pressed.connect(_on_export)
	header_extra.add_child(export_btn)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false  # the outer ScrollContainer owns scrolling
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

	_status = Label.new()
	_status.theme_type_variation = "DimLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)


func _on_export() -> void:
	var path := EpisodeRecap.export_to_file()
	if path == "":
		_status.add_theme_color_override("font_color", UIPalette.ACCENT_NEG)
		_status.text = "Export failed."
		return
	_status.add_theme_color_override("font_color", UIPalette.ACCENT_POS)
	_status.text = "Saved to %s" % ProjectSettings.globalize_path(path)
