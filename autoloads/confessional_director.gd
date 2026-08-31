extends Node
## Confessional Director: the reality-TV "talking head" layer.
##
## Observes dramatic EventBus signals and produces first-person confessional
## quips in each agent's own voice (LLM-driven, with a personality-flavored
## heuristic fallback so it works fully offline), plus occasional host recaps
## at day rollover. Purely additive — it only listens to signals other systems
## already emit, so it cannot alter or break their behavior.

var confessionals: Array[Confessional] = []  # ring buffer, oldest first
const MAX_CONFESSIONALS := 40

const COOLDOWN := 8.0            # min real seconds between confessionals (rate limit)
var cooldown_scale: float = 1.0  # better_cameras upgrade halves this
const HOST_RECAP_MIN_DAYS := 2   # don't recap before this day
const PENDING_TIMEOUT := 20.0    # give up on a stalled LLM request rather than jam the feed
const QUIRK_CHANCE := 0.3        # how often a quirk is offered to the model — see _request_llm
var _cooldown: float = 0.0
var _pending: bool = false       # true while an LLM request is in flight
var _pending_time: float = 0.0
var _last_recap_day: int = 0


func _ready() -> void:
	EventBus.confession_made.connect(_on_confession_made)
	EventBus.romance_started.connect(_on_romance_started)
	EventBus.agent_died.connect(_on_agent_died)
	EventBus.group_rivalry_detected.connect(_on_group_rivalry)
	EventBus.narrative_event.connect(_on_narrative_event)
	EventBus.day_changed.connect(_on_day_changed)


func _process(delta: float) -> void:
	if TimeManager.is_paused:
		return
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	# Safety valve: never let a lost callback block the feed forever.
	if _pending:
		_pending_time += delta
		if _pending_time >= PENDING_TIMEOUT:
			_pending = false
			_pending_time = 0.0


func request_intro(agent: Node2D, event_text: String = "") -> void:
	## One agent introduces themselves to camera. Used by the cold open and
	## by new-hire arrivals. Bypasses the rate limit deliberately — an
	## arrival IS the moment.
	if not is_instance_valid(agent) or agent.is_dead:
		return
	if event_text == "":
		event_text = "It's day one in the office. Introduce yourself to the audience in a single line, in your own voice."
	if LLMManager.is_available and not _pending:
		_request_llm("intro", event_text, agent)
	else:
		_emit("intro", _heuristic_line("intro", agent), agent)


func request_farewell(agent: Node2D, reason: String) -> void:
	## A departing agent's last word to camera.
	if not is_instance_valid(agent) or agent.is_dead:
		return
	if LLMManager.is_available and not _pending:
		_request_llm("farewell",
			"You are leaving the office for good (%s). One last line to the camera before you go." % reason,
			agent)
	else:
		_emit("farewell", _heuristic_line("farewell", agent), agent)


func request_secret_admission(agent: Node2D, secret_text: String) -> void:
	## M7's dramatic-irony beat: the booth hears what the floor never will.
	## Bypasses the rate limit like intros do — an admission IS the moment,
	## and SecretManager already paces it to at most one a day.
	if not is_instance_valid(agent) or agent.is_dead:
		return
	var event_text := "Here, and only here, you can say it: you %s. Nobody on the floor knows. Admit it to the camera in one line, in your own voice." % secret_text
	if LLMManager.is_available and not _pending:
		_request_llm("secret", event_text, agent)
	else:
		_emit("secret", _heuristic_line("secret", agent, secret_text), agent)


func request_cast_intros() -> void:
	## Cold open for a fresh sandbox: each cast member files a one-line intro
	## to camera, staggered so the cutaways play as a sequence.
	var delay := 0.0
	for agent in AgentManager.agents:
		if not is_instance_valid(agent) or agent.is_dead:
			continue
		var captured: Node2D = agent
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			request_intro(captured)
		)
		delay += 6.0


func get_recent(count: int = 20) -> Array[Confessional]:
	var start := maxi(0, confessionals.size() - count)
	var result: Array[Confessional] = []
	for i in range(start, confessionals.size()):
		result.append(confessionals[i])
	return result


