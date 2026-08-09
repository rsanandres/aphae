extends Node
## Autoload: manages random and triggered life events.

var _event_definitions: Array[EventDefinition] = []
var _active_events: Array[Dictionary] = []  # {definition, affected_agents, start_time, end_time}
var _cooldowns: Dictionary = {}  # event_id -> last_triggered_day
var _loaded: bool = false

# Producer dilemmas: one pending at a time, real-time timeout while paused.
var auto_resolve_dilemmas: bool = false  # true in headless / when no UI exists
var _pending_dilemma: Dictionary = {}  # {definition, affected, timeout_left, was_paused}

# Pacing: three roll windows per day (start / noon / late afternoon) instead
# of one midnight burst, capped so a hot streak can't flood the office.
const ROLL_WINDOW_HOURS: Array[float] = [12.0, 17.0]
const MAX_EVENTS_PER_DAY := 6
var _events_today: int = 0
var _windows_rolled: Dictionary = {}  # hour -> day it last rolled


func _ready() -> void:
	_load_events()
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.time_tick.connect(_on_time_tick)
	auto_resolve_dilemmas = DisplayServer.get_name() == "headless"


func _process(delta: float) -> void:
	# Dilemma timeout counts REAL seconds — game time is frozen while the
	# producer decides, so game minutes cannot drive it.
	if _pending_dilemma.is_empty():
		return
	_pending_dilemma["timeout_left"] = float(_pending_dilemma["timeout_left"]) - delta
	if float(_pending_dilemma["timeout_left"]) <= 0.0:
		var default_choice: int = int((_pending_dilemma["definition"] as EventDefinition).dilemma.get("default_choice", 0))
		resolve_dilemma(default_choice, true)


func resolve_dilemma(choice_idx: int, by_timeout: bool = false) -> void:
	if _pending_dilemma.is_empty():
		return
	var definition: EventDefinition = _pending_dilemma["definition"]
	var affected: Array = _pending_dilemma["affected"]
	var was_paused: bool = _pending_dilemma["was_paused"]
	_pending_dilemma = {}

	var choices: Array = definition.dilemma.get("choices", [])
	choice_idx = clampi(choice_idx, 0, maxi(choices.size() - 1, 0))
	if not choices.is_empty():
		var payload: Dictionary = choices[choice_idx].get("payload", {})
		var target: Node2D = affected[0] if not affected.is_empty() and affected[0] is Node2D else null
		ConsequenceEngine.apply(payload, target, null, {"affected": affected, "definition": definition})

	# Restore the pause state the player had before the dilemma interrupted.
	if not was_paused and TimeManager.is_paused:
		TimeManager.toggle_pause()
	EventBus.dilemma_resolved.emit(definition.event_id, choice_idx, by_timeout)


func has_pending_dilemma() -> bool:
	return not _pending_dilemma.is_empty()


func trigger_event(event_id: String, specific_agents: Array = []) -> bool:
	var definition := _find_definition(event_id)
	if not definition:
		push_warning("EventManager: Unknown event '%s'" % event_id)
		return false
	return _execute_event(definition, specific_agents)


func get_available_events() -> Array[EventDefinition]:
	return _event_definitions


func get_save_state() -> Dictionary:
	var active: Array = []
	for ev in _active_events:
		var names: Array = []
		for a in ev["affected_agents"]:
			if a is Node2D and is_instance_valid(a):
				names.append(a.agent_name)
		active.append({
			"id": (ev["definition"] as EventDefinition).event_id,
			"end_time": ev["end_time"],
			"agents": names,
		})
	return {"cooldowns": _cooldowns.duplicate(), "active": active}


func load_save_state(data: Dictionary) -> void:
	_cooldowns = data.get("cooldowns", {}).duplicate()
	_active_events.clear()
	for entry in data.get("active", []):
		var definition := _find_definition(str(entry.get("id", "")))
		if not definition:
			continue
		var agents: Array = []
		for agent_name in entry.get("agents", []):
			var agent := AgentManager.get_agent_by_name(str(agent_name))
			if agent:
				agents.append(agent)
		_active_events.append({
			"definition": definition,
			"affected_agents": agents,
			"start_time": TimeManager.game_minutes,
			"end_time": float(entry.get("end_time", 0.0)),
		})


func get_active_events() -> Array[Dictionary]:
	return _active_events


func _on_day_changed(day: int) -> void:
	_events_today = 0
	if DramaDirector:
		# Sync narrator drama into the director once per day.
		DramaDirector.sync_with_narrator()
	_roll_events(day)


