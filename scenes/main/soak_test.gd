extends Node2D
## Functional test harness for seeded runs and the soak report (dev tool).
##
## Covers: --seed parsing (and what it refuses), the seed being in force
## before the first scene, seeded personalities repeating, the report's
## arithmetic (repeat rate, stance spread, conclusion rate, time to first
## drama), the stable ordering of top repeats, the fingerprint matching for
## equal event streams and differing otherwise, the live signal wiring, the
## conversation turn carrying its pool, think-tick timing, and the
## achievement persistence seam.
##
## The end-to-end proof (same seed, same run) is tools/run_soak.sh, which
## needs two processes; this harness covers everything one process can.
##
## Run: godot --headless --path . --audio-driver Dummy res://scenes/main/soak_test.tscn

var _results: Array[String] = []
var _world: Node2D


func _ready() -> void:
	ProducerEconomy.meta_persistence_enabled = false
	SaveManager.episode_snapshots_enabled = false
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
	AchievementManager.persistence_enabled = false
	# The heuristic path is the one under test, whatever is reachable here.
	LLMManager._preferred_backend = "heuristic"
	LLMManager._update_active_backend()
	_build_world()
	await get_tree().create_timer(0.2).timeout
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


func _run() -> void:
	_test_seed_parsing()
	_test_seed_in_force()
	_test_seeded_personalities()
	_test_repeat_rate()
	_test_stance_spread()
	_test_conclusions_and_drama()
	_test_fingerprint()
	_test_document()
	_test_live_wiring()
	await _test_conversation_turn()
	_test_think_timing()
	_test_achievement_seam()


# --- F1: seeded runs ---

func _test_seed_parsing() -> void:
	_check("no --seed parses to none", SimSeed.parse(PackedStringArray(["--agents=4"])) == -1)
	_check("--seed=42 parses to 42", SimSeed.parse(PackedStringArray(["--seed=42"])) == 42)
	_check("--seed=0 is a real seed, not 'none'", SimSeed.parse(PackedStringArray(["--seed=0"])) == 0)
	_check("the last --seed wins", SimSeed.parse(PackedStringArray(["--seed=1", "--days=2", "--seed=7"])) == 7)
	_check("a non-numeric seed is refused, not read as 0", SimSeed.parse(PackedStringArray(["--seed=abc"])) == -1)
	_check("an empty seed is refused", SimSeed.parse(PackedStringArray(["--seed="])) == -1)
	_check("a negative seed is refused", SimSeed.parse(PackedStringArray(["--seed=-3"])) == -1)
	_check("a refused seed does not erase an earlier good one",
		SimSeed.parse(PackedStringArray(["--seed=9", "--seed=oops"])) == 9)


func _test_seed_in_force() -> void:
	# EventBus._init applied it before this scene existed.
	_check("a seed was applied before the first scene", SimSeed._applied)
	var parsed := SimSeed.parse(OS.get_cmdline_user_args())
	_check("explicit matches the command line", SimSeed.explicit == (parsed >= 0))
	_check("an explicit seed is the one in force", parsed < 0 or SimSeed.value == parsed)
	# The global stream really does replay from a seed.
	seed(SimSeed.value)
	var first: Array[int] = [randi(), randi(), randi()]
	seed(SimSeed.value)
	var second: Array[int] = [randi(), randi(), randi()]
	_check("re-seeding replays the global stream", first == second)


