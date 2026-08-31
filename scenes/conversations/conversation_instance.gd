class_name ConversationInstance
extends Node
## Manages a single 2-agent conversation: turn-taking, LLM calls, speech bubbles.

signal conversation_finished(agent_a_name: String, agent_b_name: String)

var agent_a: Node2D  # initiator
var agent_b: Node2D
var _history: Array[Dictionary] = []  # [{speaker, line}]
var _current_turn: int = 0
var _max_turns: int = 4
var _is_confession: bool = false
var _waiting_for_response: bool = false
var _line_timer: float = 0.0
var _showing_line: bool = false
var _name_a: String = ""
var _name_b: String = ""
var _aborted: bool = false


func start(a: Node2D, b: Node2D, confession: bool = false) -> void:
	agent_a = a
	agent_b = b
	# Held separately so the conversation can still clean up after itself
	# once one of these nodes no longer exists.
	_name_a = a.agent_name
	_name_b = b.agent_name
	_is_confession = confession
	_max_turns = 2 if confession else Config.CONVERSATION_TURNS
	# Both agents enter talking state
	agent_a.enter_talking_state()
	agent_b.enter_talking_state()
	EventBus.conversation_started.emit(agent_a.agent_name, agent_b.agent_name)
	# Start first turn
	_request_next_line()


func _participants_valid() -> bool:
	return is_instance_valid(agent_a) and is_instance_valid(agent_b)


func _abort() -> void:
	## Somebody died, departed, or was removed mid-conversation. Before this
	## existed the instance threw on its first dereference and never emitted
	## conversation_finished — so ConversationManager kept the survivor
	## flagged "in conversation" for the rest of the run (they could never
	## speak again), and AudioManager's murmur refcount never came back down.
	if _aborted:
		return
	_aborted = true
	for agent in [agent_a, agent_b]:
		if is_instance_valid(agent) and not agent.is_dead and agent.has_method("exit_talking_state"):
			agent.exit_talking_state()
	EventBus.conversation_ended.emit(_name_a, _name_b)
	conversation_finished.emit(_name_a, _name_b)
	queue_free()


func _process(delta: float) -> void:
	if _aborted:
		return
	if not _participants_valid():
		_abort()
		return
	if _showing_line:
		# Conversations advance on game time too — otherwise a chat that
		# takes 30 real seconds eats 30 game-minutes at 1x but 90 at 3x,
		# starving both agents of the day.
		_line_timer -= delta * TimeManager.current_speed
		if _line_timer <= 0.0:
			_showing_line = false
			_current_turn += 1
			if _current_turn >= _max_turns * 2:  # Each turn has 2 speakers
				_end_conversation()
			else:
				_request_next_line()


func _request_next_line() -> void:
	if _waiting_for_response:
		return
	var speaker := agent_a if _current_turn % 2 == 0 else agent_b
	var listener := agent_b if _current_turn % 2 == 0 else agent_a

	if not LLMManager.is_available:
		# Heuristic fallback — with one reroll if the exact line was already
		# said this conversation (a ~1-in-5 event that reads as a glitch).
		var line := _heuristic_line(speaker, listener)
		for entry in _history:
			if entry["line"] == line:
				line = _heuristic_line(speaker, listener)
				break
		_on_line_received(speaker, listener, line)
		return

	_waiting_for_response = true
	var template_name := "confession" if (_is_confession and _current_turn < 2) else "conversation"
	var history_text := _format_history()
	var rel: RelationshipEntry = speaker.relationships.get_relationship(listener.agent_name)

	var prompt := PromptBuilder.build(template_name, {
		"name": speaker.agent_name,
		"description": speaker.personality.description if speaker.personality else "",
		"personality": speaker.personality.get_personality_summary() if speaker.personality else "",
		"speech_style": speaker.personality.speech_style if speaker.personality else "",
		"other_name": listener.agent_name,
		"other_description": listener.personality.description if listener.personality else "",
		"relationship": rel.get_summary(),
		"affinity": "%.0f" % rel.affinity,
		"history": history_text,
		"mood": speaker.personality.get_mood(speaker.needs.get_all_values()) if speaker.personality else "neutral",
		# Both resolve to "" for agents with nothing to hide or no rumor heard,
		# so the placeholders always disappear from the template.
		"secret_line": SecretManager.denial_prompt_line(speaker.agent_name),
		"gossip_line": SecretManager.gossip_prompt_line(speaker.agent_name, listener.agent_name),
	})

	var format_schema := {
		"type": "object",
		"properties": {
			"line": {"type": "string"},
		},
		"required": ["line"],
	}

	LLMManager.request_chat(
		[{"role": "user", "content": prompt}],
		format_schema,
		func(success: bool, data: Dictionary, _error: String) -> void:
			_waiting_for_response = false
			var line := ""
			if success and data.has("line"):
				line = LLMSanitizer.clean_line(str(data["line"]))
			if line != "":
				_on_line_received(speaker, listener, line)
			else:
				_on_line_received(speaker, listener, _heuristic_line(speaker, listener)),
		LLMManager.Priority.HIGH,
	)


