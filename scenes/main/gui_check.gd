extends Node
## GUI layout check (dev tool, not shipped content).
##
## Boots the real game scene in a real window, drives it with real key events,
## and saves PNGs of each overlay at both supported window sizes. Everything in
## this project up to now was validated headless, which is structurally blind to
## layout — this is the check that can actually see a collision.
##
## Must NOT be run with --headless: there is no rendering, so the capture is blank.
##
## Run: godot --path . res://scenes/main/gui_check.tscn
## Output: user://gui_check/*.png

const OUT_DIR := "user://gui_check"
const EXPANDED := Vector2i(1280, 720)
const PET := Vector2i(480, 320)

var _main: Node = null
var _shots: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("[GUI] output dir: %s" % ProjectSettings.globalize_path(OUT_DIR))

	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	# main.gd shows a "Welcome Back" modal when a save auto-loads, which would
	# sit on top of every screenshot. Dismiss it the way a player would.
	_dismiss_modal(_main)
	await get_tree().process_frame

	_spawn(5)
	await get_tree().create_timer(1.5).timeout

	# Select someone so the inspector and producer panel have a subject.
	if not AgentManager.agents.is_empty():
		var a: Node2D = AgentManager.agents[0]
		GameManager.selected_agent = a
		EventBus.agent_selected.emit(a)
	await get_tree().process_frame

	await _sweep(EXPANDED, "expanded")
	await _sweep(PET, "pet")

	print("\n[GUI] captured %d screenshots:" % _shots.size())
	for s in _shots:
		print("  " + s)
	get_tree().quit()


func _dismiss_modal(node: Node) -> bool:
	## Depth-first search for the modal's Continue button and press it.
	if node is Button and (node as Button).text == "Continue":
		(node as Button).pressed.emit()
		print("[GUI] dismissed Welcome Back modal")
		return true
	for child in node.get_children():
		if _dismiss_modal(child):
			return true
	return false


func _spawn(n: int) -> void:
	for i in range(n):
		AgentManager.spawn_procedural_agent(Vector2(60 + i * 40, 90))
	print("[GUI] spawned %d agents" % AgentManager.agents.size())


func _sweep(size: Vector2i, tag: String) -> void:
	DisplayServer.window_set_size(size)
	await get_tree().create_timer(0.6).timeout

	# Baseline: HUD only. Catches icon-bar overflow, which is the specific risk
	# — the bar gained CAM, EP and DIR buttons and was widened twice unverified.
	await _shoot("%s_00_hud" % tag)

	# Each overlay on its own, opened through the real keybinding.
	await _panel(KEY_C, "%s_01_confessional" % tag)
	await _panel(KEY_E, "%s_02_recap" % tag)
	await _panel(KEY_P, "%s_03_producer" % tag)
	await _panel(KEY_R, "%s_04_relationships" % tag)

	# The lower-third cutaway, which sits directly above the icon bar — the
	# most likely collision in the whole UI.
	_fire_confessional()
	await get_tree().create_timer(0.8).timeout
	await _shoot("%s_05_toast" % tag)

	# Toast plus an open panel: worst case for overlap.
	await _press(KEY_P)
	_fire_confessional()
	await get_tree().create_timer(0.8).timeout
	await _shoot("%s_06_toast_plus_panel" % tag)
	await _press(KEY_P)

	# Mutual exclusion: opening R while P is up must close P (UIManager).
	await _press(KEY_P)
	await _press(KEY_R)
	await get_tree().create_timer(0.4).timeout
	await _shoot("%s_07_exclusion" % tag)
	await _press(KEY_R)

	# Speech bubbles: force two speakers and confirm screen-space bubbles.
	if AgentManager.agents.size() >= 2:
		AgentManager.agents[0].show_speech("Bubble check: a long line that has to wrap and then truncate with an ellipsis somewhere.", 4.0)
		AgentManager.agents[1].show_speech("Short.", 4.0)
	await get_tree().create_timer(0.4).timeout
	await _shoot("%s_08_bubbles" % tag)
	await get_tree().create_timer(4.0).timeout


func _panel(key: Key, name: String) -> void:
	await _press(key)
	await get_tree().create_timer(0.4).timeout
	await _shoot(name)
	await _press(key)  # close again
	await get_tree().create_timer(0.2).timeout


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


func _fire_confessional() -> void:
	if AgentManager.agents.is_empty():
		return
	var who: String = AgentManager.agents[0].agent_name
	# Importance 9 clears the director's threshold of 6.
	EventBus.narrative_event.emit(
		"%s was publicly humiliated in the quarterly review meeting." % who, [who], 9.0
	)


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	if err == OK:
		_shots.append(ProjectSettings.globalize_path(path))
	else:
		print("[GUI] FAILED to save %s (err %d)" % [path, err])
