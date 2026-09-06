class_name BoothCutaway
extends Control
## The confessional booth, on screen: a picture-in-picture talking head.
## When an agent files a confessional, the lower third cuts to a curtain
## backdrop under a spotlight, the speaker's portrait (scaled sprite) with a
## flapping mouth, a REC dot inside the frame, and their line typing itself
## out. This is the game's shareable clip format — the marquee promise as a
## picture instead of a text toast. Host recaps keep the plain lower-third
## toast: the Narrator has no face, and shouldn't.
##
## One instance, reused per cutaway, created by the HUD.

const PORTRAIT_SCALE := 4.0
const TYPE_CHARS_PER_SEC := 28.0
const HOLD_AFTER_TYPED := 2.6
const MOUTH_FLAP_PERIOD := 0.14

# Where the mouth sits on the 14x18 outlined character sprite (source px):
# face spans x3-8 on rows 2-5, so the mouth overlay lands centered row ~5.5.
const MOUTH_RECT_SRC := Rect2(5.5, 5.5, 3.0, 0.8)

var _frame_panel: PanelContainer = null
var _stage: Control = null
var _backdrop: Control = null
var _portrait: TextureRect = null
var _mouth: ColorRect = null
var _rec_dot: Label = null
var _name_label: Label = null
var _line_label: Label = null
var _full_line: String = ""
var _typed: float = 0.0
var _hold_left: float = 0.0
var _flap_accum: float = 0.0
var _fade_tween: Tween = null
var _blink: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	# --- The booth frame: curtain, spotlight, portrait, REC ------------------
	_frame_panel = PanelContainer.new()
	_frame_panel.custom_minimum_size = Vector2(64, 84)
	_frame_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.05, 0.03, 0.05)
	frame_style.border_color = Color(0.85, 0.78, 0.6)  # brass frame
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(2)
	frame_style.set_content_margin_all(0)
	_frame_panel.add_theme_stylebox_override("panel", frame_style)
	row.add_child(_frame_panel)

	# A PanelContainer stomps manually-positioned children in its layout
	# sort — the portrait vanished on the first capture. Everything placed
	# by hand lives on this plain Control instead; the container only sizes
	# the stage, never the actors on it.
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.clip_contents = true
	_frame_panel.add_child(_stage)

	_backdrop = Control.new()
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.draw.connect(_draw_backdrop)
	_stage.add_child(_backdrop)

	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.scale = Vector2(PORTRAIT_SCALE, PORTRAIT_SCALE)
	_stage.add_child(_portrait)

	_mouth = ColorRect.new()
	_mouth.color = Color(0.16, 0.08, 0.08)
	_mouth.visible = false
	_mouth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_mouth)

	_rec_dot = Label.new()
	_rec_dot.text = "• REC"
	_rec_dot.add_theme_font_size_override("font_size", 8)
	_rec_dot.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_rec_dot.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_rec_dot.add_theme_constant_override("shadow_offset_x", 1)
	_rec_dot.add_theme_constant_override("shadow_offset_y", 1)
	_rec_dot.position = Vector2(4, 2)
	_stage.add_child(_rec_dot)

	# --- The quote side ------------------------------------------------------
	var quote_panel := PanelContainer.new()
	quote_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quote_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var quote_style := StyleBoxFlat.new()
	quote_style.bg_color = Color(0.08, 0.06, 0.09, 0.92)
	quote_style.border_color = Color(0.9, 0.35, 0.35)
	quote_style.set_border_width_all(1)
	quote_style.border_width_left = 3
	quote_style.set_corner_radius_all(3)
	quote_style.set_content_margin_all(6)
	quote_panel.add_theme_stylebox_override("panel", quote_style)
	row.add_child(quote_panel)

	var quote_box := VBoxContainer.new()
	quote_box.add_theme_constant_override("separation", 2)
	quote_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quote_panel.add_child(quote_box)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 9)
	quote_box.add_child(_name_label)

	_line_label = Label.new()
	_line_label.add_theme_font_size_override("font_size", 10)
	_line_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.85))
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quote_box.add_child(_line_label)

	visible = false
	modulate.a = 0.0