func _on_line_received(speaker: Node2D, _listener: Node2D, line: String) -> void:
	if not is_instance_valid(speaker) or not _participants_valid():
		_abort()
		return
	_history.append({"speaker": speaker.agent_name, "line": line})
	speaker.show_speech(line, Config.CONVERSATION_LINE_DURATION, _tone(speaker, _listener))
	EventBus.conversation_line.emit(speaker.agent_name, line)
	_showing_line = true
	_line_timer = Config.CONVERSATION_LINE_DURATION + 0.5


func _tone(speaker: Node2D, listener: Node2D) -> String:
	## How this exchange should read at a glance: romantic pink, hostile red,
	## or neutral. Derived from the pair's relationship, not the line text —
	## reliable with or without an LLM.
	if _is_confession:
		return "romantic"
	var rel: RelationshipEntry = speaker.relationships.get_relationship(listener.agent_name)
	if rel.relationship_status == RelationshipEntry.Status.DATING \
			or rel.relationship_status == RelationshipEntry.Status.PARTNERS \
			or rel.romantic_interest > 40.0:
		return "romantic"
	if rel.affinity < -20.0:
		return "hostile"
	return ""


func _end_conversation() -> void:
	if not _participants_valid():
		_abort()
		return
	# Capture affinity before the relationship update so the outcome can be
	# shown at the scene as a floating delta.
	var before_ab: float = agent_a.relationships.get_relationship(agent_b.agent_name).affinity
	var before_ba: float = agent_b.relationships.get_relationship(agent_a.agent_name).affinity

	# Store conversation as memory for both agents
	var convo_summary := _summarize_conversation()
	agent_a.memory.add_conversation(
		"%s had a conversation with %s: %s" % [agent_a.agent_name, agent_b.agent_name, convo_summary],
		agent_b.agent_name, 5.0
	)
	agent_b.memory.add_conversation(
		"%s had a conversation with %s: %s" % [agent_b.agent_name, agent_a.agent_name, convo_summary],
		agent_a.agent_name, 5.0
	)

	# Update relationships
	agent_a.relationships.update_after_interaction(agent_b.agent_name, convo_summary, true)
	agent_b.relationships.update_after_interaction(agent_a.agent_name, convo_summary, true)

	# WHERE the conversation happened matters: SynergyManager zones with a
	# social block scale the romance/gossip rolls at the pair's midpoint.
	# (Confide scaling lives inside SecretManager itself.)
	var zone_mid: Vector2 = (agent_a.global_position + agent_b.global_position) / 2.0
	var romance_scale: float = SynergyManager.social_multiplier(zone_mid, "romance")
	var gossip_scale: float = SynergyManager.social_multiplier(zone_mid, "gossip")

	# Good conversations slowly kindle romance (compatibility-weighted)
	agent_a.relationships.update_romance(agent_b.agent_name, true, romance_scale)
	agent_b.relationships.update_romance(agent_a.agent_name, true, romance_scale)

	# Gossip travels: each side may pass on something juicy about a third
	# party, secondhand and slightly warped (RumorMill).
	RumorMill.maybe_pass(agent_a, agent_b, gossip_scale)
	RumorMill.maybe_pass(agent_b, agent_a, gossip_scale)

	# Secrets move too: a holder may confide in someone trusted, and someone
	# who already knows may needle the holder. Mechanics only — the spoken
	# lines above were flavor (SecretManager, M7).
	SecretManager.process_conversation_end(agent_a, agent_b)

	# Restore social need
	agent_a.needs.restore(NeedType.Type.SOCIAL, 20.0)
	agent_b.needs.restore(NeedType.Type.SOCIAL, 20.0)

	# One glance tells you how it went: ♥ +4 rising over the scene, or ✕ -6.
	var after_ab: float = agent_a.relationships.get_relationship(agent_b.agent_name).affinity
	var after_ba: float = agent_b.relationships.get_relationship(agent_a.agent_name).affinity
	var delta := ((after_ab - before_ab) + (after_ba - before_ba)) / 2.0
	if absf(delta) >= 1.0 and not _is_confession:
		var world := agent_a.get_tree().get_first_node_in_group("world")
		var mid: Vector2 = (agent_a.global_position + agent_b.global_position) / 2.0
		if delta > 0.0:
			FloatingText.spawn(world, mid, "<3 +%d" % roundi(delta), Color(1.0, 0.55, 0.7))
		else:
			FloatingText.spawn(world, mid, "x %d" % roundi(delta), Color(1.0, 0.45, 0.4))

	# Handle confession outcome
	if _is_confession:
		_process_confession()

	# Request reflection from LLM
	_request_reflection(agent_a, agent_b)
	_request_reflection(agent_b, agent_a)

	# Exit talking state
	agent_a.exit_talking_state()
	agent_b.exit_talking_state()

	EventBus.conversation_ended.emit(agent_a.agent_name, agent_b.agent_name)
	conversation_finished.emit(agent_a.agent_name, agent_b.agent_name)
	queue_free()


