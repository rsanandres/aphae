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
const HOST_RECAP_MIN_DAYS := 2   # don't recap before this day
const PENDING_TIMEOUT := 20.0    # give up on a stalled LLM request rather than jam the feed
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
		_emit(kind, _heuristic_line(kind, speaker), speaker)


func _request_llm(kind: String, event_text: String, speaker: Node2D) -> void:
	var profile: PersonalityProfile = speaker.personality
	if profile == null:
		_emit(kind, _heuristic_line(kind, speaker), speaker)
		return

	var quirks_line := ""
	if not profile.quirks.is_empty():
		quirks_line = "Your quirks: %s." % ", ".join(profile.quirks)

	var prompt := PromptBuilder.build("confessional", {
		"name": speaker.agent_name,
		"personality": profile.get_personality_summary(),
		"speech_style": profile.speech_style if profile.speech_style != "" else "casual",
		"quirks_line": quirks_line,
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
			line = _clean(str(data["line"]))
		if line == "":
			line = _heuristic_line(captured_kind, captured_speaker)
		_emit(captured_kind, line, captured_speaker)
	, LLMManager.Priority.LOW)


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

	_cooldown = COOLDOWN
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


func _clean(raw: String) -> String:
	var s := raw.strip_edges()
	# Strip wrapping quotes the model sometimes adds despite instructions.
	if s.length() >= 2 and (s[0] == '"' or s[0] == "'") and s[s.length() - 1] == s[0]:
		s = s.substr(1, s.length() - 2).strip_edges()
	return s


# --- Heuristic fallback ----------------------------------------------------
## Personality-flavored canned lines so the feature is fun with the LLM off.

func _heuristic_line(kind: String, speaker: Node2D) -> String:
	var p: PersonalityProfile = speaker.personality
	var catty := p != null and p.agreeableness < 0.4
	var anxious := p != null and p.neuroticism > 0.6
	var bold := p != null and p.extraversion > 0.6

	var options: Array[String] = []
	match kind:
		"romance":
			options = [
				"Honestly? I did not see that coming. But I'm not mad about it.",
				"People are gonna talk. Let them talk.",
				"Is it real? Ask me again in three days.",
			]
			if anxious:
				options.append("I've replayed it a hundred times. What if it all falls apart?")
			if bold:
				options.append("I make things happen. This place needed a little heat.")
		"tragedy":
			options = [
				"You never think it'll actually happen. And then it does.",
				"We weren't close, but... the office feels different now.",
				"I keep expecting them to walk back in.",
			]
			if anxious:
				options.append("I can't stop thinking about it. Who's next?")
		"rivalry":
			options = [
				"They started it. We're just going to finish it.",
				"May the best team win. It'll be us.",
				"There's us, and there's them. Pick a side.",
			]
			if catty:
				options.append("Bless their hearts. They really think they stand a chance.")
			if bold:
				options.append("Bring it. I've been waiting for a reason.")
		_:  # generic drama
			options = [
				"You can't make this stuff up. Except, well, here we are.",
				"I'm just here to do my job. The chaos finds me.",
				"Every day something new. I need a vacation.",
			]
			if catty:
				options.append("I'm not saying I told you so. But I told you so.")
			if anxious:
				options.append("My stomach's been in knots all day. Something's off.")

	if options.is_empty():
		return "No comment. ...Okay, maybe a little comment."
	return options[randi() % options.size()]


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