func _test_seeded_personalities() -> void:
	var was_explicit := SimSeed.explicit
	var was_value := SimSeed.value
	SimSeed.explicit = true
	SimSeed.value = 1234
	PersonalityGenerator.reset_names()
	var a := PersonalityGenerator.generate_heuristic(3)
	PersonalityGenerator.reset_names()
	var b := PersonalityGenerator.generate_heuristic(3)
	_check("a seeded cast member has the same name twice", a.agent_name == b.agent_name)
	_check("a seeded cast member has the same traits twice",
		is_equal_approx(a.openness, b.openness) and is_equal_approx(a.neuroticism, b.neuroticism)
		and is_equal_approx(a.agreeableness, b.agreeableness))
	PersonalityGenerator.reset_names()
	var other_index := PersonalityGenerator.generate_heuristic(4)
	_check("a different spawn index is a different person",
		not (is_equal_approx(a.openness, other_index.openness)
			and is_equal_approx(a.neuroticism, other_index.neuroticism)))
	SimSeed.value = 4321
	PersonalityGenerator.reset_names()
	var other_seed := PersonalityGenerator.generate_heuristic(3)
	_check("a different seed is a different person",
		not (is_equal_approx(a.openness, other_seed.openness)
			and is_equal_approx(a.neuroticism, other_seed.neuroticism)))
	SimSeed.explicit = was_explicit
	SimSeed.value = was_value
	PersonalityGenerator.reset_names()


# --- F2: the report's arithmetic ---

func _test_repeat_rate() -> void:
	var r := SoakReport.new()
	_check("an empty report has repeat rate 0, not NaN", r.repeat_rate() == 0.0)
	r.record_line("conversation", "Morning.")
	r.record_line("conversation", "Nice weather.")
	_check("two different lines: nothing repeated", r.lines_repeated() == 0)
	r.record_line("conversation", "Morning.")
	r.record_line("confessional", "Morning.")
	_check("a line heard before counts as a repeat, whoever says it", r.lines_repeated() == 2)
	_check("repeat rate is repeats over all lines", is_equal_approx(r.repeat_rate(), 2.0 / 4.0))
	r.record_line("conversation", "  Morning.  ")
	_check("surrounding whitespace does not hide a repeat", r.lines_repeated() == 3)
	r.record_line("conversation", "morning.")
	_check("a different capitalisation is a different line (verbatim means verbatim)", r.lines_repeated() == 3)
	r.record_line("conversation", "   ")
	_check("a blank line is not a line", r.lines_total() == 6)

	var top := SoakReport.new()
	for i in range(3):
		top.record_line("conversation", "b line")
		top.record_line("conversation", "a line")
	for i in range(5):
		top.record_line("conversation", "worst line")
	top.record_line("conversation", "said once")
	var rows := top.top_repeats()
	_check("top repeats lead with the worst offender", rows.size() == 3 and rows[0]["line"] == "worst line" and rows[0]["times"] == 5)
	_check("ties break alphabetically, so the list is stable", rows[1]["line"] == "a line" and rows[2]["line"] == "b line")
	_check("a line said once is not listed", not rows.any(func(row: Dictionary) -> bool: return row["line"] == "said once"))
	_check("top repeats honours its limit", top.top_repeats(1).size() == 1)


func _test_stance_spread() -> void:
	var r := SoakReport.new()
	_check("no turns: stance spread 0, not NaN", r.stance_spread() == 0.0)
	r.record_turn("neutral", "")
	r.record_turn("positive", "")
	r.record_turn("trait", "romantic")
	_check("neutral, positive and romantic turns are agreement", r.stance_spread() == 0.0)
	for kind: String in SoakReport.NON_AGREEMENT_KINDS:
		r.record_turn(kind, "")
	_check("reject, probe, deflect and negative are not", is_equal_approx(r.stance_spread(), 4.0 / 7.0))
	r.record_turn("llm", "hostile")
	_check("a model-written turn counts by a hostile tone", is_equal_approx(r.stance_spread(), 5.0 / 8.0))
	r.record_turn("llm", "")
	_check("a model-written turn with no tone is agreement", is_equal_approx(r.stance_spread(), 5.0 / 9.0))
	r.record_turn("negative", "hostile")
	_check("a hostile negative turn is counted once", is_equal_approx(r.stance_spread(), 6.0 / 10.0))


