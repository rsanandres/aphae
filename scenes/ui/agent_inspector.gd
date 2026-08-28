class_name AgentInspector
extends PanelContainer
## Detailed agent inspection panel showing needs, personality, memory, relationships, health.

var _agent: Node2D = null
var _vbox: VBoxContainer
var _name_label: Label
var _personality_label: Label
var _state_label: Label
var _health_label: Label
var _needs_container: VBoxContainer
var _relationships_container: VBoxContainer
var _groups_label: Label
var _storylines_label: Label
var _goals_label: Label
var _memory_label: Label
var _need_bars: Dictionary = {}


func _ready() -> void:
	theme = UITheme.get_theme()
	# Min must not exceed the rect the HUD assigns — a larger minimum silently
	# wins and pushes the panel off-screen (the old 170x250-vs-142x176 bug).
	custom_minimum_size = Vector2(170, 220)
	clip_contents = true
	add_theme_stylebox_override("panel", UITheme.make_panel_style())
	_build_ui()
	visible = false
	EventBus.agent_selected.connect(_on_agent_selected)
	EventBus.agent_deselected.connect(_on_agent_deselected)
	EventBus.agent_need_changed.connect(_on_need_changed)
	EventBus.agent_state_changed.connect(_on_state_changed)
	# Rebuilding relationship rows every render frame churned nodes for no
	# visual gain; a 0.5s pulse is indistinguishable and far cheaper.
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(func() -> void:
		if visible and _agent and is_instance_valid(_agent):
			_update_dynamic()
	)
	add_child(timer)
	timer.start()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 11)
	_vbox.add_child(_name_label)

	_personality_label = Label.new()
	_personality_label.add_theme_font_size_override("font_size", 9)
	_personality_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_personality_label)

	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 9)
	_state_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	_vbox.add_child(_state_label)

	_health_label = Label.new()
	_health_label.add_theme_font_size_override("font_size", 9)
	_vbox.add_child(_health_label)

	var needs_title := Label.new()
	needs_title.text = "Needs"
	needs_title.add_theme_font_size_override("font_size", 9)
	_vbox.add_child(needs_title)

	_needs_container = VBoxContainer.new()
	_vbox.add_child(_needs_container)

	_vbox.add_child(HSeparator.new())

	var rel_title := Label.new()
	rel_title.text = "Relationships"
	rel_title.add_theme_font_size_override("font_size", 9)
	_vbox.add_child(rel_title)

	_relationships_container = VBoxContainer.new()
	_relationships_container.add_theme_constant_override("separation", 1)
	_vbox.add_child(_relationships_container)

	_vbox.add_child(HSeparator.new())

	var grp_title := Label.new()
	grp_title.text = "Groups"
	grp_title.add_theme_font_size_override("font_size", 9)
	_vbox.add_child(grp_title)

	_groups_label = Label.new()
	_groups_label.add_theme_font_size_override("font_size", 9)
	_groups_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_groups_label)

	var sl_title := Label.new()
	sl_title.text = "Active Storylines"
	sl_title.add_theme_font_size_override("font_size", 9)
	_vbox.add_child(sl_title)

	_storylines_label = Label.new()
	_storylines_label.add_theme_font_size_override("font_size", 9)
	_storylines_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_storylines_label)

	_vbox.add_child(HSeparator.new())

	var goal_title := Label.new()
	goal_title.text = "Goals"
	goal_title.add_theme_font_size_override("font_size", 9)
	_vbox.add_child(goal_title)

	_goals_label = Label.new()
	_goals_label.add_theme_font_size_override("font_size", 9)
	_goals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_goals_label)

	_vbox.add_child(HSeparator.new())

	var mem_title := Label.new()
	mem_title.text = "Recent Memories"
	mem_title.add_theme_font_size_override("font_size", 9)
	_vbox.add_child(mem_title)

	_memory_label = Label.new()
	_memory_label.add_theme_font_size_override("font_size", 9)
	_memory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_memory_label)


func _on_agent_selected(agent: Node2D) -> void:
	_agent = agent
	visible = true
	_update_static()
	_rebuild_need_bars()
	_update_dynamic()


func _on_agent_deselected() -> void:
	_agent = null
	visible = false


func _on_need_changed(agent: Node2D, need: NeedType.Type, value: float) -> void:
	if agent == _agent and _need_bars.has(need):
		_need_bars[need].value = value


func _on_state_changed(agent: Node2D, _old: AgentState.Type, _new: AgentState.Type) -> void:
	if agent == _agent:
		_update_state()


func _update_static() -> void:
	if not _agent:
		return
	_name_label.text = _agent.agent_name
	if _agent.personality:
		_personality_label.text = _agent.personality.get_personality_summary()
	else:
		_personality_label.text = ""
	_update_state()


func _update_state() -> void:
	if not _agent:
		return
	var names := ["Idle", "Deciding", "Walking", "Interacting", "Talking"]
	var idx: int = _agent.state
	_state_label.text = names[idx] if idx < names.size() else "?"


func _update_dynamic() -> void:
	if not _agent or not is_instance_valid(_agent):
		return
	# Health
	if _agent.health_state:
		var hs: HealthState = _agent.health_state
		_health_label.text = "Age: Day %d | Health: %.0f | %s" % [
			hs.age_days, hs.health, LifeStage.to_string_name(hs.life_stage)
		]
		if not hs.conditions.is_empty():
			_health_label.text += " | " + ", ".join(hs.conditions)
	else:
		_health_label.text = ""
	# Relationships
	if _agent.relationships:
		_rebuild_relationships()
	# Groups
	_groups_label.text = GroupManager.get_agent_group_names(_agent.agent_name)
	# Storylines
	var agent_stories: PackedStringArray = []
	for sl in Narrator.storylines:
		if _agent.agent_name in sl.involved_agents and sl.is_active:
			agent_stories.append(sl.title)
	_storylines_label.text = "\n".join(agent_stories) if not agent_stories.is_empty() else "(none)"
	# Goals — the bar is the readable part; the number is for the curious.
	_goals_label.text = _format_goals()
	# Memory
	var recent: Array[MemoryEntry] = _agent.memory.get_recent(5)
	_memory_label.text = _agent.memory.format_memories_for_prompt(recent)


