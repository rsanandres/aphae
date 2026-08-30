extends Node2D
## Functional test harness for M5 — The Mole (dev tool).
##
## Covers: case opening (forced and gated), the mole's M7 secret, incidents
## threading evidence to one actor, the witness path feeding the rumour
## chain, vote scoring from personal evidence (knowledge, case memories,
## plantable hearsay, grudges), the mole's strategic vote, house meetings
## (cost, catch, wrongful vote and its consequences), the mole win at max
## incidents, mid-case mole death, and save round-trip.
##
## Run: godot --headless --path . --audio-driver Dummy res://scenes/main/whodunit_test.tscn

var _results: Array[String] = []


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
	SynergyManager.auto_enabled = false
	_build_world()
	for i in range(5):
		AgentManager.spawn_procedural_agent(Vector2(50 + i * 30, 90))
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


func _fresh_case(mole: Node2D) -> CaseState:
	WhodunitDirector.case = null
	SecretManager._secrets.clear()
	return WhodunitDirector.open_case(mole)


func _run() -> void:
	var agents: Array = AgentManager.agents
	var mole: Node2D = agents[0]
	var victim_pool: Node2D = agents[1]
	var witness: Node2D = agents[2]
	var voter: Node2D = agents[3]
	var bystander: Node2D = agents[4]

	# --- Case opening --------------------------------------------------------
	var opened: Array = []
	EventBus.case_opened.connect(func() -> void: opened.append(true))
	var case: CaseState = _fresh_case(mole)
	_check("a case opens on demand", case != null and case.is_open())
	_check("opening emits its signal", not opened.is_empty())
	_check("the mole is who we forced", case.mole_name == mole.agent_name)
	_check("no second case while one is open", WhodunitDirector.open_case(victim_pool) == null)
	_check("the mole carries an M7 secret",
		SecretManager.has_hidden_secret(mole.agent_name))
	_check("the case thread and the secret thread agree",
		SecretManager.get_secret(mole.agent_name).thread() == case.thread())
	_check("a meeting is available with a live case", WhodunitDirector.meeting_available())

	# --- Incidents -----------------------------------------------------------
	var incidents: Array = []
	EventBus.case_incident.connect(func(v: String) -> void: incidents.append(v))
	WhodunitDirector.commit_incident(witness)  # force the lucky glimpse
	_check("an incident fires and names a victim", incidents.size() == 1)
	_check("the incident is counted", case.incidents == 1)
	var mole_mem := false
	for m: MemoryEntry in mole.memory.memories:
		if m.narrative_thread == case.thread() and "Nobody saw" in m.description:
			mole_mem = true
	_check("the deed lives in the mole's memory, case-threaded", mole_mem)
	var witness_mem: MemoryEntry = null
	for m: MemoryEntry in witness.memory.memories:
		if m.narrative_thread == case.thread() and mole.agent_name in m.related_agents:
			witness_mem = m
	_check("the witness glimpse names the mole", witness_mem != null)
	_check("the glimpse is gossipable (about a third party)",
		witness_mem != null and not witness_mem.related_agents.is_empty())

	# --- Votes follow evidence ----------------------------------------------
	# The witness holds a case memory naming the mole; a blank voter holds
	# nothing. Zero out grudges so only evidence separates the field.
	for a: Node2D in agents:
		for b: Node2D in agents:
			if a != b:
				var rel: RelationshipEntry = a.relationships.get_relationship(b.agent_name)
				rel.affinity = 0.0
				rel.trust = 50.0
	_check("evidence raises suspicion",
		WhodunitDirector._suspicion(witness, mole) > WhodunitDirector._suspicion(witness, voter))
	_check("the witness votes for the mole",
		WhodunitDirector._vote_of(witness, agents) == mole.agent_name)
	_check("knowledge outweighs a single sighting",
		WhodunitDirector.VOTE_KNOWS > WhodunitDirector.VOTE_CASE_MEMORY)
	_check("the mole never votes for themselves",
		WhodunitDirector._vote_of(mole, agents) != mole.agent_name)

	# Planted hearsay sways a voter — the producer's lever.
	var before_plant: float = WhodunitDirector._suspicion(voter, bystander)
	PlayerDirector.plant_rumor(voter, "%s has been acting strange lately." % bystander.agent_name, bystander.agent_name)
	_check("a planted smear raises suspicion",
		WhodunitDirector._suspicion(voter, bystander) > before_plant)
	_check("a producer plant outweighs idle gossip",
		WhodunitDirector.VOTE_PLANTED > WhodunitDirector.VOTE_HEARSAY
		and WhodunitDirector._suspicion(voter, bystander) - before_plant >= WhodunitDirector.VOTE_PLANTED)
	_check("a plant is still softer than a sighting",
		WhodunitDirector.VOTE_PLANTED < WhodunitDirector.VOTE_CASE_MEMORY)

	# Grudges look like guilt.
	var rel_grudge: RelationshipEntry = voter.relationships.get_relationship(victim_pool.agent_name)
	rel_grudge.affinity = -60.0
	_check("a grudge raises suspicion",
		WhodunitDirector._suspicion(voter, victim_pool) > 0.0)
	rel_grudge.affinity = 0.0

	# --- A wrongful meeting --------------------------------------------------
	var meetings: Array = []
	EventBus.house_meeting_held.connect(func(accused: String, was_mole: bool, votes: Dictionary) -> void:
		meetings.append({"accused": accused, "was_mole": was_mole, "votes": votes}))
	# Rig the room: everyone despises the bystander; only the witness knows
	# anything real, and one voice loses to three grudges.
	for a: Node2D in [mole, victim_pool, voter]:
		var rel: RelationshipEntry = a.relationships.get_relationship(bystander.agent_name)
		rel.affinity = -80.0
	ProducerEconomy.influence = 50
	var trust_before: float = bystander.relationships.get_relationship(voter.agent_name).trust
	var outcome: Dictionary = WhodunitDirector.call_house_meeting()
	_check("the meeting returns a tally", not outcome.is_empty())
	_check("the meeting costs Influence", ProducerEconomy.influence < 50)
	_check("grudges convict the innocent", outcome["accused"] == bystander.agent_name)
	_check("a wrong vote does not close the case", case.is_open())
	_check("a wrong vote is counted", case.wrongful_votes == 1)
	_check("the innocent resents their accusers",
		bystander.relationships.get_relationship(voter.agent_name).trust < trust_before)
	var betrayal := false
	for m: MemoryEntry in bystander.memory.memories:
		if m.emotion == "betrayal" and m.decay_protected:
			betrayal = true
	_check("the innocent will not forget", betrayal)
	# A wrong vote pays information: the host reviews the tapes.
	var tape_review := false
	for c: Confessional in ConfessionalDirector.confessionals:
		if "reviewed the tapes" in c.line:
			tape_review = true
	_check("a wrongful vote buys a host tip", tape_review)

	# --- Catching the mole ---------------------------------------------------
	var resolutions: Array = []
	EventBus.case_resolved.connect(func(caught: bool, name: String) -> void:
		resolutions.append({"caught": caught, "mole": name}))
	# Undo the frame-job grudges; hand everyone the truth.
	for a: Node2D in [mole, victim_pool, voter]:
		a.relationships.get_relationship(bystander.agent_name).affinity = 0.0
	var secret: SecretState = SecretManager.get_secret(mole.agent_name)
	for a: Node2D in [victim_pool, witness, voter, bystander]:
		if a.agent_name not in secret.known_by:
			secret.known_by.append(a.agent_name)
	ProducerEconomy.influence = 50
	var cast_before: int = AgentManager.agents.size()
	outcome = WhodunitDirector.call_house_meeting()
	_check("an informed house catches the mole",
		not outcome.is_empty() and outcome["was_mole"])
	_check("catching closes the case", case.status == CaseState.Status.CAUGHT)
	_check("catching resolves with caught=true",
		not resolutions.is_empty() and resolutions[-1]["caught"])
	_check("catching pays out",
		ProducerEconomy.influence > 50 - WhodunitDirector.MEETING_COST)
	# depart() animates the walk-out on its own clock before freeing; poll
	# instead of sleeping a guessed duration — the guess lost the race on CI.
	await _wait_cast_size(cast_before - 1)
	_check("the mole leaves the show", AgentManager.agents.size() == cast_before - 1)
	_check("no meeting without a case", WhodunitDirector.call_house_meeting().is_empty())

	# --- The mole wins at max incidents --------------------------------------
	# Freed-node discipline: the winner departs and is freed mid-block, so
	# capture the NAME now and never touch the node after resolution. The
	# original compared mole2.agent_name after the free — a script error that
	# every assertion survived, which is exactly what CI's SCRIPT ERROR sweep
	# exists to catch (and did, on its first run with this harness).
	var mole2: Node2D = AgentManager.agents[0]
	var mole2_name: String = mole2.agent_name
	var case2: CaseState = _fresh_case(mole2)
	_check("a second case opens after the first closes", case2 != null and case2.case_number == 2)

	# --- An evidence-free meeting shrugs instead of lynching ------------------
	# Genuinely blind: zero the relationships AND strip every memory that can
	# score as evidence or hearsay (earlier phases left speculation naming old
	# suspects — which is the mechanic working, not blindness).
	for x: Node2D in AgentManager.agents:
		for y: Node2D in AgentManager.agents:
			if x != y:
				var rel_xy: RelationshipEntry = x.relationships.get_relationship(y.agent_name)
				rel_xy.affinity = 0.0
				rel_xy.trust = 50.0
		for i in range(x.memory.memories.size() - 1, -1, -1):
			var wipe: MemoryEntry = x.memory.memories[i]
			if not wipe.related_agents.is_empty() or wipe.narrative_thread.begins_with("secret_"):
				x.memory.memories.remove_at(i)
	ProducerEconomy.influence = 50
	var blind: Dictionary = WhodunitDirector.call_house_meeting()
	_check("a blind house meeting is inconclusive, not a lynch",
		not blind.is_empty() and blind.get("inconclusive", false) and blind["accused"] == "")
	_check("an inconclusive meeting refunds half the cost",
		ProducerEconomy.influence == 50 - WhodunitDirector.MEETING_COST + WhodunitDirector.MEETING_COST / 2)
	_check("an inconclusive meeting counts no wrongful vote", case2.wrongful_votes == 0)
	_check("the case stays open after a shrug", case2.is_open())
	var cast_before2: int = AgentManager.agents.size()
	for i in range(WhodunitDirector.MAX_INCIDENTS):
		WhodunitDirector.commit_incident()
	_check("max incidents ends the case the mole's way",
		case2.status == CaseState.Status.MOLE_WON)
	await _wait_cast_size(cast_before2 - 1)
	_check("the winner walks", AgentManager.agents.size() == cast_before2 - 1)
	_check("resolution says they got away",
		resolutions[-1]["caught"] == false and resolutions[-1]["mole"] == mole2_name)

	# Two departures put the cast below MIN_CAST; refill it. (The old fixed
	# sleeps masked this: the departs had not finished, so the roster still
	# looked full when the next case opened.)
	while AgentManager.agents.size() < WhodunitDirector.MIN_CAST + 1:
		AgentManager.spawn_procedural_agent(Vector2(60 + AgentManager.agents.size() * 25, 90))
	await get_tree().process_frame

	# --- A mole dying dissolves the case -------------------------------------
	var mole3: Node2D = AgentManager.agents[0]
	var case3: CaseState = _fresh_case(mole3)
	mole3.is_dead = true
	WhodunitDirector.commit_incident()
	_check("a dead mole dissolves the case", not case3.is_open())
	mole3.is_dead = false

	# --- Persistence ---------------------------------------------------------
	var mole4: Node2D = AgentManager.agents[1]
	var case4: CaseState = _fresh_case(mole4)
	WhodunitDirector.commit_incident()
	var state: Dictionary = WhodunitDirector.get_save_state()
	WhodunitDirector.load_save_state({})
	_check("an empty block clears the case", WhodunitDirector.case == null)
	WhodunitDirector.load_save_state(state)
	_check("save round-trip keeps the case",
		WhodunitDirector.has_open_case()
		and WhodunitDirector.case.mole_name == mole4.agent_name
		and WhodunitDirector.case.incidents == 1)

	# --- The day-roll seam ---------------------------------------------------
	WhodunitDirector.case = null
	WhodunitDirector.auto_enabled = false
	for i in range(50):
		WhodunitDirector._on_day_changed(10 + i)
	_check("the seam keeps the day-roll quiet", WhodunitDirector.case == null)


func _wait_cast_size(expected: int) -> void:
	## Departures free their node on an animation clock; wait for the roster,
	## not the wall clock. Caps at 10s so a hang still reports, not stalls.
	var waited := 0.0
	while AgentManager.agents.size() != expected and waited < 10.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25


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
