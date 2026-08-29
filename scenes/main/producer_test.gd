extends Node2D
## Functional test harness for PlayerDirector (dev tool, not shipped content).
##
## Covers the three producer actions: nudge (both compliance AND refusal must
## be reachable), interview (answers arrive, LLM or heuristic), and rumour
## planting (lands in memory and is retrievable).
##
## Run: godot --headless --path . res://scenes/main/producer_test.tscn

var _results: Array[String] = []
var _nudges: Array[Dictionary] = []
var _answers: Array[String] = []
var _rumors: Array[String] = []


func _ready() -> void:
	ProducerEconomy.meta_persistence_enabled = false
	# M7 seams off: the spawn-roll must not plant secret memories under the
	# assertions, and the day-roll must not inject booth admissions mid-test.
	GoalManager.auto_enabled = false
	WhodunitDirector.auto_enabled = false
	SecretManager.auto_assign_enabled = false
	SecretManager.auto_admit_enabled = false
	EventBus.nudge_answered.connect(func(who: String, req: String, ok: bool, reason: String) -> void:
		_nudges.append({"who": who, "req": req, "ok": ok, "reason": reason})
		print("   NUDGE %s -> %s%s" % [who, "AGREED" if ok else "REFUSED", "" if ok else " (%s)" % reason])
	)
	EventBus.interview_answered.connect(func(who: String, q: String, a: String) -> void:
		_answers.append(a)
		print("   Q: %s\n   A: <%s> %s" % [q, who, a])
	)
	EventBus.rumor_planted.connect(func(who: String, text: String) -> void:
		_rumors.append(text)
		print("   RUMOUR -> %s: %s" % [who, text])
	)

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

	# Children before tree entry — office.gd resolves $Objects/$Agents in
	# @onready, which fires on entry.
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
	_place_objects(world)


func _place_objects(world: Node) -> void:
	# Nudges resolve to a real object, so the room cannot be empty.
	var types := ["desk", "couch", "coffee_machine", "bed", "water_cooler"]
	for i in range(types.size()):
		var path := "res://scenes/objects/%s.gd" % types[i]
		if not FileAccess.file_exists(path):
			continue
		var obj := StaticBody2D.new()
		obj.collision_layer = 4
		obj.collision_mask = 0
		obj.set_script(load(path))
		var sprite := Sprite2D.new()
		sprite.name = "Sprite2D"
		obj.add_child(sprite)
		var shape := CollisionShape2D.new()
		shape.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = Vector2(24, 16)
		shape.shape = rect
		obj.add_child(shape)
		world.add_object(obj, Vector2(40 + i * 45, 60))
	print("[TEST] placed %d objects" % world.get_all_objects().size())


func _spawn(n: int) -> void:
	for i in range(n):
		AgentManager.spawn_procedural_agent(Vector2(40 + i * 30, 120))
	var names: PackedStringArray = []
	for a in AgentManager.agents:
		names.append(a.agent_name)
	print("[TEST] spawned %d agents: %s" % [AgentManager.agents.size(), ", ".join(names)])


func _pass(ok: bool, label: String) -> void:
	_results.append(("PASS  " if ok else "FAIL  ") + label)


