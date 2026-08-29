extends Node2D
## Functional test harness for object synergies (dev tool).
##
## Covers: rule loading, tag resolution for bespoke and catalog objects, zone
## formation inside the radius and not beyond it, same-tag rules, the use
## bonus (positive and negative), aura ticks, one-bonus-per-use, the
## announcement firing once, tooltip names, removal dissolving zones, and
## the seam keeping everything quiet in other harnesses.
##
## Run: godot --headless --path . --audio-driver Dummy res://scenes/main/synergy_test.tscn

var _results: Array[String] = []
var _world: Node2D


func _ready() -> void:
	ProducerEconomy.meta_persistence_enabled = false
	TimeManager.is_paused = true
	SaveManager._last_auto_save_day = 999999
	for definition in EventManager.get_available_events():
		definition.probability = 0.0
	ArcManager.auto_start_enabled = false
	GoalManager.auto_enabled = false
	SecretManager.auto_assign_enabled = false
	SecretManager.auto_admit_enabled = false
	WhodunitDirector.auto_enabled = false
	ImpactLog.auto_enabled = false
	# The system under test stays ON — but rebuilds are driven explicitly.
	SynergyManager.auto_enabled = true
	_build_world()
	AgentManager.spawn_procedural_agent(Vector2(60, 90))
	await get_tree().create_timer(0.5).timeout
	await _run()
	_report()
	get_tree().quit()


func _build_world() -> void:
	_world = Node2D.new()
	_world.add_to_group("world")
	_world.set_script(load("res://scenes/world/office.gd"))
	var objects_node := Node2D.new()
	objects_node.name = "Objects"
	_world.add_child(objects_node)
	var agents_node := Node2D.new()
	agents_node.name = "Agents"
	_world.add_child(agents_node)
	add_child(_world)


func _place(id: String, pos: Vector2) -> InteractableObject:
	var obj := ObjectFactory.create(id)
	_world.add_object(obj, pos)
	return obj