func _process_confession() -> void:
	var rel_b: RelationshipEntry = agent_b.relationships.get_relationship(agent_a.agent_name)
	var accepted: bool = rel_b.romantic_interest > 40.0
	EventBus.confession_made.emit(agent_a.agent_name, agent_b.agent_name, accepted)
	var world := agent_a.get_tree().get_first_node_in_group("world")
	var mid: Vector2 = (agent_a.global_position + agent_b.global_position) / 2.0
	if accepted:
		FloatingText.spawn(world, mid, "<3 <3 <3", Color(1.0, 0.55, 0.7))
	else:
		FloatingText.spawn(world, mid + Vector2(0, -8), "<3 . . .", Color(0.75, 0.6, 0.65))
	if accepted:
		var rel_a: RelationshipEntry = agent_a.relationships.get_relationship(agent_b.agent_name)
		rel_a.relationship_status = RelationshipEntry.Status.DATING
		rel_b.relationship_status = RelationshipEntry.Status.DATING
		rel_a.add_tag("partner")
		rel_b.add_tag("partner")
		EventBus.romance_started.emit(agent_a.agent_name, agent_b.agent_name)
		EventBus.narrative_event.emit(
			"%s confessed feelings to %s, and they started dating!" % [agent_a.agent_name, agent_b.agent_name],
			[agent_a.agent_name, agent_b.agent_name], 9.0
		)
		agent_a.memory.add_memory(MemoryEntry.MemoryType.CONVERSATION,
			"%s confessed feelings to %s and they accepted! They are now dating." % [agent_a.agent_name, agent_b.agent_name],
			10.0, PackedStringArray([agent_b.agent_name]))
		agent_b.memory.add_memory(MemoryEntry.MemoryType.CONVERSATION,
			"%s confessed their feelings, and %s said yes! They are now dating." % [agent_a.agent_name, agent_b.agent_name],
			10.0, PackedStringArray([agent_a.agent_name]))
	else:
		EventBus.narrative_event.emit(
			"%s confessed feelings to %s, but was rejected." % [agent_a.agent_name, agent_b.agent_name],
			[agent_a.agent_name, agent_b.agent_name], 7.0
		)
		agent_a.memory.add_memory(MemoryEntry.MemoryType.CONVERSATION,
			"%s confessed feelings to %s but was rejected. This is heartbreaking." % [agent_a.agent_name, agent_b.agent_name],
			9.0, PackedStringArray([agent_b.agent_name]))


func _request_reflection(agent: Node2D, other: Node2D) -> void:
	if not LLMManager.is_available:
		return
	var rel: RelationshipEntry = agent.relationships.get_relationship(other.agent_name)
	var prompt: String
	if rel.romantic_interest > 30.0 or rel.relationship_status != RelationshipEntry.Status.NONE:
		# Romance is brewing: reflect through the romantic template instead.
		prompt = PromptBuilder.build("romantic_reflect", {
			"name": agent.agent_name,
			"personality": agent.personality.get_personality_summary() if agent.personality else "",
			"relationships": "%s: %s" % [other.agent_name, rel.get_summary()],
		})
	else:
		prompt = PromptBuilder.build("conversation_reflect", {
			"name": agent.agent_name,
			"other_name": other.agent_name,
			"relationship": rel.get_summary(),
			"conversation_summary": _summarize_conversation(),
			"personality": agent.personality.get_personality_summary() if agent.personality else "",
		})
	var format_schema := {
		"type": "object",
		"properties": {
			"feeling": {"type": "string"},
			"opinion_change": {"type": "string"},
		},
		"required": ["feeling"],
	}
	LLMManager.request_chat(
		[{"role": "user", "content": prompt}],
		format_schema,
		func(success: bool, data: Dictionary, _error: String) -> void:
			if success:
				var feeling: String = data.get("feeling", "")
				if feeling != "":
					agent.memory.add_reflection(
						"%s reflects on conversation with %s: %s" % [agent.agent_name, other.agent_name, feeling]
					),
		LLMManager.Priority.LOW,
	)