func show_confessional(c: Confessional) -> void:
	var portrait := _portrait_for(c.speaker)
	if portrait == null:
		return  # no face, no booth — the caller falls back to the toast
	_portrait.texture = portrait
	# Scaling a TextureRect scales around its top-left, so position the
	# scaled portrait by hand on the stage (which the container sizes).
	var frame_size: Vector2 = _stage.size if _stage.size.x > 0.0 else Vector2(60, 80)
	var tex_size: Vector2 = portrait.get_size() * PORTRAIT_SCALE
	_portrait.size = portrait.get_size()
	_portrait.position = Vector2(
		(frame_size.x - tex_size.x) / 2.0,
		frame_size.y - tex_size.y - 2.0)
	_mouth.position = _portrait.position + MOUTH_RECT_SRC.position * PORTRAIT_SCALE
	_mouth.size = MOUTH_RECT_SRC.size * PORTRAIT_SCALE
	_backdrop.queue_redraw()

	_name_label.text = "%s — in the booth" % c.speaker
	_name_label.add_theme_color_override("font_color", c.color)
	_full_line = "\"%s\"" % c.line
	_typed = 0.0
	_hold_left = HOLD_AFTER_TYPED
	_line_label.text = ""

	visible = true
	if _blink and _blink.is_valid():
		_blink.kill()
	_rec_dot.modulate.a = 1.0
	_blink = create_tween().set_loops()
	_blink.tween_property(_rec_dot, "modulate:a", 0.15, 0.5)
	_blink.tween_property(_rec_dot, "modulate:a", 1.0, 0.5)

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.2)


func _process(delta: float) -> void:
	if not visible or _full_line == "":
		return
	if _typed < _full_line.length():
		# Typewriter + mouth flap: the booth talks while the line types.
		_typed = minf(_typed + TYPE_CHARS_PER_SEC * delta, float(_full_line.length()))
		_line_label.text = _full_line.substr(0, int(_typed))
		_flap_accum += delta
		if _flap_accum >= MOUTH_FLAP_PERIOD:
			_flap_accum = 0.0
			_mouth.visible = not _mouth.visible
		return
	_mouth.visible = false
	_hold_left -= delta
	if _hold_left <= 0.0 and (_fade_tween == null or not _fade_tween.is_valid()):
		_fade_tween = create_tween()
		_fade_tween.tween_property(self, "modulate:a", 0.0, 0.6)
		_fade_tween.tween_callback(func() -> void:
			visible = false
			if _blink and _blink.is_valid():
				_blink.kill()
		)


func _portrait_for(speaker: String) -> Texture2D:
	var agent := AgentManager.get_agent_by_name(speaker)
	if agent == null or not is_instance_valid(agent):
		return null
	# The still idle frame (no bob), so the mouth overlay lands where the
	# face actually is. The texture is refcounted — safe even if the agent
	# departs mid-cutaway.
	if not agent._idle_frames.is_empty():
		return agent._idle_frames[0]
	if agent.sprite and agent.sprite.texture:
		return agent.sprite.texture
	return null


func _draw_backdrop() -> void:
	# Stage curtain: alternating fold stripes, darker toward the edges, with
	# a spotlight pool behind where the head goes. Drawn, not textured — same
	# procedural budget as everything else in this game.
	var size_rect: Vector2 = _stage.size if _stage.size.x > 0.0 else Vector2(60, 80)
	_backdrop.size = size_rect
	var deep := Color(0.30, 0.07, 0.10)
	var fold := Color(0.42, 0.10, 0.14)
	var stripe_w := 6.0
	var x := 0.0
	var i := 0
	while x < size_rect.x:
		var col := fold if i % 2 == 0 else deep
		# Edge falloff sells the curve of the curtain.
		var edge := absf(x + stripe_w * 0.5 - size_rect.x * 0.5) / (size_rect.x * 0.5)
		_backdrop.draw_rect(Rect2(x, 0, stripe_w, size_rect.y), col.darkened(edge * 0.35))
		x += stripe_w
		i += 1
	# The spotlight: layered soft circles, brightest in the middle.
	var spot_center := Vector2(size_rect.x * 0.5, size_rect.y * 0.42)
	for layer in range(3):
		var r := 30.0 - layer * 8.0
		_backdrop.draw_circle(spot_center, r, Color(1.0, 0.95, 0.8, 0.05 + layer * 0.035))
	# Floor shadow line under the stool area.
	_backdrop.draw_rect(Rect2(0, size_rect.y - 6, size_rect.x, 6), Color(0.0, 0.0, 0.0, 0.35))
