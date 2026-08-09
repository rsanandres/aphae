extends Node
## RimWorld-style storyteller: paces events for narrative satisfaction.
## Tracks drama level, enforces cooldowns after big events, escalates when quiet.

## Current drama level on a 0-10 scale. Rises when events fire, decays over time.
var drama_level: float = 0.0

## Game-minutes elapsed since the last significant event (importance >= 4).
var time_since_last_event: float = 0.0

## Rolling average of all agent need levels (0-100). Low = stressed office.
var office_mood: float = 100.0

## True while in a post-climax cooldown window (drama_level spiked above 7).
var _in_cooldown: bool = false

## Game-minutes remaining in the current cooldown period.
var _cooldown_remaining: float = 0.0

## How fast drama_level decays per game-minute (tunable).
const DRAMA_DECAY_RATE := 0.03

## Drama thresholds.
const DRAMA_HIGH := 7.0
const DRAMA_MID_LOW := 4.0
const DRAMA_LOW := 2.0

## Time-since-event thresholds for probability escalation (game-minutes).
const QUIET_THRESHOLD := 120.0
const VERY_QUIET_THRESHOLD := 240.0

## Cooldown duration range after a big spike (game-minutes).
const COOLDOWN_MIN := 30.0
const COOLDOWN_MAX := 60.0

## Importance-to-drama conversion factor for generic narrative events.
const IMPORTANCE_TO_DRAMA := 0.6

## Drama spike magnitudes for specific event types.
const SPIKE_CONFESSION := 4.0
const SPIKE_DEATH := 7.0
const SPIKE_ROMANCE := 3.0
const SPIKE_EVENT_BASE := 2.0

## Mood sampling interval (real seconds) to avoid per-tick overhead.
const MOOD_SAMPLE_INTERVAL := 5.0
var _mood_timer: float = 0.0

## Last game-minutes value seen, used to compute deltas.
var _last_game_minutes: float = 0.0


func _ready() -> void:
	# Core time signal — drives decay and cooldown countdown.
	EventBus.time_tick.connect(_on_time_tick)

	# Event signals that increase drama.
	EventBus.event_triggered.connect(_on_event_triggered)
	EventBus.confession_made.connect(_on_confession_made)
	EventBus.agent_died.connect(_on_agent_died)
	EventBus.romance_started.connect(_on_romance_started)
	EventBus.narrative_event.connect(_on_narrative_event)


# ---------------------------------------------------------------------------
#  Public API
# ---------------------------------------------------------------------------

## Returns a multiplier that EventManager applies to each event's probability
## before the random roll. Values < 1 suppress events; values > 1 boost them.
func get_probability_modifier() -> float:
	# Cooldown after a climax — almost no events.
	if _in_cooldown:
		return 0.1

	# High drama — reduce new events.
	if drama_level > DRAMA_HIGH:
		return 0.3

	# Normal drama band — standard probabilities.
	if drama_level >= DRAMA_MID_LOW:
		return 1.0

	# Low drama — escalate based on how long it has been quiet.
	if drama_level < DRAMA_LOW:
		if time_since_last_event > VERY_QUIET_THRESHOLD:
			return 3.0
		if time_since_last_event > QUIET_THRESHOLD:
			return 2.0

	return 1.0


## Returns a brief debug dictionary for the inspector / god-mode UI.
func get_debug_state() -> Dictionary:
	return {
		"drama_level": snappedf(drama_level, 0.01),
		"time_since_last_event": snappedf(time_since_last_event, 0.1),
		"office_mood": snappedf(office_mood, 0.1),
		"in_cooldown": _in_cooldown,
		"cooldown_remaining": snappedf(_cooldown_remaining, 0.1),
		"probability_modifier": snappedf(get_probability_modifier(), 0.01),
	}


# ---------------------------------------------------------------------------
#  Signal handlers
# ---------------------------------------------------------------------------

func _on_time_tick(game_minutes: float) -> void:
	var delta_minutes: float = game_minutes - _last_game_minutes if _last_game_minutes > 0.0 else 1.0
	_last_game_minutes = game_minutes

	# Decay drama over time.
	drama_level = maxf(0.0, drama_level - DRAMA_DECAY_RATE * delta_minutes)

	# Track quiet time.
	time_since_last_event += delta_minutes

	# Countdown cooldown.
	if _in_cooldown:
		_cooldown_remaining -= delta_minutes
		if _cooldown_remaining <= 0.0:
			_in_cooldown = false
			_cooldown_remaining = 0.0