func _summarize_conversation() -> String:
	if _history.is_empty():
		return "a brief exchange"
	var parts: PackedStringArray = []
	var limit := mini(3, _history.size())
	for i in range(limit):
		parts.append("%s said '%s'" % [_history[i]["speaker"], _history[i]["line"]])
	return "; ".join(parts)


func _format_history() -> String:
	if _history.is_empty():
		return "(conversation just started)"
	var lines: PackedStringArray = []
	for entry in _history:
		lines.append("%s: %s" % [entry["speaker"], entry["line"]])
	return "\n".join(lines)


func _heuristic_line(speaker: Node2D, listener: Node2D) -> String:
	var rel: RelationshipEntry = speaker.relationships.get_relationship(listener.agent_name)
	var s_name: String = speaker.agent_name
	var l_name: String = listener.agent_name

	# --- Confession lines (expanded) ---
	if _is_confession and _current_turn == 0:
		var pool: Array[String] = [
			"I've been meaning to tell you something... I really like you, %s." % l_name,
			"I can't stop thinking about you, %s. I think I have feelings for you." % l_name,
			"%s, this is hard to say, but... I've developed feelings for you." % l_name,
			"I know this might change things between us, but %s... I like you. A lot." % l_name,
			"Every time I see you, %s, my heart does this stupid thing. I had to tell you." % l_name,
			"I've been going back and forth about this, but... %s, I have a crush on you." % l_name,
			"Okay, deep breath. %s, I think about you way more than a coworker should." % l_name,
			"I wrote this down so I wouldn't chicken out. %s, I have feelings for you." % l_name,
		]
		return pool[randi() % pool.size()]

	if _is_confession and _current_turn == 1:
		if rel.romantic_interest > 40.0:
			var pool: Array[String] = [
				"I... I feel the same way about you, %s." % s_name,
				"Really? I've been hoping you'd say that!",
				"You have no idea how long I've wanted to hear that, %s." % s_name,
				"I thought it was just me! Yes, %s, I feel it too." % s_name,
				"My heart is racing right now. I like you too, %s." % s_name,
				"I've been dropping hints for weeks! Yes, absolutely yes.",
				"I can't stop smiling. I feel exactly the same way.",
				"You just made my whole week, %s. I like you too." % s_name,
			]
			return pool[randi() % pool.size()]
		else:
			var pool: Array[String] = [
				"I appreciate you telling me, but I don't feel that way.",
				"That's really sweet, but I think we're better as friends.",
				"Oh, %s... I care about you, but not like that. I'm sorry." % s_name,
				"I'm flattered, honestly. But I don't have those feelings.",
				"That took courage, and I respect that. But I can't return those feelings.",
				"I wish I felt the same, %s. You deserve someone who does." % s_name,
				"I think you're great, but my heart's just not there. I'm sorry.",
				"I don't want to hurt you, but I have to be honest. I see you as a friend.",
			]
			return pool[randi() % pool.size()]

	# --- Secrets flavor (M7): the mechanics run at wrap-up in SecretManager;
	# these lines just make the tension audible on the floor. ---
	if SecretManager.knows(s_name, l_name) and SecretManager.has_hidden_secret(l_name) and randf() < 0.3:
		var probe_pool: Array[String] = [
			"People talk, %s. You'd be surprised what I hear." % l_name,
			"So... anything you want to tell me, %s?" % l_name,
			"You've seemed a little cagey lately, %s. Just saying." % l_name,
			"Funny — someone mentioned your name the other day. Interesting stuff.",
		]
		return probe_pool[randi() % probe_pool.size()]
	if SecretManager.has_hidden_secret(s_name) and randf() < 0.15:
		var deflect_pool: Array[String] = [
			"Anyway — how about literally anything else.",
			"Ha. Why do you ask? Who's asking? Nobody's asking.",
			"I'm fine. Everything's fine. Great quarter, right?",
			"Let's change the subject. For no reason. Just variety.",
		]
		return deflect_pool[randi() % deflect_pool.size()]

	# --- Parametric helpers ---
	var quirk: String = _random_from_array(speaker.personality.quirks) if speaker.personality and not speaker.personality.quirks.is_empty() else ""
	var goal: String = _random_from_array(speaker.personality.goals) if speaker.personality and not speaker.personality.goals.is_empty() else ""
	var l_quirk: String = _random_from_array(listener.personality.quirks) if listener.personality and not listener.personality.quirks.is_empty() else ""

	var hour: int = TimeManager.hours
	var time_greeting: String = "Morning" if hour < 12 else ("Afternoon" if hour < 17 else "Evening")
	var is_late: bool = hour >= 20 or hour < 6

	# --- Memory-driven lines (20% chance: reference a recent memory) ---
	if speaker.memory and randf() < 0.2:
		var recent: Array = speaker.memory.get_recent(3)
		if not recent.is_empty():
			var mem: MemoryEntry = recent[randi() % recent.size()]
			var mem_line := _memory_driven_line(s_name, l_name, mem)
			if mem_line != "":
				return mem_line

	# --- Personality-driven lines (25% chance: trait-specific dialogue) ---
	if speaker.personality and randf() < 0.25:
		var trait_line := _personality_driven_line(speaker, listener, s_name, l_name)
		if trait_line != "":
			return trait_line

	# --- Behavior modifier lines (mourning, avoidance) ---
	if speaker.has_method("get_active_modifiers"):
		var mods: Array = speaker.get_active_modifiers()
		for mod in mods:
			if mod.get("type", "") == "mourning" and randf() < 0.5:
				return _mourning_line(s_name, l_name, mod.get("target", "someone"))

	# --- Need-based lines (40% chance if any need is critical) ---
	var energy_val: float = speaker.needs.get_value(NeedType.Type.ENERGY)
	var hunger_val: float = speaker.needs.get_value(NeedType.Type.HUNGER)
	var productivity_val: float = speaker.needs.get_value(NeedType.Type.PRODUCTIVITY)

	var need_pools: Array[Array] = []
	if energy_val < 30.0:
		need_pools.append(_get_tired_lines(s_name, l_name))
	if hunger_val < 30.0:
		need_pools.append(_get_hungry_lines(s_name, l_name))
	if productivity_val < 30.0:
		need_pools.append(_get_stressed_lines(s_name, l_name, goal))

	if not need_pools.is_empty() and randf() < 0.4:
		var chosen_pool: Array = need_pools[randi() % need_pools.size()]
		return _apply_substitutions(chosen_pool[randi() % chosen_pool.size()], s_name, l_name, quirk, goal, l_quirk, time_greeting)

	# --- Romantic lines (romantic_interest > 40 OR dating/partners) ---
	var is_romantic: bool = rel.romantic_interest > 40.0 or rel.relationship_status == RelationshipEntry.Status.DATING or rel.relationship_status == RelationshipEntry.Status.PARTNERS
	if is_romantic:
		var pool: Array[String] = _get_romantic_lines(s_name, l_name, is_late)
		return _apply_substitutions(pool[randi() % pool.size()], s_name, l_name, quirk, goal, l_quirk, time_greeting)

	# --- Relationship-tier lines ---
	var pool: Array[String] = []
	if rel.affinity > 30.0:
		pool = _get_positive_lines(s_name, l_name, quirk, goal, l_quirk, time_greeting)
	elif rel.affinity < -20.0:
		pool = _get_negative_lines(s_name, l_name)
	else:
		pool = _get_neutral_lines(s_name, l_name, time_greeting, is_late)

	return _apply_substitutions(pool[randi() % pool.size()], s_name, l_name, quirk, goal, l_quirk, time_greeting)