func _test_conclusions_and_drama() -> void:
	var r := SoakReport.new()
	var start := TimeManager.game_minutes
	r.record_narrative(4.9, start + 10.0)
	var doc_quiet := r.build({}, {})
	_check("below the drama bar is not drama", doc_quiet["drama"]["minutes_to_first"] == null and doc_quiet["drama"]["dramatic"] == 0)
	_check("no episode wrapped: conclusion rate is null, not 0", doc_quiet["conclusion_rate"] == null)

	var r2 := SoakReport.new()
	r2.record_narrative(2.0, start + 5.0)
	r2.record_narrative(5.0, start + 40.0)
	r2.record_narrative(9.0, start + 90.0)
	r2.record_conclusion("goal")
	r2.record_conclusion("goal")
	r2.record_conclusion("exposure")
	r2.record_episode()
	r2.record_episode()
	r2.record_conversation()
	var doc := r2.build({}, {})
	_check("time to first drama is the first event at the bar", is_equal_approx(float(doc["drama"]["minutes_to_first"]), 40.0))
	_check("drama counts events at or above the bar", doc["drama"]["dramatic"] == 2 and doc["drama"]["narrative_events"] == 3)
	_check("conclusion rate is conclusions per episode", is_equal_approx(float(doc["conclusion_rate"]), 1.5))
	_check("conclusions are broken out by kind", doc["conclusions"]["by_kind"]["goal"] == 2 and doc["conclusions"]["by_kind"]["exposure"] == 1)
	_check("conversations are counted", doc["conversations"]["total"] == 1)


func _test_fingerprint() -> void:
	var a := SoakReport.new()
	var b := SoakReport.new()
	var c := SoakReport.new()
	for report: SoakReport in [a, b]:
		report._stamp("line|Ada|Morning.")
		report._stamp("event|6.0|Ada snapped at Bo")
	c._stamp("line|Ada|Morning.")
	c._stamp("event|6.0|Ada snapped at Cy")
	var fa := a.fingerprint()
	_check("the same event stream has the same fingerprint", fa == b.fingerprint())
	_check("one changed event changes the fingerprint", fa != c.fingerprint())
	_check("a fingerprint is a sha-256 hex digest", fa.length() == 64)
	a._stamp("event|9.0|after the fact")
	_check("taking the fingerprint closes the stream", a.fingerprint() == fa)

	# The clock is part of the record: the same event a minute later is a
	# different run.
	var early := SoakReport.new()
	var late := SoakReport.new()
	early._stamp("event|6.0|x")
	TimeManager.game_minutes += 1.0
	late._stamp("event|6.0|x")
	TimeManager.game_minutes -= 1.0
	_check("the same event at a different game minute differs", early.fingerprint() != late.fingerprint())


func _test_document() -> void:
	var r := SoakReport.new()
	r.record_line("conversation", "Morning.")
	r.record_line("conversation", "Morning.")
	var doc := r.build({"seed": 7}, {"wall_seconds": 1.5})
	var wanted := ["run", "game_days", "repeat_rate", "conclusion_rate", "stance_spread",
		"lines", "stances", "conclusions", "drama", "conversations", "fingerprint", "timing"]
	_check("the document has every section", wanted.all(func(key: String) -> bool: return doc.has(key)))
	_check("run and timing pass through untouched", doc["run"]["seed"] == 7 and doc["timing"]["wall_seconds"] == 1.5)
	_check("the document survives a JSON round trip",
		JSON.parse_string(JSON.stringify(doc)) is Dictionary)
	_check("lines are broken out by source", doc["lines"]["by_source"]["conversation"]["repeated"] == 1)
	_check("distinct lines are counted", doc["lines"]["distinct"] == 1)


