extends Control
## Main menu: title, new sandbox, continue, settings, quit.
## Features animated background with mini office preview and particle ambience.

var _settings_panel: Control = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _button_container: VBoxContainer = null
var _version_label: Label = null
var _bg_canvas: Node2D = null
var _mini_agents: Array[Dictionary] = []  # {pos, vel, color, flip}


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Animated background (SubViewportContainer with mini office scene)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.08, 0.12, 1.0)
	add_child(bg)

	# Background canvas for animated mini agents
	_bg_canvas = Node2D.new()
	_bg_canvas.modulate.a = 0.25
	add_child(_bg_canvas)
	_bg_canvas.draw.connect(_draw_bg)
	_spawn_mini_agents()

	# Semi-transparent gradient overlay to darken the background behind text
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.06, 0.06, 0.1, 0.65)
	add_child(overlay)

	# Center container
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.custom_minimum_size = Vector2(200, 0)
	center.add_child(vbox)

	# Title with shadow
	_title_label = Label.new()
	_title_label.text = "AYLE"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 32)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	_title_label.add_theme_color_override("font_shadow_color", Color(0.2, 0.15, 0.05, 0.5))
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	vbox.add_child(_title_label)

	# Subtitle
	_subtitle_label = Label.new()
	_subtitle_label.text = "AI Agent Office Simulation"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 9)
	_subtitle_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
	vbox.add_child(_subtitle_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# Buttons
	_button_container = VBoxContainer.new()
	_button_container.add_theme_constant_override("separation", 4)
	vbox.add_child(_button_container)

	_add_button("New Sandbox", _on_new_sandbox)
	if SaveManager.has_save():
		_add_button("Continue", _on_continue)
	_add_button("Settings", _on_settings)
	_add_button("Quit", _on_quit)

	# Version label (bottom-right)
	_version_label = Label.new()
	_version_label.text = "v0.2.0"
	_version_label.add_theme_font_size_override("font_size", 8)
	_version_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
	_version_label.anchor_left = 1.0
	_version_label.anchor_top = 1.0
	_version_label.anchor_right = 1.0
	_version_label.anchor_bottom = 1.0
	_version_label.offset_left = -60
	_version_label.offset_top = -14
	_version_label.offset_right = -4
	_version_label.offset_bottom = -2
	add_child(_version_label)

	# Shortcut hint (bottom-left)
	var hint := Label.new()
	hint.text = "Press any button to begin"
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 4
	hint.offset_top = -14
	hint.offset_right = 140
	hint.offset_bottom = -2
	add_child(hint)

	# Create settings panel (hidden)
	_settings_panel = preload("res://scenes/ui/settings_panel.gd").new()
	_settings_panel.visible = false
	add_child(_settings_panel)

	# Fade in
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.6)

	# Start menu music
	AudioManager.play_music("menu")


func _process(delta: float) -> void:
	_update_mini_agents(delta)
	_bg_canvas.queue_redraw()


func _spawn_mini_agents() -> void:
	# Create a handful of tiny colored dots that wander around the background
	var colors: Array[Color] = [
		Color(0.5, 0.65, 0.9),   # Blue (Alice)
		Color(0.55, 0.8, 0.5),   # Green (Bob)
		Color(0.9, 0.55, 0.6),   # Pink (Clara)
		Color(0.85, 0.75, 0.4),  # Gold (Dave)
		Color(0.7, 0.5, 0.85),   # Purple (Emma)
		Color(0.4, 0.8, 0.75),   # Teal
		Color(0.9, 0.6, 0.35),   # Orange
	]
	var viewport_size := get_viewport_rect().size
	for i in range(colors.size()):
		var agent := {
			"pos": Vector2(randf_range(20, viewport_size.x - 20), randf_range(20, viewport_size.y - 20)),
			"vel": Vector2(randf_range(-8, 8), randf_range(-8, 8)),
			"color": colors[i],
			"flip": false,
			"wander_timer": randf_range(0.0, 3.0),
		}
		_mini_agents.append(agent)


func _update_mini_agents(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	for agent in _mini_agents:
		agent["wander_timer"] -= delta
		if agent["wander_timer"] <= 0.0:
			agent["vel"] = Vector2(randf_range(-12, 12), randf_range(-12, 12))
			agent["wander_timer"] = randf_range(1.5, 4.0)

		var pos: Vector2 = agent["pos"]
		var vel: Vector2 = agent["vel"]
		pos += vel * delta
		# Bounce off edges
		if pos.x < 10 or pos.x > viewport_size.x - 10:
			vel.x = -vel.x
			pos.x = clampf(pos.x, 10, viewport_size.x - 10)
		if pos.y < 10 or pos.y > viewport_size.y - 10:
			vel.y = -vel.y
			pos.y = clampf(pos.y, 10, viewport_size.y - 10)
		agent["pos"] = pos
		agent["vel"] = vel
		agent["flip"] = vel.x < 0


func _draw_bg() -> void:
	# Draw mini grid (office floor feel)
	var viewport_size := get_viewport_rect().size
	var grid_color := Color(0.15, 0.15, 0.2, 0.3)
	for x in range(0, int(viewport_size.x) + 1, 16):
		_bg_canvas.draw_line(Vector2(x, 0), Vector2(x, viewport_size.y), grid_color, 1.0)
	for y in range(0, int(viewport_size.y) + 1, 16):
		_bg_canvas.draw_line(Vector2(0, y), Vector2(viewport_size.x, y), grid_color, 1.0)

	# Draw mini agents as simple sprites
	for agent in _mini_agents:
		var pos: Vector2 = agent["pos"]
		var color: Color = agent["color"]
		# Simple 3-pixel tall character
		_bg_canvas.draw_rect(Rect2(pos.x - 2, pos.y - 4, 4, 2), color.darkened(0.2))  # Head
		_bg_canvas.draw_rect(Rect2(pos.x - 2, pos.y - 2, 4, 3), color)  # Body
		_bg_canvas.draw_rect(Rect2(pos.x - 2, pos.y + 1, 1, 2), color.darkened(0.3))  # Left leg
		_bg_canvas.draw_rect(Rect2(pos.x + 1, pos.y + 1, 1, 2), color.darkened(0.3))  # Right leg


func _add_button(text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(180, 26)

	btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("ui_click", -3.0)
		callback.call()
	)
	_button_container.add_child(btn)


func _on_new_sandbox() -> void:
	_transition_to("res://scenes/main/main.tscn", func() -> void:
		SaveManager.skip_auto_load = true
	)


func _on_continue() -> void:
	var recent_slot: int = SaveManager.get_most_recent_slot()
	SaveManager.current_slot = recent_slot
	SaveManager.skip_auto_load = false
	_transition_to("res://scenes/main/main.tscn")


func _on_settings() -> void:
	AudioManager.play_sfx("ui_click", -3.0)
	_settings_panel.visible = not _settings_panel.visible


func _on_quit() -> void:
	get_tree().quit()


func _transition_to(scene_path: String, pre_callback: Callable = Callable()) -> void:
	# Fade out, then change scene
	AudioManager.stop_music()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func() -> void:
		if pre_callback.is_valid():
			pre_callback.call()
		get_tree().change_scene_to_file(scene_path)
	)