# --- Signal handlers -------------------------------------------------------

func _on_confession_made(confessor: String, target: String, accepted: bool) -> void:
	var outcome := "and they said yes" if accepted else "and got shot down"
	var speaker := _agent(confessor)
	_record("romance", "You confessed your feelings to %s %s." % [target, outcome], speaker)


func _on_romance_started(agent_a: String, agent_b: String) -> void:
	# Whichever of the pair is around gets the talking head.
	var speaker := _pick_living([agent_a, agent_b])
	var other := agent_b if (speaker and speaker.agent_name == agent_a) else agent_a
	_record("romance", "You and %s just became an item." % other, speaker)


func _on_agent_died(agent_name: String, cause: String) -> void:
	# The deceased is gone — a survivor reacts. No survivors -> host eulogy.
	var speaker := _pick_survivor(agent_name)
	_record("tragedy", "%s just died (%s)." % [agent_name, cause], speaker, speaker == null)


func _on_group_rivalry(group_a: RefCounted, group_b: RefCounted) -> void:
	var a: SocialGroup = group_a as SocialGroup
	var b: SocialGroup = group_b as SocialGroup
	if not a or not b:
		return
	var speaker := _pick_living(a.members)
	_record("rivalry", "Your crew (%s) is now at war with %s." % [a.group_name, b.group_name], speaker)


func _on_narrative_event(text: String, agents: Array, importance: float) -> void:
	if importance < 6.0:
		return  # only the juicy stuff earns a confessional
	var speaker := _pick_living(agents)
	_record("drama", text, speaker)


func _on_day_changed(day: int) -> void:
	if day < HOST_RECAP_MIN_DAYS or day == _last_recap_day:
		return
	# Recap when there's tension brewing, or every few quiet days.
	var drama: float = DramaDirector.drama_level
	if drama < 4.0 and day % 3 != 0:
		return
	_last_recap_day = day
	_record("host", _host_recap(day, drama), null, true)


# --- Recording -------------------------------------------------------------

func _record(kind: String, event_text: String, speaker: Node2D, force_host: bool = false) -> void:
	if _pending or _cooldown > 0.0:
		return  # dropped by rate limit — keeps the feed readable, not spammy
	if force_host or speaker == null:
		_emit(kind, event_text if kind == "host" else _host_line(kind, event_text), null)
		return
	if LLMManager.is_available and LLMManager.get_queue_size() <= 6:
		_request_llm(kind, event_text, speaker)
	else:
		_emit(kind, _heuristic_line(kind, speaker, event_text), speaker)


func _request_llm(kind: String, event_text: String, speaker: Node2D) -> void:
	var profile: PersonalityProfile = speaker.personality
	if profile == null:
		_emit(kind, _heuristic_line(kind, speaker), speaker)
		return

	# Quirks are strong attractors for small models. Listing them on every call
	# turns a character detail into a catchphrase: measured against gemma3, the
	# quirk appeared in 4 of 4 lines across unrelated events — including a death,
	# which came out as "KPIs are tanking!". Instructing the model to use them
	# sparingly barely helped (3 of 4); not putting them in the prompt is the only
	# reliable control. So: one quirk, occasionally.
	var quirks_line := ""
	if not profile.quirks.is_empty() and randf() < QUIRK_CHANCE:
		quirks_line = "A quirk of yours: %s." % profile.quirks[randi() % profile.quirks.size()]

	var prompt := PromptBuilder.build("confessional", {
		"name": speaker.agent_name,
		"personality": profile.get_personality_summary(),
		"speech_style": profile.speech_style if profile.speech_style != "" else "casual",
		"quirks_line": quirks_line,
		"tone": _tone_for(kind),
		"event": event_text,
	})

	var messages := [
		{"role": "system", "content": "You write short, punchy, in-character reality-TV confessional lines. Output only the line."},
		{"role": "user", "content": prompt},
	]

	var format := {
		"type": "object",
		"properties": {"line": {"type": "string"}},
		"required": ["line"],
	}

	_pending = true
	_pending_time = 0.0
	var captured_speaker: Node2D = speaker
	var captured_kind: String = kind
	LLMManager.request_chat(messages, format, func(success: bool, data: Dictionary, _error: String) -> void:
		_pending = false
		_pending_time = 0.0
		if not is_instance_valid(captured_speaker):
			return  # speaker left/died mid-request; drop the quip
		var line := ""
		if success and data.has("line"):
			line = LLMSanitizer.clean_line(_clean(str(data["line"])))
		if line == "":
			line = _heuristic_line(captured_kind, captured_speaker)
		_emit(captured_kind, line, captured_speaker)
	, LLMManager.Priority.LOW, {"temperature": 0.9})


