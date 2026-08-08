class_name BroadcastDirector
extends Node
## Knows where the drama is. Manual mode: X cuts the camera to the most
## recent point of interest. Live mode: the camera works like a TV director —
## cutting to conversations, confessions, and incidents as they happen, and
## drifting back to the wide shot when the office goes quiet.

const POI_FRESH_SECONDS := 30.0
const MIN_CUT_INTERVAL := 4.0
const IDLE_WIDE_SHOT_SECONDS := 18.0

var live_mode: bool = false:
	set(value):
		live_mode = value
		if live_mode:
			_maybe_cut(true)

var _camera: Camera2D = null
var _poi_agent: Node2D = null
var _poi_pos: Vector2 = Vector2.ZERO
var _poi_score: float = 0.0
var _poi_at: float = -1000.0
var _last_cut_at: float = -1000.0
var _on_wide_shot: bool = true


func setup(camera: Camera2D) -> void:
	_camera = camera


func _ready() -> void:
	add_to_group("broadcast")
	EventBus.narrative_event.connect(_on_narrative_event)
	EventBus.conversation_started.connect(_on_conversation_started)
	EventBus.confessional_recorded.connect(_on_confessional_recorded)
	EventBus.confession_made.connect(_on_confession_made)


func _process(_delta: float) -> void:
	if not live_mode or _camera == null:
		return
	# Dead air: drift back to the wide shot.
	if not _on_wide_shot and _now() - _poi_at > IDLE_WIDE_SHOT_SECONDS:
		_camera.center_on_office()
		_on_wide_shot = true


func cut_to_latest() -> bool:
	## Manual cut (X). Returns false when there is nothing fresh to cut to.
	if _camera == null or _now() - _poi_at > POI_FRESH_SECONDS:
		return false
	_do_cut()
	return true


func _on_narrative_event(_text: String, agents: Array, importance: float) -> void:
	if importance < 5.0 or agents.is_empty():
		return
	var agent := AgentManager.get_agent_by_name(str(agents[0]))
	if agent:
		_register_poi(agent, importance)


func _on_conversation_started(a: String, _b: String) -> void:
	var agent := AgentManager.get_agent_by_name(a)
	if agent:
		_register_poi(agent, 3.0)


func _on_confessional_recorded(confessional: RefCounted) -> void:
	var speaker_name: String = confessional.get("speaker")
	var agent := AgentManager.get_agent_by_name(speaker_name)
	if agent:
		_register_poi(agent, 6.0)


func _on_confession_made(a: String, _b: String, _accepted: bool) -> void:
	var agent := AgentManager.get_agent_by_name(a)
	if agent:
		_register_poi(agent, 9.0)


func _register_poi(agent: Node2D, score: float) -> void:
	var fresh := _now() - _poi_at < POI_FRESH_SECONDS
	# A stale POI always yields; a fresh one only to bigger drama.
	if fresh and score < _poi_score:
		return
	_poi_agent = agent
	_poi_pos = agent.global_position
	_poi_score = score
	_poi_at = _now()
	if live_mode:
		_maybe_cut(false)


func _maybe_cut(force: bool) -> void:
	if _camera == null:
		return
	if not force and _now() - _last_cut_at < MIN_CUT_INTERVAL:
		return
	if _now() - _poi_at > POI_FRESH_SECONDS:
		return
	_do_cut()


func _do_cut() -> void:
	_last_cut_at = _now()
	_on_wide_shot = false
	if _poi_agent and is_instance_valid(_poi_agent):
		_camera.follow(_poi_agent)
	else:
		_camera.focus_position(_poi_pos)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
