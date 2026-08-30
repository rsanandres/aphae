extends Node
## Contextual hint system for first-time players. Hints appear once and can be dismissed.

const STATE_PATH := "user://tutorial_state.json"

signal hint_triggered(hint_id: String, text: String)

var _shown_hints: Dictionary = {}  # hint_id -> true
var _hints_disabled: bool = false
var _session_time: float = 0.0
var _first_conversation_seen: bool = false
var _game_started: bool = false

# Hint definitions: {id, text, trigger_type, trigger_value}
var _hints := [
	{"id": "welcome", "text": "Welcome to Aphae! Watch your AI agents live, work, and form relationships in this tiny office.", "delay": 1.0},
	{"id": "click_agent", "text": "Click an agent to follow them and see their thoughts.", "delay": 10.0},
	{"id": "right_click", "text": "Right-click anywhere for the menu (speed, settings, save).", "delay": 30.0},
	{"id": "god_mode", "text": "Press Tab to toggle God Mode and rearrange the office.", "delay": 60.0},
	# Playtest finding: the 120s slot taught need-decay plumbing while the
	# reward loop (Influence, episodes, the Catalog) had no hint at all.
	{"id": "influence", "text": "Your show earns Influence (the ¤ up top) as episodes wrap. Spend it in the Catalog [B].", "delay": 120.0},
	{"id": "agent_needs", "text": "Agents have needs (energy, hunger, social) that drive their decisions.", "delay": 200.0},
]


func _ready() -> void:
	_load_state()
	if _hints_disabled:
		return
	EventBus.conversation_started.connect(_on_first_conversation)
	EventBus.game_ready.connect(_on_game_ready)
	# Event-triggered hints: the marquee features explain themselves the first
	# time they appear on screen, instead of never. (Every timed hint above
	# predates the entire producer layer — a new player was taught click,
	# right-click, and Tab, and nothing the game is actually about.)
	EventBus.confessional_recorded.connect(_on_first_confessional)


func _on_game_ready() -> void:
	_game_started = true
	_session_time = 0.0


func _process(delta: float) -> void:
	if _hints_disabled or not _game_started:
		return
	_session_time += delta
	for hint in _hints:
		var hint_id: String = hint["id"]
		if _shown_hints.has(hint_id):
			continue
		var delay: float = hint.get("delay", 0.0)
		if _session_time >= delay:
			_show_hint(hint_id, hint["text"])
			break  # Only one hint at a time


func _on_first_conversation(_a: String, _b: String) -> void:
	if not _first_conversation_seen and not _shown_hints.has("narrative_log"):
		_first_conversation_seen = true
		_show_hint("narrative_log", "Press L (or the Log button) to see what agents are saying and doing.")


func _on_first_confessional(_confessional: RefCounted) -> void:
	if not _shown_hints.has("confessional"):
		_show_hint("confessional",
			"An agent just spoke to the camera. Press C for the Confessional Cam — and P to produce the show yourself: nudge, interview, plant a rumour.")


func _show_hint(hint_id: String, text: String) -> void:
	_shown_hints[hint_id] = true
	hint_triggered.emit(hint_id, text)
	_save_state()


func dismiss_all() -> void:
	_hints_disabled = true
	_save_state()


func reset() -> void:
	_shown_hints.clear()
	_hints_disabled = false
	_save_state()


func _load_state() -> void:
	var file := FileAccess.open(STATE_PATH, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	_hints_disabled = data.get("disabled", false)
	var shown: Array = data.get("shown", [])
	for id in shown:
		_shown_hints[str(id)] = true


func _save_state() -> void:
	var shown_list: Array = []
	for id in _shown_hints:
		shown_list.append(id)
	var data := {
		"disabled": _hints_disabled,
		"shown": shown_list,
	}
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