func _roll_events(day: int) -> void:
	if _events_today >= MAX_EVENTS_PER_DAY:
		return
	var drama_mod: float = DramaDirector.get_probability_modifier() if DramaDirector else 1.0
	for definition in _event_definitions:
		if _events_today >= MAX_EVENTS_PER_DAY:
			return
		# Check cooldown
		var last_triggered: int = _cooldowns.get(definition.event_id, 0)
		if day - last_triggered < definition.cooldown_days:
			continue
		# Prerequisites gate the organic roll only; trigger_event() bypasses
		# them so the god toolbar and harnesses always work.
		if not ConsequenceEngine.prerequisites_met_global(definition.prerequisites):
			continue
		# Roll probability, scaled by drama pacing
		var adjusted_prob: float = definition.probability * drama_mod
		if randf() < adjusted_prob:
			var targets := _select_targets(definition)
			if targets.is_empty() and definition.target_mode != "global":
				continue
			if not targets.is_empty() and not ConsequenceEngine.prerequisites_met_target(definition.prerequisites, targets[0]):
				continue
			if _execute_event(definition, targets):
				_events_today += 1


func _on_time_tick(game_minutes: float) -> void:
	# Midday roll windows: drama can start at lunch, not only at midnight.
	var hour := fmod(game_minutes / 60.0, 24.0)
	for window_hour in ROLL_WINDOW_HOURS:
		if hour >= window_hour and _windows_rolled.get(window_hour, 0) != TimeManager.day:
			_windows_rolled[window_hour] = TimeManager.day
			_roll_events(TimeManager.day)

	# Check for ending active events
	var to_remove: Array[int] = []
	for i in range(_active_events.size()):
		var ev: Dictionary = _active_events[i]
		if ev["end_time"] > 0.0 and game_minutes >= ev["end_time"]:
			_end_event(ev)
			to_remove.append(i)
	to_remove.reverse()
	for idx in to_remove:
		_active_events.remove_at(idx)


func _execute_event(definition: EventDefinition, specific_agents: Array = []) -> bool:
	var affected: Array = specific_agents
	if affected.is_empty():
		affected = _select_targets(definition)
	if affected.is_empty() and definition.target_mode != "global":
		return false

	_cooldowns[definition.event_id] = TimeManager.day

	var start_time := TimeManager.game_minutes
	var end_time := start_time + definition.duration_minutes if definition.duration_minutes > 0 else 0.0

	var event_data := {
		"definition": definition,
		"affected_agents": affected,
		"start_time": start_time,
		"end_time": end_time,
	}

	if definition.duration_minutes > 0:
		_active_events.append(event_data)

	# Producer dilemmas hold their consequences until the player chooses
	# (or the clock runs out). The choice payloads ARE the event.
	if not definition.dilemma.is_empty():
		return _offer_dilemma(definition, affected)

	# Apply immediate effects (legacy enum-keyed need deltas)
	_apply_effects(definition, affected)

	# Apply the declarative consequence payload (relationships, modifiers,
	# conditions, memories, trait shifts, scripts — see ConsequenceEngine)
	ConsequenceEngine.apply_event(definition, affected)

	# Default memories when the payload declares none: affected agents
	# remember it; agents within 160px witness it (global events broadcast).
	if not definition.payload.has("memory"):
		_create_event_memories(definition, affected)

	# Emit signals
	var agent_names: Array = []
	for a in affected:
		agent_names.append(a.agent_name if a is Node2D and a.has_method("request_think") else str(a))
	EventBus.event_triggered.emit(definition.event_id, agent_names)
	EventBus.narrative_event.emit(
		definition.description,
		agent_names, 6.0
	)
	return true


func _offer_dilemma(definition: EventDefinition, affected: Array) -> bool:
	if not _pending_dilemma.is_empty():
		return false  # one at a time; the roll can retry another day
	var names: Array = []
	for a in affected:
		if a is Node2D and is_instance_valid(a):
			names.append(a.agent_name)
	_pending_dilemma = {
		"definition": definition,
		"affected": affected,
		"timeout_left": float(definition.dilemma.get("timeout_sec", 25.0)),
		"was_paused": TimeManager.is_paused,
	}
	if not TimeManager.is_paused:
		TimeManager.toggle_pause()
	EventBus.dilemma_offered.emit(definition, names)
	if auto_resolve_dilemmas:
		resolve_dilemma(int(definition.dilemma.get("default_choice", 0)), true)
	return true


