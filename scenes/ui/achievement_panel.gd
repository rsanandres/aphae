extends PanelContainer
## Grid viewer showing all achievements and unlock status.

var _content: VBoxContainer = null


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(280, 240)
	offset_left = -140
	offset_top = -120
	offset_right = 140
	offset_bottom = 120
	add_theme_stylebox_override("panel", UITheme.make_panel_style())

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 2)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	_rebuild()
	EventBus.achievement_unlocked.connect(func(_id: String, _name: String) -> void:
		_rebuild()
	)


func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild()


func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()

	# Title
	var title := Label.new()
	title.text = "Achievements (%d/%d)" % [AchievementManager.get_unlocked_count(), AchievementManager.get_total_count()]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = "HeaderLabel"
	_content.add_child(title)

	var sep := HSeparator.new()
	_content.add_child(sep)

	var all := AchievementManager.get_all()
	for a in all:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_content.add_child(row)

		var icon := Label.new()
		icon.text = "[x]" if a["unlocked"] else "[ ]"
		icon.add_theme_color_override("font_color", UIPalette.ACCENT_WARM if a["unlocked"] else UIPalette.TEXT_FAINT)
		icon.custom_minimum_size = Vector2(20, 0)
		row.add_child(icon)

		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		row.add_child(info)

		var name_lbl := Label.new()
		name_lbl.text = a["name"]
		name_lbl.add_theme_color_override("font_color", UIPalette.TEXT if a["unlocked"] else UIPalette.TEXT_FAINT)
		info.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = a["description"]
		desc_lbl.theme_type_variation = "DimLabel"
		info.add_child(desc_lbl)

	# Close button
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: visible = false)
	_content.add_child(close)
