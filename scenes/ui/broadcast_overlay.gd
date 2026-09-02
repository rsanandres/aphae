class_name BroadcastOverlay
extends Node
## Broadcast chrome: the frame that makes every screenshot read as television.
## A LIVE bug with a blinking dot, a DAY/time stamp, a channel bug, and a
## soft vignette. Two CanvasLayers: the vignette sits just above the world so
## it never darkens UI panels; the bugs sit above the HUD like a real
## station's graphics package. Pure presentation — it listens, never writes.

const CHROME_LAYER := 6
const VIGNETTE_LAYER := 1
const BLINK_PERIOD := 0.9

var _chrome: CanvasLayer = null
var _vignette_layer: CanvasLayer = null
var _live_dot: Label = null
var _live_label: Label = null
var _blink_accum: float = 0.0


func _ready() -> void:
	_build_vignette()
	_build_chrome()


func set_shown(on: bool) -> void:
	## Desktop-pet mode drops the chrome — a 480x320 corner pet has no room
	## for a graphics package.
	_chrome.visible = on
	_vignette_layer.visible = on


func _process(delta: float) -> void:
	# The dot blinks while the show is live and holds steady on pause.
	if TimeManager.is_paused:
		_live_dot.modulate.a = 0.9
		_live_label.text = "HOLD"
		return
	_live_label.text = "LIVE"
	_blink_accum = fmod(_blink_accum + delta, BLINK_PERIOD)
	_live_dot.modulate.a = 0.95 if _blink_accum < BLINK_PERIOD * 0.62 else 0.25


func _build_chrome() -> void:
	_chrome = CanvasLayer.new()
	_chrome.layer = CHROME_LAYER
	add_child(_chrome)

	# Top-left, tucked under the status bar (which already carries the
	# day/time — a second stamp here was pure duplication, verified on a
	# gui_check capture). The dot is • not ●: the bundled web font has no
	# geometric-shapes block and ● renders as tofu in the browser demo.
	var live_box := HBoxContainer.new()
	live_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live_box.position = Vector2(8, 19)
	live_box.add_theme_constant_override("separation", 3)
	_chrome.add_child(live_box)
	_live_dot = _bug_label("•", Color(0.95, 0.2, 0.2))
	live_box.add_child(_live_dot)
	_live_label = _bug_label("LIVE", Color(0.95, 0.93, 0.9))
	live_box.add_child(_live_label)

	# Bottom-right: the channel bug, translucent like a real watermark.
	var channel := _bug_label("APHAE-1", Color(0.9, 0.88, 0.85, 0.45))
	channel.anchor_left = 1.0
	channel.anchor_right = 1.0
	channel.anchor_top = 1.0
	channel.anchor_bottom = 1.0
	channel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	channel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	channel.offset_right = -8
	channel.offset_bottom = -22  # clear of the status bar
	_chrome.add_child(channel)


func _bug_label(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0.03, 0.03, 0.05, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl


func _build_vignette() -> void:
	_vignette_layer = CanvasLayer.new()
	_vignette_layer.layer = VIGNETTE_LAYER
	add_child(_vignette_layer)

	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.30;
void fragment() {
	float d = distance(UV, vec2(0.5));
	float v = smoothstep(0.42, 0.86, d);
	COLOR = vec4(0.0, 0.0, 0.02, v * strength);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	_vignette_layer.add_child(rect)


func flash() -> void:
	## One-frame white pop on a hard cut. Spawned per call and freed after —
	## cuts are rare enough that pooling would be ceremony.
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(1.0, 1.0, 1.0, 0.22)
	_chrome.add_child(rect)
	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.0, 0.12)
	tween.tween_callback(rect.queue_free)