func _random_from_array(arr: Array) -> String:
	if arr.is_empty():
		return ""
	return str(arr[randi() % arr.size()])


func _apply_substitutions(line: String, s_name: String, l_name: String, quirk: String, goal: String, l_quirk: String, time_greeting: String) -> String:
	# Replace parametric tokens with actual values
	line = line.replace("{speaker}", s_name)
	line = line.replace("{listener}", l_name)
	line = line.replace("{quirk}", quirk if quirk != "" else "that thing I do")
	line = line.replace("{goal}", goal if goal != "" else "what I'm working toward")
	line = line.replace("{l_quirk}", l_quirk if l_quirk != "" else "your thing")
	line = line.replace("{greeting}", time_greeting)
	line = line.replace("{time}", TimeManager.time_string)
	return line


func _get_tired_lines(_s_name: String, l_name: String) -> Array:
	var pool: Array[String] = [
		"*yawns* Sorry, {listener}. I'm running on fumes today.",
		"I could really use a nap right now, not gonna lie.",
		"Is it just me or is this day lasting forever?",
		"I think I need another coffee... or maybe three.",
		"My eyes keep closing on their own. How are you so awake, {listener}?",
		"I barely slept last night. Everything is a blur.",
		"If I fall asleep mid-sentence, just... let it happen.",
		"I need to find that couch before I collapse at my desk.",
		"*stifles a yawn* What were we talking about?",
		"I've hit a wall, {listener}. A big, soft, sleepy wall.",
		"I'm basically a zombie right now. Be gentle.",
		"You know that feeling where your brain just... stops? That's me right now.",
		"Can we talk sitting down? Standing is... a lot right now.",
		"I think the couch is calling my name. Do you hear it too?",
		"Every blink is a micro-nap at this point.",
		"I wonder if anyone would notice if I napped under my desk.",
		"My energy level is somewhere between 'depleted' and 'nonexistent'.",
		"*rubs eyes* Sorry, you were saying something, {listener}?",
	]
	return pool


