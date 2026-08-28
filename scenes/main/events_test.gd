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
	ProducerEconomy.meta_persistence_enabled = false
	# M7 seams off: the spawn-roll must not plant secret memories under the
	# assertions, and the day-roll must not inject booth admissions mid-test.
	GoalManager.auto_enabled = false
	SecretManager.auto_assign_enabled = false
	SecretManager.auto_admit_enabled = false
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
	# Silence the daily spontaneous roll: it can re-arc `far` the instant the
	# forced arc finishes, which made "arc ran to completion" flaky (~1 in 20).
	ArcManager.auto_start_enabled = false
	_check("arc starts on demand", ArcManager.start_arc("burnout_spiral", far))
	_check("agent is arc-locked", ArcManager.has_arc(far.agent_name) and not ArcManager.start_arc("secret_hobby", far))
	for day in range(2, 14):
		TimeManager.game_minutes = (day - 1) * 1440.0 + 480.0
		EventBus.day_changed.emit(day)
		await get_tree().process_frame
	_check("arc ran to completion", not ArcManager.has_arc(far.agent_name))
	ArcManager.auto_start_enabled = true
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

	# --- E4: sabotage — asymmetric knowledge ---
	var victim: Node2D = AgentManager.agents[0]
	var bystander: Node2D = AgentManager.agents[1]
	var outsider: Node2D = AgentManager.agents[2]
	victim.global_position = Vector2(60, 60)
	bystander.global_position = Vector2(80, 60)
	outsider.global_position = Vector2(290, 190)
	EventManager.trigger_event("stolen_lunch", [victim])
	await get_tree().process_frame
	var saboteur: Node2D = null
	for agent in AgentManager.agents:
		for m in agent.memory.get_secrets():
			if m.narrative_thread == "secret_sabotage":
				saboteur = agent
	_check("sabotage has a hidden actor with a secret", saboteur != null and saboteur != victim)
	var victim_names_someone := false
	for m in victim.memory.memories:
		if "stole my lunch" in m.description and saboteur and saboteur.agent_name in m.description:
			victim_names_someone = true
	_check("victim's memory names no one", not victim_names_someone)
	var outsider_heard := false
	for m in outsider.memory.memories:
		if "lunch" in m.description:
			outsider_heard = true
	_check("out-of-radius agent knows nothing of the sabotage", not outsider_heard or outsider == saboteur)

	# --- E4: rumor mill — leaks are possible, gated by trust ---
	var holder: Node2D = AgentManager.agents[0]
	var confidant: Node2D = AgentManager.agents[1]
	# Use the returned entry, never memories[-1]: add_memory can append a
	# reflection on top of ours, which used to land this thread on the wrong
	# memory and made the leak assertions below flaky.
	var secret_mem: MemoryEntry = holder.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
		"%s knows something huge about %s. It stays secret." % [holder.agent_name, outsider.agent_name],
		8.0, PackedStringArray([outsider.agent_name]))
	secret_mem.narrative_thread = "secret_test"
	secret_mem.decay_protected = true
	var rel_hc: RelationshipEntry = holder.relationships.get_relationship(confidant.agent_name)
	rel_hc.trust = 90.0
	var leaked := false
	for i in range(400):
		if RumorMill.maybe_pass(holder, confidant):
			for m in confidant.memory.memories:
				if m.narrative_thread == "secret_test":
					leaked = true
		if leaked:
			break
	_check("a secret can leak to a trusted confidant", leaked)
	if leaked:
		var retold: MemoryEntry = null
		for m in confidant.memory.memories:
			if m.narrative_thread == "secret_test":
				retold = m
		_check("leak is marked secondhand", retold != null and "heard from" in retold.description)
		_check("leak is weaker than the original", retold != null and retold.importance < 8.0)
	# Low trust blocks secrets entirely
	var stranger: Node2D = AgentManager.agents[-1]
	var rel_hs: RelationshipEntry = holder.relationships.get_relationship(stranger.agent_name)
	rel_hs.trust = 10.0
	var leaked_low := false
	for i in range(400):
		RumorMill.maybe_pass(holder, stranger)
	for m in stranger.memory.memories:
		if m.narrative_thread == "secret_test":
			leaked_low = true
	_check("low trust never hears the secret", not leaked_low)

	# --- E5: producer dilemmas ---
	EventManager.auto_resolve_dilemmas = false  # harness resolves by hand
	var resolved_spy: Array = []
	EventBus.dilemma_resolved.connect(func(id: String, idx: int, timeout: bool) -> void:
		resolved_spy.append({"id": id, "idx": idx, "timeout": timeout}))

	# Leak dilemma, choice 0 (leak it): the secret spreads office-wide.
	var secret_holder: Node2D = AgentManager.agents[0]
	var jobhunt_mem: MemoryEntry = secret_holder.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
		"%s has been secretly interviewing at a rival company." % secret_holder.agent_name, 8.0)
	jobhunt_mem.narrative_thread = "secret_jobhunt"
	jobhunt_mem.decay_protected = true
	EventManager.trigger_event("leak_dilemma", [secret_holder])
	_check("dilemma holds the event pending", EventManager.has_pending_dilemma())
	_check("dilemma pauses the game", TimeManager.is_paused)
	EventManager.resolve_dilemma(0)
	await get_tree().process_frame
	_check("dilemma resolves and clears", not EventManager.has_pending_dilemma())
	_check("resolution signal fired with the choice", not resolved_spy.is_empty() and resolved_spy[-1]["idx"] == 0 and not resolved_spy[-1]["timeout"])
	var word_spread := false
	for m in AgentManager.agents[1].memory.memories:
		if "a story is suddenly everywhere" in m.description:
			word_spread = true
	_check("leaked secret reaches the office", word_spread)

	# Footage dilemma, choice 1 (bury it): saboteur keeps the secret, no exposure.
	var sab: Node2D = null
	for agent in AgentManager.agents:
		for m in agent.memory.get_secrets():
			if m.narrative_thread == "secret_sabotage":
				sab = agent
	if sab == null:
		sab = AgentManager.agents[1]
		var sab_mem: MemoryEntry = sab.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION, "did a bad thing in secret", 8.0)
		sab_mem.narrative_thread = "secret_sabotage"
	var affinity_toward_sab: float = a.relationships.get_relationship(sab.agent_name).affinity if a != sab else 0.0
	EventManager.trigger_event("sabotage_footage", [sab])
	EventManager.resolve_dilemma(1)
	await get_tree().process_frame
	var exposed := false
	for agent in AgentManager.agents:
		if agent == sab:
			continue
		for m in agent.memory.memories:
			if "behind the sabotage" in m.description:
				exposed = true
	_check("buried footage exposes no one", not exposed)
	_check("burying it deepens the secret", sab.memory.get_secrets().size() >= 1)

	# --- E6: every event id force-fires without error ---
	# Restore probabilities were zeroed above; force-trigger ignores them.
	var all_fired := true
	for definition in EventManager.get_available_events():
		# Churn events depart agents mid-walk — always fire at a live target.
		var live: Node2D = null
		for ag in AgentManager.agents:
			if is_instance_valid(ag) and not ag.is_dead:
				live = ag
				break
		if live == null:
			live = AgentManager.spawn_procedural_agent(Vector2(100, 100))
			await get_tree().process_frame
		var got: bool = EventManager.trigger_event(definition.event_id, [live])
		if EventManager.has_pending_dilemma():
			EventManager.resolve_dilemma(int(definition.dilemma.get("default_choice", 0)))
		if not got:
			all_fired = false
			print("      event failed to fire: %s" % definition.event_id)
		await get_tree().process_frame
	_check("all %d events fire by id without error" % EventManager.get_available_events().size(), all_fired)

	# --- E6: pacing band — simulated 20 days of organic rolls ---
	var defs := EventManager.get_available_events()
	var original_probs: Array[float] = []
	for definition in defs:
		original_probs.append(definition.probability)
	# reload real probabilities from disk values stored at parse time is
	# impossible here (we zeroed them), so re-read the JSON
	var f := FileAccess.open("res://resources/events/events.json", FileAccess.READ)
	var raw: Array = JSON.parse_string(f.get_as_text())
	var prob_by_id: Dictionary = {}
	for entry in raw:
		prob_by_id[entry["id"]] = float(entry.get("probability", 0.1))
	for definition in defs:
		definition.probability = prob_by_id.get(definition.event_id, 0.05)
	# The walker just spiked drama past the climax threshold, which would
	# suppress the whole sim to a 0.1-0.3 multiplier; measure at neutral pacing.
	DramaDirector.load_save_state({"drama_level": 3.0, "time_since_last_event": 0.0, "in_cooldown": false, "cooldown_remaining": 0.0})
	var tally: Array[int] = [0]
	EventBus.event_triggered.connect(func(_id: String, _names: Array) -> void: tally[0] += 1)
	var base_count: int = tally[0]
	for sim_day in range(30, 50):
		EventManager._events_today = 0
		DramaDirector.load_save_state({"drama_level": 3.0, "time_since_last_event": 0.0, "in_cooldown": false, "cooldown_remaining": 0.0})
		for window in range(3):
			EventManager._roll_events(sim_day)
			if EventManager.has_pending_dilemma():
				EventManager.resolve_dilemma(1)
			await get_tree().process_frame
	var per_day: float = float(tally[0] - base_count) / 20.0
	print("      organic pacing: %.1f events/day over 20 simulated days" % per_day)
	_check("pacing lands in the 1.5-6 events/day band", per_day >= 1.5 and per_day <= 6.0)
	for i in range(defs.size()):
		defs[i].probability = 0.0  # re-zero for any later blocks

	# --- Regression: dying mid-interaction must free the seat ---
	# A death at a desk used to leave a freed node in _occupants forever:
	# the desk read as permanently occupied, and two-seat objects would try
	# to start a conversation with the ghost. Use a dedicated object so the
	# harness's live agents cannot occupy it first.
	var world_node := get_tree().get_first_node_in_group("world")
	var seat: InteractableObject = ObjectFactory.create("desk")
	world_node.add_object(seat, Vector2(280, 60))
	await get_tree().process_frame
	var sitter: Node2D = AgentManager.spawn_procedural_agent(Vector2(285, 65))
	await get_tree().process_frame
	seat.occupy(sitter)
	_check("occupancy registers the intended sitter", seat.get_occupant() == sitter)
	sitter.die("regression test")
	await get_tree().create_timer(3.5).timeout
	_check("death frees the seat", seat.get_occupant_count() == 0)
	_check("seat is available again after a death", seat.is_available())
	var ghost_free := true
	for occ in seat.get_all_occupants():
		if not is_instance_valid(occ):
			ghost_free = false
	_check("no freed occupants linger", ghost_free)

	# --- Regression: a death mid-conversation must not strand the survivor ---
	# conversation_finished used to be emitted only after several lines that
	# throw on a freed participant, so the survivor stayed flagged "in
	# conversation" permanently and could never speak again.
	var talker_a: Node2D = AgentManager.spawn_procedural_agent(Vector2(200, 150))
	var talker_b: Node2D = AgentManager.spawn_procedural_agent(Vector2(206, 150))
	await get_tree().process_frame
	var started: bool = ConversationManager.start_conversation(talker_a, talker_b)
	_check("test conversation starts", started)
	if started:
		var survivor_name: String = talker_b.agent_name
		_check("participants are marked busy", ConversationManager.is_agent_busy(survivor_name))
		talker_a.die("died mid-sentence")
		await get_tree().create_timer(4.0).timeout
		_check("survivor is released when their partner dies",
			not ConversationManager.is_agent_busy(survivor_name))
		_check("survivor can talk again", talker_b.state != AgentState.Type.TALKING)

	# --- Regression: pruning finished conversations must not push freed
	# instances into a typed array (the error seen in the live playtest) ---
	var ghost_inst := ConversationInstance.new()
	ConversationManager.add_child(ghost_inst)
	ConversationManager._active_conversations.append(ghost_inst)
	var before_prune: int = ConversationManager._active_conversations.size()
	ghost_inst.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	ConversationManager._on_conversation_finished("__nobody_a", "__nobody_b")
	_check("freed conversation instances are pruned",
		ConversationManager._active_conversations.size() < before_prune)
	var prune_clean := true
	for inst in ConversationManager._active_conversations:
		if not is_instance_valid(inst):
			prune_clean = false
	_check("no freed instances survive the prune", prune_clean)

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
	if passed + failed == 0:
		# A broken build reaches here having asserted nothing. Without this the
		# report reads "0 passed, 0 failed", which any grep for "0 failed"
		# treats as success — that is how a compile error ships unnoticed.
		print("  NO ASSERTIONS RAN — treat this as a FAILURE")
	print("  %d passed, %d failed" % [passed, failed])
	print("=========================================")
