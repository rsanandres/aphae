extends Node
## Panel sweep (dev tool, not shipped content).
##
## Opens every window in the game, screenshots it, and asserts it closes
## again — by Esc, by its X button, and by its icon-bar button. Layout bugs
## are only visible in a window (that is what gui_check is for); THIS check
## is about behavior: can the player always get rid of what they opened?
##
## Must NOT be run headless (no rendering, blank captures).
## Run: godot --path . --audio-driver Dummy res://scenes/main/panel_check.tscn
## Output: user://panel_check/*.png

const OUT_DIR := "user://panel_check"

# name -> [key, panel_registry_name, icon_bar_label]
const PANELS: Array = [
	["narrative_log", KEY_L, "log", "Log"],
	["story_feed", KEY_NONE, "stories", "Talk"],
	["confessional_feed", KEY_C, "confessionals", "Cam"],
	["relationships", KEY_R, "relationships", "Rel"],
	["producer", KEY_P, "producer", "Prod"],
	["recap", KEY_E, "recap", "Recap"],
	["catalog", KEY_B, "catalog", "Shop"],
]

var _main: Node = null
var _hud: Node = null
var _ui: Node = null
var _results: Array[String] = []
var _shots: Array[String] = []


func _ready() -> void:
	ProducerEconomy.meta_persistence_enabled = false
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_dismiss_modal(_main)
	await get_tree().create_timer(1.0).timeout

	_hud = _find_hud(_main)
	if _hud == null:
		print("[PANEL] FATAL: HUD not found")
		get_tree().quit()
		return
	_ui = _hud.get("_ui")

	# Give the panels a subject and some funds so they render populated.
	AgentManager.spawn_procedural_agent(Vector2(120, 90))
	AgentManager.spawn_procedural_agent(Vector2(170, 90))
	ProducerEconomy.influence = 500
	ProducerEconomy.lifetime_episodes = 12
	ProducerEconomy.best_episode_score = 90
	await get_tree().create_timer(1.0).timeout
	if not AgentManager.agents.is_empty():
		GameManager.selected_agent = AgentManager.agents[0]
		EventBus.agent_selected.emit(AgentManager.agents[0])
	await get_tree().process_frame

	await _sweep_registered_panels()
	await _sweep_icon_bar_buttons()
	await _sweep_special_windows()

	_report()
	get_tree().quit()


# --- Registered panels: key open, screenshot, Esc close, X close ------------

func _sweep_registered_panels() -> void:
	for entry in PANELS:
		var label: String = entry[0]
		var key: int = entry[1]
		var registry: String = entry[2]
		var panel: Control = _panel_for(registry)
		if panel == null:
			_check("%s: registered in UIManager" % label, false)
			continue

		# Open via UIManager (the path every key and button funnels into)
		_ui.open(registry)
		await get_tree().create_timer(0.35).timeout
		_check("%s: opens" % label, panel.visible)
		await _shoot("%s" % label)

		# Esc must close overlays. Docks are deliberately exempt (the log is
		# meant to persist), so assert the documented behavior either way.
		var is_dock: bool = label == "narrative_log"
		await _press(KEY_ESCAPE)
		await get_tree().create_timer(0.25).timeout
		if is_dock:
			_check("%s: dock survives Esc (by design)" % label, panel.visible)
			panel.visible = false
		else:
			_check("%s: closes on Esc" % label, not panel.visible)

		# X button must close it
		_ui.open(registry)
		await get_tree().create_timer(0.25).timeout
		var x_btn := _find_button(panel, "X")
		if x_btn:
			x_btn.pressed.emit()
			await get_tree().create_timer(0.25).timeout
			_check("%s: closes on X button" % label, not panel.visible)
		else:
			_check("%s: has an X button" % label, false)

		# Key toggle (where one exists) must close it too
		if key != KEY_NONE:
			_ui.open(registry)
			await get_tree().create_timer(0.25).timeout
			await _press(key)
			await get_tree().create_timer(0.25).timeout
			_check("%s: closes on its key" % label, not panel.visible)

		_close_everything()
		await get_tree().process_frame


# --- Icon bar: the mouse path a real player uses ---------------------------

func _sweep_icon_bar_buttons() -> void:
	for entry in PANELS:
		var label: String = entry[0]
		var registry: String = entry[2]
		var btn_text: String = entry[3]
		var panel: Control = _panel_for(registry)
		var btn := _find_button(_hud, btn_text)
		if panel == null or btn == null:
			_check("%s: icon-bar button '%s' exists" % [label, btn_text], false)
			continue
		btn.pressed.emit()
		await get_tree().create_timer(0.25).timeout
		var opened: bool = panel.visible
		btn.pressed.emit()
		await get_tree().create_timer(0.25).timeout
		var closed: bool = not panel.visible
		_check("%s: icon-bar button opens AND closes" % label, opened and closed)
		_check("%s: button lamp matches panel state" % label, btn.button_pressed == panel.visible)
		_close_everything()
		await get_tree().process_frame


# --- Windows that are not simple toggles ----------------------------------

