class_name SpeechBubbleLayer
extends CanvasLayer
## Screen-space speech bubbles. Agents delegate show_speech() here, so bubble
## size no longer depends on camera zoom (the old world-space panels were
## 150px wide — half the screen — and scaled with the world).
##
## Bubbles track their agent every frame, clamp to the play area between the
## status bar and icon bar, and are capped: when a fifth agent speaks, the
## oldest non-selected bubble fades early. Full lines always land in the
## narrative log's Talk tab; the bubble is just the in-world cue.

const MAX_BUBBLES := 4
const BUBBLE_WIDTH := 150.0
const TOP_MARGIN := 24.0
const BOTTOM_MARGIN := 34.0
const TAIL_HEIGHT := 5.0

var _bubbles: Dictionary = {}  # agent (Node2D) -> PanelContainer


func _ready() -> void:
	layer = 5
	add_to_group("speech_bubbles")


func show_bubble(agent: Node2D, text: String, duration: float, tone: String = "") -> void:
	if not is_instance_valid(agent):
		return
	var bubble: PanelContainer = _bubbles.get(agent)
	if bubble == null:
		_enforce_cap()
		bubble = _make_bubble(agent)
		_bubbles[agent] = bubble
		add_child(bubble)

	_apply_tone(bubble, agent, tone)
	var line_label: Label = bubble.get_meta("line_label")
	line_label.text = text
	bubble.visible = true
	bubble.modulate.a = 1.0

	var old_tween: Tween = bubble.get_meta("tween") if bubble.has_meta("tween") else null
	if old_tween and old_tween.is_valid():
		old_tween.kill()
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(bubble, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void: _drop(agent))
	bubble.set_meta("tween", tween)
	bubble.set_meta("shown_at", Time.get_ticks_msec())


func _process(_delta: float) -> void:
	if _bubbles.is_empty():
		return
	var view := get_viewport().get_visible_rect().size
	var camera := get_viewport().get_camera_2d()
	var zoom: float = camera.zoom.x if camera else 1.0
	var dead: Array = []
	for agent: Node2D in _bubbles:
		if not is_instance_valid(agent):
			dead.append(agent)
			continue
		var bubble: PanelContainer = _bubbles[agent]
		# Agent position in screen space, courtesy of the canvas transform.
		var screen_pos: Vector2 = agent.get_global_transform_with_canvas().origin
		var bsize := bubble.size
		var pos := Vector2(
			screen_pos.x - bsize.x / 2.0,
			screen_pos.y - 16.0 * zoom - bsize.y - TAIL_HEIGHT
		)
		pos.x = clampf(pos.x, 4.0, view.x - bsize.x - 4.0)
		pos.y = clampf(pos.y, TOP_MARGIN, view.y - bsize.y - BOTTOM_MARGIN)
		bubble.position = pos
	for agent in dead:
		_drop(agent)


func _make_bubble(agent: Node2D) -> PanelContainer:
	var bubble := PanelContainer.new()
	bubble.theme = UITheme.get_theme()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var agent_color: Color = agent.agent_color if "agent_color" in agent else UIPalette.BORDER
	var style := UITheme.make_panel_style(agent_color)
	style.set_content_margin_all(4)
	bubble.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(vbox)

	var name_tag := Label.new()
	name_tag.text = agent.agent_name if "agent_name" in agent else "?"
	name_tag.theme_type_variation = "DimLabel"
	name_tag.add_theme_color_override("font_color", agent_color.lightened(0.35))
	vbox.add_child(name_tag)

	var line_label := Label.new()
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0)
	line_label.max_lines_visible = 2
	line_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(line_label)
	bubble.set_meta("line_label", line_label)

	# Tail: a small triangle below the panel pointing at the speaker.
	var tail := _BubbleTail.new()
	tail.color = style.bg_color
	tail.border = agent_color
	bubble.add_child(tail)
	bubble.set_meta("tail", tail)

	return bubble


func _apply_tone(bubble: PanelContainer, agent: Node2D, tone: String) -> void:
	## Border color telegraphs how the exchange reads: pink for romance, red
	## for hostility, the speaker's own color otherwise.
	var accent: Color
	match tone:
		"romantic":
			accent = UIPalette.ACCENT_ROMANCE
		"hostile":
			accent = UIPalette.ACCENT_NEG
		_:
			accent = agent.agent_color if "agent_color" in agent else UIPalette.BORDER
	var style := UITheme.make_panel_style(accent)
	style.set_content_margin_all(4)
	bubble.add_theme_stylebox_override("panel", style)
	var tail: Control = bubble.get_meta("tail") if bubble.has_meta("tail") else null
	if tail:
		tail.border = accent
		tail.queue_redraw()


func _enforce_cap() -> void:
	if _bubbles.size() < MAX_BUBBLES:
		return
	var selected: Node2D = GameManager.selected_agent
	var oldest: Node2D = null
	var oldest_time := 9223372036854775807
	for agent: Node2D in _bubbles:
		if agent == selected:
			continue  # the followed conversation keeps its bubble
		var bubble: PanelContainer = _bubbles[agent]
		var t: int = bubble.get_meta("shown_at") if bubble.has_meta("shown_at") else 0
		if t < oldest_time:
			oldest_time = t
			oldest = agent
	if oldest:
		_drop(oldest)


func _drop(agent: Node2D) -> void:
	var bubble: PanelContainer = _bubbles.get(agent)
	if bubble:
		var tween: Tween = bubble.get_meta("tween") if bubble.has_meta("tween") else null
		if tween and tween.is_valid():
			tween.kill()
		bubble.queue_free()
	_bubbles.erase(agent)


class _BubbleTail:
	extends Control
	## Triangle pointing down from the bubble's bottom edge.
	var color := Color.BLACK
	var border := Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		queue_redraw()

	func _draw() -> void:
		var cx := size.x / 2.0
		var base_y := size.y
		var points := PackedVector2Array([
			Vector2(cx - 5, base_y),
			Vector2(cx + 5, base_y),
			Vector2(cx, base_y + 5),
		])
		draw_colored_polygon(points, color)
		draw_line(points[0], points[2], border, 1.0)
		draw_line(points[1], points[2], border, 1.0)
