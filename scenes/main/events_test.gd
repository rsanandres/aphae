extends Node2D
## Functional test harness for the event/consequence system (dev tool).
##
## Verifies the ConsequenceEngine vocabulary end to end: relationship deltas,
## tags, modifiers, conditions, witness-radius memories, trait shifts, and
## the save/load round-trip for modifiers + cooldowns + drama state.
##
## Run: godot --headless --path . --audio-driver Dummy res://scenes/main/events_test.tscn

var _results: Array[String] = []


func _ready() -> void:
	_build_world()
	_spawn(4)
	await get_tree().create_timer(1.0).timeout
	await _run()
	_report()
	get_tree().quit()


func _build_world() -> void:
	var world := Node2D.new()
	world.add_to_group("world")
	world.set_script(load("res://scenes/world/office.gd"))
	var objects_node := Node2D.new()
	objects_node.name = "Objects"
	world.add_child(objects_node)
	var agents_node := Node2D.new()
	agents_node.name = "Agents"
	world.add_child(agents_node)
	var nav_region := NavigationRegion2D.new()
	nav_region.name = "NavigationRegion2D"
	var poly := NavigationPolygon.new()
	poly.add_outline(PackedVector2Array([
		Vector2(10, 10), Vector2(300, 10), Vector2(300, 200), Vector2(10, 200),
	]))
	poly.make_polygons_from_outlines()
	nav_region.navigation_polygon = poly
	world.add_child(nav_region)
	add_child(world)

	# One bed so exhaustion_collapse has a destination.
	var obj := StaticBody2D.new()
	obj.collision_layer = 4
	obj.collision_mask = 0
	obj.set_script(load("res://scenes/objects/bed.gd"))
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	obj.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 16)
	shape.shape = rect
	obj.add_child(shape)
	world.add_object(obj, Vector2(250, 150))


func _spawn(n: int) -> void:
	for i in range(n):
		AgentManager.spawn_procedural_agent(Vector2(60 + i * 30, 90))