func _format_goals() -> String:
	## An ASCII meter reads at 9px where a real ProgressBar per goal would not,
	## and it survives the 170px panel width without clipping.
	var goals: Array[GoalState] = GoalManager.get_goals(_agent.agent_name)
	if goals.is_empty():
		return "(none)"
	var today: int = TimeManager.day
	var lines: PackedStringArray = []
	for goal: GoalState in goals:
		match goal.status:
			GoalState.Status.ACHIEVED:
				lines.append("[done] %s" % goal.text)
			GoalState.Status.FAILED:
				lines.append("[gave up] %s" % goal.text)
			_:
				var filled: int = int(round(goal.progress / 10.0))
				var meter := "=".repeat(filled) + ".".repeat(10 - filled)
				var days: int = maxi(0, goal.days_left(today))
				lines.append("%s %d%% (%dd)\n%s" % [meter, int(goal.progress), days, goal.text])
	return "\n".join(lines)


func _rebuild_need_bars() -> void:
	for child in _needs_container.get_children():
		child.queue_free()
	_need_bars.clear()
	if not _agent:
		return
	var data: Dictionary = _agent.needs.get_all_values()
	for need in NeedType.get_all():
		var hbox := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = NeedType.to_string_name(need).substr(0, 4).capitalize()
		lbl.custom_minimum_size.x = 35
		lbl.add_theme_font_size_override("font_size", 9)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = Config.NEED_MAX
		bar.value = data.get(need, 0.0)
		bar.custom_minimum_size = Vector2(80, 10)
		bar.show_percentage = false
		hbox.add_child(lbl)
		hbox.add_child(bar)
		_needs_container.add_child(hbox)
		_need_bars[need] = bar


func _rebuild_relationships() -> void:
	for child in _relationships_container.get_children():
		child.queue_free()
	if not _agent or not _agent.relationships:
		return
	var all_rels: Dictionary = _agent.relationships.get_all_relationships()
	if all_rels.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(no relationships)"
		empty_lbl.add_theme_font_size_override("font_size", 9)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		_relationships_container.add_child(empty_lbl)
		return
	# Sort by absolute affinity (most significant first), max 5
	var sorted_names: Array[String] = []
	for n in all_rels:
		var rel: RelationshipEntry = all_rels[n]
		if rel.familiarity > 5.0:
			sorted_names.append(n)
	sorted_names.sort_custom(func(a: String, b: String) -> bool:
		return absf(all_rels[a].affinity) > absf(all_rels[b].affinity)
	)
	var count: int = mini(sorted_names.size(), 5)
	for i in range(count):
		var rel_name: String = sorted_names[i]
		var rel: RelationshipEntry = all_rels[rel_name]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		# Status icon
		var icon := Label.new()
		icon.add_theme_font_size_override("font_size", 9)
		match rel.relationship_status:
			RelationshipEntry.Status.DATING, RelationshipEntry.Status.PARTNERS:
				icon.text = "♥"
				icon.add_theme_color_override("font_color", Color(1.0, 0.4, 0.5))
			RelationshipEntry.Status.CRUSHING:
				icon.text = "~"
				icon.add_theme_color_override("font_color", Color(1.0, 0.6, 0.7))
			RelationshipEntry.Status.EX:
				icon.text = "x"
				icon.add_theme_color_override("font_color", Color(0.6, 0.5, 0.6))
			_:
				if rel.affinity > 50.0:
					icon.text = "+"
					icon.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
				elif rel.affinity < -30.0:
					icon.text = "-"
					icon.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
				else:
					icon.text = "·"
					icon.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		icon.custom_minimum_size.x = 8
		row.add_child(icon)
		# Name
		var name_lbl := Label.new()
		name_lbl.text = rel_name
		name_lbl.custom_minimum_size.x = 40
		name_lbl.add_theme_font_size_override("font_size", 9)
		row.add_child(name_lbl)
		# Affinity bar (centered on 0, range -100 to 100)
		var bar_bg := ColorRect.new()
		bar_bg.custom_minimum_size = Vector2(60, 6)
		bar_bg.color = Color(0.15, 0.15, 0.2)
		row.add_child(bar_bg)
		var bar_fill := ColorRect.new()
		var norm: float = clampf(rel.affinity / 100.0, -1.0, 1.0)
		if norm >= 0:
			bar_fill.color = Color(0.3, 0.7, 0.3, 0.8)
			bar_fill.position.x = 30.0
			bar_fill.size = Vector2(norm * 30.0, 6.0)
		else:
			bar_fill.color = Color(0.8, 0.3, 0.3, 0.8)
			var width: float = absf(norm) * 30.0
			bar_fill.position.x = 30.0 - width
			bar_fill.size = Vector2(width, 6.0)
		bar_bg.add_child(bar_fill)
		# Center marker
		var center_mark := ColorRect.new()
		center_mark.position = Vector2(29.0, 0.0)
		center_mark.size = Vector2(1.0, 6.0)
		center_mark.color = Color(0.4, 0.4, 0.45)
		bar_bg.add_child(center_mark)
		_relationships_container.add_child(row)