func _get_hungry_lines(_s_name: String, l_name: String) -> Array:
	var pool: Array[String] = [
		"Is it lunchtime yet? I'm starving.",
		"I can't focus on anything except food right now.",
		"My stomach just growled so loud I think the whole office heard it.",
		"Want to grab something to eat, {listener}? I'm desperate.",
		"I skipped breakfast and I'm paying the price.",
		"I keep thinking about what's in the break room fridge.",
		"If someone doesn't feed me soon, I might get cranky. Well, crankier.",
		"Do you have any snacks? I will trade you literally anything.",
		"I'm so hungry I'd eat whatever's been in the microwave for a week.",
		"My brain has been replaced by a single thought: food.",
		"*stomach growls* ...pretend you didn't hear that.",
		"I think I could eat an entire pizza by myself right now.",
		"Who decided we only get one lunch break? I need at least three.",
		"Have you tried the coffee machine snacks? Asking for a very hungry friend.",
		"I've been staring at my screen but all I see is sandwiches.",
		"Fun fact, {listener}: I get progressively more useless when hungry. We're at stage four.",
		"I would sell my desk for a burrito right now.",
		"Is it weird that I keep smelling food that isn't there?",
	]
	return pool


func _get_stressed_lines(_s_name: String, _l_name: String, _goal: String) -> Array:
	var pool: Array[String] = [
		"I'm so behind on everything. The deadlines are piling up.",
		"I feel like I haven't accomplished anything productive all day.",
		"There's this project I keep putting off and it's eating at me.",
		"I really need to buckle down and get some work done.",
		"Does it ever feel like the to-do list just keeps growing, {listener}?",
		"I'm stressed about {goal}. It's all I can think about.",
		"My productivity today has been absolutely abysmal.",
		"I should be working right now but my brain won't cooperate.",
		"The pressure is really getting to me today.",
		"I keep staring at my tasks and none of them are getting done.",
		"Have you ever had one of those days where nothing goes right? That's today.",
		"I think I need to step back and reprioritize. Everything feels urgent.",
		"I'm falling behind and it's stressing me out, {listener}.",
		"My desk is covered in notes and I can't make sense of any of them.",
		"I need a plan. Or a miracle. Either works.",
		"I keep switching between tasks and finishing none of them.",
		"If I don't make progress on {goal} soon, I'm going to lose it.",
		"It's that kind of day where the coffee isn't strong enough and the clock isn't fast enough.",
	]
	return pool


func _get_romantic_lines(_s_name: String, l_name: String, is_late: bool) -> Array[String]:
	var pool: Array[String] = [
		"Hey you. I was hoping I'd run into you today, {listener}.",
		"You look really nice today, {listener}. Just thought you should know.",
		"I always feel better when you're around, {listener}.",
		"I saved you a spot by the coffee machine. Your usual, right?",
		"Every time you walk by, I completely forget what I was doing.",
		"I keep finding excuses to come talk to you. Is it obvious?",
		"You know what I like about you, {listener}? Everything. I like everything.",
		"I had this dream about us last night. It was... nice.",
		"My favorite part of the day is whenever I get to see you.",
		"I made you something. It's just a doodle, but... I was thinking of you.",
		"You make even the boring parts of office life feel special, {listener}.",
		"I catch myself smiling every time you laugh. It's embarrassing, honestly.",
		"Want to sneak out for a walk later? Just the two of us.",
		"I brought extra snacks today. The good kind. For you, obviously.",
		"Is it cheesy if I say I missed you? Because I kind of did.",
		"Nobody else in this office makes me feel the way you do, {listener}.",
		"I keep replaying our last conversation in my head. Is that weird?",
		"I wrote your name in my notebook margin. Very subtle, I know.",
		"When you smile like that, {listener}, the whole room gets brighter.",
		"I'm not great with words, but... being with you feels like home.",
	]
	if is_late:
		pool.append("It's late. Walk back together? I'd feel better knowing you're okay.")
		pool.append("The office is so quiet at night. I'm glad you're still here, {listener}.")
		pool.append("We should head out soon. But I'm not ready to stop talking to you.")
	return pool