func _emit(kind: String, line: String, speaker: Node2D) -> void:
	if line == "":
		return
	var c := Confessional.new()
	c.kind = kind
	c.line = line
	c.day = TimeManager.day
	c.timestamp = TimeManager.time_string
	if speaker and is_instance_valid(speaker):
		c.speaker = speaker.agent_name
		if speaker.personality:
			c.color = speaker.personality.color
	else:
		c.speaker = "Narrator"
		c.is_host = true
		c.color = Color(1.0, 0.85, 0.4)  # host gold

	confessionals.append(c)
	while confessionals.size() > MAX_CONFESSIONALS:
		confessionals.pop_front()

	_cooldown = COOLDOWN * cooldown_scale
	EventBus.confessional_recorded.emit(c)


# --- Helpers ---------------------------------------------------------------

func _agent(agent_name: String) -> Node2D:
	var a := AgentManager.get_agent_by_name(agent_name)
	if a and is_instance_valid(a) and not a.is_dead:
		return a
	return null


func _pick_living(names: Array) -> Node2D:
	var pool: Array[Node2D] = []
	for n in names:
		var a := AgentManager.get_agent_by_name(str(n))
		if a and is_instance_valid(a) and not a.is_dead:
			pool.append(a)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


func _pick_survivor(exclude_name: String) -> Node2D:
	var pool: Array[Node2D] = []
	for a in AgentManager.agents:
		if is_instance_valid(a) and not a.is_dead and a.agent_name != exclude_name:
			pool.append(a)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


func _tone_for(kind: String) -> String:
	## Without a tone cue the model answers every event in the same register —
	## a death drew the same upbeat work-speak as a promotion.
	match kind:
		"intro":
			return "First day, meet-the-cast energy. One punchy line, fully in character."
		"farewell":
			return "Last day. One parting line — wistful, salty, or triumphant, in character."
		"tragedy":
			return "Someone has died. Be subdued and human. No jokes, no work-speak."
		"romance":
			return "Be candid and a little exposed."
		"rivalry":
			return "Be combative, or smug about your side."
		"secret":
			return "You are finally admitting something you hide from everyone. Relief, guilt, or defiance — but honest, for once."
		_:
			return "Be candid and a little dramatic."


func _clean(raw: String) -> String:
	var s := raw.strip_edges()
	# Strip wrapping quotes the model sometimes adds despite instructions.
	if s.length() >= 2 and (s[0] == '"' or s[0] == "'") and s[s.length() - 1] == s[0]:
		s = s.substr(1, s.length() - 2).strip_edges()
	return s


# --- Heuristic fallback ----------------------------------------------------
## Personality-flavored canned lines so the feature is fun with the LLM off.
## The lines themselves live in resources/dialogue/confessional.json (the
## voice pipeline); this function only picks buckets and fills tokens.

## Coverage contract for the pool file — what this code draws. The harness
## lints the JSON against this, so a pool edit cannot silently strand a
## personality bucket. Growing a pool needs no change here; removing a
## bucket does.
const POOL_EXPECTATIONS := {
	"secret": {"base": 3, "anxious": 1, "catty": 1, "bold": 1},
	"farewell": {"base": 3, "anxious": 1, "catty": 1, "bold": 1},
	"intro": {"base": 3, "anxious": 1, "catty": 1, "bold": 1},
	"romance": {"base": 3, "anxious": 1, "bold": 1, "even": 1, "partner": 2},
	"tragedy": {"base": 3, "anxious": 1, "even": 1, "lost": 2},
	"rivalry": {"base": 3, "catty": 1, "bold": 1, "even": 1, "enemy": 1},
	"drama": {"base": 5, "catty": 1, "anxious": 1, "even": 1},
}

