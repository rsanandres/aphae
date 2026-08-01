extends CanvasLayer
## Minimal desktop HUD: status bar, agent tooltip on hover/click, right-click menu.
## Integrates god mode toolbar, narrative log, relationship web, agent inspector.

@onready var status_bar: HBoxContainer = $StatusBar
@onready var time_label: Label = $StatusBar/TimeLabel
@onready var speed_label: Label = $StatusBar/SpeedLabel
@onready var llm_label: Label = $StatusBar/LLMLabel
@onready var context_menu: PopupMenu = $ContextMenu

var _selected_agent: Node2D = null
var _god_mode: bool = false
var _drama_label: Label = null
var _pause_overlay: ColorRect = null
var _pause_label: Label = null
var _god_toolbar: GodToolbar
var _agent_inspector: AgentInspector
var _narrative_log: NarrativeLog
var _relationship_web: RelationshipWeb
var _story_feed: StoryFeedPanel
var _confessional_feed: ConfessionalFeed
var _confessional_toast: ConfessionalToast
var _recap_panel: RecapPanel
var _producer_panel: ProducerPanel
var _settings_panel: Control = null
var _achievement_panel: Control = null
var _save_picker: SaveSlotPicker = null


func _ready() -> void:
	EventBus.time_tick.connect(_on_time_tick)
	EventBus.time_speed_changed.connect(_on_speed_changed)
	EventBus.agent_selected.connect(_on_agent_selected)
	EventBus.agent_deselected.connect(_on_agent_deselected)
	LLMManager.ollama_status_changed.connect(func(_a: bool) -> void: _update_llm_label())
	LLMManager.active_backend_changed.connect(func(_b: String) -> void: _update_llm_label())
	context_menu.id_pressed.connect(_on_context_menu)
	_update_time()
	_update_speed()
	_update_llm_label()

	# Drama indicator in status bar
	var sep3 := HSeparator.new()
	sep3.custom_minimum_size = Vector2(12, 0)
	status_bar.add_child(sep3)
	_drama_label = Label.new()
	_drama_label.add_theme_font_size_override("font_size", 10)
	_drama_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8, 0.8))
	status_bar.add_child(_drama_label)

	# Create god mode toolbar
	_god_toolbar = GodToolbar.new()
	add_child(_god_toolbar)

	# Create agent inspector (right side)
	_agent_inspector = AgentInspector.new()
	# Same ordering trap as the narrative log — anchors first, then offsets.
	_agent_inspector.anchors_preset = Control.PRESET_TOP_RIGHT
	_agent_inspector.anchor_left = 1.0
	_agent_inspector.anchor_right = 1.0
	_agent_inspector.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_agent_inspector.offset_left = -150
	_agent_inspector.offset_top = 24
	_agent_inspector.offset_right = -8
	_agent_inspector.offset_bottom = 200
	add_child(_agent_inspector)

	# Create narrative log (bottom-left, always visible)
	_narrative_log = NarrativeLog.new()
	# Anchors MUST be set before offsets: assigning anchors_preset resets the
	# offsets, so the old order silently discarded every value below. That is
	# why the log ignored its bounds and sprayed text across the world view.
	_narrative_log.anchors_preset = Control.PRESET_BOTTOM_LEFT
	_narrative_log.anchor_top = 1.0
	_narrative_log.anchor_bottom = 1.0
	_narrative_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_narrative_log.offset_left = 8
	_narrative_log.offset_top = -120
	_narrative_log.offset_right = 200
	_narrative_log.offset_bottom = -26
	add_child(_narrative_log)

	# Create relationship web (center overlay)
	_relationship_web = RelationshipWeb.new()
	_relationship_web.offset_left = 20
	_relationship_web.offset_top = 24
	_relationship_web.offset_right = 300
	_relationship_web.offset_bottom = 200
	add_child(_relationship_web)

	# Create story feed panel (center-right)
	_story_feed = StoryFeedPanel.new()
	_story_feed.offset_left = 90
	_story_feed.offset_top = 24
	_story_feed.offset_right = 310
	_story_feed.offset_bottom = 200
	add_child(_story_feed)

	# Create confessional feed panel (center-left, toggled with C)
	_confessional_feed = ConfessionalFeed.new()
	_confessional_feed.offset_left = 20
	_confessional_feed.offset_top = 26
	_confessional_feed.offset_right = 250
	_confessional_feed.offset_bottom = 190
	add_child(_confessional_feed)

	# Confessional cutaway toast (lower third, above the icon bar)
	_confessional_toast = ConfessionalToast.new()
	_confessional_toast.anchor_left = 0.5
	_confessional_toast.anchor_right = 0.5
	_confessional_toast.anchor_top = 1.0
	_confessional_toast.anchor_bottom = 1.0
	_confessional_toast.offset_left = -130
	_confessional_toast.offset_right = 130
	_confessional_toast.offset_top = -78
	_confessional_toast.offset_bottom = -30
	_confessional_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confessional_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_confessional_toast)
	EventBus.confessional_recorded.connect(_on_confessional_recorded)

	# Episode recap viewer (center overlay, toggled with E)
	_recap_panel = RecapPanel.new()
	_recap_panel.offset_left = 40
	_recap_panel.offset_top = 26
	_recap_panel.offset_right = 300
	_recap_panel.offset_bottom = 240
	add_child(_recap_panel)

	# Producer panel (right of centre, toggled with P). Acts on the selected
	# agent — the inspector shows you a person, this one lets you touch them.
	_producer_panel = ProducerPanel.new()
	# Viewport is 320x214 — anything past those bounds is simply off-screen.
	_producer_panel.offset_left = 78
	_producer_panel.offset_top = 24
	_producer_panel.offset_right = 308
	_producer_panel.offset_bottom = 200
	add_child(_producer_panel)

	# Persistent icon bar (bottom-center quick access)
	_setup_icon_bar()

	# Achievement toast listener
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)

	# LLM status toast
	LLMManager.ollama_status_changed.connect(_on_llm_status_changed)
	LLMManager.active_backend_changed.connect(_on_llm_backend_changed)

	# Pause visual
	EventBus.time_paused.connect(_on_paused)
	EventBus.time_resumed.connect(_on_resumed)
	_setup_pause_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_show_context_menu(event.global_position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB:
				_toggle_god_mode()
				get_viewport().set_input_as_handled()
			KEY_SPACE:
				TimeManager.toggle_pause()
				get_viewport().set_input_as_handled()
			KEY_1:
				TimeManager.set_speed(1)
				get_viewport().set_input_as_handled()
			KEY_2:
				TimeManager.set_speed(2)
				get_viewport().set_input_as_handled()
			KEY_3:
				TimeManager.set_speed(3)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_close_all_overlays()
				get_viewport().set_input_as_handled()
			KEY_F5:
				SaveManager.save_game()
				get_viewport().set_input_as_handled()
			KEY_F9:
				SaveManager.load_game()
				get_viewport().set_input_as_handled()
			KEY_L:
				_narrative_log.toggle()
				get_viewport().set_input_as_handled()
			KEY_R:
				_relationship_web.toggle()
				get_viewport().set_input_as_handled()
			KEY_C:
				_confessional_feed.toggle()
				get_viewport().set_input_as_handled()
			KEY_E:
				_recap_panel.toggle()
				get_viewport().set_input_as_handled()
			KEY_P:
				_producer_panel.toggle()
				get_viewport().set_input_as_handled()


func _on_time_tick(_gm: float) -> void:
	_update_time()
	_update_drama()


func _on_speed_changed(_i: int) -> void:
	_update_speed()
	# Brief flash on the speed label
	speed_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 1.0))
	var tween := create_tween()
	tween.tween_property(speed_label, "theme_override_colors/font_color", Color(0.75, 0.75, 0.8, 0.8), 0.5)