func _run() -> void:
	# Freeze the clock and zero every event's organic probability: the
	# harness drives day_changed by hand, and organic rolls firing mid-test
	# (a returning_ex once consumed the archive between two assertions)
	# make the run nondeterministic. trigger_event() bypasses probability.
	TimeManager.is_paused = true
	for definition in EventManager.get_available_events():
		definition.probability = 0.0
	var agents: Array = AgentManager.agents
	var a: Node2D = agents[0]
	var b: Node2D = agents[1]
	var far: Node2D = agents[3]

	# Place a and b together, far away from the fourth agent.
	a.global_position = Vector2(60, 60)
	b.global_position = Vector2(80, 60)
	agents[2].global_position = Vector2(100, 60)
	far.global_position = Vector2(290, 190)

	# --- 1. Migrated heated_argument: full data-driven consequence ---
	var affinity_before: float = a.relationships.get_relationship(b.agent_name).affinity
	EventManager.trigger_event("heated_argument", [a])
	await get_tree().process_frame
	# The second actor is whoever was nearby (b or agents[2]); the avoidance
	# modifier records the pairing.
	var second_name := ""
	for mod in a.get_active_modifiers():
		if mod.get("type") == "avoidance":
			second_name = mod.get("target", "")
	_check("argument picked a nearby second actor", second_name != "")
	if second_name != "":
		var second := AgentManager.get_agent_by_name(second_name)
		var rel_a_to_s: RelationshipEntry = a.relationships.get_relationship(second_name)
		_check("argument cut affinity by 15", absf(rel_a_to_s.affinity - (affinity_before - 15.0)) < 0.01 or rel_a_to_s.affinity <= affinity_before - 10.0)
		_check("argument added angry tag", rel_a_to_s.has_tag("angry_at_%s" % second_name))
		_check("argument is mutual", second.relationships.get_relationship(a.agent_name).has_tag("angry_at_%s" % a.agent_name))
		_check("avoidance modifier on both", a.has_modifier("avoidance", second_name) and second.has_modifier("avoidance", a.agent_name))
		var found_anger := false
		for m in a.memory.memories:
			if m.emotion == "anger" and "argument" in m.description:
				found_anger = true
		_check("argument memory carries anger", found_anger)
	var far_knows := false
	for m in far.memory.memories:
		if "argument" in m.description or "tear into" in m.description:
			far_knows = true
	_check("out-of-radius agent did not witness it", not far_knows)

	# --- 2. Conditions from JSON (recovery clears) ---
	a.health_state.add_condition("flu")
	EventManager.trigger_event("recovery", [a])
	await get_tree().process_frame
	_check("recovery clears conditions via JSON", a.health_state.conditions.is_empty())

	# --- 3. Promotion bystanders incl. default band ---
	for other in [b, agents[2], far]:
		other.personality.agreeableness = 0.55  # the old dead zone
	EventManager.trigger_event("promotion", [a])
	await get_tree().process_frame
	_check("motivated modifier applied", a.has_modifier("motivated"))
	var mid_band_reacted := false
	for m in b.memory.memories:
		if "promoted" in m.description:
			mid_band_reacted = true
	_check("mid-agreeableness bystander reacts (old dead zone)", mid_band_reacted)

	# --- 4. Trait shifts clamp ---
	var n_before: float = a.personality.neuroticism
	ConsequenceEngine.apply({"trait_shifts": {"neuroticism": 0.9}}, a, null, {"affected": [a]})
	_check("trait shift capped at 0.05", absf(a.personality.neuroticism - minf(n_before + 0.05, 1.0)) < 0.001)

	# --- 5. Save/load round-trip: modifiers + cooldowns + drama ---
	DramaDirector.drama_level = 5.5
	var save_data: Dictionary = SaveManager._serialize_world()
	_check("save carries behavior modifiers", not save_data["agents"][0].get("behavior_modifiers", []).is_empty() or not save_data["agents"][1].get("behavior_modifiers", []).is_empty())
	_check("save carries event cooldowns", not save_data["event_state"]["cooldowns"].is_empty())
	_check("save carries personality for procedural cast", save_data["agents"][0].has("personality_data"))
	_check("save carries drama state", absf(save_data["drama_state"]["drama_level"] - 5.5) < 0.01)

	a.load_modifiers_data([])
	EventManager.load_save_state({})
	DramaDirector.drama_level = 0.0
	# Restore
	EventManager.load_save_state(save_data["event_state"])
	DramaDirector.load_save_state(save_data["drama_state"])
	a.load_modifiers_data(save_data["agents"][0].get("behavior_modifiers", []))
	_check("cooldowns restored", not EventManager._cooldowns.is_empty())
	_check("drama restored", absf(DramaDirector.drama_level - 5.5) < 0.01)

	# --- E2: romance pipeline ---
	var rel_rom: RelationshipEntry = a.relationships.get_relationship(b.agent_name)
	rel_rom.affinity = 30.0
	var rel_back: RelationshipEntry = b.relationships.get_relationship(a.agent_name)
	rel_back.affinity = 30.0
	var interest_before: float = rel_rom.romantic_interest
	for i in range(30):
		a.relationships.update_romance(b.agent_name)
	_check("romantic interest grows from positive interactions", rel_rom.romantic_interest > interest_before)
	_check("crossing threshold sets CRUSHING", rel_rom.relationship_status == RelationshipEntry.Status.CRUSHING)
	# committed elsewhere blocks growth
	var rel_c: RelationshipEntry = agents[2].relationships.get_relationship(far.agent_name)
	rel_c.relationship_status = RelationshipEntry.Status.DATING
	var rel_block: RelationshipEntry = agents[2].relationships.get_relationship(a.agent_name)
	rel_block.affinity = 50.0
	var blocked_before: float = rel_block.romantic_interest
	agents[2].relationships.update_romance(a.agent_name)
	_check("committed agents do not grow new crushes", absf(rel_block.romantic_interest - blocked_before) < 0.001)

	# --- E2: arc engine (burnout spiral, forced) ---
	SaveManager._last_auto_save_day = 999999  # keep the day loop from autosaving over a real slot
	_check("arc starts on demand", ArcManager.start_arc("burnout_spiral", far))
	_check("agent is arc-locked", ArcManager.has_arc(far.agent_name) and not ArcManager.start_arc("secret_hobby", far))
	for day in range(2, 14):
		TimeManager.game_minutes = (day - 1) * 1440.0 + 480.0
		EventBus.day_changed.emit(day)
		await get_tree().process_frame
	_check("arc ran to completion", not ArcManager.has_arc(far.agent_name))
	var arc_touched := false
	for m in far.memory.memories:
		if "pushing way too hard" in m.description or "snapped at" in m.description \
				or "pulled aside" in m.description or "collapsed" in m.description:
			arc_touched = true
	_check("arc left memories on its subject", arc_touched)

	# --- E2: arc save round-trip ---
	ArcManager.start_arc("goal_pursuit", b)
	var arcs_saved: Array = ArcManager.get_save_state()
	_check("goal arc resolved its {goal} token", not ("{goal}" in JSON.stringify(arcs_saved)))
	ArcManager.load_save_state([])
	_check("arc state clears", not ArcManager.has_arc(b.agent_name))
	ArcManager.load_save_state(arcs_saved)
	_check("arc state restores", ArcManager.has_arc(b.agent_name))
	ArcManager.load_save_state([])

	# --- E3: cast churn ---
	var died_spy: Array = []
	EventBus.agent_died.connect(func(n: String, _c: String) -> void: died_spy.append(n))
	var count_before: int = AgentManager.agents.size()
	EventManager.trigger_event("new_hire", AgentManager.agents.duplicate())
	await get_tree().process_frame
	_check("new hire joins the cast", AgentManager.agents.size() == count_before + 1)
	var hire: Node2D = AgentManager.agents[-1]
	var met := false
	for m in a.memory.memories:
		if "new hire" in m.description and hire.agent_name in m.description:
			met = true
	_check("cast forms first impressions of the hire", met)
	_check("first impressions are seeded from compatibility", absf(a.relationships.get_relationship(hire.agent_name).affinity) > 0.001 or absf(hire.relationships.get_relationship(a.agent_name).affinity) > 0.001)

	# Departure: archive, tags, no death signal
	var hire_name: String = hire.agent_name
	var dating_rel: RelationshipEntry = a.relationships.get_relationship(hire_name)
	dating_rel.relationship_status = RelationshipEntry.Status.DATING
	var count_predepart: int = AgentManager.agents.size()
	AgentManager.depart_agent(hire, "poached by a rival company")
	await get_tree().create_timer(2.5).timeout
	_check("departure removes the agent", AgentManager.agents.size() == count_predepart - 1)
	_check("departure does not emit agent_died", died_spy.is_empty())
	_check("departure archived with memories", not AgentManager.departed_agents.is_empty() and not AgentManager.departed_agents[-1]["memories"].is_empty())
	_check("stayers tag the departed", a.relationships.get_relationship(hire_name).has_tag("departed"))
	_check("departure breaks couples to EX", a.relationships.get_relationship(hire_name).relationship_status == RelationshipEntry.Status.EX)

	# Return: memories and relationships intact
	var returned := AgentManager.respawn_departed()
	_check("departed agent can return", returned != null)
	if returned:
		_check("returnee kept their memories", returned.memory.memories.size() > 1)
		var back_knows := false
		for m in returned.memory.memories:
			if "back in the office" in m.description:
				back_knows = true
		_check("returnee knows they returned", back_knows)

	# Save round-trip for the archive
	AgentManager.depart_agent(returned, "quit in a blaze of glory")
	await get_tree().create_timer(2.5).timeout
	var churn_save: Dictionary = SaveManager._serialize_world()
	_check("save carries departed archive", not churn_save.get("departed_agents", []).is_empty())

	# --- 6. specific target mode never fires organically ---
	var spec_def := EventDefinition.from_dict({
		"id": "__test_specific", "name": "t", "description": "t",
		"target_mode": "specific", "probability": 1.0,
	})
	_check("specific mode selects no organic targets", EventManager._select_targets(spec_def).is_empty())


func _check(test_name: String, ok: bool) -> void:
	_results.append("%s  %s" % ["PASS" if ok else "FAIL", test_name])
	print("  %s  %s" % ["PASS" if ok else "FAIL", test_name])


func _report() -> void:
	var passed := 0
	var failed := 0
	for r in _results:
		if r.begins_with("PASS"):
			passed += 1
		else:
			failed += 1
	print("=========================================")
	print("  %d passed, %d failed" % [passed, failed])
	print("=========================================")
