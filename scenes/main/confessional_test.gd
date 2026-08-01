extends Node2D
## Functional test harness for ConfessionalDirector (dev tool, not shipped content).
## Fires every EventBus path the director listens to and asserts it responds
## correctly, including the negative cases (cooldown suppression, low-importance
## filtering). Exercises the heuristic path when no LLM backend is present.
##
## Run: godot --headless --path . res://scenes/main/confessional_test.tscn

var _received: Array[Confessional] = []
var _expect: String = ""
var _results: Array[String] = []


func _ready() -> void:
	EventBus.confessional_recorded.connect(_on_confessional)
	_build_world()
	_spawn(4)
	await get_tree().create_timer(1.0).timeout
	await _run()
	_report()
	get_tree().quit()


func _build_world() -> void:
	# Minimal world: AgentManager.spawn_procedural_agent needs a "world"
	# group node with an "Agents" child.
	var world := Node2D.new()
	world.add_to_group("world")
	add_child(world)
	var agents_node := Node2D.new()
	agents_node.name = "Agents"
	world.add_child(agents_node)


func _spawn(n: int) -> void:
	for i in range(n):
		AgentManager.spawn_procedural_agent(Vector2(40 + i * 30, 60))
	print("[TEST] spawned %d agents: %s" % [AgentManager.agents.size(), _names()])


func _names() -> String:
	var out: PackedStringArray = []
	for a in AgentManager.agents:
		out.append(a.agent_name)
	return ", ".join(out)


func _on_confessional(c: RefCounted) -> void:
	var conf: Confessional = c as Confessional
	if conf:
		_received.append(conf)
		print("   CAM  <%s> [%s] \"%s\"" % [conf.speaker, conf.kind, conf.line])


func _check(label: String, expect_kind: String, before: int) -> void:
	# `before` must be sampled BEFORE the emit — signals deliver synchronously,
	# and LLM-backed quips arrive later via callback.
	await get_tree().create_timer(1.5).timeout
	var got := _received.size() > before
	var kind_ok := got and _received[-1].kind == expect_kind
	var speaker_ok := got and _received[-1].speaker != "" and _received[-1].line != ""
	if got and kind_ok and speaker_ok:
		_results.append("PASS  %s" % label)
	else:
		_results.append("FAIL  %s (fired=%s kind_ok=%s speaker_ok=%s)" % [label, got, kind_ok, speaker_ok])


func _cool() -> void:
	# Director enforces an 8s cooldown between quips.
	await get_tree().create_timer(9.0).timeout


func _run() -> void:
	var a: String = AgentManager.agents[0].agent_name
	var b: String = AgentManager.agents[1].agent_name

	print("\n[TEST] 1. confession_made -> agent voice")
	var n1 := _received.size()
	EventBus.confession_made.emit(a, b, false)
	await _check("confession_made produces agent confessional", "romance", n1)

	print("[TEST] 2. rate limit: immediate second event must be dropped")
	var before := _received.size()
	EventBus.romance_started.emit(a, b)
	await get_tree().create_timer(1.5).timeout
	if _received.size() == before:
		_results.append("PASS  cooldown suppresses back-to-back quips")
	else:
		_results.append("FAIL  cooldown did not suppress second quip")

	await _cool()
	print("[TEST] 3. romance_started -> agent voice")
	var n3 := _received.size()
	EventBus.romance_started.emit(a, b)
	await _check("romance_started produces agent confessional", "romance", n3)

	await _cool()
	print("[TEST] 4. narrative_event (importance 8) -> agent voice")
	var n4 := _received.size()
	EventBus.narrative_event.emit("%s was publicly humiliated in the meeting." % a, [a], 8.0)
	await _check("high-importance narrative event fires", "drama", n4)

	await _cool()
	print("[TEST] 5. low-importance narrative event must be ignored")
	var before2 := _received.size()
	EventBus.narrative_event.emit("%s refilled the stapler." % a, [a], 2.0)
	await get_tree().create_timer(1.5).timeout
	if _received.size() == before2:
		_results.append("PASS  low-importance events ignored")
	else:
		_results.append("FAIL  low-importance event wrongly fired")

	print("[TEST] 6. group_rivalry -> agent voice")
	var g1 := SocialGroup.new()
	g1.group_name = "The Breakroom Crew"
	g1.members = [a, b] as Array[String]
	var g2 := SocialGroup.new()
	g2.group_name = "Third Floor"
	g2.members = [AgentManager.agents[2].agent_name] as Array[String]
	var n6 := _received.size()
	EventBus.group_rivalry_detected.emit(g1, g2)
	await _check("group rivalry produces agent confessional", "rivalry", n6)

	await _cool()
	print("[TEST] 7. agent_died -> a survivor reacts")
	var n7 := _received.size()
	EventBus.agent_died.emit(AgentManager.agents[3].agent_name, "old age")
	await _check("death produces survivor confessional", "tragedy", n7)

	await _cool()
	print("[TEST] 8. day_changed -> host recap")
	DramaDirector.drama_level = 8.0
	var n8 := _received.size()
	EventBus.day_changed.emit(3)
	await _check("day change produces host recap", "host", n8)
	if not _received.is_empty() and _received[-1].is_host and _received[-1].speaker == "Narrator":
		_results.append("PASS  host recap flagged is_host with Narrator speaker")
	else:
		_results.append("FAIL  host recap not flagged correctly")


func _report() -> void:
	print("\n================ RESULTS ================")
	var failed := 0
	for r in _results:
		print("  " + r)
		if r.begins_with("FAIL"):
			failed += 1
	print("-----------------------------------------")
	print("  %d passed, %d failed (%d confessionals)" % [_results.size() - failed, failed, _received.size()])
	print("=========================================\n")
