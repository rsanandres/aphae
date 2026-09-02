class_name GodToolbar
extends CanvasLayer
## The Tab toolbar, two postures (Roadmap Now #5 — the economy gate):
##  - SET DESIGN (default): the placement palette runs through Influence.
##    Objects carry prices, categories unlock progressively on lifetime
##    episodes, and the cheat tabs (spawn agents, trigger events) are gone.
##  - CREATIVE: everything free, everything visible — and the save is
##    flagged for good the first time it's switched on. A labeled choice,
##    not a hidden key that voids the economy.

var _enabled: bool = false
var _toolbar: HBoxContainer
var _object_panel: VBoxContainer
var _agent_panel: VBoxContainer
var _event_panel: VBoxContainer
var _groups_panel: VBoxContainer
var _stories_panel: VBoxContainer
var _inspect_mode: bool = false
var _placing_object_type: String = ""
var _panel_bg: PanelContainer
var _agent_count_label: Label
var _agents_btn: Button
var _events_btn: Button
var _creative_btn: Button
var _mode_label: Label


func _ready() -> void:
	layer = 10
	_build_toolbar()
	_build_panels()
	visible = false
	EventBus.god_mode_toggled.connect(_on_god_mode_toggled)
	EventBus.creative_mode_changed.connect(func(_on: bool) -> void: _refresh_mode())


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _placing_object_type != "" and event.position.y > 20:
			_place_object_at(event.position)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _enabled and _agent_count_label:
		_agent_count_label.text = "Agents: %d" % AgentManager.agents.size()


func _on_god_mode_toggled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	if not enabled:
		_hide_all_panels()
		_placing_object_type = ""


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.theme = UITheme.get_theme()
	# Below the status bar (y 4..18) — at the old y 2 the two overlapped.
	_toolbar.offset_left = 10
	_toolbar.offset_top = 22
	_toolbar.offset_right = 620
	_toolbar.offset_bottom = 40
	_toolbar.add_theme_constant_override("separation", 4)
	add_child(_toolbar)

	_add_toolbar_button("Objects", _toggle_object_panel)
	_agents_btn = _add_toolbar_button("Agents", _toggle_agent_panel)
	_events_btn = _add_toolbar_button("Events", _toggle_event_panel)
	_add_toolbar_button("Groups", _toggle_groups_panel)
	_add_toolbar_button("Stories", _toggle_stories_panel)
	_add_toolbar_button("Inspect", _toggle_inspect)
	_creative_btn = _add_toolbar_button("Creative: off", _toggle_creative)
	_creative_btn.custom_minimum_size = Vector2(64, 14)
	_creative_btn.tooltip_text = "Free placement, spawns, and events — flags this save as Creative permanently."

	# Agent count
	_agent_count_label = Label.new()
	_agent_count_label.text = "Agents: 0"
	_agent_count_label.add_theme_font_size_override("font_size", 9)
	_agent_count_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	_toolbar.add_child(_agent_count_label)

	# Mode label: SET DESIGN or CREATIVE MODE
	_mode_label = Label.new()
	_mode_label.add_theme_font_size_override("font_size", 9)
	_toolbar.add_child(_mode_label)
	_refresh_mode()


func _build_panels() -> void:
	_panel_bg = PanelContainer.new()
	_panel_bg.theme = UITheme.get_theme()
	_panel_bg.add_theme_stylebox_override("panel", UITheme.make_panel_style())
	_panel_bg.offset_left = 10
	_panel_bg.offset_top = 44
	_panel_bg.offset_right = 230
	_panel_bg.offset_bottom = 326
	_panel_bg.visible = false
	add_child(_panel_bg)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_bg.add_child(scroll)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_vbox)

	_object_panel = VBoxContainer.new()
	_object_panel.visible = false
	panel_vbox.add_child(_object_panel)

	_agent_panel = VBoxContainer.new()
	_agent_panel.visible = false
	panel_vbox.add_child(_agent_panel)

	_event_panel = VBoxContainer.new()
	_event_panel.visible = false
	panel_vbox.add_child(_event_panel)

	_groups_panel = VBoxContainer.new()
	_groups_panel.visible = false
	panel_vbox.add_child(_groups_panel)

	_stories_panel = VBoxContainer.new()
	_stories_panel.visible = false
	panel_vbox.add_child(_stories_panel)


