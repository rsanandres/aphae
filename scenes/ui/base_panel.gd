class_name BasePanel
extends PanelContainer
## Shared chrome for overlay panels: themed background, header row with title
## and close button, body container, and a short open/close tween.
##
## Subclasses call _setup_chrome() in _ready() and build content into `body`.
## Panels that refresh on open override _on_opened().

signal closed

var body: VBoxContainer
var header_extra: HBoxContainer  # slot for extra header buttons (left of X)

var _title_label: Label
var _open_tween: Tween = null


func _setup_chrome(title: String, accent: Color = UIPalette.ACCENT_WARM) -> void:
	theme = UITheme.get_theme()
	visible = false
	clip_contents = true
	add_theme_stylebox_override("panel", UITheme.make_panel_style(accent * Color(1, 1, 1, 0.7)))

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	outer.add_child(header)

	_title_label = Label.new()
	_title_label.text = title
	_title_label.theme_type_variation = "HeaderLabel"
	_title_label.add_theme_color_override("font_color", accent)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	header_extra = HBoxContainer.new()
	header_extra.add_theme_constant_override("separation", 4)
	header.add_child(header_extra)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.tooltip_text = "Close [Esc]"
	close_btn.custom_minimum_size = Vector2(18, 18)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	outer.add_child(HSeparator.new())

	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	visible = true
	_on_opened()
	pivot_offset = size / 2.0
	modulate.a = 0.0
	scale = Vector2(0.96, 0.96)
	if _open_tween:
		_open_tween.kill()
	_open_tween = create_tween().set_parallel(true)
	_open_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_open_tween.tween_property(self, "scale", Vector2.ONE, 0.12)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	if _open_tween:
		_open_tween.kill()
		_open_tween = null
	visible = false
	modulate.a = 1.0
	scale = Vector2.ONE
	closed.emit()


func _on_opened() -> void:
	pass
