class_name SoakReport
extends RefCounted
## The numbers a soak run is judged by.
##
## Listens to the same signals the console log prints from and reduces a run
## to a small JSON document, so "the cast repeats itself" and "nothing ever
## concludes" stop being impressions and become figures CI can hold a line
## on. headless_sim owns one, attaches it, and writes it at exit.
##
## The three headline measures (docs/ROADMAP.md):
##   repeat_rate      share of spoken lines already heard, verbatim, this run
##   conclusion_rate  stories that reached an ending, per episode wrapped
##   stance_spread    share of conversation turns that are not agreement
##
## Everything under "timing" is wall-clock and differs between two runs of
## the same seed. Everything else is covered by "fingerprint", a hash of the
## run's event stream: equal seeds must produce equal fingerprints.

## The importance at which a narrative event counts as drama. The same bar
## ProducerEconomy uses for a beat.
const DRAMA_IMPORTANCE := 5.0

## Line pools that read as something other than agreement. Until stances are
## chosen in code (roadmap B4) the pool a heuristic line was drawn from is
## the only stance signal there is; model-written lines carry kind "llm"
## and count only when the pair's tone is hostile.
const NON_AGREEMENT_KINDS: Array[String] = ["reject", "probe", "deflect", "negative"]
const HOSTILE_TONE := "hostile"

const TOP_REPEATS := 5

var _start_minutes: float = 0.0
var _line_counts: Dictionary = {}    # text -> times spoken
var _lines: Dictionary = {}          # source -> {"total": int, "repeated": int}
var _turns_total: int = 0
var _turns_non_agreement: int = 0
var _turns_by_kind: Dictionary = {}  # kind -> int
var _conversations: int = 0
var _conclusions: Dictionary = {"goal": 0, "romance": 0, "exposure": 0, "case": 0}
var _episodes: int = 0
var _narrative_events: int = 0
var _drama_events: int = 0
var _first_drama_minutes: float = -1.0
var _hash := HashingContext.new()
var _digest: String = ""  # set once the fingerprint has been taken


func _init() -> void:
	_hash.start(HashingContext.HASH_SHA256)
	_start_minutes = TimeManager.game_minutes


func attach() -> void:
	## Subscribe to the live simulation. Tests skip this and call record_*.
	_start_minutes = TimeManager.game_minutes
	EventBus.conversation_started.connect(func(_a: String, _b: String) -> void: record_conversation())
	EventBus.conversation_turn.connect(
		func(speaker: String, _listener: String, line: String, kind: String, tone: String) -> void:
			record_line("conversation", line)
			record_turn(kind, tone)
			_stamp("line|%s|%s" % [speaker, line]))
	EventBus.confessional_recorded.connect(_on_confessional)
	EventBus.narrative_event.connect(
		func(text: String, _agents: Array, importance: float) -> void:
			record_narrative(importance, TimeManager.game_minutes)
			_stamp("event|%.1f|%s" % [importance, text]))
	EventBus.goal_achieved.connect(func(_who: String, _text: String, _kind: int) -> void: record_conclusion("goal"))
	EventBus.romance_started.connect(func(_a: String, _b: String) -> void: record_conclusion("romance"))
	EventBus.secret_exposed.connect(func(_holder: String, _text: String) -> void: record_conclusion("exposure"))
	EventBus.case_resolved.connect(func(_caught: bool, _mole: String) -> void: record_conclusion("case"))
	EventBus.episode_ended.connect(func(_s: int, _e: int, _score: int, _payout: int) -> void: record_episode())


func _on_confessional(confessional: RefCounted) -> void:
	var c: Confessional = confessional as Confessional
	if c == null:
		return
	record_line("confessional", c.line)
	_stamp("cam|%s|%s" % [c.speaker, c.line])


func _stamp(record: String) -> void:
	## Fold one event into the fingerprint, with the game clock, so two runs
	## only match if the same things happened at the same game minute.
	if _digest != "":
		return  # the fingerprint is taken; the run is over
	_hash.update(("%d|%s\n" % [int(TimeManager.game_minutes), record]).to_utf8_buffer())


# --- Recording (the live handlers and the harness both go through these) ---

func record_line(source: String, text: String) -> void:
	var line := text.strip_edges()
	if line == "":
		return
	if not _lines.has(source):
		_lines[source] = {"total": 0, "repeated": 0}
	_lines[source]["total"] += 1
	var seen: int = _line_counts.get(line, 0)
	if seen > 0:
		_lines[source]["repeated"] += 1
	_line_counts[line] = seen + 1