func _run() -> void:
	var agent: Node2D = AgentManager.agents[0]

	# --- Rules and tags -------------------------------------------------------
	_check("the rulebook loads", SynergyManager._rules.size() >= 20)
	var espresso := _place("espresso_machine", Vector2(60, 60))
	_check("catalog objects resolve tags",
		"caffeine" in SynergyManager.tags_of(espresso))
	var coffee := _place("coffee_machine", Vector2(200, 200))
	_check("bespoke objects resolve tags",
		"caffeine" in SynergyManager.tags_of(coffee))

	# --- Zone formation -------------------------------------------------------
	var donuts := _place("donut_box", Vector2(90, 60))  # ~30px from espresso
	SynergyManager.rebuild()
	var names := SynergyManager.zone_names_for(espresso)
	_check("caffeine + sweet nearby forms the Breakfast Corner",
		"Breakfast Corner" in names)
	_check("the far coffee machine is in no zone",
		SynergyManager.zone_names_for(coffee).is_empty())

	# Distance matters: move the donuts out of radius, zone dissolves.
	donuts.position = Vector2(400, 300)
	SynergyManager.rebuild()
	_check("beyond the radius there is no zone",
		SynergyManager.zone_names_for(espresso).is_empty())
	donuts.position = Vector2(90, 60)
	SynergyManager.rebuild()
	_check("moving back reforms it",
		"Breakfast Corner" in SynergyManager.zone_names_for(espresso))

	# Same-tag rule: two sport objects.
	var pingpong := _place("ping_pong_table", Vector2(60, 160))
	var foosball := _place("foosball_table", Vector2(100, 160))
	SynergyManager.rebuild()
	_check("a same-tag rule (sport+sport) forms a zone",
		"Tournament Zone" in SynergyManager.zone_names_for(pingpong))

	# --- The use bonus --------------------------------------------------------
	agent.needs.set_value(NeedType.Type.HUNGER, 50.0)
	agent.needs.set_value(NeedType.Type.ENERGY, 50.0)
	EventBus.agent_action_completed.emit(agent, ActionType.Type.GO_TO_OBJECT, espresso)
	_check("using a zone member grants the bonus (hunger)",
		agent.needs.get_value(NeedType.Type.HUNGER) > 50.0)
	_check("using a zone member grants the bonus (energy)",
		agent.needs.get_value(NeedType.Type.ENERGY) > 50.0)
	# One bonus per use even when corners overlap.
	agent.needs.set_value(NeedType.Type.HUNGER, 50.0)
	var jukebox := _place("jukebox", Vector2(70, 70))  # music near the seat-less corner
	SynergyManager.rebuild()
	EventBus.agent_action_completed.emit(agent, ActionType.Type.GO_TO_OBJECT, espresso)
	_check("overlapping zones do not stack per use",
		agent.needs.get_value(NeedType.Type.HUNGER) <= 55.1)

	# Negative rule: music beside quiet.
	var booth := _place("focus_booth", Vector2(100, 90))
	SynergyManager.rebuild()
	_check("a negative rule forms too (Noise Complaint)",
		"Noise Complaint" in SynergyManager.zone_names_for(booth))
	agent.needs.set_value(NeedType.Type.PRODUCTIVITY, 50.0)
	EventBus.agent_action_completed.emit(agent, ActionType.Type.GO_TO_OBJECT, booth)
	_check("a negative bonus actually stings",
		agent.needs.get_value(NeedType.Type.PRODUCTIVITY) < 50.0)

	# --- Aura ticks -----------------------------------------------------------
	var fountain := _place("wall_fountain", Vector2(500, 90))
	var zen := _place("zen_garden", Vector2(530, 90))
	SynergyManager.rebuild()
	_check("an aura zone forms (Zen Pool)",
		"Zen Pool" in SynergyManager.zone_names_for(fountain))
	agent.global_position = Vector2(515, 95)
	if AgentManager.spatial_grid:
		AgentManager.spatial_grid.update_agent(agent)
	agent.needs.set_value(NeedType.Type.HEALTH, 50.0)
	for i in range(10):
		SynergyManager._on_time_tick(480.0 + i)
	_check("standing in an aura zone is felt",
		agent.needs.get_value(NeedType.Type.HEALTH) > 50.0)

	# --- Announcement fires once ---------------------------------------------
	var announcements: Array = []
	EventBus.narrative_event.connect(func(text: String, _a: Array, _i: float) -> void:
		if "breakfast corner" in text.to_lower():
			announcements.append(text))
	SynergyManager.rebuild()
	SynergyManager.rebuild()
	_check("a zone announces itself at most once", announcements.size() == 0)  # already announced earlier this session

	# --- Removal dissolves ----------------------------------------------------
	_world.remove_object(donuts)
	await get_tree().process_frame
	SynergyManager.rebuild()
	_check("removing a member dissolves the zone",
		not "Breakfast Corner" in SynergyManager.zone_names_for(espresso))

	# --- The seam -------------------------------------------------------------
	SynergyManager.auto_enabled = false
	agent.needs.set_value(NeedType.Type.PRODUCTIVITY, 50.0)
	EventBus.agent_action_completed.emit(agent, ActionType.Type.GO_TO_OBJECT, booth)
	_check("the seam silences use bonuses",
		is_equal_approx(agent.needs.get_value(NeedType.Type.PRODUCTIVITY), 50.0))
	agent.needs.set_value(NeedType.Type.HEALTH, 50.0)
	SynergyManager._on_time_tick(600.0)
	_check("the seam silences auras",
		is_equal_approx(agent.needs.get_value(NeedType.Type.HEALTH), 50.0))
	SynergyManager.auto_enabled = true

	for leftover: Node2D in [espresso, coffee, pingpong, foosball, jukebox, booth, fountain, zen]:
		if is_instance_valid(leftover):
			_world.remove_object(leftover)


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
	if passed + failed == 0:
		print("  NO ASSERTIONS RAN — treat this as a FAILURE")
	print("  %d passed, %d failed" % [passed, failed])
	print("=========================================")