var _last_heuristic: Dictionary = {}  # kind -> last line emitted


func _heuristic_line(kind: String, speaker: Node2D, detail: String = "") -> String:
	var p: PersonalityProfile = speaker.personality
	var catty := p != null and p.agreeableness < 0.4
	var anxious := p != null and p.neuroticism > 0.6
	var bold := p != null and p.extraversion > 0.6
	# Mid-range personalities hit none of the gates above and were stuck with
	# the generic lines forever. The middle of the bell curve gets deadpan.
	var even := p != null and not (catty or anxious or bold)
	var pool_kind := kind if DialoguePools.domain_data("confessional").has(kind) else "drama"

	# Tokens the pool lines may thread. A line whose token is empty here is
	# skipped by fill() — the secret kind, for example, only speaks when it
	# can carry its specifics, because the admission is the player's only
	# organic way to learn the truth without an LLM.
	var desc: String = p.description if p and p.description != "" else "hard to sum up"
	var tokens := {
		"name": speaker.agent_name,
		"detail": detail,
		"desc": desc,
		"desc_cap": desc.capitalize(),
	}
	if kind == "romance":
		if detail.begins_with("You and "):
			tokens["partner"] = detail.substr(8).get_slice(" ", 0)
		elif "confessed your feelings to " in detail:
			tokens["partner"] = detail.get_slice("confessed your feelings to ", 1).get_slice(" ", 0)
	elif kind == "tragedy":
		var lost := detail.get_slice(" ", 0)
		if lost.length() > 1 and lost[0] == lost[0].to_upper() and not detail.begins_with("You"):
			tokens["lost"] = lost
	elif kind == "rivalry" and "at war with " in detail:
		tokens["enemy"] = detail.get_slice("at war with ", 1).trim_suffix(".")

	var options: Array[String] = []
	options.append_array(DialoguePools.fill("confessional", pool_kind, "base", tokens))
	if anxious:
		options.append_array(DialoguePools.fill("confessional", pool_kind, "anxious", tokens))
	if catty:
		options.append_array(DialoguePools.fill("confessional", pool_kind, "catty", tokens))
	if bold:
		options.append_array(DialoguePools.fill("confessional", pool_kind, "bold", tokens))
	if even:
		options.append_array(DialoguePools.fill("confessional", pool_kind, "even", tokens))
	# Detail-threaded buckets: fill() already drops them when the token is
	# absent, so these appends are no-ops on a detail-less draw.
	for threaded_bucket in ["partner", "lost", "enemy"]:
		options.append_array(DialoguePools.fill("confessional", pool_kind, threaded_bucket, tokens))

	if options.is_empty():
		return "No comment. ...Okay, maybe a little comment."
	var line: String = options[randi() % options.size()]
	if options.size() > 1 and line == str(_last_heuristic.get(kind, "")):
		line = options[randi() % options.size()]
	_last_heuristic[kind] = line
	return line


func _host_line(kind: String, event_text: String) -> String:
	# Used when a would-be confessional has no living speaker. Event text for
	# agent-directed kinds is second-person, so those need a host rewrite.
	match kind:
		"tragedy":
			return "And just like that, the office says goodbye to one of its own."
		"romance":
			return "Love finds a way around here. It always does."
		"rivalry":
			return "Lines have been drawn. Nobody's staying neutral for long."
		_:
			return event_text  # narrative_event text is already third-person


func _host_recap(day: int, drama: float) -> String:
	var options: Array[String]
	if drama >= 7.0:
		options = [
			"Previously on the office: tensions boiling over. Day %d — someone's going to crack." % day,
			"Day %d. The gloves are off, the alliances are shaky, and nobody's safe." % day,
		]
	elif drama >= 4.0:
		options = [
			"Day %d. Something's simmering under the surface. You can feel it." % day,
			"Welcome to Day %d — quiet on top, chaos underneath." % day,
		]
	else:
		options = [
			"Day %d. Calm before the storm? We'll see." % day,
			"Another day at the office. Day %d — deceptively peaceful." % day,
		]
	return options[randi() % options.size()]
