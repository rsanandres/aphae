extends Node
## Registry of all agents. Tiered round-robin think ticks with spatial grid.

enum ThinkTier { ACTIVE, NORMAL, BACKGROUND }

var agents: Array[Node2D] = []
var spatial_grid: SpatialGrid = null
var _spawn_index: int = 0

# Tiered scheduling
var _agent_tiers: Dictionary = {}  # Node2D -> ThinkTier
var low_power: bool = false  # set by AmbientMode when the window is unfocused
var _tier_timers: Dictionary = {
	ThinkTier.ACTIVE: 0.0,
	ThinkTier.NORMAL: 0.0,
	ThinkTier.BACKGROUND: 0.0,
}
var _tier_indices: Dictionary = {
	ThinkTier.ACTIVE: 0,
	ThinkTier.NORMAL: 0,
	ThinkTier.BACKGROUND: 0,
}
var _tier_reclassify_timer: float = 0.0
var _grid_update_timer: float = 0.0
var _early_hook_done: bool = false
var _think_count: int = 0


func _ready() -> void:
	spatial_grid = SpatialGrid.new(Config.SPATIAL_GRID_CELL_SIZE)


func register(agent: Node2D) -> void:
	if agent not in agents:
		agents.append(agent)
		_agent_tiers[agent] = ThinkTier.NORMAL
		spatial_grid.update_agent(agent)
		EventBus.agent_spawned.emit(agent)


func unregister(agent: Node2D) -> void:
	agents.erase(agent)
	_agent_tiers.erase(agent)
	spatial_grid.remove_agent(agent)
	# Check if all agents are dead
	if agents.is_empty():
		call_deferred("_check_all_dead")


func _check_all_dead() -> void:
	if agents.is_empty():
		EventBus.all_agents_dead.emit()


func get_agent_by_name(agent_name: String) -> Node2D:
	for agent in agents:
		if agent.agent_name == agent_name:
			return agent
	return null


func get_agents_near(position: Vector2, radius: float, exclude: Node2D = null) -> Array[Node2D]:
	# Use spatial grid for large populations, linear scan for small
	if agents.size() > 10:
		return spatial_grid.get_agents_in_radius(position, radius, exclude)
	var result: Array[Node2D] = []
	for agent in agents:
		if agent == exclude or not is_instance_valid(agent):
			continue
		if agent.global_position.distance_to(position) <= radius:
			result.append(agent)
	return result


func spawn_agent(personality_file: String, pos: Vector2) -> Node2D:
	var agent_scene := preload("res://scenes/agents/agent.tscn")
	var agent: Node2D = agent_scene.instantiate()
	agent.personality_file = personality_file
	agent.position = pos
	var world := _get_world()
	if world:
		world.get_node("Agents").add_child(agent)
		EventBus.agent_spawned_dynamic.emit(agent)
		EventBus.narrative_event.emit(
			"A new person appeared: %s" % agent.agent_name,
			[agent.agent_name], 5.0
		)
		return agent
	return null


func spawn_procedural_agent(pos: Vector2, personality_data: Dictionary = {}) -> Node2D:
	var agent_scene := preload("res://scenes/agents/agent.tscn")
	var agent: Node2D = agent_scene.instantiate()
	agent.personality_file = "__procedural__"
	if personality_data.is_empty():
		var profile := PersonalityGenerator.generate_heuristic(_spawn_index)
		personality_data = profile.to_dict()
	agent.procedural_personality_data = personality_data
	agent.position = pos
	_spawn_index += 1
	var world := _get_world()
	if world:
		world.get_node("Agents").add_child(agent)
		EventBus.agent_spawned_dynamic.emit(agent)
		EventBus.narrative_event.emit(
			"A new person appeared: %s" % agent.agent_name,
			[agent.agent_name], 5.0
		)
		return agent
	return null


var departed_agents: Array[Dictionary] = []  # {personality_data, relationships, memories, day, reason}


func depart_agent(agent: Node2D, reason: String = "a new opportunity") -> void:
	## Archive them first — a returnee who remembers is drama; a blank
	## respawn is a stranger with a familiar name.
	if not is_instance_valid(agent) or agent.is_dead:
		return
	var archive := {
		"name": agent.agent_name,
		"personality_data": agent.personality.to_dict() if agent.personality else {},
		"relationships": {},
		"memories": [],
		"day": TimeManager.day,
		"reason": reason,
	}
	for other_name in agent.relationships.get_all_relationships():
		archive["relationships"][other_name] = agent.relationships.get_relationship(other_name).to_dict()
	for mem in agent.memory.get_recent(50):
		archive["memories"].append(mem.to_dict())
	departed_agents.append(archive)
	# Farewell to camera before the walk-out.
	ConfessionalDirector.request_farewell(agent, reason)
	agent.depart(reason)


