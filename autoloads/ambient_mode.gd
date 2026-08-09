extends Node
## Ambient play: the office keeps living while you work.
##
## This is the spine of the "leave it running in the corner" identity. When
## the window loses focus the game does NOT stop (that default was the single
## most anti-ambient thing in the project) — instead it drops into a low-power
## posture: every agent thinks with the heuristic brain, think cadence
## stretches, and audio can mute. Meanwhile anything notable that happens is
## collected, so coming back tells you what you missed.
##
## Attention is rewarded, never required: nothing here blocks on the player.

const LOW_POWER_THINK_MULTIPLIER := 3.0
const DIGEST_MIN_EVENTS := 2
const DIGEST_MIN_AWAY_SECONDS := 60.0
const DIGEST_MAX_ENTRIES := 12
const NOTABLE_IMPORTANCE := 6.0

var is_backgrounded: bool = false
var low_power_enabled: bool = true
var mute_when_unfocused: bool = true

var _away_entries: Array[Dictionary] = []
var _away_started_msec: int = 0


func _ready() -> void:
	_sync_settings()
	SettingsManager.settings_changed.connect(_sync_settings)
	EventBus.narrative_event.connect(_on_narrative_event)
	EventBus.confessional_recorded.connect(_on_confessional)
	EventBus.episode_ended.connect(_on_episode_ended)


func _sync_settings() -> void:
	low_power_enabled = SettingsManager.low_power_when_unfocused
	mute_when_unfocused = SettingsManager.mute_when_unfocused


func enter_background() -> void:
	## Called when the window loses focus and auto-pause is off.
	if is_backgrounded:
		return
	is_backgrounded = true
	_away_entries.clear()
	_away_started_msec = Time.get_ticks_msec()
	if low_power_enabled:
		AgentManager.low_power = true
	if mute_when_unfocused:
		var master := AudioServer.get_bus_index("Master")
		if master != -1:
			AudioServer.set_bus_mute(master, true)


func exit_background() -> Array[Dictionary]:
	## Called on focus return. Returns the digest worth showing, or [] when
	## the player only glanced away — a quick alt-tab should never nag.
	if not is_backgrounded:
		return []
	is_backgrounded = false
	AgentManager.low_power = false
	if mute_when_unfocused:
		# SettingsManager owns bus volume/mute; let it re-derive the truth
		# rather than blindly unmuting a bus the player set to zero.
		SettingsManager.apply_audio()

	var away_seconds: float = (Time.get_ticks_msec() - _away_started_msec) / 1000.0
	if away_seconds < DIGEST_MIN_AWAY_SECONDS or _away_entries.size() < DIGEST_MIN_EVENTS:
		_away_entries.clear()
		return []
	var digest: Array[Dictionary] = _away_entries.duplicate()
	_away_entries.clear()
	return digest


func away_seconds() -> float:
	if not is_backgrounded:
		return 0.0
	return (Time.get_ticks_msec() - _away_started_msec) / 1000.0


func _record(kind: String, text: String) -> void:
	if not is_backgrounded:
		return
	_away_entries.append({
		"kind": kind,
		"text": text,
		"day": TimeManager.day,
		"time": TimeManager.time_string,
	})
	while _away_entries.size() > DIGEST_MAX_ENTRIES:
		_away_entries.pop_front()


func _on_narrative_event(text: String, _agents: Array, importance: float) -> void:
	if importance >= NOTABLE_IMPORTANCE:
		_record("event", text)


func _on_confessional(confessional: RefCounted) -> void:
	var c: Confessional = confessional as Confessional
	if c and not c.is_host:
		_record("confessional", "%s: \"%s\"" % [c.speaker, c.line])


func _on_episode_ended(ended_season: int, ended_episode: int, score: int, payout: int) -> void:
	_record("episode", "S%dE%d wrapped — score %d, +%d influence." % [
		ended_season, ended_episode, score, payout])
