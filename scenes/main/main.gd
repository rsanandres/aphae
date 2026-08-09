extends Node2D
## Root scene: starts in expanded mode (1280x720) by default.
## Can shrink to desktop pet mode (480x320 transparent) via context menu.
## All camera behavior lives in $GameCamera; this script only routes input.

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var expanded_mode: bool = true  # Default to expanded
var _camera_panning: bool = false

@onready var _camera: Camera2D = $GameCamera


func _ready() -> void:
	var win := get_window()
	win.mouse_passthrough = false

	# Start in expanded mode
	_setup_expanded_mode()

	# Broadcast director: knows where the drama is, can drive the camera
	var director := BroadcastDirector.new()
	director.setup(_camera)
	add_child(director)

	EventBus.game_ready.emit()

	# Fade in from menu
	modulate.a = 0.0
	var fade_tween := create_tween()
	fade_tween.tween_property(self, "modulate:a", 1.0, 0.5)

	# Game over overlay
	var game_over := GameOverOverlay.new()
	add_child(game_over)

	# Tutorial hint overlay
	var hint_overlay := HintOverlay.new()
	add_child(hint_overlay)

	# Event notification feed (top-right floating notifications)
	var event_notif := EventNotification.new()
	add_child(event_notif)

	# LLM loading overlay
	_setup_loading_overlay()

	# Focus handling. By default the office KEEPS RUNNING while you work and
	# drops to a low-power posture; auto-pause is opt-in for players who want
	# the old foreground behavior.
	get_window().focus_exited.connect(func() -> void:
		if SettingsManager.auto_pause_on_focus_loss:
			if not TimeManager.is_paused:
				TimeManager.toggle_pause()
			return
		AmbientMode.enter_background()
	)
	get_window().focus_entered.connect(func() -> void:
		var digest := AmbientMode.exit_background()
		if not digest.is_empty():
			EventBus.away_digest_ready.emit(digest)
	)

	# Try loading save on startup (unless "New Sandbox" was chosen)
	var fresh_sandbox := not (SaveManager.has_save() and not SaveManager.skip_auto_load)
	if not fresh_sandbox:
		call_deferred("_try_load_save")
	SaveManager.skip_auto_load = false

	# Cold open: on a brand-new sandbox the cast introduces itself to camera,
	# so the first minutes have personality instead of silent wandering.
	if fresh_sandbox:
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			ConfessionalDirector.request_cast_intros()
		)


func _try_load_save() -> void:
	var slot: int = SaveManager.current_slot
	# Get summary before loading (reads save file)
	var summary: String = SaveManager.get_load_summary(slot)
	SaveManager.load_game(slot)
	# Show "While you were away" overlay if there's meaningful info
	if summary != "":
		_show_load_summary(summary)


func _show_load_summary(summary: String) -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 92
	add_child(overlay)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.1, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = Color(0.4, 0.5, 0.6, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(220, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Welcome Back"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var content := Label.new()
	content.text = summary
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_theme_font_size_override("font_size", 9)
	content.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	vbox.add_child(content)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer)

	var btn := Button.new()
	btn.text = "Continue"
	btn.add_theme_font_size_override("font_size", 9)
	btn.pressed.connect(func() -> void:
		overlay.queue_free()
	)
	vbox.add_child(btn)

	# Fade in
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.5)


func _setup_expanded_mode() -> void:
	var win := get_window()
	win.transparent = false
	get_viewport().transparent_bg = false
	win.borderless = false
	win.always_on_top = false
	win.min_size = Vector2i(480, 320)
	_camera.center_on_office()


func set_expanded_mode(enable: bool) -> void:
	if expanded_mode == enable:
		return
	expanded_mode = enable
	var win := get_window()
	if enable:
		win.transparent = false
		get_viewport().transparent_bg = false
		win.borderless = false
		win.always_on_top = false
		win.size = Vector2i(1280, 720)
		win.min_size = Vector2i(480, 320)
		var world := get_tree().get_first_node_in_group("world")
		if world and world.has_method("resize_for_agents"):
			world.resize_for_agents(AgentManager.agents.size())
		_camera.center_on_office()
	else:
		win.transparent = true
		get_viewport().transparent_bg = true
		win.borderless = true
		win.always_on_top = true
		win.size = Vector2i(Config.DESKTOP_WINDOW_WIDTH, Config.DESKTOP_WINDOW_HEIGHT)
		var world := get_tree().get_first_node_in_group("world")
		if world and world.has_method("resize_for_agents"):
			world.resize_for_agents(Config.MAX_AGENTS_DESKTOP)
		_camera.fit_office()


func _unhandled_input(event: InputEvent) -> void:
	# Screenshot key (F12)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_take_screenshot()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if expanded_mode:
			_handle_expanded_input(event)
		else:
			_handle_desktop_input(event)

	elif event is InputEventMouseMotion:
		if expanded_mode and _camera_panning:
			_camera.pan_screen(event.relative)
		elif not expanded_mode and _dragging:
			var mouse_pos := DisplayServer.mouse_get_position()
			get_window().position = Vector2i(
				int(mouse_pos.x) + int(_drag_offset.x),
				int(mouse_pos.y) + int(_drag_offset.y)
			)

	elif expanded_mode and event is InputEventMagnifyGesture:
		# macOS trackpad pinch-to-zoom
		_camera.zoom_by_factor(event.factor)

	elif expanded_mode and event is InputEventPanGesture:
		# macOS trackpad two-finger pan
		_camera.pan_screen(-event.delta * 3.0)


func _handle_desktop_input(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_window().position - Vector2i(
				int(DisplayServer.mouse_get_position().x),
				int(DisplayServer.mouse_get_position().y)
			)
		else:
			_dragging = false
		EventBus.agent_deselected.emit()


func _handle_expanded_input(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		EventBus.agent_deselected.emit()
	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		_camera_panning = event.pressed
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_camera.zoom_in()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_camera.zoom_out()


func _take_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "user://screenshot_%s.png" % timestamp
	img.save_png(path)
	EventBus.narrative_event.emit("Screenshot saved.", [], 1.0)


func _setup_loading_overlay() -> void:
	# Show overlay while bundled LLM loads
	var overlay := CanvasLayer.new()
	overlay.layer = 95
	overlay.name = "LoadingOverlay"
	add_child(overlay)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.05, 0.08, 0.85)
	bg.visible = false
	overlay.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)

	var lbl := Label.new()
	lbl.text = "Loading AI brain..."
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(lbl)

	# Show while model is loading
	LLMManager.model_loading.connect(func(is_loading: bool) -> void:
		if is_loading:
			bg.visible = true
			bg.modulate.a = 1.0
		else:
			# Fade out then remove
			var tween := create_tween()
			tween.tween_property(bg, "modulate:a", 0.0, 0.5)
			tween.tween_callback(func() -> void:
				overlay.queue_free()
			)
	)