func _add_toolbar_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(40, 14)
	btn.add_theme_font_size_override("font_size", 9)
	btn.pressed.connect(callback)
	_toolbar.add_child(btn)
	return btn


func _toggle_creative() -> void:
	ProducerEconomy.set_creative_mode(not ProducerEconomy.creative_mode)
	_hide_all_panels()
	_placing_object_type = ""


func _refresh_mode() -> void:
	var creative := ProducerEconomy.creative_mode
	# The cheat tabs exist only in Creative; Set Design is set design.
	_agents_btn.visible = creative
	_events_btn.visible = creative
	_creative_btn.text = "Creative: %s" % ("ON" if creative else "off")
	_mode_label.text = "CREATIVE MODE" if creative else "SET DESIGN"
	_mode_label.add_theme_color_override("font_color",
		Color(1.0, 0.8, 0.3, 0.9) if creative else Color(0.6, 0.8, 1.0, 0.9))


func _toggle_object_panel() -> void:
	_hide_all_panels()
	_object_panel.visible = not _object_panel.visible
	_panel_bg.visible = _object_panel.visible
	if _object_panel.visible:
		_rebuild_object_panel()


func _toggle_agent_panel() -> void:
	_hide_all_panels()
	_agent_panel.visible = not _agent_panel.visible
	_panel_bg.visible = _agent_panel.visible
	if _agent_panel.visible:
		_rebuild_agent_panel()


func _toggle_event_panel() -> void:
	_hide_all_panels()
	_event_panel.visible = not _event_panel.visible
	_panel_bg.visible = _event_panel.visible
	if _event_panel.visible:
		_rebuild_event_panel()


func _toggle_groups_panel() -> void:
	_hide_all_panels()
	_groups_panel.visible = not _groups_panel.visible
	_panel_bg.visible = _groups_panel.visible
	if _groups_panel.visible:
		_rebuild_groups_panel()


func _toggle_stories_panel() -> void:
	_hide_all_panels()
	_stories_panel.visible = not _stories_panel.visible
	_panel_bg.visible = _stories_panel.visible
	if _stories_panel.visible:
		_rebuild_stories_panel()


func _toggle_inspect() -> void:
	_inspect_mode = not _inspect_mode
	_hide_all_panels()


func _hide_all_panels() -> void:
	_object_panel.visible = false
	_agent_panel.visible = false
	_event_panel.visible = false
	_groups_panel.visible = false
	_stories_panel.visible = false
	_panel_bg.visible = false


func _rebuild_object_panel() -> void:
	for child in _object_panel.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Place Object"
	title.add_theme_font_size_override("font_size", 9)
	_object_panel.add_child(title)

	# 113 placeable types (13 bespoke + the data catalog) need a scroll and
	# categories, not a flat column that runs off the screen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(150, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_object_panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var groups: Dictionary = {"classic": ["desk", "couch", "coffee_machine", "water_cooler",
		"whiteboard", "bookshelf", "plant", "radio", "bed", "karaoke_machine",
		"arcade_cabinet", "meditation_pod", "aquarium"]}
	groups.merge(DataObject.get_ids_by_category())
	for cat in groups.keys():
		var header := Label.new()
		header.text = str(cat).capitalize()
		header.add_theme_font_size_override("font_size", 9)
		header.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
		list.add_child(header)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 2)
		grid.add_theme_constant_override("v_separation", 1)
		list.add_child(grid)
		for t in groups[cat]:
			var btn := Button.new()
			var def := DataObject.get_def(t)
			var display := str(def.get("name", str(t).replace("_", " ").capitalize()))
			if ProducerEconomy.creative_mode:
				btn.text = display
			elif not ProducerEconomy.is_placement_unlocked(str(t)):
				btn.text = display
				btn.disabled = true
				btn.tooltip_text = ProducerEconomy.placement_unlock_text(str(t))
			else:
				# Show mode: the price IS the interface — placement spends it.
				btn.text = "%s ¤%d" % [display, ProducerEconomy.placement_price(str(t))]
			btn.clip_text = true
			btn.custom_minimum_size = Vector2(72, 0)
			btn.add_theme_font_size_override("font_size", 8)
			btn.pressed.connect(_on_select_object_type.bind(str(t)))
			grid.add_child(btn)


