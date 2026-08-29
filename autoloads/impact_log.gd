extends Node
## Autoload: the "Because of you" log (player-agency backlog #10).
##
## Control you cannot see the effect of does not feel like control. Every
## producer intervention opens a short attribution window; anything notable
## that happens to the people you touched inside that window is recorded as
## a ripple under your action. It is honest about being a heuristic — the
## sim does not track true causality, and neither does a TV producer.
##
## Writes nothing back into the simulation: no memories, no signals, no
## narrative events. It can never collide with a harness, but it carries the
## standard seam anyway, per the repo rule.

const MAX_ENTRIES := 30
const MAX_RIPPLES := 3
const WINDOW_MINUTES := 180.0     # game-minutes an intervention stays attributable
const RIPPLE_MIN_IMPORTANCE := 4.0

var auto_enabled: bool = true

# Each entry: {day, time, text, subjects: Array[String], ripples: Array[String],
#             opened_minutes: float}
var _entries: Array[Dictionary] = []


func _ready() -> void:
	EventBus.nudge_answered.connect(_on_nudge_answered)
	EventBus.rumor_planted.connect(_on_rumor_planted)
	EventBus.house_meeting_held.connect(_on_house_meeting)
	EventBus.catalog_purchased.connect(_on_catalog_purchased)
	EventBus.dilemma_resolved.connect(_on_dilemma_resolved)
	EventBus.star_chosen.connect(_on_star_chosen)
	# Ripple sources: things that happen to the people you touched.
	EventBus.narrative_event.connect(_on_narrative_event)
	EventBus.romance_started.connect(func(a: String, b: String) -> void:
		_ripple([a, b], "%s and %s became an item" % [a, b]))
	EventBus.goal_achieved.connect(func(agent: String, text: String, _k: int) -> void:
		_ripple([agent], "%s achieved a goal: %s" % [agent, text]))
	EventBus.secret_exposed.connect(func(holder: String, _text: String) -> void:
		_ripple([holder], "%s's secret went public" % holder))
	EventBus.conversation_ended.connect(func(a: String, b: String) -> void:
		_ripple([a, b], "%s and %s talked" % [a, b], "talk"))


func get_entries() -> Array[Dictionary]:
	## Newest first, for the log view.
	var out: Array[Dictionary] = []
	for i in range(_entries.size() - 1, -1, -1):
		out.append(_entries[i])
	return out


# --- Interventions -----------------------------------------------------------

func _open(text: String, subjects: Array) -> void:
	if not auto_enabled:
		return
	var names: Array[String] = []
	for s in subjects:
		if str(s) != "":
			names.append(str(s))
	_entries.append({
		"day": TimeManager.day,
		"time": TimeManager.time_string,
		"text": text,
		"subjects": names,
		"ripples": [],
		"opened_minutes": TimeManager.game_minutes,
	})
	if _entries.size() > MAX_ENTRIES:
		_entries.remove_at(0)


func _on_nudge_answered(agent_name: String, request: String, complied: bool, reason: String) -> void:
	if complied:
		_open("You nudged %s to %s — they went along with it" % [agent_name, request], [agent_name])
	elif reason != "":
		_open("You nudged %s to %s — they shrugged it off: %s" % [agent_name, request, reason], [agent_name])
	else:
		_open("You nudged %s to %s — they refused" % [agent_name, request], [agent_name])


func _on_rumor_planted(agent_name: String, text: String) -> void:
	_open("You planted a rumour with %s: \"%s\"" % [agent_name, text], [agent_name])


func _on_house_meeting(accused: String, was_mole: bool, _votes: Dictionary) -> void:
	if accused == "":
		_open("You called a house meeting — nobody could point a finger", [])
		return
	var verdict := "and the house was RIGHT" if was_mole else "and the house was wrong"
	# Subjects: the accused only. Listing every voter made the whole office a
	# "subject", so anything anyone did for three hours "rippled" to it.
	_open("You called a house meeting — the house accused %s, %s" % [accused, verdict],
		[accused])


func _on_catalog_purchased(item_id: String) -> void:
	_open("You bought %s from the catalog" % item_id.replace("_", " "), [])


func _on_dilemma_resolved(event_id: String, choice_idx: int, by_timeout: bool) -> void:
	if by_timeout:
		_open("You let the clock decide the %s dilemma" % event_id.replace("_", " "), [])
	else:
		_open("You made the call on the %s dilemma (option %d)" % [event_id.replace("_", " "), choice_idx + 1], [])


func _on_star_chosen(agent_name: String) -> void:
	if agent_name == "":
		_open("You took the spotlight away", [])
	else:
		_open("You made %s the star of the episode" % agent_name, [agent_name])


# --- Ripples -----------------------------------------------------------------

func _on_narrative_event(text: String, agents: Array, importance: float) -> void:
	if importance < RIPPLE_MIN_IMPORTANCE:
		return
	var names: Array[String] = []
	for a in agents:
		names.append(str(a))
	_ripple(names, text)


func _ripple(who: Array, text: String, kind: String = "event") -> void:
	## Attach to the newest open intervention that touched any of these people.
	if not auto_enabled or who.is_empty():
		return
	var now: float = TimeManager.game_minutes
	for i in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[i]
		# Same-minute events are the intervention's own announcement echoing
		# back ("You planted a rumour…" / "↳ X heard something…"). Skip them.
		if now - float(entry["opened_minutes"]) < 1.0:
			continue
		if now - float(entry["opened_minutes"]) > WINDOW_MINUTES or now < float(entry["opened_minutes"]):
			continue
		if (entry["ripples"] as Array).size() >= MAX_RIPPLES:
			continue
		# Mundane chatter gets at most ONE slot; without this, "X and Y
		# talked" filled the cap before anything interesting could attach.
		if kind == "talk":
			var has_talk := false
			for r in (entry["ripples"] as Array):
				if str(r).ends_with("talked"):
					has_talk = true
					break
			if has_talk:
				continue
		var touches := false
		for name in who:
			if name in (entry["subjects"] as Array):
				touches = true
				break
		if not touches:
			continue
		var line := "↳ " + text
		if line not in (entry["ripples"] as Array):
			(entry["ripples"] as Array).append(line)
		return  # one intervention per ripple: the newest plausible cause


# --- Persistence -------------------------------------------------------------

func get_save_state() -> Dictionary:
	return {"entries": _entries.duplicate(true)}


func load_save_state(data: Dictionary) -> void:
	_entries.clear()
	for entry in data.get("entries", []):
		if entry is Dictionary and entry.has("text"):
			_entries.append(entry.duplicate(true))