func _update_time() -> void:
	var agent_count := AgentManager.agents.size()
	if agent_count > Config.MAX_AGENTS_DESKTOP:
		time_label.text = "Day %d  %s  [%d agents]" % [TimeManager.day, TimeManager.time_string, agent_count]
	else:
		time_label.text = "Day %d  %s" % [TimeManager.day, TimeManager.time_string]


func _update_speed() -> void:
	speed_label.text = TimeManager.SPEED_LABELS[TimeManager.speed_index]


func _update_drama() -> void:
	if not _drama_label:
		return
	var level: float = DramaDirector.drama_level
	if level < 1.0:
		_drama_label.text = ""
		return
	var desc: String
	if level >= 7.0:
		desc = "CLIMAX"
		_drama_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 0.9))
	elif level >= 4.0:
		desc = "Tense"
		_drama_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3, 0.85))
	else:
		desc = "Calm"
		_drama_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5, 0.8))
	_drama_label.text = desc


func _update_llm_label() -> void:
	llm_label.text = LLMManager.get_status_text()
	if LLMManager.is_available:
		llm_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	else:
		llm_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))


func _on_confessional_recorded(confessional: RefCounted) -> void:
	var c: Confessional = confessional as Confessional
	if c and _confessional_toast:
		_confessional_toast.show_confessional(c)


func _on_agent_selected(agent: Node2D) -> void:
	_selected_agent = agent


func _on_agent_deselected() -> void:
	_selected_agent = null


func _toggle_god_mode() -> void:
	_god_mode = not _god_mode
	EventBus.god_mode_toggled.emit(_god_mode)


