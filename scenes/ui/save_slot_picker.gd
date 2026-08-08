class_name SaveSlotPicker
extends PanelContainer
## Save/load slot picker UI with 5 slots, overwrite confirmation, and delete option.

signal slot_selected(slot: int)

var _mode: String = "save"  # "save" or "load"
var _content: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(240, 200)
	offset_left = -120
	offset_top = -100
	offset_right = 120
	offset_bottom = 100

	theme = UITheme.get_theme()
	add_theme_stylebox_override("panel", UITheme.make_panel_style())

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 3)
	add_child(_content)


func show_picker(mode: String) -> void:
	_mode = mode
	visible = true
	_rebuild()


func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "Save Game" if _mode == "save" else "Load Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = "HeaderLabel"
	_content.add_child(title)

	var sep := HSeparator.new()
	_content.add_child(sep)

	for i in range(SaveManager.MAX_SLOTS):
		var info := SaveManager.get_slot_info(i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		_content.add_child(row)

		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 9)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if info.get("exists", false):
			btn.text = "Slot %d  Day %d  %d agents  %s" % [
				i + 1, info.get("day", 0), info.get("agent_count", 0),
				str(info.get("save_time", "")).substr(0, 10)
			]
		else:
			btn.text = "Slot %d  [Empty]" % (i + 1)
			if _mode == "load":
				btn.disabled = true

		var slot := i
		var exists: bool = info.get("exists", false)
		btn.pressed.connect(func() -> void:
			if _mode == "save" and exists:
				_confirm_overwrite(slot)
			else:
				_do_action(slot)
		)
		row.add_child(btn)

		# Delete button (only for existing saves)
		if info.get("exists", false):
			var del_btn := Button.new()
			del_btn.text = "X"
			del_btn.add_theme_font_size_override("font_size", 9)
			del_btn.custom_minimum_size = Vector2(18, 0)
			del_btn.tooltip_text = "Delete save"
			var del_style := StyleBoxFlat.new()
			del_style.bg_color = Color(0.3, 0.12, 0.12, 0.8)
			del_style.set_corner_radius_all(2)
			del_style.set_content_margin_all(2)
			del_btn.add_theme_stylebox_override("normal", del_style)
			del_btn.pressed.connect(func() -> void:
				_confirm_delete(slot)
			)
			row.add_child(del_btn)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	_content.add_child(spacer)

	var close := Button.new()
	close.text = "Cancel  [Esc]"
	close.add_theme_font_size_override("font_size", 9)
	close.pressed.connect(func() -> void: visible = false)
	_content.add_child(close)


func _do_action(slot: int) -> void:
	slot_selected.emit(slot)
	if _mode == "save":
		SaveManager.save_game(slot)
	else:
		SaveManager.load_game(slot)
	visible = false


func _confirm_overwrite(slot: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Overwrite save in Slot %d?" % (slot + 1)
	dialog.ok_button_text = "Overwrite"
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		_do_action(slot)
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()


func _confirm_delete(slot: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Delete save in Slot %d? This cannot be undone." % (slot + 1)
	dialog.ok_button_text = "Delete"
	dialog.confirmed.connect(func() -> void:
		SaveManager.delete_save(slot)
		dialog.queue_free()
		_rebuild()
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()
