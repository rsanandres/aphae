class_name ConfessionalFeed
extends PanelContainer
## Scrollable history of reality-TV confessionals recorded by ConfessionalDirector.

var _scroll: ScrollContainer
var _vbox: VBoxContainer
var _title: Label


func _ready() -> void:
	custom_minimum_size = Vector2(230, 160)
	visible = false
	_build_ui()
	EventBus.confessional_recorded.connect(func(_c: RefCounted) -> void:
		if visible:
			_rebuild_display()
	)


func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild_display()


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(outer)

	_title = Label.new()
	_title.text = "Confessional Cam"
	_title.add_theme_font_size_override("font_size", 10)
	_title.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	outer.add_child(_title)

	outer.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_vbox)


func _rebuild_display() -> void:
	for child in _vbox.get_children():
		child.queue_free()

	var recent: Array[Confessional] = ConfessionalDirector.get_recent(20)
	if recent.is_empty():
		var empty := Label.new()
		empty.text = "No confessionals yet. Drama takes time..."
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_vbox.add_child(empty)
		return

	# Newest first — most recent drama at the top.
	for i in range(recent.size() - 1, -1, -1):
		var c: Confessional = recent[i]
		var box := VBoxContainer.new()

		var who := Label.new()
		who.text = "%s  [Day %d %s]" % [c.speaker, c.day, c.timestamp]
		who.add_theme_font_size_override("font_size", 9)
		who.add_theme_color_override("font_color", c.color)
		box.add_child(who)

		var quote := Label.new()
		quote.text = "\"%s\"" % c.line
		quote.add_theme_font_size_override("font_size", 9)
		quote.add_theme_color_override("font_color", Color(0.8, 0.8, 0.88))
		quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(quote)

		box.add_child(HSeparator.new())
		_vbox.add_child(box)

	_scroll.call_deferred("set_v_scroll", 0)