func respawn_departed(archived_name: String = "") -> Node2D:
	## Bring a departed agent back, memories and grudges intact.
	if departed_agents.is_empty():
		return null
	var idx := -1
	if archived_name == "":
		idx = randi() % departed_agents.size()
	else:
		for i in range(departed_agents.size()):
			if departed_agents[i].get("name", "") == archived_name:
				idx = i
				break
	if idx == -1:
		return null
	var archive: Dictionary = departed_agents[idx]
	departed_agents.remove_at(idx)
	var world := _get_world()
	if not world:
		return null
	var bounds: Rect2 = world.get_bounds()
	var pos := Vector2(
		randf_range(bounds.position.x + 20, bounds.end.x - 20),
		randf_range(bounds.position.y + 20, bounds.end.y - 20)
	)
	var agent := spawn_procedural_agent(pos, archive.get("personality_data", {}))
	if agent == null:
		return null
	for other_name in archive.get("relationships", {}):
		var rel := RelationshipEntry.from_dict(archive["relationships"][other_name])
		agent.relationships._relationships[other_name] = rel
	for mem_dict in archive.get("memories", []):
		agent.memory.memories.append(MemoryEntry.from_dict(mem_dict))
	agent.memory.add_memory(
		MemoryEntry.MemoryType.REFLECTION,
		"%s is back in the office after leaving on day %d. Everything is the same and nothing is." % [agent.agent_name, archive.get("day", 0)],
		8.0
	)
	agent.memory.memories[-1].decay_protected = true
	agent.memory.memories[-1].emotion = "candid"
	return agent


func remove_agent(agent_name: String) -> void:
	var agent := get_agent_by_name(agent_name)
	if agent:
		EventBus.agent_removed.emit(agent_name)
		EventBus.narrative_event.emit(
			"%s has left the office." % agent_name,
			[agent_name], 5.0
		)
		agent.queue_free()


func get_tier(agent: Node2D) -> ThinkTier:
	return _agent_tiers.get(agent, ThinkTier.NORMAL)


func _get_world() -> Node2D:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		return tree.get_first_node_in_group("world")
	return null


func _process(delta: float) -> void:
	if agents.is_empty() or TimeManager.is_paused:
		return

	# Update spatial grid periodically
	_grid_update_timer += delta
	if _grid_update_timer >= 0.5:
		_grid_update_timer = 0.0
		for agent in agents:
			if is_instance_valid(agent):
				spatial_grid.update_agent(agent)

	# Reclassify tiers every 2 seconds
	_tier_reclassify_timer += delta
	if _tier_reclassify_timer >= 2.0:
		_tier_reclassify_timer = 0.0
		_reclassify_tiers()

	# Small population: use simple round-robin like before
	if agents.size() <= Config.MAX_AGENTS_DESKTOP:
		_tier_timers[ThinkTier.ACTIVE] += delta
		if _tier_timers[ThinkTier.ACTIVE] >= Config.AGENT_THINK_INTERVAL:
			_tier_timers[ThinkTier.ACTIVE] -= Config.AGENT_THINK_INTERVAL
			_trigger_next_think_simple()
		return

	# Large population: tiered scheduling
	_tier_timers[ThinkTier.ACTIVE] += delta
	_tier_timers[ThinkTier.NORMAL] += delta
	_tier_timers[ThinkTier.BACKGROUND] += delta

	for tier in [ThinkTier.ACTIVE, ThinkTier.NORMAL, ThinkTier.BACKGROUND]:
		var interval: float = think_interval_for(tier)
		if _tier_timers[tier] >= interval:
			_tier_timers[tier] -= interval
			_trigger_tier_think(tier)


