class_name NarrativeLog
extends PanelContainer
## Scrollable log with tabbed Events / Stories view.

var _entries: Array[Dictionary] = []  # {text, agents, importance, timestamp, day}
var _talk_entries: Array[Dictionary] = []  # {speaker, line, timestamp, day}
var _vbox: VBoxContainer
var _scroll: ScrollContainer
var _tab_bar: HBoxContainer
var _events_btn: Button
var _stories_btn: Button
var _talk_btn: Button
var _content_vbox: VBoxContainer
var _active_tab: String = "events"
const MAX_ENTRIES := 100
const MAX_TALK_ENTRIES := 200


func _ready() -> void:
	theme = UITheme.get_theme()
	# Must fit the rect HUD assigns — a larger minimum silently wins over the
	# offsets and pushes the panel over the world view.
	custom_minimum_size = Vector2(240, 104)
	clip_contents = true  # long entries must not spill outside the panel
	add_theme_stylebox_override("panel", UITheme.make_panel_style(UIPalette.BORDER_DIM))
	visible = true  # Visible by default
	_build_ui()
	EventBus.narrative_event.connect(_on_narrative_event)
	# Subscribe to more detailed events
	EventBus.agent_state_changed.connect(_on_agent_state_changed)
	EventBus.agent_action_started.connect(_on_agent_action_started)
	EventBus.conversation_started.connect(_on_conversation_started)
	EventBus.conversation_line.connect(_on_conversation_line)
	EventBus.conversation_ended.connect(_on_conversation_ended)


func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild_display()


func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(outer)

	# Tab bar
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 2)
	outer.add_child(_tab_bar)

	_events_btn = Button.new()
	_events_btn.text = "Events"
	_events_btn.add_theme_font_size_override("font_size", 9)
	_events_btn.pressed.connect(_show_events_tab)
	_tab_bar.add_child(_events_btn)

	_stories_btn = Button.new()
	_stories_btn.text = "Stories"
	_stories_btn.add_theme_font_size_override("font_size", 9)
	_stories_btn.pressed.connect(_show_stories_tab)
	_tab_bar.add_child(_stories_btn)

	_talk_btn = Button.new()
	_talk_btn.text = "Talk"
	_talk_btn.add_theme_font_size_override("font_size", 9)
	_talk_btn.pressed.connect(_show_talk_tab)
	_tab_bar.add_child(_talk_btn)

	outer.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)

	_content_vbox = VBoxContainer.new()
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content_vbox)


func _show_events_tab() -> void:
	_active_tab = "events"
	_rebuild_display()


func _show_stories_tab() -> void:
	_active_tab = "stories"
	_rebuild_display()


func _show_talk_tab() -> void:
	_active_tab = "talk"
	_rebuild_display()


func _on_narrative_event(text: String, agents: Array, importance: float) -> void:
	var entry := {
		"text": text,
		"agents": agents,
		"importance": importance,
		"timestamp": TimeManager.time_string,
		"day": TimeManager.day,
	}
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	if visible and _active_tab == "events":
		_add_event_label(entry)
		_scroll.call_deferred("set_v_scroll", _scroll.get_v_scroll_bar().max_value as int)


func _rebuild_display() -> void:
	for child in _content_vbox.get_children():
		child.queue_free()

	for btn in [_events_btn, _stories_btn, _talk_btn]:
		btn.remove_theme_color_override("font_color")
	if _active_tab == "events":
		_events_btn.add_theme_color_override("font_color", UIPalette.ACCENT_WARM)
		for entry in _entries:
			_add_event_label(entry)
	elif _active_tab == "talk":
		_talk_btn.add_theme_color_override("font_color", UIPalette.ACCENT_WARM)
		for entry in _talk_entries:
			_add_talk_label(entry)
		_scroll.call_deferred("set_v_scroll", _scroll.get_v_scroll_bar().max_value as int)
	else:
		_stories_btn.add_theme_color_override("font_color", UIPalette.ACCENT_WARM)
		_build_stories_view()


func _add_event_label(entry: Dictionary) -> void:
	var lbl := Label.new()
	lbl.text = "[Day %d %s] %s" % [entry["day"], entry["timestamp"], entry["text"]]
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var importance: float = entry["importance"]
	if importance >= 8.0:
		lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	elif importance >= 5.0:
		lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	else:
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_content_vbox.add_child(lbl)