func _sweep_special_windows() -> void:
	# Episode wrap card (auto-opens on the signal)
	var card := _panel_for("episode")
	if card:
		EventBus.episode_ended.emit(1, 2, 63, 83)
		await get_tree().create_timer(0.5).timeout
		_check("episode card: opens on episode_ended", card.visible)
		await _shoot("episode_card")
		await _press(KEY_ESCAPE)
		await get_tree().create_timer(0.25).timeout
		_check("episode card: closes on Esc", not card.visible)
	else:
		_check("episode card: registered", false)

	# While You Were Away digest
	var away := _panel_for("away")
	if away:
		EventBus.away_digest_ready.emit([
			{"kind": "event", "day": 2, "time": "11:20", "text": "Something big happened."},
			{"kind": "confessional", "day": 2, "time": "11:24", "text": "Someone: \"No comment.\""},
		])
		await get_tree().create_timer(0.5).timeout
		_check("away digest: opens on signal", away.visible)
		await _shoot("away_digest")
		await _press(KEY_ESCAPE)
		await get_tree().create_timer(0.25).timeout
		_check("away digest: closes on Esc", not away.visible)
	else:
		_check("away digest: registered", false)

	# Producer dilemma (pauses; must release the pause on resolve)
	var dilemma := _panel_for("dilemma")
	if dilemma:
		var was_paused: bool = TimeManager.is_paused
		if was_paused:
			TimeManager.toggle_pause()
		var holder: Node2D = AgentManager.agents[0]
		holder.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
			"%s is hiding something big." % holder.agent_name, 8.0)
		holder.memory.memories[-1].narrative_thread = "secret_probe"
		EventManager.auto_resolve_dilemmas = false
		EventManager.trigger_event("leak_dilemma", [holder])
		await get_tree().create_timer(0.5).timeout
		_check("dilemma: opens and pauses", dilemma.visible and TimeManager.is_paused)
		await _shoot("dilemma")
		EventManager.resolve_dilemma(1)
		await get_tree().create_timer(0.35).timeout
		_check("dilemma: closes on resolve", not dilemma.visible)
		_check("dilemma: releases the pause it took", not TimeManager.is_paused)
	else:
		_check("dilemma: registered", false)

	# Lazily-built modals reached through the toolbar
	_hud.call("_toggle_settings")
	await get_tree().create_timer(0.4).timeout
	var settings: Control = _hud.get("_settings_panel")
	_check("settings: opens", settings != null and settings.visible)
	await _shoot("settings")
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.25).timeout
	_check("settings: closes on Esc", settings != null and not settings.visible)

	_hud.call("_toggle_achievements")
	await get_tree().create_timer(0.4).timeout
	var achievements: Control = _hud.get("_achievement_panel")
	_check("achievements: opens", achievements != null and achievements.visible)
	await _shoot("achievements")
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.25).timeout
	_check("achievements: closes on Esc", achievements != null and not achievements.visible)

	_hud.call("_show_save_picker", "save")
	await get_tree().create_timer(0.4).timeout
	var picker: Control = _hud.get("_save_picker")
	_check("save picker: opens", picker != null and picker.visible)
	await _shoot("save_picker")
	await _press(KEY_ESCAPE)
	await get_tree().create_timer(0.25).timeout
	_check("save picker: closes on Esc", picker != null and not picker.visible)

	# God mode toolbar
	await _press(KEY_TAB)
	await get_tree().create_timer(0.4).timeout
	await _shoot("god_mode")
	await _press(KEY_TAB)
	await get_tree().create_timer(0.25).timeout

	# Exclusivity: opening one center overlay must banish the previous one
	_ui.open("producer")
	await get_tree().create_timer(0.25).timeout
	_ui.open("catalog")
	await get_tree().create_timer(0.35).timeout
	var producer_panel := _panel_for("producer")
	var catalog_panel := _panel_for("catalog")
	_check("exclusivity: opening the catalog closes the producer panel",
		catalog_panel.visible and not producer_panel.visible)
	await _shoot("exclusivity")
	_close_everything()


# --- Helpers ---------------------------------------------------------------

func _panel_for(registry_name: String) -> Control:
	var panels: Dictionary = _ui.get("_panels")
	var entry: Dictionary = panels.get(registry_name, {})
	return entry.get("control", null)


func _close_everything() -> void:
	for i in range(6):
		if not _ui.call("close_top"):
			break


func _find_hud(node: Node) -> Node:
	if node.get_script() != null and "hud.gd" in str(node.get_script().resource_path):
		return node
	for c in node.get_children():
		var r := _find_hud(c)
		if r:
			return r
	return null


func _find_button(root_node: Node, text: String) -> Button:
	var stack: Array = [root_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == text:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


func _press(key: int) -> void:
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


func _dismiss_modal(node: Node) -> bool:
	if node is Button and (node as Button).text == "Continue":
		(node as Button).pressed.emit()
		return true
	for child in node.get_children():
		if _dismiss_modal(child):
			return true
	return false


func _shoot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	if img.save_png(path) == OK:
		_shots.append(ProjectSettings.globalize_path(path))


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
	print("\n[PANEL] %d screenshots -> %s" % [_shots.size(), ProjectSettings.globalize_path(OUT_DIR)])
	print("=========================================")
	print("  %d passed, %d failed" % [passed, failed])
	print("=========================================")
