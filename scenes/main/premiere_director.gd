class_name PremiereDirector
extends Node
## The authored first session. A fresh sandbox used to open on silent
## wandering and hope; this node guarantees the premiere beats the roadmap
## promises: cast intros in the first minutes, one seeded secret with an
## early booth admission, at least one event before noon of day 1, and the
## mole case open by day 3-4.
##
## Deliberately NOT an autoload: main.gd creates it only on a brand-new
## sandbox, so it cannot exist in a harness and needs no auto_* seam. It is
## a first-session experience and is not persisted — a save/load mid-day-1
## keeps the 1-day pilot (that lives in ProducerEconomy) and simply loses
## whichever nudges had not fired yet. Every beat here defers to the organic
## path: it only forces what the dice failed to deliver on their own.

const SECRET_ADMIT_AT_MINUTES := 600.0   # 10:00 day 1 — the audience learns a truth early
const EVENT_GUARANTEE_AT_MINUTES := 660.0  # 11:00 day 1 — "before noon" with margin for the noon roll window
const MOLE_GUARANTEE_FROM_DAY := 3       # open_case() forced on day 3; retried day 4
const MOLE_GUARANTEE_UNTIL_DAY := 4

## Light, social, premiere-friendly events — nothing that departs or kills a
## cast member the audience just met. Picked in order; first that fires wins.
const PREMIERE_EVENTS: Array[String] = [
	"pizza_delivery", "stolen_lunch", "gossip_spreads", "birthday",
]

var _seeded_secret: SecretState = null
var _saw_event: bool = false
var _secret_beat_done: bool = false
var _event_beat_done: bool = false
var _mole_beat_done: bool = false


func _ready() -> void:
	EventBus.event_triggered.connect(func(_id: String, _agents: Array) -> void: _saw_event = true)
	EventBus.time_tick.connect(_on_time_tick)
	EventBus.day_changed.connect(_on_day_changed)


func start() -> void:
	## Called by main.gd once the fresh cast has spawned.
	# Cold open: the cast introduces itself to camera, staggered.
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		ConfessionalDirector.request_cast_intros()
	)
	_seed_secret()


func _seed_secret() -> void:
	## Guarantee at least one secret in the premiere cast. The spawn roll
	## (35% per agent) usually delivers; when it does, keep the organic one.
	for agent in AgentManager.agents:
		if not is_instance_valid(agent) or agent.is_dead:
			continue
		var existing: SecretState = SecretManager.get_secret(agent.agent_name)
		if existing != null and existing.is_hidden():
			_seeded_secret = existing
			return
	var living: Array[Node2D] = []
	for agent in AgentManager.agents:
		if is_instance_valid(agent) and not agent.is_dead:
			living.append(agent)
	if living.is_empty():
		return
	_seeded_secret = SecretManager.assign_secret(living[randi() % living.size()])


func _on_time_tick(game_minutes: float) -> void:
	if TimeManager.day != 1:
		return
	# Early booth admission: the pilot's dramatic irony must not wait on the
	# 30%-per-day roll. One truth reaches the camera before mid-morning ends.
	if not _secret_beat_done and game_minutes >= SECRET_ADMIT_AT_MINUTES:
		_secret_beat_done = true
		if _seeded_secret != null and _seeded_secret.is_hidden() and not _seeded_secret.admitted_on_camera:
			SecretManager.admit_on_camera(_seeded_secret)
	# Something must HAPPEN before lunch. The organic windows can roll
	# nothing at all on a quiet seed; the premiere doesn't get a second take.
	if not _event_beat_done and game_minutes >= EVENT_GUARANTEE_AT_MINUTES:
		_event_beat_done = true
		if not _saw_event:
			for event_id in PREMIERE_EVENTS:
				if EventManager.trigger_event(event_id):
					break


func _on_day_changed(day: int) -> void:
	if day > MOLE_GUARANTEE_UNTIL_DAY:
		queue_free()  # every premiere beat has had its chance; the show runs itself now
		return
	if _mole_beat_done or day < MOLE_GUARANTEE_FROM_DAY:
		return
	# The organic roll is 12%/day gated by pacing — most premieres would end
	# without the headline system ever appearing. Day 3-4, the host opens it.
	if WhodunitDirector.has_open_case():
		_mole_beat_done = true
		return
	if WhodunitDirector.open_case() != null:
		_mole_beat_done = true