func _close_all_overlays() -> void:
	if _settings_panel and _settings_panel.visible:
		_settings_panel.visible = false
		return
	if _achievement_panel and _achievement_panel.visible:
		_achievement_panel.visible = false
		return
	if _save_picker and _save_picker.visible:
		_save_picker.visible = false
		return
	if _relationship_web.visible:
		_relationship_web.visible = false
		return
	if _story_feed.visible:
		_story_feed.visible = false
		return
	if _confessional_feed.visible:
		_confessional_feed.visible = false
		return
	if _recap_panel.visible:
		_recap_panel.visible = false
		return
	if _producer_panel.visible:
		_producer_panel.visible = false
		return


func _show_context_menu(pos: Vector2) -> void:
	context_menu.clear()
	context_menu.add_item("Pause / Resume  [Space]", 0)
	context_menu.add_item("Speed Up  [>]", 1)
	context_menu.add_item("Speed Down  [<]", 2)
	context_menu.add_separator()
	context_menu.add_item("God Mode  [Tab]", 5)
	context_menu.add_item("Narrative Log  [L]", 6)
	context_menu.add_item("Story Feed", 8)
	context_menu.add_item("Confessional Cam  [C]", 9)
	context_menu.add_item("Episode Recap  [E]", 15)
	context_menu.add_item("Producer  [P]", 16)
	context_menu.add_item("Relationships  [R]", 7)
	context_menu.add_separator()
	var root := get_tree().current_scene
	if root and root.has_method("set_expanded_mode"):
		if root.expanded_mode:
			context_menu.add_item("Shrink to Desktop Pet", 20)
		else:
			context_menu.add_item("Expand to Full Window", 20)
	context_menu.add_separator()
	context_menu.add_item("Reconnect LLM", 3)
	context_menu.add_item("Save  [F5]", 10)
	context_menu.add_item("Load  [F9]", 11)
	context_menu.add_separator()
	context_menu.add_item("Achievements", 13)
	context_menu.add_item("Settings", 12)
	context_menu.add_item("Return to Menu", 14)
	context_menu.add_separator()
	context_menu.add_item("Quit", 99)
	context_menu.position = Vector2i(int(pos.x), int(pos.y))
	context_menu.popup()


func _on_context_menu(id: int) -> void:
	match id:
		0: TimeManager.toggle_pause()
		1: TimeManager.increase_speed()
		2: TimeManager.decrease_speed()
		3: LLMManager.retry_health_check()
		5: _toggle_god_mode()
		6: _narrative_log.toggle()
		7: _relationship_web.toggle()
		8: _story_feed.toggle()
		9: _confessional_feed.toggle()
		15: _recap_panel.toggle()
		10: _show_save_picker("save")
		11: _show_save_picker("load")
		12: _toggle_settings()
		13: _toggle_achievements()
		14: _return_to_menu()
		16: _producer_panel.toggle()
		20:
			var root := get_tree().current_scene
			if root and root.has_method("set_expanded_mode"):
				root.set_expanded_mode(not root.expanded_mode)
		99: _confirm_quit()


func _confirm_quit() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Save and quit?"
	dialog.ok_button_text = "Quit"
	dialog.add_button("Save & Quit", true, "save_quit")
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		get_tree().quit()
	)
	dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "save_quit":
			SaveManager.save_game()
		dialog.queue_free()
		get_tree().quit()
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()


func _toggle_settings() -> void:
	if not _settings_panel:
		_settings_panel = preload("res://scenes/ui/settings_panel.gd").new()
		add_child(_settings_panel)
	_settings_panel.visible = not _settings_panel.visible


func _toggle_achievements() -> void:
	if not _achievement_panel:
		var panel_script := load("res://scenes/ui/achievement_panel.gd")
		if panel_script:
			_achievement_panel = panel_script.new()
			add_child(_achievement_panel)
	if _achievement_panel:
		_achievement_panel.visible = not _achievement_panel.visible


func _show_save_picker(mode: String) -> void:
	if not _save_picker:
		_save_picker = SaveSlotPicker.new()
		add_child(_save_picker)
	_save_picker.show_picker(mode)


func _return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_achievement_unlocked(_id: String, achievement_name: String) -> void:
	var toast := AchievementToast.new()
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 0.0
	toast.offset_left = -80
	toast.offset_right = 80
	toast.offset_top = 4
	toast.offset_bottom = 24
	add_child(toast)
	toast.show_achievement(achievement_name)


func _show_toast(text: String, is_error: bool = false) -> void:
	var toast := ErrorToast.new()
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 0.0
	toast.offset_left = -100
	toast.offset_right = 100
	toast.offset_top = 28
	toast.offset_bottom = 48
	add_child(toast)
	if is_error:
		toast.show_error(text, 4.0)
	else:
		toast.show_warning(text, 3.0)