func _trigger_next_think_simple() -> void:
	if agents.is_empty():
		return

	# Early hook: force first 2 agents to seek each other out in the first few ticks
	_think_count += 1
	if not _early_hook_done and _think_count <= agents.size() and agents.size() >= 2:
		_force_early_social()
		if _think_count >= agents.size():
			_early_hook_done = true
		return

	var idx: int = _tier_indices.get(ThinkTier.ACTIVE, 0) % agents.size()
	var agent := agents[idx]
	if agent.has_method("request_think"):
		agent.request_think()
	_tier_indices[ThinkTier.ACTIVE] = (idx + 1) % agents.size()


func _force_early_social() -> void:
	## In the first round of thinks, force agents to seek conversations
	## with the most personality-different agent. Creates instant drama hook.
	var idx: int = (_think_count - 1) % agents.size()
	var agent: Node2D = agents[idx]
	if not is_instance_valid(agent) or agent.is_dead:
		return
	if agent.state != AgentState.Type.IDLE:
		return

	# Find the most personality-different available agent
	var best_target: Node2D = null
	var best_diff: float = -1.0
	for other in agents:
		if other == agent or not is_instance_valid(other) or other.is_dead:
			continue
		if other.state == AgentState.Type.TALKING:
			continue
		var diff := _personality_difference(agent, other)
		if diff > best_diff:
			best_diff = diff
			best_target = other

	if best_target:
		# Force a talk decision
		agent._execute_decision({"action": ActionType.Type.TALK_TO_AGENT, "target": best_target})
	else:
		agent.request_think()


func _personality_difference(a: Node2D, b: Node2D) -> float:
	## Returns 0-1 personality difference score (higher = more different).
	if not a.personality or not b.personality:
		return randf() * 0.5
	var diff: float = 0.0
	diff += absf(a.personality.extraversion - b.personality.extraversion)
	diff += absf(a.personality.agreeableness - b.personality.agreeableness)
	diff += absf(a.personality.neuroticism - b.personality.neuroticism)
	diff += absf(a.personality.openness - b.personality.openness)
	diff += absf(a.personality.conscientiousness - b.personality.conscientiousness)
	return diff / 5.0


func think_interval_for(tier: ThinkTier) -> float:
	var base: float = Config.THINK_TIER_NORMAL_INTERVAL
	match tier:
		ThinkTier.ACTIVE: base = Config.THINK_TIER_ACTIVE_INTERVAL
		ThinkTier.BACKGROUND: base = Config.THINK_TIER_BACKGROUND_INTERVAL
	return base * (AmbientMode.LOW_POWER_THINK_MULTIPLIER if low_power else 1.0)


func _trigger_tier_think(tier: ThinkTier) -> void:
	var tier_agents: Array[Node2D] = _get_agents_in_tier(tier)
	if tier_agents.is_empty():
		return
	var idx: int = _tier_indices.get(tier, 0) % tier_agents.size()
	var agent := tier_agents[idx]
	if agent.has_method("request_think"):
		# Background agents always use heuristic — and in low-power mode
		# (window unfocused) so does everyone, so an idling office never
		# holds the LLM hostage while the player is doing real work.
		if agent.has_node("AgentBrain"):
			agent.get_node("AgentBrain").force_heuristic = low_power or tier == ThinkTier.BACKGROUND
		agent.request_think()
	_tier_indices[tier] = (idx + 1) % tier_agents.size()


func _get_agents_in_tier(tier: ThinkTier) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for agent in agents:
		if not is_instance_valid(agent):
			continue
		if _agent_tiers.get(agent, ThinkTier.NORMAL) == tier:
			result.append(agent)
	return result


func _reclassify_tiers() -> void:
	# Get camera/viewport reference point
	var viewport := get_viewport()
	if not viewport:
		return
	var camera := viewport.get_camera_2d()
	var view_center := Vector2(240, 160)  # Desktop default
	var view_radius := 300.0

	if camera:
		view_center = camera.global_position
		var zoom: float = camera.zoom.x if camera.zoom.x > 0 else 1.0
		view_radius = max(viewport.get_visible_rect().size.x, viewport.get_visible_rect().size.y) / zoom

	# Selected agent is always active
	var selected: Node2D = GameManager.selected_agent

	for agent in agents:
		if not is_instance_valid(agent):
			continue
		var dist := agent.global_position.distance_to(view_center)
		if agent == selected or dist < 100.0:
			_agent_tiers[agent] = ThinkTier.ACTIVE
		elif dist < view_radius:
			_agent_tiers[agent] = ThinkTier.NORMAL
		else:
			_agent_tiers[agent] = ThinkTier.BACKGROUND
