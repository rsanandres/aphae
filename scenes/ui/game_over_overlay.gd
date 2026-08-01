class_name GameOverOverlay
extends CanvasLayer
## Shown when all agents have died.

var _panel: PanelContainer = null


func _ready() -> void:
	layer = 100
	visible = false
	EventBus.all_agents_dead.connect(_show)


func _show() -> void:
	if _panel:
		return

	# Wait 5 seconds for dramatic effect
	await get_tree().create_timer(5.0).timeout

	visible = true
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.9)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	center.add_child(vbox)

	var msg := Label.new()
	msg.text = "The office has fallen silent."
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 12)
	msg.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(msg)

	var submsg := Label.new()
	submsg.text = "All agents have passed on."
	submsg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	submsg.add_theme_font_size_override("font_size", 9)
	submsg.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	vbox.add_child(submsg)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	# The run is over, so this is the moment its story is worth reading.
	var recap_scroll := ScrollContainer.new()
	recap_scroll.custom_minimum_size = Vector2(280, 120)
	vbox.add_child(recap_scroll)

	var recap_label := RichTextLabel.new()
	recap_label.bbcode_enabled = true
	recap_label.fit_content = true
	recap_label.scroll_active = false
	recap_label.text = EpisodeRecap.build_display()
	recap_label.add_theme_font_size_override("normal_font_size", 8)
	recap_label.add_theme_font_size_override("bold_font_size", 8)
	recap_label.add_theme_color_override("default_color", Color(0.72, 0.72, 0.8))
	recap_label.custom_minimum_size = Vector2(268, 0)
	recap_scroll.add_child(recap_label)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer2)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var retry_btn := Button.new()
	retry_btn.text = "Try Again"
	retry_btn.add_theme_font_size_override("font_size", 9)
	retry_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	)
	btn_row.add_child(retry_btn)

	var load_btn := Button.new()
	load_btn.text = "Load Save"
	load_btn.add_theme_font_size_override("font_size", 9)
	load_btn.disabled = not SaveManager.has_save()
	load_btn.pressed.connect(func() -> void:
		SaveManager.load_game()
		_dismiss()
	)
	btn_row.add_child(load_btn)

	var save_recap_btn := Button.new()
	save_recap_btn.text = "Save Recap"
	save_recap_btn.add_theme_font_size_override("font_size", 9)
	save_recap_btn.pressed.connect(func() -> void:
		var path := EpisodeRecap.export_to_file()
		save_recap_btn.text = "Saved" if path != "" else "Failed"
		save_recap_btn.disabled = path != ""
	)
	btn_row.add_child(save_recap_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Return to Menu"
	menu_btn.add_theme_font_size_override("font_size", 9)
	menu_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	)
	btn_row.add_child(menu_btn)

	# Fade in
	_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_panel, "modulate:a", 1.0, 1.0)


func _dismiss() -> void:
	visible = false
	if _panel:
		_panel.queue_free()
		_panel = null
