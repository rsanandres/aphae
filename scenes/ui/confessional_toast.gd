class_name ConfessionalToast
extends PanelContainer
## Reality-TV "lower third" cutaway: flashes a confessional quip on screen
## with a REC dot, then fades out. One instance, reused for every quip.

var _name_label: Label = null
var _line_label: Label = null
var _rec_dot: Label = null
var _tween: Tween = null
var _blink: Tween = null
var _rest_offset_top: float = 0.0  # captured once so repeat cutaways don't drift


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.09, 0.92)
	style.border_color = Color(0.9, 0.35, 0.35)
	style.set_border_width_all(1)
	style.border_width_left = 3  # accent bar on the left, recolored per speaker
	style.set_corner_radius_all(3)
	style.set_content_margin_all(5)
	add_theme_stylebox_override("panel", style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 1)
	add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	outer.add_child(header)

	_rec_dot = Label.new()
	_rec_dot.text = "REC"
	_rec_dot.add_theme_font_size_override("font_size", 8)
	_rec_dot.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	header.add_child(_rec_dot)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 9)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_name_label)

	_line_label = Label.new()
	_line_label.add_theme_font_size_override("font_size", 10)
	_line_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.85))
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_line_label)

	visible = false
	modulate.a = 0.0
	_rest_offset_top = offset_top


func show_confessional(c: Confessional) -> void:
	_name_label.text = "%s — confessional" % c.speaker
	_name_label.add_theme_color_override("font_color", c.color)
	_line_label.text = "\"%s\"" % c.line

	# Recolor the left accent bar to the speaker.
	var style: StyleBoxFlat = get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var s := style.duplicate() as StyleBoxFlat
		s.border_color = c.color
		add_theme_stylebox_override("panel", s)

	visible = true

	# Blink the REC dot while the cutaway is up.
	if _blink and _blink.is_valid():
		_blink.kill()
	_rec_dot.modulate.a = 1.0
	_blink = create_tween().set_loops()
	_blink.tween_property(_rec_dot, "modulate:a", 0.15, 0.5)
	_blink.tween_property(_rec_dot, "modulate:a", 1.0, 0.5)

	# Slide up + fade in, hold, fade out.
	if _tween and _tween.is_valid():
		_tween.kill()
	offset_top = _rest_offset_top + 6
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.25)
	_tween.tween_property(self, "offset_top", _rest_offset_top, 0.25)
	_tween.set_parallel(false)
	_tween.tween_interval(5.0)
	_tween.tween_property(self, "modulate:a", 0.0, 0.6)
	_tween.tween_callback(func() -> void:
		visible = false
		if _blink and _blink.is_valid():
			_blink.kill()
	)