func _get_positive_lines(s_name: String, l_name: String, quirk: String, goal: String, l_quirk: String, time_greeting: String) -> Array[String]:
	var pool: Array[String] = [
		"Hey {listener}! {greeting}! How's everything going?",
		"I've been meaning to catch up with you, {listener}. It's been a while!",
		"You know, working with you makes the tough days easier, {listener}.",
		"I had this idea I wanted to run by you, {listener}. Got a minute?",
		"Want to grab some coffee later, {listener}? My treat.",
		"I was just thinking about that thing you said the other day. You were so right.",
		"Remember when we worked on that project together? Good times, {listener}.",
		"You always know how to lighten the mood, {listener}. I appreciate that.",
		"I trust your judgment on stuff like this, {listener}. What do you think?",
		"I heard something funny and immediately thought of you, {listener}.",
		"You've been doing great work lately, {listener}. Seriously impressive.",
		"Hey {listener}, thanks for always being supportive. It means a lot.",
		"I feel like we make a really good team, {listener}.",
		"Got any plans this weekend, {listener}? We should hang out!",
		"That was a brilliant point you made in the meeting, {listener}.",
		"I love that you're someone who {l_quirk}. Don't ever stop.",
		"You always have such interesting things to say, {listener}. Tell me more.",
		"I'm working on {goal} and I'd love your input, {listener}.",
		"Not gonna lie, talking to you is the highlight of my day sometimes.",
		"You ever notice how we always end up chatting? I'm not complaining.",
		"I brought snacks. Want some, {listener}? I got your favorite.",
		"I keep meaning to say this: you're a really good friend, {listener}.",
		"Can I be honest? I'm glad you're on this team, {listener}.",
		"I just wanted to check in. How are you really doing, {listener}?",
		"If I'm ever stuck on something, you're the first person I think to ask.",
	]
	return pool


func _get_negative_lines(_s_name: String, l_name: String) -> Array[String]:
	var pool: Array[String] = [
		"Oh. It's you.",
		"Hmm.",
		"I suppose.",
		"Let's keep this brief.",
		"What do you want, {listener}?",
		"Can this wait? I'm busy.",
		"I'd rather not, but fine. What is it?",
		"Sure. Whatever you say.",
		"...right.",
		"Is this going to take long?",
		"I have things to do, {listener}.",
		"That's... one way to look at it.",
		"Must we do this right now?",
		"I'll keep my thoughts to myself on that one.",
		"How nice for you.",
		"Fascinating. Truly.",
		"I'm going to pretend I didn't hear that.",
		"We clearly see things differently.",
		"Look, I'd love to chat but actually no I wouldn't.",
		"Some of us have actual work to do.",
		"I see you're still... like that.",
		"Are we done here?",
		"Noted. Moving on.",
		"You and I never seem to agree on anything.",
		"I'll smile and nod. That's the best I can offer right now.",
	]
	return pool


func _get_neutral_lines(_s_name: String, l_name: String, time_greeting: String, is_late: bool) -> Array[String]:
	var pool: Array[String] = [
		"Hey there, {listener}.",
		"How's it going?",
		"Nice weather today, don't you think?",
		"Back to work, I guess.",
		"{greeting}, {listener}. Getting much done today?",
		"Have you tried the coffee today? It's... something.",
		"Another day at the office, huh?",
		"I keep losing track of time. Is it really {time} already?",
		"The office is kind of quiet today, isn't it?",
		"Did you see the new thing on the whiteboard? Interesting stuff.",
		"I've been meaning to reorganize my desk. One of these days.",
		"Any exciting plans for after work, {listener}?",
		"I think someone left something in the microwave again.",
		"How long have you been working here, {listener}? Feels like forever sometimes.",
		"I wonder what's for lunch. Do you meal prep, {listener}?",
		"This chair is killing my back. Is yours comfortable?",
		"I read something interesting this morning but I already forgot what it was.",
		"Do you ever zone out and then realize twenty minutes have passed?",
		"The plant by the window is looking rough. Someone should water it.",
		"Oh hey, {listener}. Didn't see you there.",
		"I've been going back and forth on something. Nothing major, just life stuff.",
		"Is it just me or do weeks go faster the longer you work here?",
		"I'm trying to decide if I need more coffee or less coffee.",
		"That clock can't be right. There's no way it's {time}.",
		"Some days are just... days, you know? This is one of those.",
	]
	if is_late:
		pool.append("Working late again? We should probably both go home, {listener}.")
		pool.append("The office is kind of eerie this late. You're braver than I am, {listener}.")
	return pool


func _memory_driven_line(s_name: String, l_name: String, mem: MemoryEntry) -> String:
	## Reference a recent memory — but only one that survives being SPOKEN.
	## Splicing raw memory prose produced bubbles like "remember when hugo had
	## a conversation with dex: hugo said 'i...? That was something." — a
	## playtester's single worst line in the game. Colons mean transcripts or
	## quotes (unspeakable); mid-sentence truncation reads as machine output;
	## and lowercasing mangled proper names. Unusable memory -> return "" and
	## let the normal pools handle the turn.
	if mem.type == MemoryEntry.MemoryType.CONVERSATION:
		return ""
	var desc: String = mem.description
	if ":" in desc or desc.length() > 70:
		return ""
	# Third-person memories start with the speaker's own name; make them
	# first-person instead of quoting themselves ("I keep thinking about
	# Hugo used the couch" -> "...about that time I used the couch").
	if desc.begins_with(s_name + " "):
		desc = "that time I " + desc.substr(s_name.length() + 1)
	desc = desc.trim_suffix(".")

	var templates: Array[String] = [
		"You know, I keep thinking about %s." % desc,
		"I can't get it out of my head — %s." % desc,
		"This reminds me... %s." % desc,
	]
	if mem.emotion != "" and mem.emotion != "neutral":
		templates.append("I'm still feeling %s about it — %s." % [mem.emotion, desc])
	return templates[randi() % templates.size()]