func record_turn(kind: String, tone: String) -> void:
	_turns_total += 1
	_turns_by_kind[kind] = int(_turns_by_kind.get(kind, 0)) + 1
	if kind in NON_AGREEMENT_KINDS or tone == HOSTILE_TONE:
		_turns_non_agreement += 1


func record_conversation() -> void:
	_conversations += 1


func record_conclusion(kind: String) -> void:
	_conclusions[kind] = int(_conclusions.get(kind, 0)) + 1


func record_episode() -> void:
	_episodes += 1


func record_narrative(importance: float, game_minutes: float) -> void:
	_narrative_events += 1
	if importance < DRAMA_IMPORTANCE:
		return
	_drama_events += 1
	if _first_drama_minutes < 0.0:
		_first_drama_minutes = game_minutes - _start_minutes


# --- Reading ---

func lines_total() -> int:
	var total := 0
	for source: String in _lines:
		total += int(_lines[source]["total"])
	return total


func lines_repeated() -> int:
	var repeated := 0
	for source: String in _lines:
		repeated += int(_lines[source]["repeated"])
	return repeated


func repeat_rate() -> float:
	var total := lines_total()
	return float(lines_repeated()) / total if total > 0 else 0.0


func stance_spread() -> float:
	return float(_turns_non_agreement) / _turns_total if _turns_total > 0 else 0.0


func conclusions_total() -> int:
	var total := 0
	for kind: String in _conclusions:
		total += int(_conclusions[kind])
	return total


func top_repeats(count: int = TOP_REPEATS) -> Array:
	## The lines heard most often, worst first. Ties break alphabetically so
	## the list is stable between two runs of the same seed.
	var rows: Array = []
	for line: String in _line_counts:
		if int(_line_counts[line]) > 1:
			rows.append({"line": line, "times": int(_line_counts[line])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["times"] != b["times"]:
			return a["times"] > b["times"]
		return a["line"] < b["line"])
	return rows.slice(0, count)


func fingerprint() -> String:
	## Hash of everything stamped. Taking it closes the stream: later
	## events are ignored and later calls return the same digest.
	if _digest == "":
		_digest = _hash.finish().hex_encode()
	return _digest


func build(run: Dictionary, timing: Dictionary) -> Dictionary:
	## The report document. `run` describes the run (seed, agents, speed,
	## backend); `timing` is the wall-clock block. Building closes the
	## fingerprint.
	var game_days := maxf((TimeManager.game_minutes - _start_minutes) / 1440.0, 0.0)
	var by_source := {}
	for source: String in _lines:
		var total: int = _lines[source]["total"]
		var repeated: int = _lines[source]["repeated"]
		by_source[source] = {
			"total": total,
			"repeated": repeated,
			"rate": _round(float(repeated) / total if total > 0 else 0.0),
		}
	var conclusions := conclusions_total()
	return {
		"run": run,
		"game_days": _round(game_days),
		"repeat_rate": _round(repeat_rate()),
		"conclusion_rate": _round(float(conclusions) / _episodes) if _episodes > 0 else null,
		"stance_spread": _round(stance_spread()),
		"lines": {
			"total": lines_total(),
			"repeated": lines_repeated(),
			"distinct": _line_counts.size(),
			"by_source": by_source,
			"top_repeats": top_repeats(),
		},
		"stances": {
			"turns": _turns_total,
			"non_agreement": _turns_non_agreement,
			"by_kind": _turns_by_kind,
			"basis": "line pool and pair tone; model-written turns count by tone only",
		},
		"conclusions": {
			"total": conclusions,
			"by_kind": _conclusions,
			"episodes": _episodes,
			"per_game_day": _round(conclusions / game_days) if game_days > 0.0 else null,
		},
		"drama": {
			"narrative_events": _narrative_events,
			"dramatic": _drama_events,
			"drama_bar": DRAMA_IMPORTANCE,
			"minutes_to_first": _round(_first_drama_minutes) if _first_drama_minutes >= 0.0 else null,
		},
		"conversations": {
			"total": _conversations,
			"per_game_day": _round(_conversations / game_days) if game_days > 0.0 else null,
		},
		"fingerprint": fingerprint(),
		"timing": timing,
	}


static func _round(x: float) -> float:
	return snappedf(x, 0.0001)
