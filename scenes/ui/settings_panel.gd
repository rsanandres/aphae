extends PanelContainer
## Settings panel: audio, display, LLM, game options.


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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = "HeaderLabel"
	vbox.add_child(title)

	# --- Audio ---
	_add_section(vbox, "Audio")
	_add_slider(vbox, "Master", SettingsManager.master_volume, func(v: float) -> void: SettingsManager.set_master_volume(v))
	_add_slider(vbox, "Music", SettingsManager.music_volume, func(v: float) -> void: SettingsManager.set_music_volume(v))
	_add_slider(vbox, "SFX", SettingsManager.sfx_volume, func(v: float) -> void: SettingsManager.set_sfx_volume(v))

	# --- Display ---
	_add_section(vbox, "Display")
	_add_checkbox(vbox, "Fullscreen", SettingsManager.fullscreen, func(v: bool) -> void:
		SettingsManager.fullscreen = v
		SettingsManager.set_fullscreen(v)
	)
	_add_checkbox(vbox, "Auto-pause on focus loss", SettingsManager.auto_pause_on_focus_loss, func(v: bool) -> void:
		SettingsManager.auto_pause_on_focus_loss = v
	)

	# --- LLM ---
	_add_section(vbox, "AI Backend")
	var llm_options := ["Auto (Recommended)", "Bundled Only", "Ollama Only", "Heuristic Only"]
	_add_dropdown(vbox, "Backend", llm_options, _llm_backend_to_index(SettingsManager.llm_backend), func(idx: int) -> void:
		SettingsManager.llm_backend = _index_to_llm_backend(idx)
	)

	# Ollama URL
	_add_text_input(vbox, "Ollama URL", SettingsManager.ollama_url, func(text: String) -> void:
		SettingsManager.ollama_url = text
	)

	# --- Game ---
	_add_section(vbox, "Game")
	_add_slider_int(vbox, "Max Agents", SettingsManager.max_agents, 3, 50, func(v: int) -> void:
		SettingsManager.max_agents = v
	)

	# Save & Close buttons
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(func() -> void:
		SettingsManager.save_settings()
	)
	btn_row.add_child(save_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func() -> void:
		SettingsManager.save_settings()
		visible = false
	)
	btn_row.add_child(close_btn)


func _add_section(parent: VBoxContainer, title: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var lbl := Label.new()
	lbl.text = title
	lbl.theme_type_variation = "DimLabel"
	parent.add_child(lbl)


func _add_slider(parent: VBoxContainer, label_text: String, initial: float, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(60, 0)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(80, 0)
	slider.value_changed.connect(callback)
	row.add_child(slider)


func _add_slider_int(parent: VBoxContainer, label_text: String, initial: int, min_val: int, max_val: int, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(60, 0)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 1
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(80, 0)

	var val_label := Label.new()
	val_label.text = str(initial)
	val_label.custom_minimum_size = Vector2(20, 0)

	slider.value_changed.connect(func(v: float) -> void:
		val_label.text = str(int(v))
		callback.call(int(v))
	)
	row.add_child(slider)
	row.add_child(val_label)


func _add_checkbox(parent: VBoxContainer, label_text: String, initial: bool, callback: Callable) -> void:
	var cb := CheckBox.new()
	cb.text = label_text
	cb.button_pressed = initial
	cb.toggled.connect(callback)
	parent.add_child(cb)


func _add_dropdown(parent: VBoxContainer, label_text: String, options: Array, selected: int, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(60, 0)
	row.add_child(lbl)

	var opt := OptionButton.new()
	for o in options:
		opt.add_item(o)
	opt.selected = selected
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.item_selected.connect(callback)
	row.add_child(opt)


func _add_text_input(parent: VBoxContainer, label_text: String, initial: String, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(60, 0)
	row.add_child(lbl)

	var input := LineEdit.new()
	input.text = initial
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(callback)
	row.add_child(input)


func _llm_backend_to_index(backend: String) -> int:
	match backend:
		"auto": return 0
		"bundled": return 1
		"ollama": return 2
		"heuristic": return 3
		_: return 0


func _index_to_llm_backend(idx: int) -> String:
	match idx:
		0: return "auto"
		1: return "bundled"
		2: return "ollama"
		3: return "heuristic"
		_: return "auto"
