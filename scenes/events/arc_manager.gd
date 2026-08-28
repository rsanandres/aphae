extends Node
## Autoload: multi-day personal storylines ("arcs") for single agents.
## An arc is a small state machine defined in resources/events/arcs.json;
## each stage waits some days, then applies a ConsequenceEngine payload and
## follows a branch. EventManager decides what happens *today*; ArcManager
## carries a story across days — and can compose events via trigger_event.
##
## One active arc per agent; at most one new arc starts per day, gated by
## the DramaDirector's pacing like everything else.

const START_PROBABILITY := 0.3  # daily chance that some eligible agent starts an arc

## Test seam, mirroring EventManager.auto_resolve_dilemmas. A harness that
## forces one arc and then asserts it finished must switch this off: the daily
## spontaneous roll can hand the SAME agent a fresh arc the moment the forced
## one ends, which reads as "the arc never completed". Cost a flaky assertion.
var auto_start_enabled: bool = true

var _arc_defs: Array[Dictionary] = []
var _active: Array[Dictionary] = []  # {arc_id, agent, stage_id, entered_day, wait_days}


func _ready() -> void:
	_load_arcs()
	EventBus.day_changed.connect(_on_day_changed)


func get_active_arcs() -> Array[Dictionary]:
	return _active


func has_arc(agent_name: String) -> bool:
	for arc in _active:
		if arc["agent"] == agent_name:
			return true
	return false


func start_arc(arc_id: String, agent: Node2D) -> bool:
	## Force-start (harnesses, dilemmas). Bypasses eligibility rolls.
	var def := _find_def(arc_id)
	if def.is_empty() or not is_instance_valid(agent) or has_arc(agent.agent_name):
		return false
	_begin(def, agent)
	return true


func _on_day_changed(day: int) -> void:
	_tick_active(day)
	_maybe_start(day)


func _tick_active(day: int) -> void:
	var finished: Array[int] = []
	for i in range(_active.size()):
		var arc: Dictionary = _active[i]
		var agent := AgentManager.get_agent_by_name(arc["agent"])
		if agent == null or not is_instance_valid(agent) or agent.is_dead:
			finished.append(i)
			continue
		if day - int(arc["entered_day"]) < int(arc["wait_days"]):
			continue
		var def := _find_def(arc["arc_id"])
		var stage := _find_stage(def, arc["stage_id"])
		if stage.is_empty():
			finished.append(i)
			continue
		# Stage-level probability: not ready to fire yet — try again tomorrow.
		if stage.has("probability") and randf() > float(stage["probability"]):
			arc["entered_day"] = day
			arc["wait_days"] = 1
			continue
		var next_id := _fire_stage(def, stage, agent)
		if next_id == "" or next_id == "end":
			finished.append(i)
		else:
			var next_stage := _find_stage(def, next_id)
			arc["stage_id"] = next_id
			arc["entered_day"] = day
			arc["wait_days"] = _roll_wait(next_stage)
	finished.reverse()
	for idx in finished:
		_active.remove_at(idx)


func _fire_stage(def: Dictionary, stage: Dictionary, agent: Node2D) -> String:
	var second: Node2D = null
	if stage.has("second_actor"):
		second = ConsequenceEngine._select_second(str(stage["second_actor"]), agent)
	if stage.has("payload"):
		_apply_payload(stage["payload"], agent, second)
	# Choose a branch: conditioned branches are eligible only when their
	# prerequisites hold for the agent; pick weighted among eligible.
	var branches: Array = stage.get("branches", [])
	if branches.is_empty():
		return str(stage.get("next", "end"))
	var eligible: Array = []
	for branch in branches:
		if ConsequenceEngine.prerequisites_met_target(branch.get("conditions", {}), agent):
			eligible.append(branch)
	if eligible.is_empty():
		eligible = branches
	var chosen: Dictionary = ConsequenceEngine._pick_outcome(eligible)
	if chosen.has("payload"):
		_apply_payload(chosen["payload"], agent, second)
	return str(chosen.get("next", "end"))


