extends Node2D
## Functional test harness for the Premiere package (dev tool).
##
## Covers: the seeded secret (guaranteed one per fresh cast, organic holder
## kept when the spawn roll delivered), the early booth admission at 10:00,
## the before-noon event guarantee (fires only when nothing happened
## organically), the day-3 mole case, and the director retiring itself once
## every beat has had its chance. The 1-day pilot itself is covered in
## economy_test; this harness owns the authored curve.
##
## Run: godot --headless --path . --audio-driver Dummy res://scenes/main/premiere_test.tscn

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
	SynergyManager.auto_enabled = false
	SecretManager.auto_assign_enabled = false
	SecretManager.auto_admit_enabled = false
	_build_world()
	for i in range(5):
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
	TimeManager.game_minutes = 480.0  # day 1, 8:00

	# --- Seeding: a cast with no organic secret gets exactly one -------------
	var director := PremiereDirector.new()
	add_child(director)
	director.start()
	var seeded: int = 0
	for agent in AgentManager.agents:
		if SecretManager.has_hidden_secret(agent.agent_name):
			seeded += 1
	_check("a bare cast gets exactly one seeded secret", seeded == 1)
	_check("the director holds the seeded state", director._seeded_secret != null)

	# --- Seeding keeps an organic holder instead of adding a second ----------
	var director2 := PremiereDirector.new()
	add_child(director2)
	director2.start()
	var after_second: int = 0
	for agent in AgentManager.agents:
		if SecretManager.has_hidden_secret(agent.agent_name):
			after_second += 1
	_check("an existing secret is kept, not duplicated", after_second == 1)
	_check("the second director adopted the existing holder",
		director2._seeded_secret == director._seeded_secret)
	director2.queue_free()

	# --- Early booth admission at 10:00 --------------------------------------
	var admissions: Array = []
	EventBus.secret_admitted.connect(func(agent_name: String, _text: String) -> void:
		admissions.append(agent_name))
	TimeManager.game_minutes = 599.0
	EventBus.time_tick.emit(599.0)
	_check("no admission before 10:00", admissions.is_empty())
	TimeManager.game_minutes = 600.0
	EventBus.time_tick.emit(600.0)
	_check("the seeded secret reaches the booth at 10:00",
		admissions.size() == 1 and admissions[0] == director._seeded_secret.agent_name)
	_check("the admission is marked on camera", director._seeded_secret.admitted_on_camera)
	var latest: Array = ConfessionalDirector.get_recent(1)
	_check("the admission landed in the confessional feed",
		not latest.is_empty() and latest[0].kind == "secret")

	# --- The before-noon event guarantee -------------------------------------
	var fired: Array = []
	EventBus.event_triggered.connect(func(event_id: String, _agents: Array) -> void:
		fired.append(event_id))
	TimeManager.game_minutes = 660.0
	EventBus.time_tick.emit(660.0)
	_check("a quiet morning gets a forced premiere event",
		fired.size() == 1 and fired[0] in PremiereDirector.PREMIERE_EVENTS)

	# A morning that already produced drama is left alone: rebuild the guard
	# state on a fresh director and mark an event as seen before the deadline.
	var director3 := PremiereDirector.new()
	add_child(director3)
	director3._saw_event = true
	var fired_before: int = fired.size()
	EventBus.time_tick.emit(660.0)
	_check("an organic event suppresses the forced one", fired.size() == fired_before)
	director3.queue_free()

	# --- The mole case opens on day 3 ----------------------------------------
	_check("no case before the guarantee", not WhodunitDirector.has_open_case())
	TimeManager.game_minutes = 2.0 * 1440.0 + 480.0  # day 3
	EventBus.day_changed.emit(TimeManager.day)
	_check("day 3 opens the mole case", WhodunitDirector.has_open_case())

	# --- The director retires after day 4 ------------------------------------
	TimeManager.game_minutes = 4.0 * 1440.0 + 480.0  # day 5
	EventBus.day_changed.emit(TimeManager.day)
	_check("the director frees itself once the premiere is over",
		director.is_queued_for_deletion())


func _check(test_name: String, passed: bool) -> void:
	_results.append(("PASS" if passed else "FAIL") + ": " + test_name)


func _report() -> void:
	var passed := 0
	var failed := 0
	print("\n===== PREMIERE TEST RESULTS =====")
	for r in _results:
		print(r)
		if r.begins_with("PASS"):
			passed += 1
		else:
			failed += 1
	if passed + failed == 0:
		print("NO ASSERTIONS RAN — treat this as a FAILURE")
	print("  %d passed, %d failed" % [passed, failed])
	print("=================================\n")
