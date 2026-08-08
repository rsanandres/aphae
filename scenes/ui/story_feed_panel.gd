class_name StoryFeedPanel
extends BasePanel
## UI panel showing ranked storylines from the Narrator.

var _scroll: ScrollContainer
var _vbox: VBoxContainer


func _ready() -> void:
	_setup_chrome("Top Stories")
	_build_ui()
	EventBus.storyline_updated.connect(func(_sl: RefCounted) -> void:
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

	var top_stories: Array[Storyline] = Narrator.get_top_storylines(8)
	if top_stories.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No stories yet..."
		empty_lbl.theme_type_variation = "DimLabel"
		_vbox.add_child(empty_lbl)
		return

	for sl in top_stories:
		var entry_box := VBoxContainer.new()

		# Title + drama bar
		var header := HBoxContainer.new()
		var title_lbl := Label.new()
		title_lbl.text = sl.title
		title_lbl.add_theme_color_override("font_color", _drama_color(sl.drama_score))
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		header.add_child(title_lbl)

		var drama_lbl := Label.new()
		drama_lbl.text = "%.0f" % sl.drama_score
		drama_lbl.add_theme_color_override("font_color", _drama_color(sl.drama_score))
		header.add_child(drama_lbl)
		entry_box.add_child(header)

		# Summary or agents
		var detail_lbl := Label.new()
		if sl.summary != "":
			detail_lbl.text = sl.summary
		else:
			detail_lbl.text = "Involving: %s" % ", ".join(sl.involved_agents)
		detail_lbl.theme_type_variation = "DimLabel"
		detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry_box.add_child(detail_lbl)

		entry_box.add_child(HSeparator.new())
		_vbox.add_child(entry_box)


func _drama_color(score: float) -> Color:
	return UIPalette.drama_color(score)
