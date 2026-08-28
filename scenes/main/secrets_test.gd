extends Node2D
## Functional test harness for M7 — secrets & lies (dev tool).
##
## Covers: assignment (memory substance, no self-gossip), the confide trust
## gate and its memories, the rumour-mill hop updating known_by, exposure at
## the threshold, the probe's trust cost, booth admission reaching the
## confessional feed and the player-facing flags, prompt lines for holders
## and knowers, heuristic flavor lines, inspector tease, and save round-trip.
##
## Run: godot --headless --path . --audio-driver Dummy res://scenes/main/secrets_test.tscn

var _results: Array[String] = []


func _ready() -> void:
	ProducerEconomy.meta_persistence_enabled = false
	TimeManager.is_paused = true
	SaveManager._last_auto_save_day = 999999
	for definition in EventManager.get_available_events():
		definition.probability = 0.0
	ArcManager.auto_start_enabled = false
	GoalManager.auto_enabled = false
	WhodunitDirector.auto_enabled = false
	ImpactLog.auto_enabled = false
	SecretManager.auto_assign_enabled = false
	SecretManager.auto_admit_enabled = false
	_build_world()
	for i in range(4):
		AgentManager.spawn_procedural_agent(Vector2(60 + i * 30, 90))
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
	add_child(world)