func _apply_payload(payload: Dictionary, agent: Node2D, second: Node2D) -> void:
	# Arcs may compose whole events; everything else is the shared vocabulary.
	if payload.has("trigger_event"):
		EventManager.trigger_event(str(payload["trigger_event"]), [agent])
	ConsequenceEngine.apply(payload, agent, second, {"affected": [agent]})


func _maybe_start(day: int) -> void:
	if not auto_start_enabled:
		return
	if _arc_defs.is_empty() or randf() > START_PROBABILITY * DramaDirector.get_probability_modifier():
		return
	var candidates: Array = []
	for agent in AgentManager.agents:
		if is_instance_valid(agent) and not agent.is_dead and not has_arc(agent.agent_name):
			candidates.append(agent)
	if candidates.is_empty():
		return
	candidates.shuffle()
	for agent in candidates:
		var eligible_defs: Array = []
		for def in _arc_defs:
			if ConsequenceEngine.prerequisites_met_target(def.get("target_conditions", {}), agent):
				eligible_defs.append(def)
		if eligible_defs.is_empty():
			continue
		var def: Dictionary = eligible_defs[randi() % eligible_defs.size()]
		_begin(def, agent)
		return  # one new arc per day, office-wide


func _begin(def: Dictionary, agent: Node2D) -> void:
	var working := def
	# Goal-template arcs weave one of the agent's own goals into the text.
	if def.get("goal_template", false):
		var goals: Array = agent.personality.goals if agent.personality else []
		if goals.is_empty():
			return
		var goal := str(goals[randi() % goals.size()])
		working = JSON.parse_string(JSON.stringify(def).replace("{goal}", goal))
	var stages: Array = working.get("stages", [])
	if stages.is_empty():
		return
	var first: Dictionary = stages[0]
	_active.append({
		"arc_id": str(working["id"]),
		"agent": agent.agent_name,
		"stage_id": str(first["id"]),
		"entered_day": TimeManager.day,
		"wait_days": _roll_wait(first),
		"resolved_def": working if def.get("goal_template", false) else {},
	})


func _roll_wait(stage: Dictionary) -> int:
	var wait: Array = stage.get("wait_days", [0, 0])
	if wait.size() < 2:
		return int(wait[0]) if wait.size() == 1 else 0
	return randi_range(int(wait[0]), int(wait[1]))


func _find_def(arc_id: String) -> Dictionary:
	# An in-flight goal arc carries its own resolved copy (goal substituted).
	for arc in _active:
		if arc["arc_id"] == arc_id and not (arc.get("resolved_def", {}) as Dictionary).is_empty():
			return arc["resolved_def"]
	for def in _arc_defs:
		if str(def.get("id", "")) == arc_id:
			return def
	return {}


func _find_stage(def: Dictionary, stage_id: String) -> Dictionary:
	for stage in def.get("stages", []):
		if str(stage.get("id", "")) == stage_id:
			return stage
	return {}


func _load_arcs() -> void:
	var file := FileAccess.open("res://resources/events/arcs.json", FileAccess.READ)
	if not file:
		push_warning("ArcManager: could not load arcs.json")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for entry in parsed:
			if entry is Dictionary:
				_arc_defs.append(entry)


# --- Persistence -------------------------------------------------------------

func get_save_state() -> Array:
	var out: Array = []
	for arc in _active:
		out.append({
			"arc_id": arc["arc_id"],
			"agent": arc["agent"],
			"stage_id": arc["stage_id"],
			"entered_day": arc["entered_day"],
			"wait_days": arc["wait_days"],
			"resolved_def": arc.get("resolved_def", {}),
		})
	return out


func load_save_state(data: Array) -> void:
	_active.clear()
	for entry in data:
		if entry is Dictionary and entry.has("arc_id"):
			_active.append(entry.duplicate(true))
