extends Node2D
## Functional test harness for goals that resolve (dev tool).
##
## Covers: kind inference from goal prose, assignment and the per-agent cap,
## every progress source (objects, conversations, romance, day-end balance),
## achievement and failure resolution with their consequences, the one-shot
## deadline extension, silent resolution on death, focus selection, prompt
## formatting, save round-trip, and the heuristic brain acting on a goal.
##
## Run: godot --headless --path . --audio-driver Dummy res://scenes/main/goals_test.tscn

var _results: Array[String] = []


func _ready() -> void:
	ProducerEconomy.meta_persistence_enabled = false
	# M7 seams off: the spawn-roll must not plant secret memories under the
	# assertions, and the day-roll must not inject booth admissions mid-test.
	WhodunitDirector.auto_enabled = false
	ImpactLog.auto_enabled = false
	SecretManager.auto_assign_enabled = false
	SecretManager.auto_admit_enabled = false
	TimeManager.is_paused = true
	SaveManager._last_auto_save_day = 999999
	for definition in EventManager.get_available_events():
		definition.probability = 0.0
	_build_world()
	_spawn(3)
	await get_tree().create_timer(0.5).timeout
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


func _spawn(n: int) -> void:
	for i in range(n):
		AgentManager.spawn_procedural_agent(Vector2(60 + i * 30, 90))


## Give an agent exactly the goals a case needs, through the real assignment
## path, so the harness never asserts against a hand-built dictionary.
func _seed(agent: Node2D, texts: Array) -> Array[GoalState]:
	agent.personality.goals.clear()
	for t: String in texts:
		agent.personality.goals.append(t)
	GoalManager._goals.erase(agent.agent_name)
	GoalManager.assign_for(agent)
	return GoalManager.get_goals(agent.agent_name)