func _run() -> void:
	var a: Node2D = AgentManager.agents[0]

	# --- Nudge ---
	# Compliance is probabilistic by design, so assert over many samples rather
	# than one: every nudge must produce an answer, and across a fair sample
	# BOTH outcomes must be reachable. A director that always complies is a
	# puppet; one that never does is furniture.
	print("\n[TEST] 1. nudges always produce an answer")
	var kinds: Array = PlayerDirector.get_nudge_kinds()
	var before := _nudges.size()
	var attempts := 0
	for round in range(6):
		for kind in kinds:
			var target: Node2D = AgentManager.agents[attempts % AgentManager.agents.size()]
			if is_instance_valid(target) and not target.is_dead:
				PlayerDirector.nudge(target, kind)
				attempts += 1
	_pass(_nudges.size() - before == attempts, "every nudge emits a result (%d/%d)" % [_nudges.size() - before, attempts])

	var agreed := 0
	var refused := 0
	for n in _nudges:
		if n["ok"]:
			agreed += 1
		else:
			refused += 1
	print("   -> %d agreed, %d refused over %d nudges" % [agreed, refused, _nudges.size()])
	_pass(agreed > 0, "agents sometimes comply (%d)" % agreed)
	_pass(refused > 0, "agents sometimes refuse (%d)" % refused)
	for n in _nudges:
		if not n["ok"] and n["reason"] == "":
			_pass(false, "every refusal carries a reason")
			break
	if refused > 0:
		_pass(true, "every refusal carries a reason")

	print("[TEST] 2. unknown nudge is rejected, not crashed")
	_pass(PlayerDirector.nudge(a, "do_a_backflip") == false, "unknown nudge kind returns false")

	# --- Interview ---
	print("[TEST] 3. interview returns an in-character answer")
	var n_before := _answers.size()
	PlayerDirector.interview(a, "How are you finding the office so far?")
	var deadline := 30.0
	while _answers.size() == n_before and deadline > 0.0:
		await get_tree().create_timer(0.25).timeout
		deadline -= 0.25
	var got_answer := _answers.size() > n_before
	_pass(got_answer, "interview produces an answer")
	_pass(got_answer and _answers[-1].strip_edges() != "", "answer is non-empty")
	_pass(got_answer and not ("{" in _answers[-1] and "}" in _answers[-1]), "no unfilled prompt tokens leaked")

	print("[TEST] 4. empty question is ignored")
	var n2 := _answers.size()
	PlayerDirector.interview(a, "   ")
	await get_tree().create_timer(1.0).timeout
	_pass(_answers.size() == n2, "blank question produces nothing")

	# --- Rumour ---
	print("[TEST] 5. rumour lands in memory and is retrievable")
	var subject: String = AgentManager.agents[1].agent_name
	var rumor: String = PlayerDirector.rumor_templates(subject)[0]
	var mem_before: int = a.memory.memories.size()
	PlayerDirector.plant_rumor(a, rumor, subject)
	await get_tree().process_frame
	_pass(a.memory.memories.size() > mem_before, "rumour added a memory")
	_pass(not _rumors.is_empty(), "rumor_planted signal fired")

	var found := false
	for m in a.memory.get_memories_about(subject, 10):
		if m.description == rumor:
			found = true
			break
	_pass(found, "rumour is retrievable as a memory about the subject")

	print("[TEST] 6. empty rumour is ignored")
	var mem2: int = a.memory.memories.size()
	PlayerDirector.plant_rumor(a, "  ", subject)
	await get_tree().process_frame
	_pass(a.memory.memories.size() == mem2, "blank rumour produces nothing")

	print("[TEST] 7. dead agents reject everything")
	var victim: Node2D = AgentManager.agents[3]
	victim.is_dead = true
	var n3 := _nudges.size()
	var m3: int = victim.memory.memories.size()
	PlayerDirector.nudge(victim, "rest")
	PlayerDirector.plant_rumor(victim, "something juicy", subject)
	await get_tree().create_timer(0.5).timeout
	_pass(_nudges.size() == n3 and victim.memory.memories.size() == m3, "dead agents are inert")
	victim.is_dead = false

	print("[TEST] 8. star of the episode")
	ProducerEconomy.influence = 50
	_pass(PlayerDirector.set_star(a), "an agent can be made the star")
	_pass(PlayerDirector.star_name == a.agent_name, "the star is recorded")
	AgentManager._reclassify_tiers()
	_pass(AgentManager.get_tier(a) == AgentManager.ThinkTier.ACTIVE,
		"the star is forced into the ACTIVE tier")
	var star_state: Dictionary = PlayerDirector.get_star_save()
	PlayerDirector.clear_star()
	_pass(PlayerDirector.star_name == "", "the spotlight clears")
	PlayerDirector.load_star_save(star_state)
	_pass(PlayerDirector.star_name == a.agent_name, "the star survives a save round-trip")
	PlayerDirector.set_star(a)  # toggling the current star clears it
	_pass(PlayerDirector.star_name == "", "choosing the star again clears them")
	_pass(not PlayerDirector.set_star(victim) if victim.is_dead else true, "sanity")

	print("[TEST] 9. because-of-you log")
	ImpactLog.auto_enabled = true
	ImpactLog._entries.clear()
	EventBus.nudge_answered.emit(a.agent_name, "get coffee", true, "")
	var log_entries: Array[Dictionary] = ImpactLog.get_entries()
	_pass(log_entries.size() == 1 and "nudged" in str(log_entries[0]["text"]),
		"a complied nudge opens an intervention")
	# Same-minute events are treated as the intervention echoing itself, so
	# step the clock past the guard before rippling.
	TimeManager.game_minutes += 2.0
	EventBus.narrative_event.emit("%s spilled coffee dramatically." % a.agent_name, [a.agent_name], 5.0)
	log_entries = ImpactLog.get_entries()
	_pass((log_entries[0]["ripples"] as Array).size() == 1,
		"a ripple attaches to the intervention")
	# Unrelated people do not ripple.
	EventBus.narrative_event.emit("Someone else did something.", ["Nobody Real"], 5.0)
	_pass((ImpactLog.get_entries()[0]["ripples"] as Array).size() == 1,
		"unrelated events do not attach")
	# Outside the window, nothing attaches.
	TimeManager.game_minutes += ImpactLog.WINDOW_MINUTES + 10.0
	EventBus.narrative_event.emit("%s did a thing much later." % a.agent_name, [a.agent_name], 5.0)
	_pass((ImpactLog.get_entries()[0]["ripples"] as Array).size() == 1,
		"the attribution window closes")
	# Ripple cap holds.
	EventBus.rumor_planted.emit(a.agent_name, "a planted line")
	TimeManager.game_minutes += 2.0
	for i in range(5):
		EventBus.narrative_event.emit("%s ripple %d." % [a.agent_name, i], [a.agent_name], 5.0)
	_pass((ImpactLog.get_entries()[0]["ripples"] as Array).size() == ImpactLog.MAX_RIPPLES,
		"the ripple cap holds")
	# Save round-trip.
	var impact_state: Dictionary = ImpactLog.get_save_state()
	ImpactLog.load_save_state({})
	_pass(ImpactLog.get_entries().is_empty(), "an empty block clears the log")
	ImpactLog.load_save_state(impact_state)
	_pass(ImpactLog.get_entries().size() == 2, "the log survives a save round-trip")
	# Self-echo guard: a same-minute event is the intervention announcing
	# itself and must not consume a ripple slot.
	ImpactLog._entries.clear()
	EventBus.rumor_planted.emit(a.agent_name, "echo test")
	EventBus.narrative_event.emit("%s heard something: echo test" % a.agent_name, [a.agent_name], 6.0)
	_pass((ImpactLog.get_entries()[0]["ripples"] as Array).is_empty(),
		"a same-minute event does not ripple to its own intervention")
	# Mundane chatter gets at most one slot.
	TimeManager.game_minutes += 2.0
	EventBus.conversation_ended.emit(a.agent_name, "Whoever")
	EventBus.conversation_ended.emit(a.agent_name, "Someone")
	_pass((ImpactLog.get_entries()[0]["ripples"] as Array).size() == 1,
		"talked ripples occupy at most one slot")
	ImpactLog.auto_enabled = false
	SynergyManager.auto_enabled = false


func _report() -> void:
	print("\n================ RESULTS ================")
	var failed := 0
	for r in _results:
		print("  " + r)
		if r.begins_with("FAIL"):
			failed += 1
	print("-----------------------------------------")
	if _results.is_empty():
		# A broken build reaches here having asserted nothing, and the line
		# below would read "0 passed, 0 failed" — which any grep for
		# "0 failed" treats as success. That is how a compile error ships.
		print("  NO ASSERTIONS RAN — treat this as a FAILURE")
	print("  %d passed, %d failed" % [_results.size() - failed, failed])
	print("=========================================\n")