func _end_event(event_data: Dictionary) -> void:
	var definition: EventDefinition = event_data["definition"]
	# Undo global effects
	if definition.global_effect == "disable_objects":
		pass  # Objects auto-resume when event ends
	EventBus.event_ended.emit(definition.event_id)


func _select_targets(definition: EventDefinition) -> Array:
	var agents := AgentManager.agents
	if agents.is_empty():
		return []
	match definition.target_mode:
		"random":
			return [agents[randi() % agents.size()]]
		"most_productive":
			var best: Node2D = null
			var best_val: float = -1.0
			for a in agents:
				var val: float = a.needs.get_value(NeedType.Type.PRODUCTIVITY)
				if val > best_val:
					best_val = val
					best = a
			return [best] if best else []
		"most_social":
			var best: Node2D = null
			var best_val: float = -1.0
			for a in agents:
				var val: float = a.needs.get_value(NeedType.Type.SOCIAL)
				if val > best_val:
					best_val = val
					best = a
			return [best] if best else []
		"global":
			return agents.duplicate()
		"specific":
			# Only fires via trigger_event(id, agents) — arcs, dilemmas,
			# scripts. An organic roll selects nobody and is skipped.
			return []
		_:
			return [agents[randi() % agents.size()]]


func _apply_effects(definition: EventDefinition, affected: Array) -> void:
	for agent in affected:
		if not is_instance_valid(agent) or not agent.has_node("AgentNeeds"):
			continue
		for need in definition.need_effects:
			var delta: float = definition.need_effects[need]
			agent.needs.restore(need, delta)


func _create_event_memories(definition: EventDefinition, affected: Array) -> void:
	# Affected agents remember it; only agents near the scene witness it.
	# Broadcasting to the whole office made sneaky events impossible and gave
	# agents memories of things they could not have seen.
	var origin: Vector2 = Vector2.ZERO
	var has_origin := false
	for a in affected:
		if a is Node2D and is_instance_valid(a):
			origin = a.global_position
			has_origin = true
			break
	for agent in AgentManager.agents:
		if not is_instance_valid(agent):
			continue
		var is_affected := agent in affected
		if not is_affected and definition.target_mode != "global":
			if not has_origin or agent.global_position.distance_to(origin) > 160.0:
				continue
		var importance: float = 6.0 if is_affected else 3.0
		var desc: String
		if is_affected:
			desc = "%s experienced: %s" % [agent.agent_name, definition.description]
		else:
			desc = "%s observed: %s" % [agent.agent_name, definition.description]
		agent.memory.add_observation(desc, importance)


func _find_definition(event_id: String) -> EventDefinition:
	for ed in _event_definitions:
		if ed.event_id == event_id:
			return ed
	return null


func _load_events() -> void:
	var path := "res://resources/events/events.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("EventManager: Could not load events.json")
		_load_default_events()
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("EventManager: JSON parse error in events.json")
		_load_default_events()
		return
	var data: Array = json.data
	for entry in data:
		_event_definitions.append(EventDefinition.from_dict(entry))
	_loaded = true


func _load_default_events() -> void:
	# Hardcoded fallback if JSON fails
	var events_data: Array = [
		{"id": "gossip_spreads", "name": "Gossip Spreads", "description": "Office gossip is making the rounds.", "probability": 0.15, "category": "social", "target_mode": "random", "need_effects": {"social": 10}, "cooldown_days": 2},
		{"id": "heated_argument", "name": "Heated Argument", "description": "A heated argument breaks out.", "probability": 0.05, "category": "social", "target_mode": "random", "need_effects": {"social": -15}, "cooldown_days": 3},
		{"id": "promotion", "name": "Promotion", "description": "Someone earned a promotion!", "probability": 0.03, "category": "work", "target_mode": "most_productive", "need_effects": {"productivity": 30, "social": 10}, "cooldown_days": 10},
		{"id": "pizza_delivery", "name": "Pizza Delivery", "description": "Someone ordered pizza for the office!", "probability": 0.1, "category": "environment", "target_mode": "global", "need_effects": {"hunger": 40}, "cooldown_days": 3},
		{"id": "flu_outbreak", "name": "Flu Outbreak", "description": "A flu is going around the office.", "probability": 0.04, "category": "health", "target_mode": "random", "need_effects": {"energy": -20, "health": -10}, "cooldown_days": 7},
		{"id": "birthday", "name": "Birthday", "description": "It's someone's birthday today!", "probability": 0.08, "category": "personal", "target_mode": "random", "need_effects": {"social": 25}, "cooldown_days": 5},
	]
	for entry in events_data:
		_event_definitions.append(EventDefinition.from_dict(entry))
	_loaded = true
