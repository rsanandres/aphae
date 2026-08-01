extends Node2D
## Functional test harness for the Confessional Cam feature (dev tool, not shipped).
## Fires every EventBus path the director listens to and asserts it responds
## correctly, including the negative cases (cooldown suppression, low-importance
## filtering). Exercises the heuristic path when no LLM backend is present.
## Also covers the episode recap and confessional persistence across save/load,
## including a pre-v4 save that predates the confessionals key.
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
	# AgentManager.spawn_procedural_agent needs a "world" group node with an
	# "Agents" child. office.gd is attached so the world answers get_all_objects()
	# — SaveManager calls it while serializing, so the save/load tests need it.
	var world := Node2D.new()
	world.add_to_group("world")
	world.set_script(load("res://scenes/world/office.gd"))

	# Build the hierarchy BEFORE entering the tree: office.gd resolves $Objects
	# and $Agents via @onready, which fires on tree entry.
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
	# but an LLM-backed quip arrives later via callback, so poll instead of
	# assuming a fixed delay. A fixed wait tuned for the synchronous heuristic
	# path reports false failures the moment a real backend is configured.
	var budget: float = 45.0 if LLMManager.is_available else 2.0
	var waited: float = 0.0
	while waited < budget and _received.size() <= before:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var got := _received.size() > before
	var kind_ok := got and _received[-1].kind == expect_kind
	var speaker_ok := got and _received[-1].speaker != "" and _received[-1].line != ""
	if got and kind_ok and speaker_ok:
		_results.append("PASS  %s" % label)
	else:
		_results.append("FAIL  %s (fired=%s kind_ok=%s speaker_ok=%s)" % [label, got, kind_ok, speaker_ok])


func _cool() -> void:
	# Director enforces an 8s cooldown between quips, and drops anything raised
	# while a request is still in flight — so wait out both, or the next emit is
	# silently swallowed and reads as a failure.
	await get_tree().create_timer(9.0).timeout
	var waited: float = 0.0
	while ConfessionalDirector._pending and waited < 45.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25


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

	print("[TEST] 9. episode recap assembles from storylines + confessionals")
	var recap := EpisodeRecap.build()
	var recap_ok: bool = recap.begins_with("# Ayle — Episode Recap") \
		and "## From the Confessional Booth" in recap \
		and "## The Cast" in recap \
		and not ("{" in recap and "}" in recap)
	_results.append(("PASS  " if recap_ok else "FAIL  ") + "episode recap renders every section")

	print("[TEST] 10. recap exports to a file")
	var path := EpisodeRecap.export_to_file()
	var export_ok := path != "" and FileAccess.file_exists(path)
	var content_ok := false
	if export_ok:
		var f := FileAccess.open(path, FileAccess.READ)
		content_ok = f.get_as_text().length() == recap.length()
		f.close()
		print("   -> %s" % ProjectSettings.globalize_path(path))
	_results.append(("PASS  " if export_ok and content_ok else "FAIL  ") + "recap exports to user://recaps/")

	print("[TEST] 11. confessionals survive save/load (v4)")
	var before_save := _fingerprint()
	var saved := SaveManager.save_game(0)
	ConfessionalDirector.confessionals.clear()
	var loaded := SaveManager.load_game(0)
	await get_tree().process_frame
	var round_trip: bool = saved and loaded and not before_save.is_empty() \
		and _fingerprint() == before_save
	_results.append(("PASS  " if round_trip else "FAIL  ") + "confessionals survive save/load")

	print("[TEST] 12. pre-v4 save without a confessionals key still loads")
	var lf := FileAccess.open("user://saves/slot_4.json", FileAccess.WRITE)
	lf.store_string(JSON.stringify({
		"version": 3, "game_time": 500.0, "agents": [], "objects": [],
	}, "\t"))
	lf.close()
	var legacy_ok := SaveManager.load_game(4)
	await get_tree().process_frame
	_results.append(("PASS  " if legacy_ok and ConfessionalDirector.confessionals.is_empty() else "FAIL  ")
		+ "pre-v4 save loads with empty confessionals")


func _fingerprint() -> Array[String]:
	## Stable identity of the current confessional list, for round-trip comparison.
	var out: Array[String] = []
	for c in ConfessionalDirector.confessionals:
		out.append("%s|%s|%d|%s" % [c.speaker, c.line, c.day, c.kind])
	return out


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
