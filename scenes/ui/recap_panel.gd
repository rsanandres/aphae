class_name RecapPanel
extends PanelContainer
## Viewer for the episode recap, with export to user://recaps/.

var _scroll: ScrollContainer
var _body: RichTextLabel
var _status: Label


func _ready() -> void:
	custom_minimum_size = Vector2(260, 200)
	visible = false
	# Opaque background: without one the narrative log and the world show
	# straight through the text, which is unreadable at the 480x320 size.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.1, 0.96)
	style.border_color = Color(0.35, 0.32, 0.2, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)
	_build_ui()


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	_body.text = EpisodeRecap.build_display()
	_status.text = ""
	_scroll.call_deferred("set_v_scroll", 0)


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(outer)

	var header := HBoxContainer.new()
	outer.add_child(header)

	var title := Label.new()
	title.text = "Episode Recap"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var export_btn := Button.new()
	export_btn.text = "Export"
	export_btn.tooltip_text = "Write this recap to user://recaps/ as Markdown"
	export_btn.add_theme_font_size_override("font_size", 9)
	export_btn.pressed.connect(_on_export)
	header.add_child(export_btn)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.add_theme_font_size_override("font_size", 9)
	close_btn.pressed.connect(func() -> void: visible = false)
	header.add_child(close_btn)

	outer.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false  # the outer ScrollContainer owns scrolling
	_body.add_theme_font_size_override("normal_font_size", 9)
	_body.add_theme_font_size_override("bold_font_size", 9)
	_body.add_theme_color_override("default_color", Color(0.82, 0.82, 0.88))
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 8)
	_status.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)


func _on_export() -> void:
	var path := EpisodeRecap.export_to_file()
	if path == "":
		_status.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
		_status.text = "Export failed."
		return
	_status.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	_status.text = "Saved to %s" % ProjectSettings.globalize_path(path)