func _on_llm_status_changed(available: bool) -> void:
	_update_llm_label()
	if available:
		_show_toast("AI brain connected")
	else:
		_show_toast("AI brain offline. Using simpler decisions.", true)


func _on_llm_backend_changed(backend_name: String) -> void:
	_update_llm_label()
	match backend_name:
		"bundled":
			_show_toast("Using bundled AI model")
		"ollama":
			_show_toast("Connected to Ollama")


func _setup_icon_bar() -> void:
	var bar := HBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	# 13 buttons must fit inside a 320px viewport. At 24px wide with 3px gaps
	# the row needed ~358px and was clipped at both ends, losing the pause
	# button and half of SET.
	bar.offset_left = -145
	bar.offset_right = 145
	bar.offset_top = -22
	bar.offset_bottom = -4
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.add_theme_constant_override("separation", 1)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bar)

	# Background for the bar
	var bar_bg := PanelContainer.new()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.08, 0.08, 0.12, 0.8)
	bar_style.border_color = Color(0.25, 0.25, 0.3, 0.6)
	bar_style.set_border_width_all(1)
	bar_style.set_corner_radius_all(3)
	bar_style.set_content_margin_all(2)
	bar_bg.add_theme_stylebox_override("panel", bar_style)
	bar_bg.anchor_left = 0.5
	bar_bg.anchor_right = 0.5
	bar_bg.anchor_top = 1.0
	bar_bg.anchor_bottom = 1.0
	bar_bg.offset_left = -150
	bar_bg.offset_right = 150
	bar_bg.offset_top = -24
	bar_bg.offset_bottom = -2
	bar_bg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar_bg.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_bg)
	# Move bar on top of background
	move_child(bar, get_child_count() - 1)

	_add_icon_btn(bar, "||", "Pause [Space]", func() -> void: TimeManager.toggle_pause())
	_add_icon_btn(bar, "1x", "Speed 1x", func() -> void: TimeManager.set_speed(1))
	_add_icon_btn(bar, "2x", "Speed 2x", func() -> void: TimeManager.set_speed(2))
	_add_icon_btn(bar, "3x", "Speed 3x", func() -> void: TimeManager.set_speed(3))

	var sep1 := VSeparator.new()
	sep1.custom_minimum_size = Vector2(2, 0)
	bar.add_child(sep1)

	_add_icon_btn(bar, "GOD", "God Mode [Tab]", func() -> void: _toggle_god_mode())
	_add_icon_btn(bar, "LOG", "Narrative Log [L]", func() -> void: _narrative_log.toggle())
	_add_icon_btn(bar, "REL", "Relationships [R]", func() -> void: _relationship_web.toggle())
	_add_icon_btn(bar, "CAM", "Confessional Cam [C]", func() -> void: _confessional_feed.toggle())
	_add_icon_btn(bar, "EP", "Episode Recap [E]", func() -> void: _recap_panel.toggle())
	_add_icon_btn(bar, "DIR", "Producer [P]", func() -> void: _producer_panel.toggle())

	var sep2 := VSeparator.new()
	sep2.custom_minimum_size = Vector2(2, 0)
	bar.add_child(sep2)

	_add_icon_btn(bar, "ACH", "Achievements", func() -> void: _toggle_achievements())
	_add_icon_btn(bar, "SET", "Settings", func() -> void: _toggle_settings())


func _add_icon_btn(parent: HBoxContainer, text: String, tooltip: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(20, 16)
	btn.add_theme_font_size_override("font_size", 9)
	btn.pressed.connect(callback)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.6)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(1)
	btn.add_theme_stylebox_override("normal", style)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.25, 0.35, 0.8)
	hover_style.set_corner_radius_all(2)
	hover_style.set_content_margin_all(1)
	btn.add_theme_stylebox_override("hover", hover_style)
	parent.add_child(btn)


func _setup_pause_overlay() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.color = Color(0.05, 0.05, 0.1, 0.3)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	_pause_label = Label.new()
	_pause_label.text = "PAUSED"
	_pause_label.add_theme_font_size_override("font_size", 14)
	_pause_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 0.7))
	_pause_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.15, 0.5))
	_pause_label.add_theme_constant_override("shadow_offset_x", 1)
	_pause_label.add_theme_constant_override("shadow_offset_y", 1)
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.anchor_left = 0.5
	_pause_label.anchor_right = 0.5
	_pause_label.anchor_top = 0.0
	_pause_label.offset_left = -40
	_pause_label.offset_right = 40
	_pause_label.offset_top = 2
	_pause_label.offset_bottom = 18
	_pause_label.visible = false
	add_child(_pause_label)


func _on_paused() -> void:
	_pause_overlay.visible = true
	_pause_label.visible = true
	_pause_label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_pause_label, "modulate:a", 1.0, 0.2)


func _on_resumed() -> void:
	_pause_overlay.visible = false
	_pause_label.visible = false
