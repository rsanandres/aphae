extends Node2D
## Headless simulation: no rendering, just agent logic + console output.
## Run via: ./run_headless.sh [agent_count] [speed]

var _world: Node2D
var _agent_count: int = 10
var _speed: int = 3  # 0=pause, 1=1x, 2=2x, 3=3x
var _tick_count: int = 0


func _ready() -> void:
	ProducerEconomy.meta_persistence_enabled = false
	# Parse command line args
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--agents="):
			_agent_count = int(arg.split("=")[1])
		elif arg.begins_with("--speed="):
			_speed = int(arg.split("=")[1])

	print("")
	print("========================================")
	print("  AYLE Headless Simulation")
	print("  Agents: %d | Speed: %dx" % [_agent_count, _speed])
	print("========================================")
	print("")

	_build_world()
	_place_objects()
	_spawn_agents()

	# Set game speed
	TimeManager.set_speed(_speed)

	# Subscribe to all events for console logging
	EventBus.narrative_event.connect(_on_narrative)
	EventBus.agent_state_changed.connect(_on_state_changed)
	EventBus.agent_action_started.connect(_on_action)
	EventBus.conversation_started.connect(_on_convo_start)
	EventBus.conversation_line.connect(_on_convo_line)
	EventBus.conversation_ended.connect(_on_convo_end)
	EventBus.confession_made.connect(_on_confession)
	EventBus.agent_died.connect(_on_death)
	EventBus.romance_started.connect(_on_romance)
	EventBus.relationship_changed.connect(_on_relationship)
	EventBus.day_changed.connect(_on_day)
	EventBus.group_formed.connect(_on_group_formed)
	EventBus.group_rivalry_detected.connect(_on_rivalry)
	EventBus.storyline_updated.connect(_on_storyline)
	EventBus.confessional_recorded.connect(_on_confessional)

	EventBus.game_ready.emit()
	print("[SIM] Simulation started. Ctrl+C to stop.\n")


func _process(_delta: float) -> void:
	_tick_count += 1
	# Print status every 300 ticks (~5s at 60fps)
	if _tick_count % 300 == 0:
		_print_status()


func _build_world() -> void:
	_world = Node2D.new()
	_world.add_to_group("world")
	_world.set_script(load("res://scenes/world/office.gd"))

	# Build the child hierarchy BEFORE entering the tree. office.gd resolves
	# $Objects and $Agents via @onready, which fires on tree entry — adding
	# _world first left both null and silently placed no objects at all.
	var objects_node := Node2D.new()
	objects_node.name = "Objects"
	_world.add_child(objects_node)

	var agents_node := Node2D.new()
	agents_node.name = "Agents"
	_world.add_child(agents_node)

	# Navigation region
	var nav_region := NavigationRegion2D.new()
	nav_region.name = "NavigationRegion2D"
	var poly := NavigationPolygon.new()
	var outline := PackedVector2Array([
		Vector2(10, 10), Vector2(300, 10),
		Vector2(300, 200), Vector2(10, 200),
	])
	poly.add_outline(outline)
	poly.make_polygons_from_outlines()
	nav_region.navigation_polygon = poly
	_world.add_child(nav_region)

	# Hierarchy is complete — now it is safe to enter the tree.
	add_child(_world)

	# Resize for agent count
	if _world.has_method("resize_for_agents"):
		_world.resize_for_agents(_agent_count)


func _place_objects() -> void:
	var object_types := [
		"desk", "desk", "desk",
		"coffee_machine",
		"water_cooler",
		"couch",
		"whiteboard",
		"bookshelf",
		"plant",
		"radio",
		"bed",
	]
	# Add more objects for larger populations
	if _agent_count > 10:
		for i in range(_agent_count / 5):
			object_types.append(["desk", "couch", "coffee_machine", "water_cooler"][i % 4])

	var bounds: Rect2 = _world.get_bounds() if _world.has_method("get_bounds") else Rect2(10, 10, 280, 180)
	for i in range(object_types.size()):
		var obj_type: String = object_types[i]
		var script_path := "res://scenes/objects/%s.gd" % obj_type
		if not FileAccess.file_exists(script_path):
			continue
		var obj := StaticBody2D.new()
		obj.collision_layer = 4
		obj.collision_mask = 0
		obj.set_script(load(script_path))
		# Add required children
		var sprite := Sprite2D.new()
		sprite.name = "Sprite2D"
		obj.add_child(sprite)
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = Vector2(24, 16)
		shape.shape = rect
		obj.add_child(shape)
		# Position in grid
		var col: int = i % 4
		var row: int = i / 4
		var pos := Vector2(
			bounds.position.x + 40 + col * 70,
			bounds.position.y + 30 + row * 50,
		)
		_world.add_object(obj, pos)

	print("[SIM] Placed %d objects" % object_types.size())


func _spawn_agents() -> void:
	var bounds: Rect2 = _world.get_bounds() if _world.has_method("get_bounds") else Rect2(10, 10, 280, 180)
	for i in range(_agent_count):
		var pos := Vector2(
			randf_range(bounds.position.x + 20, bounds.end.x - 20),
			randf_range(bounds.position.y + 20, bounds.end.y - 20),
		)
		AgentManager.spawn_procedural_agent(pos)

	# Print all spawned agents
	print("[SIM] Spawned %d agents:" % _agent_count)
	for agent in AgentManager.agents:
		var p: String = ""
		if agent.personality:
			p = agent.personality.get_personality_summary()
		print("  - %s: %s" % [agent.agent_name, p])
	print("")


# --- Console logging callbacks ---