func _run() -> void:
	var agents: Array = AgentManager.agents
	var holder: Node2D = agents[0]
	var friend: Node2D = agents[1]
	var gossip: Node2D = agents[2]
	var outsider: Node2D = agents[3]

	# --- Assignment ----------------------------------------------------------
	var secret: SecretState = SecretManager.assign_secret(holder, "job_hunt")
	_check("assignment returns the state", secret != null and secret.id == "job_hunt")
	_check("one secret per agent", SecretManager.assign_secret(holder, "resume") == null)
	_check("unknown pool id is refused",
		SecretManager.assign_secret(friend, "nuclear_codes") == null)
	_check("has_hidden_secret sees it", SecretManager.has_hidden_secret(holder.agent_name))
	var holder_mem: MemoryEntry = null
	for m: MemoryEntry in holder.memory.memories:
		if m.narrative_thread == "secret_job_hunt":
			holder_mem = m
	_check("the secret is backed by a protected memory",
		holder_mem != null and holder_mem.decay_protected)
	_check("the holder's own memory names no third party",
		holder_mem != null and holder_mem.related_agents.is_empty())
	_check("get_secrets() finds it (producer leak dilemma path)",
		not holder.memory.get_secrets().is_empty())

	# The RumorMill must never lift the secret straight out of the holder's
	# head: their own memory has no third party, so it is not gossipable.
	var rel_hf: RelationshipEntry = holder.relationships.get_relationship(friend.agent_name)
	rel_hf.trust = 95.0
	var leaked_direct := false
	for i in range(300):
		RumorMill.maybe_pass(holder, friend)
	for m: MemoryEntry in friend.memory.memories:
		if m.narrative_thread == "secret_job_hunt":
			leaked_direct = true
	_check("a holder never gossips their own secret", not leaked_direct)

	# --- Confide -------------------------------------------------------------
	var confided: Array = []
	EventBus.secret_confided.connect(func(h: String, c: String) -> void:
		confided.append([h, c]))

	# Below the gate: never confides, no matter how many conversations.
	rel_hf.trust = 30.0
	for i in range(200):
		SecretManager.process_conversation_end(holder, friend)
	_check("low trust blocks confiding", confided.is_empty()
		and friend.agent_name not in secret.known_by)

	rel_hf.trust = 95.0
	for i in range(200):
		SecretManager.process_conversation_end(holder, friend)
		if not confided.is_empty():
			break
	_check("high trust lets the holder confide", not confided.is_empty()
		and friend.agent_name in secret.known_by)
	_check("confiding is not repeated", secret.known_by.count(friend.agent_name) == 1)
	var confide_mem: MemoryEntry = null
	for m: MemoryEntry in friend.memory.memories:
		if m.narrative_thread == "secret_job_hunt":
			confide_mem = m
	_check("the confidant's memory is about the holder",
		confide_mem != null and holder.agent_name in confide_mem.related_agents)

	# --- The rumour hop ------------------------------------------------------
	# Now the confidant CAN gossip it: their memory names a third party.
	var rel_fg: RelationshipEntry = friend.relationships.get_relationship(gossip.agent_name)
	rel_fg.trust = 95.0
	var hopped := false
	for i in range(400):
		RumorMill.maybe_pass(friend, gossip)
		if gossip.agent_name in secret.known_by:
			hopped = true
			break
	_check("the rumour mill carries a confided secret onward", hopped)
	_check("the new ear is tracked in known_by", gossip.agent_name in secret.known_by)

	# --- Exposure ------------------------------------------------------------
	var exposed_events: Array = []
	EventBus.secret_exposed.connect(func(h: String, t: String) -> void:
		exposed_events.append([h, t]))
	var narratives: Array = []
	EventBus.narrative_event.connect(func(text: String, _ag: Array, importance: float) -> void:
		narratives.append({"text": text, "importance": importance}))

	# Third ear crosses the threshold.
	var rel_fo: RelationshipEntry = friend.relationships.get_relationship(outsider.agent_name)
	rel_fo.trust = 95.0
	for i in range(400):
		RumorMill.maybe_pass(friend, outsider)
		if secret.exposed:
			break
	_check("enough ears exposes the secret", secret.exposed)
	_check("exposure emits its signal",
		not exposed_events.is_empty() and exposed_events[0][0] == holder.agent_name)
	_check("exposure narrates above the confessional bar",
		not narratives.is_empty() and narratives[-1]["importance"] >= 6.0)
	_check("an exposed secret is no longer hidden",
		not SecretManager.has_hidden_secret(holder.agent_name))
	_check("an exposed secret stops prompting denial",
		SecretManager.denial_prompt_line(holder.agent_name) == "")

	# --- Probe (fresh pair, so exposure state does not interfere) -------------
	SecretManager._secrets.clear()
	var secret2: SecretState = SecretManager.assign_secret(friend, "resume")
	secret2.known_by.append(gossip.agent_name)
	var confronted: Array = []
	EventBus.secret_confronted.connect(func(h: String, k: String) -> void:
		confronted.append([h, k]))
	var rel_before: float = friend.relationships.get_relationship(gossip.agent_name).trust
	for i in range(200):
		SecretManager.process_conversation_end(gossip, friend)
		if not confronted.is_empty():
			break
	_check("a knower eventually probes the holder", not confronted.is_empty())
	_check("being probed costs the pair trust",
		friend.relationships.get_relationship(gossip.agent_name).trust < rel_before)
	_check("an outsider who knows nothing cannot probe",
		not SecretManager.knows(outsider.agent_name, friend.agent_name))

	# --- Prompt lines --------------------------------------------------------
	var denial := SecretManager.denial_prompt_line(friend.agent_name)
	_check("a holder's prompt carries the denial instruction",
		"hiding" in denial and "embellished" in denial)
	var gossip_line := SecretManager.gossip_prompt_line(gossip.agent_name, friend.agent_name)
	_check("a knower's prompt carries the rumor", "heard a rumor" in gossip_line)
	_check("a stranger's prompt carries nothing",
		SecretManager.gossip_prompt_line(outsider.agent_name, friend.agent_name) == ""
		and SecretManager.denial_prompt_line(outsider.agent_name) == "")

	# --- Booth admission -----------------------------------------------------
	var admitted: Array = []
	EventBus.secret_admitted.connect(func(h: String, t: String) -> void:
		admitted.append(h))
	var feed_before: int = ConfessionalDirector.confessionals.size()
	ConfessionalDirector._cooldown = 0.0
	SecretManager.admit_on_camera(secret2)
	# The heuristic path emits synchronously; the LLM path would not, but no
	# LLM is configured in this harness.
	_check("admission emits its signal", friend.agent_name in admitted)
	_check("admission is flagged for the player", secret2.admitted_on_camera)
	_check("the booth actually recorded it",
		ConfessionalDirector.confessionals.size() > feed_before)
	var quip: Confessional = ConfessionalDirector.confessionals[-1]
	_check("the admission names the truth", "embellished" in quip.line)
	_check("the admission is kind=secret", quip.kind == "secret")
	_check("the cast still does not know",
		not SecretManager.knows(outsider.agent_name, friend.agent_name))

	# --- Heuristic flavor sees the state -------------------------------------
	# (Line pools are probabilistic; assert the gates, not the dice.)
	_check("knows() gates the probe flavor line",
		SecretManager.knows(gossip.agent_name, friend.agent_name))
	_check("has_hidden_secret() gates the deflect flavor line",
		SecretManager.has_hidden_secret(friend.agent_name))

	# --- Inspector tease -----------------------------------------------------
	var inspector := AgentInspector.new()
	add_child(inspector)
	inspector._agent = friend
	inspector._update_dynamic()
	_check("inspector reveals an admitted secret",
		"admitted on camera" in inspector._goals_label.text)
	SecretManager._secrets.clear()
	var secret3: SecretState = SecretManager.assign_secret(outsider, "novel")
	inspector._agent = outsider
	inspector._update_dynamic()
	_check("inspector only teases a hidden secret",
		"hiding something" in inspector._goals_label.text
		and "novel" not in inspector._goals_label.text)
	inspector.queue_free()

	# --- Save round-trip -----------------------------------------------------
	secret3.known_by.append(friend.agent_name)
	var state: Dictionary = SecretManager.get_save_state()
	SecretManager.load_save_state(state)
	var restored: SecretState = SecretManager.get_secret(outsider.agent_name)
	_check("save round-trip keeps the secret",
		restored != null and restored.id == "novel")
	_check("save round-trip keeps who knows",
		restored != null and friend.agent_name in restored.known_by)
	SecretManager.load_save_state({})
	_check("an empty block clears cleanly",
		SecretManager.get_secret(outsider.agent_name) == null)

	# --- Producer leak keeps the M7 state honest -----------------------------
	SecretManager._secrets.clear()
	# The leak script grabs get_secrets()[0], so purge this agent's stale
	# secret-thread memories from earlier cases (backwards, by index).
	for i in range(holder.memory.memories.size() - 1, -1, -1):
		if holder.memory.memories[i].narrative_thread.begins_with("secret_"):
			holder.memory.memories.remove_at(i)
	var leak_secret: SecretState = SecretManager.assign_secret(holder, "moonlight")
	ConsequenceEngine._script_leak_secret(holder)
	_check("a producer leak exposes the M7 state", leak_secret.exposed)
	_check("a leaked secret stops prompting denial",
		SecretManager.denial_prompt_line(holder.agent_name) == "")

	# --- Removal -------------------------------------------------------------
	SecretManager.assign_secret(outsider, "savings")
	EventBus.agent_removed.emit(outsider.agent_name)
	_check("removing an agent drops their secret",
		SecretManager.get_secret(outsider.agent_name) == null)


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