func _on_event_triggered(event_id: String, _affected_agents: Array) -> void:
	_add_drama(SPIKE_EVENT_BASE)
	time_since_last_event = 0.0


func _on_confession_made(_confessor: String, _target: String, _accepted: bool) -> void:
	_add_drama(SPIKE_CONFESSION)
	time_since_last_event = 0.0


func _on_agent_died(_agent_name: String, _cause: String) -> void:
	_add_drama(SPIKE_DEATH)
	time_since_last_event = 0.0
	# Force a long cooldown after death.
	_start_cooldown(COOLDOWN_MAX)


func _on_romance_started(_agent_a: String, _agent_b: String) -> void:
	_add_drama(SPIKE_ROMANCE)
	time_since_last_event = 0.0


func _on_narrative_event(_text: String, _agents: Array, importance: float) -> void:
	# Scale drama by event importance (0-10 scale in the narrator).
	var spike: float = importance * IMPORTANCE_TO_DRAMA
	_add_drama(spike)
	if importance >= 4.0:
		time_since_last_event = 0.0


# ---------------------------------------------------------------------------
#  Internal helpers
# ---------------------------------------------------------------------------

func _add_drama(amount: float) -> void:
	drama_level = clampf(drama_level + amount, 0.0, 10.0)
	# If drama just crossed the high threshold, start a cooldown.
	if drama_level >= DRAMA_HIGH and not _in_cooldown:
		var duration: float = lerpf(COOLDOWN_MIN, COOLDOWN_MAX, (drama_level - DRAMA_HIGH) / (10.0 - DRAMA_HIGH))
		_start_cooldown(duration)


func _start_cooldown(duration: float) -> void:
	_in_cooldown = true
	# If already in cooldown, extend it rather than shorten.
	_cooldown_remaining = maxf(_cooldown_remaining, duration)


func _process(delta: float) -> void:
	# Periodically sample office mood from agent needs.
	_mood_timer += delta
	if _mood_timer >= MOOD_SAMPLE_INTERVAL:
		_mood_timer = 0.0
		_update_office_mood()


func _update_office_mood() -> void:
	var agents: Array[Node2D] = AgentManager.agents
	if agents.is_empty():
		office_mood = 100.0
		return
	var total: float = 0.0
	var count: int = 0
	for agent in agents:
		if not is_instance_valid(agent) or not agent.has_node("AgentNeeds"):
			continue
		var needs: AgentNeeds = agent.get_node("AgentNeeds")
		# Average all five need values for this agent.
		var agent_avg: float = 0.0
		var need_count: int = 0
		for need in NeedType.get_all():
			agent_avg += needs.get_value(need)
			need_count += 1
		if need_count > 0:
			total += agent_avg / float(need_count)
			count += 1
	office_mood = total / float(count) if count > 0 else 100.0

	# Feed office mood back into drama — a miserable office nudges drama up.
	if office_mood < 30.0:
		_add_drama(0.1)


# ---------------------------------------------------------------------------
#  Narrator integration: absorb top-storyline drama as ambient input.
# ---------------------------------------------------------------------------

## Called by external code or can be polled. Checks the Narrator's top storyline
## drama_score and blends it into our drama_level so we respect narrative arcs
## already being tracked.
func sync_with_narrator() -> void:
	if not is_instance_valid(Narrator):
		return
	var top: Array[Storyline] = Narrator.get_top_storylines(1)
	if top.is_empty():
		return
	var narrator_drama: float = top[0].drama_score
	# Blend: if narrator thinks drama is very high, nudge ours up gently.
	if narrator_drama > drama_level + 2.0:
		drama_level = clampf(drama_level + 0.5, 0.0, 10.0)


func get_save_state() -> Dictionary:
	return {
		"drama_level": drama_level,
		"time_since_last_event": time_since_last_event,
		"in_cooldown": _in_cooldown,
		"cooldown_remaining": _cooldown_remaining,
	}


func load_save_state(data: Dictionary) -> void:
	drama_level = float(data.get("drama_level", 0.0))
	time_since_last_event = float(data.get("time_since_last_event", 0.0))
	_in_cooldown = bool(data.get("in_cooldown", false))
	_cooldown_remaining = float(data.get("cooldown_remaining", 0.0))