func _rebuild_agent_panel() -> void:
	for child in _agent_panel.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Agents (%d)" % AgentManager.agents.size()
	title.add_theme_font_size_override("font_size", 9)
	_agent_panel.add_child(title)

	# Spawn buttons for presets
	var personalities := ["alice", "bob", "clara", "dave", "emma"]
	for p in personalities:
		var btn := Button.new()
		btn.text = "Spawn %s" % p.capitalize()
		btn.add_theme_font_size_override("font_size", 9)
		btn.pressed.connect(_on_spawn_agent.bind(p))
		_agent_panel.add_child(btn)

	_agent_panel.add_child(HSeparator.new())

	# Procedural spawn buttons
	var spawn_one := Button.new()
	spawn_one.text = "Spawn Random Agent"
	spawn_one.add_theme_font_size_override("font_size", 9)
	spawn_one.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	spawn_one.pressed.connect(_on_spawn_random)
	_agent_panel.add_child(spawn_one)

	var spawn_ten := Button.new()
	spawn_ten.text = "Spawn 10 Random"
	spawn_ten.add_theme_font_size_override("font_size", 9)
	spawn_ten.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	spawn_ten.pressed.connect(_on_spawn_batch)
	_agent_panel.add_child(spawn_ten)

	_agent_panel.add_child(HSeparator.new())

	# Remove buttons for existing agents
	for agent in AgentManager.agents:
		var btn := Button.new()
		btn.text = "X %s" % agent.agent_name
		btn.add_theme_font_size_override("font_size", 9)
		btn.pressed.connect(_on_remove_agent.bind(agent.agent_name))
		_agent_panel.add_child(btn)


func _rebuild_event_panel() -> void:
	for child in _event_panel.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Trigger Event"
	title.add_theme_font_size_override("font_size", 9)
	_event_panel.add_child(title)

	var events := EventManager.get_available_events()
	for ev in events:
		var btn := Button.new()
		btn.text = ev.event_name
		btn.add_theme_font_size_override("font_size", 9)
		btn.tooltip_text = ev.description
		btn.pressed.connect(_on_trigger_event.bind(ev.event_id))
		_event_panel.add_child(btn)


func _rebuild_groups_panel() -> void:
	for child in _groups_panel.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Social Groups (%d)" % GroupManager.groups.size()
	title.add_theme_font_size_override("font_size", 9)
	_groups_panel.add_child(title)

	if GroupManager.groups.is_empty():
		var empty := Label.new()
		empty.text = "No groups formed yet."
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		_groups_panel.add_child(empty)
		return

	for group in GroupManager.groups:
		var box := VBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = group.group_name
		name_lbl.add_theme_font_size_override("font_size", 9)
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
		box.add_child(name_lbl)

		var members_lbl := Label.new()
		members_lbl.text = "%s (%s)" % [", ".join(group.members), group.group_type]
		members_lbl.add_theme_font_size_override("font_size", 9)
		members_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(members_lbl)

		if not group.rival_groups.is_empty():
			var rival_lbl := Label.new()
			rival_lbl.text = "Rivals: %d groups" % group.rival_groups.size()
			rival_lbl.add_theme_font_size_override("font_size", 9)
			rival_lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
			box.add_child(rival_lbl)

		box.add_child(HSeparator.new())
		_groups_panel.add_child(box)


