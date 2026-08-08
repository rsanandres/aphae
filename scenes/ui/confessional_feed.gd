class_name ConfessionalFeed
extends BasePanel
## Scrollable history of reality-TV confessionals recorded by ConfessionalDirector.

var _scroll: ScrollContainer
var _vbox: VBoxContainer


func _ready() -> void:
	_setup_chrome("Confessional Cam", UIPalette.ACCENT_REC)
	_build_ui()
	EventBus.confessional_recorded.connect(func(_c: RefCounted) -> void:
		if visible:
			_rebuild_display()
	)


func _on_opened() -> void:
	_rebuild_display()


func _build_ui() -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)

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
		empty.theme_type_variation = "DimLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_vbox.add_child(empty)
		return

	# Newest first — most recent drama at the top.
	for i in range(recent.size() - 1, -1, -1):
		var c: Confessional = recent[i]
		var box := VBoxContainer.new()

		var who := Label.new()
		who.text = "%s  [Day %d %s]" % [c.speaker, c.day, c.timestamp]
		who.add_theme_color_override("font_color", c.color)
		box.add_child(who)

		var quote := Label.new()
		quote.text = "\"%s\"" % c.line
		quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(quote)

		box.add_child(HSeparator.new())
		_vbox.add_child(box)

	_scroll.call_deferred("set_v_scroll", 0)
