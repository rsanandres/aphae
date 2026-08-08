class_name RelationshipWeb
extends Control
## Visual graph showing agents as nodes and relationship lines between them.
## Filter modes for scalability: significant, selected, groups.

enum FilterMode { ALL, SIGNIFICANT, SELECTED, GROUPS }

var _filter_mode: FilterMode = FilterMode.SIGNIFICANT


func _ready() -> void:
	theme = UITheme.get_theme()
	visible = false
	custom_minimum_size = Vector2(200, 150)
	# Redraw on a slow pulse instead of every frame: relationships move on
	# think ticks, not render frames, and this view is data-driven.
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.timeout.connect(func() -> void:
		if visible:
			queue_redraw()
	)
	add_child(timer)
	timer.start()


func toggle() -> void:
	visible = not visible
	if visible:
		queue_redraw()


func set_filter(mode: FilterMode) -> void:
	_filter_mode = mode
	if visible:
		queue_redraw()


func _draw() -> void:
	if not visible:
		return

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), UIPalette.BG_PANEL)
	draw_rect(Rect2(Vector2.ZERO, size), UIPalette.BORDER, false, 1.0)

	# Filter label
	var filter_names := ["All", "Significant", "Selected", "Groups"]
	var filter_text := "Filter: %s" % filter_names[_filter_mode]
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(6.0, 14.0), filter_text + "   (right-click to change)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UIPalette.TEXT_DIM)

	var agents := AgentManager.agents
	if agents.is_empty():
		return

	# Position agents in a circle
	var center := size / 2.0
	var radius := minf(size.x, size.y) * 0.35
	var positions: Dictionary = {}

	for i in range(agents.size()):
		var angle := (TAU / agents.size()) * i - PI / 2.0
		var pos := center + Vector2(cos(angle), sin(angle)) * radius
		positions[agents[i].agent_name] = pos

	# Draw relationship lines (filtered)
	for agent in agents:
		if not agent.relationships:
			continue
		var rels: Dictionary = agent.relationships.get_all_relationships()
		for other_name in rels:
			if not positions.has(other_name):
				continue
			var rel: RelationshipEntry = rels[other_name]
			if not _should_draw_line(agent, other_name, rel):
				continue

			var from_pos: Vector2 = positions[agent.agent_name]
			var to_pos: Vector2 = positions[other_name]

			var line_color: Color
			if rel.relationship_status == RelationshipEntry.Status.DATING or rel.relationship_status == RelationshipEntry.Status.PARTNERS:
				line_color = Color(1.0, 0.5, 0.7, 0.8)
			elif rel.affinity > 30:
				line_color = Color(0.3, 0.8, 0.3, 0.6)
			elif rel.affinity < -30:
				line_color = Color(0.8, 0.3, 0.3, 0.6)
			else:
				line_color = Color(0.5, 0.5, 0.5, 0.3)

			# Color by group in groups mode
			if _filter_mode == FilterMode.GROUPS:
				line_color = _get_group_color(agent.agent_name, other_name, line_color)

			var thickness := clampf(rel.familiarity / 30.0, 1.0, 3.0)
			draw_line(from_pos, to_pos, line_color, thickness)

	# Draw agent nodes
	for agent in agents:
		var pos: Vector2 = positions[agent.agent_name]

		# Highlight color in groups mode
		var node_color: Color = agent.agent_color
		if _filter_mode == FilterMode.GROUPS:
			var agent_groups := GroupManager.get_agent_groups(agent.agent_name)
			if not agent_groups.is_empty():
				# Tint by first group's index
				var group_idx := GroupManager.groups.find(agent_groups[0])
				if group_idx >= 0:
					var hue: float = fmod(group_idx * 137.508, 360.0) / 360.0
					node_color = Color.from_hsv(hue, 0.7, 0.9)

		draw_circle(pos, 8.0, node_color)
		draw_circle(pos, 8.0, Palette.OUTLINE, false, 1.0)

		# Name label
		var font_size := 10
		var text_size := font.get_string_size(agent.agent_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, pos - Vector2(text_size.x / 2.0, -14.0), agent.agent_name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)


func _should_draw_line(agent: Node2D, other_name: String, rel: RelationshipEntry) -> bool:
	match _filter_mode:
		FilterMode.ALL:
			return rel.familiarity > 5.0
		FilterMode.SIGNIFICANT:
			return absf(rel.affinity) > 30.0 or rel.familiarity > 40.0 or rel.relationship_status != RelationshipEntry.Status.NONE
		FilterMode.SELECTED:
			var selected_name := ""
			if GameManager.selected_agent and is_instance_valid(GameManager.selected_agent):
				selected_name = GameManager.selected_agent.agent_name
			return agent.agent_name == selected_name or other_name == selected_name
		FilterMode.GROUPS:
			# Show intra-group bonds + inter-group rivalries
			var groups_a := GroupManager.get_agent_groups(agent.agent_name)
			var groups_b := GroupManager.get_agent_groups(other_name)
			for ga in groups_a:
				if other_name in ga.members:
					return true  # Same group
				for gb in groups_b:
					if gb.group_id in ga.rival_groups:
						return true  # Rival groups
			return false
	return false


func _get_group_color(name_a: String, name_b: String, default: Color) -> Color:
	var groups_a := GroupManager.get_agent_groups(name_a)
	for ga in groups_a:
		if name_b in ga.members:
			var idx := GroupManager.groups.find(ga)
			if idx >= 0:
				var hue: float = fmod(idx * 137.508, 360.0) / 360.0
				return Color.from_hsv(hue, 0.6, 0.8, 0.7)
		# Check rivalry
		var groups_b := GroupManager.get_agent_groups(name_b)
		for gb in groups_b:
			if gb.group_id in ga.rival_groups:
				return Color(0.9, 0.2, 0.2, 0.7)  # Red for rivalry
	return default


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Cycle filter mode on right-click
		_filter_mode = (_filter_mode + 1) % 4 as FilterMode
		queue_redraw()