func _test_live_wiring() -> void:
	var r := SoakReport.new()
	r.attach()
	EventBus.conversation_started.emit("Ada", "Bo")
	EventBus.conversation_turn.emit("Ada", "Bo", "We need to talk.", "negative", "hostile")
	EventBus.conversation_turn.emit("Bo", "Ada", "We need to talk.", "neutral", "")
	EventBus.narrative_event.emit("Ada snapped at Bo", ["Ada", "Bo"], 6.0)
	EventBus.goal_achieved.emit("Ada", "Ship the feature", 0)
	EventBus.romance_started.emit("Ada", "Bo")
	EventBus.secret_exposed.emit("Bo", "secretly job hunting")
	EventBus.case_resolved.emit(true, "Bo")
	EventBus.episode_ended.emit(1, 1, 70, 12)
	_check("live: a conversation is counted", r._conversations == 1)
	# Counted by source: the drama above may also draw a confessional quip,
	# which is a spoken line too.
	var spoken: Dictionary = r._lines.get("conversation", {})
	_check("live: turns become lines and stances",
		spoken.get("total", 0) == 2 and r._turns_total == 2 and r._turns_non_agreement == 1)
	_check("live: the second identical line is a repeat", spoken.get("repeated", 0) == 1)
	_check("live: every kind of conclusion lands", r.conclusions_total() == 4)
	_check("live: the episode wrap is counted", r._episodes == 1)
	_check("live: drama is timed from attach", is_equal_approx(r._first_drama_minutes, 0.0))
	var silent := SoakReport.new()
	_check("live: events reached the fingerprint", r.fingerprint() != silent.fingerprint())


func _test_conversation_turn() -> void:
	var a := AgentManager.spawn_procedural_agent(Vector2(60, 90))
	var b := AgentManager.spawn_procedural_agent(Vector2(80, 90))
	await get_tree().create_timer(0.3).timeout
	var turns: Array[Dictionary] = []
	var lines: Array[String] = []
	var on_turn := func(speaker: String, listener: String, line: String, kind: String, tone: String) -> void:
		turns.append({"speaker": speaker, "listener": listener, "line": line, "kind": kind, "tone": tone})
	var on_line := func(_speaker: String, line: String) -> void:
		lines.append(line)
	EventBus.conversation_turn.connect(on_turn)
	EventBus.conversation_line.connect(on_line)
	var started := ConversationManager.start_conversation(a, b)
	await get_tree().create_timer(0.3).timeout
	EventBus.conversation_turn.disconnect(on_turn)
	EventBus.conversation_line.disconnect(on_line)
	_check("a conversation started", started)
	_check("the opening line raised a turn", turns.size() >= 1)
	if turns.is_empty():
		return
	var turn: Dictionary = turns[0]
	_check("the turn names speaker and listener", turn["speaker"] == a.agent_name and turn["listener"] == b.agent_name)
	_check("the turn carries the same line the bubble shows", lines.size() >= 1 and turn["line"] == lines[0])
	var known := ["confess", "accept", "reject", "probe", "deflect", "memory", "trait",
		"mourning", "need", "romantic", "positive", "negative", "neutral"]
	_check("a heuristic turn names the pool it came from", turn["kind"] in known)
	_check("the tone is one the bubble knows", turn["tone"] in ["", "hostile", "romantic"])


func _test_think_timing() -> void:
	var before := AgentManager.think_calls
	var ran := [false]
	AgentManager._timed_think(func() -> void: ran[0] = true)
	_check("a timed think runs its trigger", ran[0])
	_check("a timed think is counted", AgentManager.think_calls == before + 1)
	_check("the slowest think is at least the total's share",
		AgentManager.think_usec_max >= 0 and AgentManager.think_usec_total >= AgentManager.think_usec_max)


func _test_achievement_seam() -> void:
	# With the seam off, a save must not reach the file.
	var sentinel := 987654321
	var kept: int = AchievementManager._objects_placed
	AchievementManager._objects_placed = sentinel
	AchievementManager._save_progress()
	AchievementManager._objects_placed = kept
	var on_disk := ""
	if FileAccess.file_exists(AchievementManager.ACHIEVEMENTS_PATH):
		on_disk = FileAccess.get_file_as_string(AchievementManager.ACHIEVEMENTS_PATH)
	_check("achievements do not persist while the seam is off", not on_disk.contains(str(sentinel)))


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