func _rebuild_stories_panel() -> void:
	for child in _stories_panel.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "Top Storylines"
	title.add_theme_font_size_override("font_size", 9)
	_stories_panel.add_child(title)

	var top: Array[Storyline] = Narrator.get_top_storylines(5)
	if top.is_empty():
		var empty := Label.new()
		empty.text = "No storylines yet."
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		_stories_panel.add_child(empty)
		return

	for sl in top:
		var box := VBoxContainer.new()
		var title_lbl := Label.new()
		title_lbl.text = "%s (%.0f)" % [sl.title, sl.drama_score]
		title_lbl.add_theme_font_size_override("font_size", 9)
		title_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(title_lbl)

		if sl.summary != "":
			var sum_lbl := Label.new()
			sum_lbl.text = sl.summary
			sum_lbl.add_theme_font_size_override("font_size", 9)
			sum_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(sum_lbl)

		box.add_child(HSeparator.new())
		_stories_panel.add_child(box)


func _on_select_object_type(obj_type: String) -> void:
	_placing_object_type = obj_type
	_hide_all_panels()


func _place_object_at(pos: Vector2) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if not world:
		return
	# Show mode pays on placement, same contract as the Catalog. Creative
	# places free — and the save already wears the flag for it.
	if not ProducerEconomy.creative_mode:
		if not ProducerEconomy.is_placement_unlocked(_placing_object_type):
			_placing_object_type = ""
			return
		var price := ProducerEconomy.placement_price(_placing_object_type)
		if not ProducerEconomy.spend(price, "place_" + _placing_object_type):
			EventBus.narrative_event.emit("Not enough Influence for that (¤%d)." % price, [], 1.0)
			_placing_object_type = ""
			return
	var obj := _create_object(_placing_object_type)
	if obj:
		# pos is a SCREEN coordinate; the world lives behind a zoom-2 camera.
		# Passing it raw placed objects in the wrong spot whenever the view
		# was panned or zoomed — convert through the canvas transform.
		var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * pos
		world.add_object(obj, world_pos)
	_placing_object_type = ""


func _create_object(obj_type: String) -> InteractableObject:
	return ObjectFactory.create(obj_type)



func _on_spawn_agent(personality_file: String) -> void:
	var spawn_pos := Vector2(randf_range(50, 400), randf_range(50, 250))
	AgentManager.spawn_agent(personality_file, spawn_pos)
	_hide_all_panels()


func _on_spawn_random() -> void:
	var world := get_tree().get_first_node_in_group("world")
	var bounds := Rect2(50, 50, 380, 200)
	if world and world.has_method("get_bounds"):
		bounds = world.get_bounds()
	var pos := Vector2(
		randf_range(bounds.position.x + 20, bounds.end.x - 20),
		randf_range(bounds.position.y + 20, bounds.end.y - 20),
	)
	AgentManager.spawn_procedural_agent(pos)
	_rebuild_agent_panel()


func _on_spawn_batch() -> void:
	var world := get_tree().get_first_node_in_group("world")
	var bounds := Rect2(50, 50, 380, 200)
	if world and world.has_method("get_bounds"):
		bounds = world.get_bounds()
	for i in range(10):
		var pos := Vector2(
			randf_range(bounds.position.x + 20, bounds.end.x - 20),
			randf_range(bounds.position.y + 20, bounds.end.y - 20),
		)
		AgentManager.spawn_procedural_agent(pos)
	# Auto-expand office if needed
	if world and world.has_method("resize_for_agents"):
		world.resize_for_agents(AgentManager.agents.size())
	_rebuild_agent_panel()


func _on_remove_agent(agent_name: String) -> void:
	AgentManager.remove_agent(agent_name)
	_hide_all_panels()


func _on_trigger_event(event_id: String) -> void:
	EventManager.trigger_event(event_id)
	_hide_all_panels()
