extends Node
## Marketing screenshot capture (dev tool, not shipped content).
##
## Differs from gui_check.tscn, which proves layout correctness with whatever is
## on screen. This one waits for the simulation to actually become interesting —
## agents spread out, the log fills with real activity, a confessional lands —
## and then captures. Output is meant for the README.
##
## Must NOT be run headless (no rendering → blank captures).
## Run: godot --path . --audio-driver Dummy res://scenes/main/screenshots.tscn

const OUT_DIR := "user://screenshots"
const SIZE := Vector2i(960, 640)
const SETTLE_SEC := 28.0   # let agents disperse and the log fill with real events

var _main: Node = null
var _last_confessional: Confessional = null
var _shots: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	EventBus.confessional_recorded.connect(func(c: RefCounted) -> void:
		_last_confessional = c as Confessional
	)

	DisplayServer.window_set_size(SIZE)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_dismiss_modal(_main)

	for i in range(6):
		AgentManager.spawn_procedural_agent(Vector2(50 + i * 38, 70 + (i % 3) * 45))
	TimeManager.set_speed(3)

	# Warm the model. A cold gemma3 load plus generation can exceed the 30s
	# request timeout, and the first quip then silently falls back to a canned
	# heuristic line — which is exactly what we do NOT want in a screenshot.
	_warm_llm()

	print("[SHOT] settling for %ds so the office looks lived-in..." % int(SETTLE_SEC))
	await get_tree().create_timer(SETTLE_SEC).timeout

	# 1. The office itself, mid-life. No selection, so the inspector stays out
	#    of the frame.
	await _shoot("01_office")

	# 2. Hero shot: the confessional cutaway, also uncluttered.
	await _await_confessional()
	await _shoot("02_confessional")

	# The cutaway holds ~5s then fades over 0.6s. Wait it out so it does not
	# sit on top of the panel shots below.
	await get_tree().create_timer(6.5).timeout

	# Selection only now — the panels below need a subject.
	if not AgentManager.agents.is_empty():
		var a: Node2D = AgentManager.agents[0]
		GameManager.selected_agent = a
		EventBus.agent_selected.emit(a)
		await get_tree().create_timer(0.5).timeout

	# 3. Producer panel on the selected agent.
	await _press(KEY_P)
	await get_tree().create_timer(0.5).timeout
	await _shoot("03_producer")
	await _press(KEY_P)

	# 4. Relationship web, once bonds have had time to form.
	await _press(KEY_R)
	await get_tree().create_timer(0.6).timeout
	await _shoot("04_relationships")
	await _press(KEY_R)

	# 5. Confessional history.
	await _press(KEY_C)
	await get_tree().create_timer(0.5).timeout
	await _shoot("05_confessional_feed")
	await _press(KEY_C)

	print("\n[SHOT] wrote %d screenshots to %s" % [
		_shots.size(), ProjectSettings.globalize_path(OUT_DIR)
	])
	for s in _shots:
		print("  " + s)
	get_tree().quit()


func _warm_llm() -> void:
	if not LLMManager.is_available:
		print("[SHOT] WARNING: no LLM backend — quips will be canned heuristics")
		return
	LLMManager.request_chat(
		[{"role": "user", "content": "Reply with the single word: ready"}],
		{"type": "object", "properties": {"line": {"type": "string"}}, "required": ["line"]},
		func(ok: bool, _d: Dictionary, _e: String) -> void:
			print("[SHOT] model warm-up %s" % ("ok" if ok else "failed")),
		LLMManager.Priority.HIGH
	)


func _await_confessional() -> void:
	_last_confessional = null
	var who: String = AgentManager.agents[0].agent_name
	EventBus.narrative_event.emit(
		"%s was publicly humiliated in the quarterly review meeting." % who, [who], 9.0
	)
	# The toast holds for ~5s, so capture while it is still up.
	var waited := 0.0
	while _last_confessional == null and waited < 40.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	if _last_confessional:
		print("[SHOT] confessional: <%s> \"%s\"" % [_last_confessional.speaker, _last_confessional.line])
	else:
		print("[SHOT] WARNING: no confessional arrived; shot 02 will lack the toast")
	await get_tree().create_timer(0.6).timeout


func _dismiss_modal(node: Node) -> bool:
	if node is Button and (node as Button).text == "Continue":
		(node as Button).pressed.emit()
		return true
	for child in node.get_children():
		if _dismiss_modal(child):
			return true
	return false


func _press(key: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = key
	down.pressed = true
	get_viewport().push_input(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = key
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().process_frame


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	if img.save_png(path) == OK:
		_shots.append(ProjectSettings.globalize_path(path))
	else:
		print("[SHOT] FAILED to save %s" % path)