func _build_stories_view() -> void:
	var top: Array[Storyline] = Narrator.get_top_storylines(10)
	if top.is_empty():
		var empty := Label.new()
		empty.text = "No stories yet. Events need time to develop into narratives."
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content_vbox.add_child(empty)
		return

	for sl in top:
		var box := VBoxContainer.new()

		var title_lbl := Label.new()
		title_lbl.text = "%s [%.0f]" % [sl.title, sl.drama_score]
		title_lbl.add_theme_font_size_override("font_size", 9)
		if sl.drama_score >= 7.0:
			title_lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
		elif sl.drama_score >= 4.0:
			title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		else:
			title_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		box.add_child(title_lbl)

		if sl.summary != "":
			var sum_lbl := Label.new()
			sum_lbl.text = sl.summary
			sum_lbl.add_theme_font_size_override("font_size", 9)
			sum_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(sum_lbl)

		var agents_lbl := Label.new()
		agents_lbl.text = ", ".join(sl.involved_agents)
		agents_lbl.add_theme_font_size_override("font_size", 9)
		agents_lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
		box.add_child(agents_lbl)

		box.add_child(HSeparator.new())
		_content_vbox.add_child(box)


func _on_agent_state_changed(agent: Node2D, _old_state: AgentState.Type, new_state: AgentState.Type) -> void:
	if not is_instance_valid(agent):
		return
	# Only log interesting state changes
	match new_state:
		AgentState.Type.WALKING:
			_log_activity(agent.agent_name, "started walking", 0.5)
		AgentState.Type.INTERACTING:
			var target_name := ""
			if agent.current_target and agent.current_target.has_method("get") and "display_name" in agent.current_target:
				target_name = agent.current_target.display_name
			else:
				target_name = "something"
			_log_activity(agent.agent_name, "is using the %s" % target_name, 1.5)
		AgentState.Type.TALKING:
			pass  # Handled by conversation signals


func _on_agent_action_started(agent: Node2D, action: ActionType.Type, target: Node2D) -> void:
	if not is_instance_valid(agent):
		return
	var target_name := "?"
	if target:
		if target.has_method("get") and "display_name" in target:
			target_name = target.display_name
		elif "agent_name" in target:
			target_name = target.agent_name
	match action:
		ActionType.Type.GO_TO_OBJECT:
			_log_activity(agent.agent_name, "heads to the %s" % target_name, 1.0)
		ActionType.Type.TALK_TO_AGENT:
			_log_activity(agent.agent_name, "goes to talk to %s" % target_name, 2.0)
		ActionType.Type.CONFESS_FEELINGS:
			_log_activity(agent.agent_name, "is going to confess feelings to %s!" % target_name, 6.0)
		ActionType.Type.WANDER:
			_log_activity(agent.agent_name, "wanders around", 0.3)


func _on_conversation_started(agent_a: String, agent_b: String) -> void:
	_log_activity(agent_a, "started a conversation with %s" % agent_b, 2.5)


func _on_conversation_line(speaker: String, line: String) -> void:
	# Full, untruncated line — the bubble over the agent's head is the teaser,
	# this tab is the transcript. Kept out of Events, which it used to flood.
	_talk_entries.append({
		"speaker": speaker,
		"line": line,
		"timestamp": TimeManager.time_string,
		"day": TimeManager.day,
	})
	if _talk_entries.size() > MAX_TALK_ENTRIES:
		_talk_entries.pop_front()
	if visible and _active_tab == "talk":
		_add_talk_label(_talk_entries[-1])
		_scroll.call_deferred("set_v_scroll", _scroll.get_v_scroll_bar().max_value as int)


func _add_talk_label(entry: Dictionary) -> void:
	var lbl := Label.new()
	lbl.text = "[%s] %s: %s" % [entry["timestamp"], entry["speaker"], entry["line"]]
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var agent := AgentManager.get_agent_by_name(entry["speaker"]) if AgentManager.has_method("get_agent_by_name") else null
	if agent and "agent_color" in agent:
		lbl.add_theme_color_override("font_color", (agent.agent_color as Color).lightened(0.4))
	_content_vbox.add_child(lbl)


func _on_conversation_ended(agent_a: String, agent_b: String) -> void:
	_log_activity(agent_a, "finished talking with %s" % agent_b, 1.5)


func _log_activity(agent_name: String, text: String, importance: float) -> void:
	var entry := {
		"text": "%s %s" % [agent_name, text],
		"agents": [agent_name],
		"importance": importance,
		"timestamp": TimeManager.time_string,
		"day": TimeManager.day,
	}
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	if visible and _active_tab == "events":
		_add_event_label(entry)
		_scroll.call_deferred("set_v_scroll", _scroll.get_v_scroll_bar().max_value as int)


func get_entries() -> Array[Dictionary]:
	return _entries


func load_entries(entries: Array) -> void:
	_entries.clear()
	for e in entries:
		_entries.append(e)
