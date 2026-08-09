class_name AwayDigestPanel
extends BasePanel
## "While you were away" — the check-in half of ambient play. The office kept
## living; this is the catch-up. Only appears when enough actually happened
## (AmbientMode gates on time away and event count), so a quick alt-tab is
## never punished with a popup.

var _intro: Label
var _list: VBoxContainer


func _ready() -> void:
	_setup_chrome("While You Were Away", UIPalette.ACCENT_COOL)
	custom_minimum_size = Vector2(260, 0)

	_intro = Label.new()
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_intro)

	body.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	EventBus.away_digest_ready.connect(_on_digest)


func _on_digest(entries: Array) -> void:
	for child in _list.get_children():
		child.queue_free()

	_intro.text = "The office didn't wait for you. %d things happened:" % entries.size()
	for entry in entries:
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.text = "[Day %d %s] %s" % [entry.get("day", 0), entry.get("time", ""), entry.get("text", "")]
		match entry.get("kind", ""):
			"confessional":
				row.add_theme_color_override("font_color", UIPalette.ACCENT_REC)
			"episode":
				row.add_theme_color_override("font_color", UIPalette.ACCENT_WARM)
			_:
				row.add_theme_color_override("font_color", UIPalette.TEXT)
		_list.add_child(row)
	open()