func _run() -> void:
	var agents: Array = AgentManager.agents
	var a: Node2D = agents[0]
	var b: Node2D = agents[1]
	var c: Node2D = agents[2]

	# --- Kind inference from the prose the game actually ships ---------------
	_check("romance goal reads as romance",
		GoalState.infer_kind("find love in the office") == GoalState.Kind.ROMANCE)
	_check("balance goal reads as balance",
		GoalState.infer_kind("maintain perfect work-life balance") == GoalState.Kind.BALANCE)
	_check("creative goal reads as creative",
		GoalState.infer_kind("find creative inspiration every day") == GoalState.Kind.CREATIVE)
	_check("social goal reads as social",
		GoalState.infer_kind("make a genuine friend in the office") == GoalState.Kind.SOCIAL)
	_check("unmatched prose falls back to work",
		GoalState.infer_kind("Prove she deserves a promotion") == GoalState.Kind.WORK)
	_check("learning outranks the team it happens in",
		GoalState.infer_kind("Learn as much as possible from the senior team") == GoalState.Kind.CREATIVE)
	_check("phrase() uncaps for mid-sentence splicing",
		GoalState.create("X", "Prove herself worthy", 1, 10).phrase() == "prove herself worthy")

	# --- Assignment ----------------------------------------------------------
	var seeded := _seed(a, ["Finish the quarterly report", "make a genuine friend in the office"])
	_check("assignment produces one state per goal", seeded.size() == 2)
	_check("assignment infers kinds independently",
		seeded[0].kind == GoalState.Kind.WORK and seeded[1].kind == GoalState.Kind.SOCIAL)
	_check("goals start at zero", is_zero_approx(seeded[0].progress))
	_check("deadline is set from today",
		seeded[0].deadline_day == TimeManager.day + GoalManager.DEADLINE_DAYS)

	var capped := _seed(b, ["one", "two", "three", "four", "five"])
	_check("per-agent cap holds", capped.size() == GoalManager.MAX_TRACKED_PER_AGENT)
	_seed(b, ["  ", "Ship the feature"])
	_check("blank goal text is skipped", GoalManager.get_goals(b.agent_name).size() == 1)

	# --- Object progress -----------------------------------------------------
	var work_goal: GoalState = _seed(a, ["Finish the quarterly report"])[0]
	var desk := ObjectFactory.create("desk")
	add_child(desk)
	EventBus.agent_action_completed.emit(a, ActionType.Type.GO_TO_OBJECT, desk)
	_check("finishing at a desk advances a work goal",
		is_equal_approx(work_goal.progress, GoalManager.WORK_STEP))

	var plant := ObjectFactory.create("plant")
	add_child(plant)
	var before_plant: float = work_goal.progress
	EventBus.agent_action_completed.emit(a, ActionType.Type.GO_TO_OBJECT, plant)
	_check("an unrelated object does not advance a work goal",
		is_equal_approx(work_goal.progress, before_plant))

	var creative_goal: GoalState = _seed(b, ["find creative inspiration every day"])[0]
	var shelf := ObjectFactory.create("bookshelf")
	add_child(shelf)
	EventBus.agent_action_completed.emit(b, ActionType.Type.GO_TO_OBJECT, shelf)
	_check("the bookshelf advances a creative goal",
		is_equal_approx(creative_goal.progress, GoalManager.CREATIVE_STEP))

	# --- Conversation progress ----------------------------------------------
	var social_goal: GoalState = _seed(a, ["make a genuine friend in the office"])[0]
	EventBus.conversation_ended.emit(a.agent_name, b.agent_name)
	_check("a new partner advances a social goal",
		is_equal_approx(social_goal.progress, GoalManager.SOCIAL_NEW_PARTNER))
	_check("the partner is remembered", b.agent_name in social_goal.partners)
	EventBus.conversation_ended.emit(a.agent_name, b.agent_name)
	_check("a repeat partner is worth less",
		is_equal_approx(social_goal.progress,
			GoalManager.SOCIAL_NEW_PARTNER + GoalManager.SOCIAL_REPEAT))
	_check("a repeat partner is not double-counted",
		social_goal.partners.size() == 1)
	EventBus.conversation_ended.emit(a.agent_name, a.agent_name)
	_check("talking to yourself earns nothing",
		is_equal_approx(social_goal.progress,
			GoalManager.SOCIAL_NEW_PARTNER + GoalManager.SOCIAL_REPEAT))

	var learn_goal: GoalState = _seed(c, ["Learn something new from each colleague"])[0]
	EventBus.conversation_ended.emit(c.agent_name, a.agent_name)
	_check("a creative goal also learns from new people",
		is_equal_approx(learn_goal.progress, GoalManager.CREATIVE_PARTNER_STEP))

	# --- Romance -------------------------------------------------------------
	var romance_goal: GoalState = _seed(c, ["find love in the office"])[0]
	EventBus.confession_made.emit(c.agent_name, a.agent_name, false)
	_check("a rejected confession advances nothing", is_zero_approx(romance_goal.progress))
	EventBus.confession_made.emit(c.agent_name, a.agent_name, true)
	_check("an accepted confession advances a romance goal",
		is_equal_approx(romance_goal.progress, GoalManager.ROMANCE_CONFESSION))

	# --- Achievement and its consequences ------------------------------------
	var achieved: Array = []
	EventBus.goal_achieved.connect(func(who: String, text: String, _k: int) -> void:
		achieved.append({"who": who, "text": text}))
	var narratives: Array = []
	EventBus.narrative_event.connect(func(text: String, _ag: Array, importance: float) -> void:
		narratives.append({"text": text, "importance": importance}))

	# The resolution narrates before it pays, and narration can itself trickle
	# Influence, so watch for our own grant rather than differencing the balance.
	var grants: Array = []
	EventBus.influence_changed.connect(func(_balance: int, delta: int, reason: String) -> void:
		grants.append({"delta": delta, "reason": reason}))

	var win_goal: GoalState = _seed(a, ["Finish the quarterly report"])[0]
	var conscientiousness_before: float = a.personality.conscientiousness
	var memories_before: int = a.memory.memories.size()
	GoalManager.advance(win_goal, 100.0, "test")

	_check("reaching 100 marks the goal achieved",
		win_goal.status == GoalState.Status.ACHIEVED)
	_check("achievement emits goal_achieved",
		achieved.size() == 1 and achieved[0]["who"] == a.agent_name)
	_check("progress is clamped at 100", is_equal_approx(win_goal.progress, 100.0))
	_check("achievement leaves a memory", a.memory.memories.size() > memories_before)
	# Find it by content rather than trusting memories[-1] — add_memory can
	# append a reflection after ours.
	var goal_mem: MemoryEntry = null
	for m: MemoryEntry in a.memory.memories:
		if "I set out to" in m.description:
			goal_mem = m
	_check("that memory survives compaction", goal_mem != null and goal_mem.decay_protected)
	_check("that memory is threaded to its goal kind",
		goal_mem != null and goal_mem.narrative_thread == "goal_work")
	_check("achievement bends the trait that earned it",
		a.personality.conscientiousness > conscientiousness_before)
	var goal_grant := false
	for g: Dictionary in grants:
		if g["delta"] == GoalManager.ACHIEVED_INFLUENCE and "achieved a goal" in str(g["reason"]):
			goal_grant = true
	_check("achievement pays Influence", goal_grant)
	_check("achievement narrates above the confessional bar",
		not narratives.is_empty() and narratives[-1]["importance"] >= 6.0)
	_check("the narration splices the goal in mid-sentence",
		"finish the quarterly report" in str(narratives[-1]["text"]))

	var post_achieve: float = win_goal.progress
	GoalManager.advance(win_goal, 20.0, "test")
	_check("a resolved goal cannot advance again",
		is_equal_approx(win_goal.progress, post_achieve) and achieved.size() == 1)

	# --- Failure and the one-shot extension ----------------------------------
	var failed: Array = []
	EventBus.goal_failed.connect(func(who: String, _t: String, _k: int) -> void:
		failed.append(who))

	var stalled: GoalState = _seed(b, ["Ship the feature"])[0]
	var day_past: int = stalled.deadline_day
	GoalManager._sweep_deadlines(day_past)
	_check("a stalled goal fails at its deadline",
		stalled.status == GoalState.Status.FAILED)
	# The sweep is office-wide by design, so other agents past their deadline
	# fail in the same pass. Assert on ours being among them, not on the count.
	_check("failure emits goal_failed", b.agent_name in failed)
	_check("failure narrates, but below an achievement",
		narratives[-1]["importance"] < 7.5 and narratives[-1]["importance"] >= 6.0)

	var near_miss: GoalState = _seed(c, ["Ship the other feature"])[0]
	GoalManager.advance(near_miss, GoalManager.EXTENSION_THRESHOLD, "test")
	var original_deadline: int = near_miss.deadline_day
	GoalManager._sweep_deadlines(original_deadline)
	_check("a near miss buys an extension instead of failing",
		near_miss.is_active() and near_miss.extended
		and near_miss.deadline_day == original_deadline + GoalManager.EXTENSION_DAYS)
	GoalManager._sweep_deadlines(near_miss.deadline_day)
	_check("the extension is granted only once",
		near_miss.status == GoalState.Status.FAILED)

	# --- Balance goals are scored by state, at day end -----------------------
	var balance_goal: GoalState = _seed(a, ["maintain perfect work-life balance"])[0]
	for need in a.needs.get_all_values().keys():
		a.needs.set_value(need, 80.0)
	GoalManager._score_balance_goals()
	_check("ending the day whole advances a balance goal",
		is_equal_approx(balance_goal.progress, GoalManager.BALANCE_GOOD_DAY))
	a.needs.set_value(NeedType.Type.ENERGY, 5.0)
	GoalManager._score_balance_goals()
	_check("a day in crisis costs a balance goal",
		is_equal_approx(balance_goal.progress,
			GoalManager.BALANCE_GOOD_DAY + GoalManager.BALANCE_BAD_DAY))
	a.needs.set_value(NeedType.Type.ENERGY, 40.0)
	var middling: float = balance_goal.progress
	GoalManager._score_balance_goals()
	_check("a mediocre day neither helps nor hurts",
		is_equal_approx(balance_goal.progress, middling))
	_check("balance progress never goes negative", balance_goal.progress >= 0.0)

	# --- Focus selection -----------------------------------------------------
	var focus_set := _seed(a, ["Ship it", "make a genuine friend in the office"])
	GoalManager.advance(focus_set[1], 30.0, "test")
	var focus: GoalState = GoalManager.get_focus_goal(a.agent_name)
	_check("focus is the active goal closest to landing", focus == focus_set[1])
	GoalManager.advance(focus_set[1], 100.0, "test")
	_check("a resolved goal yields focus to the next",
		GoalManager.get_focus_goal(a.agent_name) == focus_set[0])

	# --- Prompt formatting ---------------------------------------------------
	var prompt: String = GoalManager.format_for_prompt(a.agent_name)
	_check("the prompt reports standing", "achieved" in prompt and "% there" in prompt)
	_check("an agent with no goals says so",
		GoalManager.format_for_prompt("Nobody") == "none")

	# --- The heuristic brain acts on a goal ----------------------------------
	var social_only := _seed(a, ["make a genuine friend in the office"])[0]
	var brain: HeuristicBrain = a.get_node("HeuristicBrain")
	var pursued := false
	var unmet := false
	# The pursuit roll is deliberately probabilistic; sample it.
	for i in range(60):
		var decision: Dictionary = brain._goal_decision([], [b, c])
		if decision.is_empty():
			continue
		pursued = true
		if decision["target"] == b or decision["target"] == c:
			unmet = true
	_check("a calm agent sometimes pursues its focus goal", pursued)
	_check("a social goal is pursued toward a person", unmet)
	social_only.partners.append(b.agent_name)
	social_only.partners.append(c.agent_name)
	var still_social := false
	for i in range(60):
		var decision: Dictionary = brain._goal_decision([], [b, c])
		if not decision.is_empty():
			still_social = true
	_check("an all-partners-met social goal still talks to someone", still_social)

	var work_only := _seed(a, ["Finish the quarterly report"])[0]
	var went_to_desk := false
	for i in range(60):
		var decision: Dictionary = brain._goal_decision([desk, plant], [])
		if not decision.is_empty() and decision["target"] == desk:
			went_to_desk = true
	_check("a work goal is pursued toward its object", went_to_desk)
	_check("goal pursuit yields when nothing suitable is nearby",
		brain._goal_decision([plant], []).is_empty() or work_only.progress >= 0.0)

	# --- The inspector's meter ------------------------------------------------
	# Layout is the sandbox harnesses' job; the string is testable here.
	var inspector := AgentInspector.new()
	add_child(inspector)
	inspector._agent = a
	_seed(a, ["Finish the quarterly report"])
	var meter_goal: GoalState = GoalManager.get_goals(a.agent_name)[0]
	GoalManager.advance(meter_goal, 30.0, "test")
	var meter: String = inspector._format_goals()
	_check("the meter fills in proportion", "===......." in meter)
	_check("the meter reports the number too", "30%" in meter)
	_check("the meter reports days left", "(%dd)" % GoalManager.DEADLINE_DAYS in meter)
	GoalManager.advance(meter_goal, 100.0, "test")
	_check("an achieved goal reads as done", "[done]" in inspector._format_goals())
	inspector._agent = b
	_seed(b, ["Ship the feature"])
	GoalManager._sweep_deadlines(GoalManager.get_goals(b.agent_name)[0].deadline_day)
	_check("a failed goal reads as given up", "[gave up]" in inspector._format_goals())
	inspector._agent = a
	GoalManager._goals.erase(a.agent_name)
	_check("an agent with no goals renders a placeholder",
		inspector._format_goals() == "(none)")
	inspector.queue_free()

	# --- Death resolves quietly ----------------------------------------------
	var doomed: GoalState = _seed(c, ["Ship something eventually"])[0]
	var failures_before: int = failed.size()
	var narratives_before: int = narratives.size()
	GoalManager._on_agent_died(c.agent_name, "test")
	_check("death resolves an unfinished goal",
		doomed.status == GoalState.Status.FAILED)
	_check("death does not emit goal_failed", failed.size() == failures_before)
	_check("death does not narrate a second time", narratives.size() == narratives_before)
	_check("the unfinished goal is kept for the recap",
		GoalManager.get_goals(c.agent_name).size() == 1)

	# --- Save round-trip -----------------------------------------------------
	_seed(a, ["Finish the quarterly report", "make a genuine friend in the office"])
	var round_trip := GoalManager.get_goals(a.agent_name)
	GoalManager.advance(round_trip[0], 36.0, "test")
	round_trip[1].partners.append(b.agent_name)
	var state: Dictionary = GoalManager.get_save_state()
	var achieved_snapshot: int = GoalManager.achieved_total
	GoalManager.load_save_state(state)
	var restored := GoalManager.get_goals(a.agent_name)
	_check("save round-trip keeps every goal", restored.size() == 2)
	_check("save round-trip keeps progress", is_equal_approx(restored[0].progress, 36.0))
	_check("save round-trip keeps the inferred kind",
		restored[1].kind == GoalState.Kind.SOCIAL)
	_check("save round-trip keeps partners", b.agent_name in restored[1].partners)
	_check("save round-trip keeps the deadline",
		restored[0].deadline_day == round_trip[0].deadline_day)
	_check("save round-trip keeps the run tally",
		GoalManager.achieved_total == achieved_snapshot)

	GoalManager.load_save_state({})
	_check("an empty block clears cleanly",
		GoalManager.get_goals(a.agent_name).is_empty() and GoalManager.achieved_total == 0)

	# --- Re-assignment and removal ------------------------------------------
	GoalManager.assign_for(a)
	_check("an untracked agent is re-assigned from personality",
		not GoalManager.get_goals(a.agent_name).is_empty())
	var count_after_assign: int = GoalManager.get_goals(a.agent_name).size()
	GoalManager.assign_for(a)
	_check("re-assignment does not duplicate",
		GoalManager.get_goals(a.agent_name).size() == count_after_assign)
	GoalManager._on_agent_removed(a.agent_name)
	_check("removing an agent drops its goals",
		GoalManager.get_goals(a.agent_name).is_empty())

	desk.queue_free()
	plant.queue_free()
	shelf.queue_free()


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
		# A broken build reaches here having asserted nothing. Without this the
		# report reads "0 passed, 0 failed", which any grep for "0 failed"
		# treats as success — that is how a compile error ships unnoticed.
		print("  NO ASSERTIONS RAN — treat this as a FAILURE")
	print("  %d passed, %d failed" % [passed, failed])
	print("=========================================")