func _personality_driven_line(speaker: Node2D, listener: Node2D, s_name: String, l_name: String) -> String:
	## Generate a line driven by the speaker's dominant personality trait.
	var p: PersonalityProfile = speaker.personality
	if not p:
		return ""

	# Find dominant trait
	var traits := {
		"openness": p.openness,
		"conscientiousness": p.conscientiousness,
		"extraversion": p.extraversion,
		"agreeableness": p.agreeableness,
		"neuroticism": p.neuroticism,
	}
	var max_trait: String = ""
	var max_val: float = 0.0
	for t in traits:
		if traits[t] > max_val:
			max_val = traits[t]
			max_trait = t

	match max_trait:
		"openness":
			var pool: Array[String] = [
				"I had the most fascinating idea last night, %s. Want to hear it?" % l_name,
				"Have you ever wondered why things are the way they are?",
				"I've been reading about something really interesting. It's about...",
				"Sometimes I think we should completely rethink how this office works.",
				"I love learning new things. Did you know...",
				"What if we tried something completely different today?",
				"I saw something beautiful on my way here. It made me think.",
			]
			return pool[randi() % pool.size()]
		"conscientiousness":
			var pool: Array[String] = [
				"I've got my whole day planned out. Want to see my list?",
				"Staying organized is the key to everything, %s." % l_name,
				"I finished my tasks early today. Now onto the bonus list.",
				"Have you met your goals for today, %s?" % l_name,
				"I can't relax until everything on my desk is sorted.",
				"Discipline is freedom, %s. Trust me on this." % l_name,
				"I made a spreadsheet for our project. Want a copy?",
			]
			return pool[randi() % pool.size()]
		"extraversion":
			var pool: Array[String] = [
				"I've talked to everyone today and I still want more! How are YOU, %s?" % l_name,
				"This place is so much better when everyone's chatting.",
				"Let's get the whole group together later. The more the merrier!",
				"I get so much energy from talking to people like you, %s." % l_name,
				"I was literally just looking for someone to talk to. Perfect timing!",
				"Silence makes me uncomfortable, honestly. Let's keep talking!",
				"Want to go say hi to everyone? I'll come with you!",
			]
			return pool[randi() % pool.size()]
		"agreeableness":
			var pool: Array[String] = [
				"I just want everyone to get along. Is that too much to ask?",
				"How are you really doing, %s? You can tell me anything." % l_name,
				"I noticed you seemed a bit off today. Everything okay?",
				"I baked... well, I planned to bake something for everyone. It's the thought that counts.",
				"I just think it's so important that we look out for each other.",
				"You're having a tough day? Here, take my spot by the coffee machine.",
				"I don't like conflict. Can we all just be friends?",
			]
			return pool[randi() % pool.size()]
		"neuroticism":
			var pool: Array[String] = [
				"I'm overthinking everything again. Do you think I'm doing okay?",
				"What if something goes wrong today? I have a bad feeling.",
				"Sorry, I'm a bit on edge. It's been one of those days, %s." % l_name,
				"Do you think people actually like me here? Be honest.",
				"I couldn't sleep last night. Too many thoughts racing around.",
				"I need reassurance. Tell me everything's going to be fine.",
				"I just realized I might have said something wrong earlier. Did I?",
			]
			return pool[randi() % pool.size()]
	return ""


func _mourning_line(s_name: String, l_name: String, deceased: String) -> String:
	## Lines for an agent who is mourning a death.
	var pool: Array[String] = [
		"I still can't believe %s is gone..." % deceased,
		"The office feels so different without %s." % deceased,
		"I keep looking for %s out of habit. Then I remember." % deceased,
		"Sorry, %s. I'm not great company today. Still thinking about %s." % [l_name, deceased],
		"Do you remember that thing %s used to do? I miss that." % deceased,
		"%s would have loved today. I wish they were here." % deceased,
		"I had a dream about %s last night. It felt so real." % deceased,
		"I don't know how to be okay yet, %s. Give me time." % l_name,
	]
	return pool[randi() % pool.size()]