func _on_narrative(text: String, agents: Array, importance: float) -> void:
	if importance < 2.0:
		return  # Skip trivial
	var prefix := "   "
	if importance >= 8.0:
		prefix = "!! "
	elif importance >= 5.0:
		prefix = " ! "
	print("%s[Day %d %s] %s" % [prefix, TimeManager.day, TimeManager.time_string, text])


func _on_confessional(confessional: RefCounted) -> void:
	var c: Confessional = confessional as Confessional
	if not c:
		return
	print("CAM[Day %d %s] %s: \"%s\"" % [c.day, c.timestamp, c.speaker, c.line])


func _on_state_changed(agent: Node2D, _old: AgentState.Type, new_state: AgentState.Type) -> void:
	if not is_instance_valid(agent):
		return
	if new_state == AgentState.Type.INTERACTING:
		var target_name := "something"
		if agent.current_target and "display_name" in agent.current_target:
			target_name = agent.current_target.display_name
		print("   [Day %d %s] %s uses the %s" % [TimeManager.day, TimeManager.time_string, agent.agent_name, target_name])


func _on_action(agent: Node2D, action: ActionType.Type, target: Node2D) -> void:
	if not is_instance_valid(agent):
		return
	var target_name := "?"
	if target:
		if "display_name" in target:
			target_name = target.display_name
		elif "agent_name" in target:
			target_name = target.agent_name
	match action:
		ActionType.Type.TALK_TO_AGENT:
			print("   [Day %d %s] %s -> talks to %s" % [TimeManager.day, TimeManager.time_string, agent.agent_name, target_name])
		ActionType.Type.CONFESS_FEELINGS:
			print("!! [Day %d %s] %s -> confesses to %s!" % [TimeManager.day, TimeManager.time_string, agent.agent_name, target_name])


func _on_convo_start(a: String, b: String) -> void:
	print(" > [Day %d %s] Conversation: %s & %s" % [TimeManager.day, TimeManager.time_string, a, b])


func _on_convo_line(speaker: String, line: String) -> void:
	var display := line
	if display.length() > 80:
		display = display.substr(0, 77) + "..."
	print("   %s: \"%s\"" % [speaker, display])


func _on_convo_end(a: String, b: String) -> void:
	print(" < [Day %d %s] %s & %s finished talking" % [TimeManager.day, TimeManager.time_string, a, b])


func _on_confession(confessor: String, target: String, accepted: bool) -> void:
	var result := "ACCEPTED" if accepted else "rejected"
	print("!! [Day %d %s] %s confessed to %s -> %s" % [TimeManager.day, TimeManager.time_string, confessor, target, result])


func _on_death(agent_name: String, cause: String) -> void:
	print("!! [Day %d %s] %s DIED (%s)" % [TimeManager.day, TimeManager.time_string, agent_name, cause])


func _on_romance(a: String, b: String) -> void:
	print("!! [Day %d %s] ROMANCE: %s & %s" % [TimeManager.day, TimeManager.time_string, a, b])


func _on_relationship(agent_name: String, target_name: String, rel: RefCounted) -> void:
	var r: RelationshipEntry = rel as RelationshipEntry
	if not r:
		return
	# Only log significant changes
	if absf(r.affinity) > 40 or r.relationship_status != RelationshipEntry.Status.NONE:
		print("   [Day %d %s] Relationship: %s -> %s: %s" % [TimeManager.day, TimeManager.time_string, agent_name, target_name, r.get_summary()])


func _on_day(day: int) -> void:
	print("")
	print("=== DAY %d ===" % day)
	# Print group summary
	if not GroupManager.groups.is_empty():
		print("Groups:")
		for g in GroupManager.groups:
			var rival_text := ""
			if not g.rival_groups.is_empty():
				rival_text = " (rivals: %d)" % g.rival_groups.size()
			print("  [%s] %s: %s%s" % [g.group_type, g.group_name, ", ".join(g.members), rival_text])
	# Print top storylines
	var top: Array[Storyline] = Narrator.get_top_storylines(3)
	if not top.is_empty():
		print("Top Stories:")
		for sl in top:
			var summary := sl.summary if sl.summary != "" else "(developing...)"
			print("  [%.0f] %s - %s" % [sl.drama_score, sl.title, summary])
	print("")


func _on_group_formed(group: RefCounted) -> void:
	var g: SocialGroup = group as SocialGroup
	if not g:
		return
	print("!! [Day %d %s] GROUP FORMED: [%s] %s — %s" % [TimeManager.day, TimeManager.time_string, g.group_type, g.group_name, ", ".join(g.members)])


func _on_rivalry(group_a: RefCounted, group_b: RefCounted) -> void:
	var a: SocialGroup = group_a as SocialGroup
	var b: SocialGroup = group_b as SocialGroup
	if not a or not b:
		return
	print("!! [Day %d %s] RIVALRY: %s vs %s" % [TimeManager.day, TimeManager.time_string, a.group_name, b.group_name])


func _on_storyline(storyline: RefCounted) -> void:
	var sl: Storyline = storyline as Storyline
	if not sl:
		return
	if sl.drama_score >= 5.0:
		print(" ! [Day %d %s] STORY: [%.0f] %s" % [TimeManager.day, TimeManager.time_string, sl.drama_score, sl.title])


func _print_status() -> void:
	var alive := 0
	var talking := 0
	var interacting := 0
	for agent in AgentManager.agents:
		if not agent.is_dead:
			alive += 1
		if agent.state == AgentState.Type.TALKING:
			talking += 1
		elif agent.state == AgentState.Type.INTERACTING:
			interacting += 1
	print("--- [Day %d %s] Alive: %d | Talking: %d | Busy: %d | LLM queue: %d | Groups: %d ---" % [
		TimeManager.day, TimeManager.time_string,
		alive, talking, interacting,
		LLMManager.get_queue_size(),
		GroupManager.groups.size(),
	])
