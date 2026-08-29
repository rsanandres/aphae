extends Node
## Player Director — the "producer" layer: the player's direct line to a person.
##
## The god toolbar reshapes the world (objects, roster, events); nothing there
## reaches an individual agent. This does, with three actions:
##
##   nudge()       suggest an action — the agent may refuse
##   interview()   ask a question, answered in character from real memories
##   plant_rumor() inject a memory, true or not
##
## Agents stay autonomous. A nudge is a suggestion weighed against personality
## and current needs, never a command — refusal is the feature, not a failure.
## Everything here goes through existing public APIs (`_execute_decision`, which
## AgentManager already drives, and `AgentMemory`), so no agent code changes.

## Suggestions the player can make, and what each one means mechanically.
const NUDGES := {
	"rest": {
		"label": "Break",
		"objects": ["couch", "bed"],
		"need": NeedType.Type.ENERGY,
		"phrasing": "take a break",
	},
	"refuel": {
		"label": "Coffee",
		"objects": ["coffee_machine", "water_cooler"],
		"need": NeedType.Type.HUNGER,
		"phrasing": "go get a coffee",
	},
	"work": {
		"label": "Work",
		"objects": ["desk", "whiteboard"],
		"need": NeedType.Type.PRODUCTIVITY,
		"phrasing": "get back to work",
	},
	"mingle": {
		"label": "Mingle",
		"objects": [],
		"need": NeedType.Type.SOCIAL,
		"phrasing": "go talk to someone",
	},
}


## Player-agency backlog #6: pin one agent as the star of the episode.
## Attention literally buys them the LLM brain — AgentManager forces their
## think tier to ACTIVE — and the camera follows them.
var star_name: String = ""


func set_star(agent: Node2D) -> bool:
	if agent == null or not is_instance_valid(agent) or agent.is_dead:
		return false
	if agent.agent_name == star_name:
		clear_star()
		return true
	star_name = agent.agent_name
	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("follow"):
		camera.follow(agent)
	EventBus.star_chosen.emit(star_name)
	EventBus.narrative_event.emit(
		"The cameras have a favorite now: %s is this episode's star." % star_name,
		[star_name], 4.0)
	return true


func clear_star() -> void:
	star_name = ""
	EventBus.star_chosen.emit("")


func get_star_save() -> Dictionary:
	return {"star": star_name}


func load_star_save(data: Dictionary) -> void:
	star_name = str(data.get("star", ""))


func get_nudge_kinds() -> Array:
	return NUDGES.keys()


# --- 1. Nudge ---------------------------------------------------------------

func nudge(agent: Node2D, kind: String) -> bool:
	## Suggest an action. Returns whether the agent complied.
	if not NUDGES.has(kind):
		push_warning("PlayerDirector: unknown nudge '%s'" % kind)
		return false
	if agent == null or not is_instance_valid(agent) or agent.is_dead:
		return false

	var spec: Dictionary = NUDGES[kind]
	var request: String = spec["phrasing"]

	# Hard refusal: mid-conversation, they simply brush you off. Interrupting a
	# conversation would strand the other agent in TALKING.
	if agent.state == AgentState.Type.TALKING:
		_refuse(agent, request, "is mid-conversation and waves you off")
		return false

	if randf() >= _compliance_chance(agent, kind):
		_refuse(agent, request, _refusal_reason(agent, kind))
		return false

	return _comply(agent, kind, spec, request)


func _compliance_chance(agent: Node2D, kind: String) -> float:
	var p: PersonalityProfile = agent.personality
	if p == null:
		return 0.5

	# Agreeableness is the spine: disagreeable agents ignore you a lot.
	var chance: float = 0.30 + p.agreeableness * 0.45

	# A conscientious agent takes a work suggestion well; a slacker resents it.
	if kind == "work":
		chance += (p.conscientiousness - 0.5) * 0.30
	if kind == "mingle":
		chance += (p.extraversion - 0.5) * 0.30

	# Suggesting what they already wanted is easy to accept. Suggesting
	# something they have no use for reads as meddling.
	var need_type: int = NUDGES[kind]["need"]
	var value: float = agent.needs.get_all_values().get(need_type, 100.0)
	if value < 40.0:
		chance += 0.25
	elif value > 85.0:
		chance -= 0.25

	return clampf(chance, 0.05, 0.95)


func _comply(agent: Node2D, kind: String, spec: Dictionary, request: String) -> bool:
	var decision: Dictionary = {}

	if kind == "mingle":
		var partner := _pick_social_target(agent)
		if partner:
			decision = {"action": ActionType.Type.TALK_TO_AGENT, "target": partner}
		else:
			decision = {"action": ActionType.Type.WANDER, "target": null}
	else:
		var obj := _find_object(spec["objects"])
		if obj == null:
			# Willing, but there is nothing to comply *with*.
			_refuse(agent, request, "would, but there's nothing free to use")
			return false
		decision = {"action": ActionType.Type.GO_TO_OBJECT, "target": obj}

	agent._execute_decision(decision)
	agent.memory.add_observation("Someone suggested %s should %s, and %s went along with it." % [
		agent.agent_name, request, agent.agent_name
	], 3.0)
	EventBus.nudge_answered.emit(agent.agent_name, request, true, "")
	EventBus.narrative_event.emit(
		"%s takes the suggestion to %s." % [agent.agent_name, request],
		[agent.agent_name], 3.5
	)
	return true


func _refuse(agent: Node2D, request: String, reason: String) -> void:
	agent.memory.add_observation("Someone told %s to %s. %s ignored it." % [
		agent.agent_name, request, agent.agent_name
	], 4.0)
	EventBus.nudge_answered.emit(agent.agent_name, request, false, reason)
	EventBus.narrative_event.emit(
		"%s was told to %s and %s." % [agent.agent_name, request, reason],
		[agent.agent_name], 4.0
	)


func _refusal_reason(agent: Node2D, kind: String) -> String:
	var p: PersonalityProfile = agent.personality
	var options: Array[String] = ["doesn't feel like it"]
	if p:
		if p.agreeableness < 0.4:
			options = ["flatly refuses", "pretends not to hear", "has other ideas"]
		elif p.neuroticism > 0.6:
			options = ["gets flustered and doesn't move", "hesitates, then doesn't"]
		elif p.conscientiousness > 0.6 and kind != "work":
			options = ["says there's work to finish first"]
		elif p.extraversion < 0.4 and kind == "mingle":
			options = ["would rather not, thanks"]
	return options[randi() % options.size()]


# --- 2. Interview -----------------------------------------------------------

func interview(agent: Node2D, question: String, callback: Callable = Callable()) -> void:
	## Ask an agent a question. Answered in character, from memories they
	## actually hold — so the answer changes as their life does.
	if agent == null or not is_instance_valid(agent) or agent.is_dead:
		return
	if question.strip_edges() == "":
		return

	var mems: Array[MemoryEntry] = agent.memory.retrieve(question, 5)
	var memory_text: String = agent.memory.format_memories_for_prompt(mems)
	if memory_text.strip_edges() == "":
		memory_text = "(nothing specific comes to mind)"

	if not LLMManager.is_available:
		_answer(agent, question, _heuristic_answer(agent, mems), callback)
		return

	var p: PersonalityProfile = agent.personality
	var prompt := PromptBuilder.build("interview", {
		"name": agent.agent_name,
		"personality": p.get_personality_summary() if p else "balanced",
		"speech_style": (p.speech_style if p and p.speech_style != "" else "casual"),
		"memories": memory_text,
		"question": question,
	})

	var messages := [
		{"role": "system", "content": "You answer as a character being interviewed. Reply with the answer only."},
		{"role": "user", "content": prompt},
	]
	var format := {
		"type": "object",
		"properties": {"answer": {"type": "string"}},
		"required": ["answer"],
	}

	var captured: Node2D = agent
	var captured_mems: Array[MemoryEntry] = mems
	# HIGH priority: unlike a confessional, a person is sitting there waiting.
	LLMManager.request_chat(messages, format, func(success: bool, data: Dictionary, _err: String) -> void:
		if not is_instance_valid(captured):
			return
		var answer := ""
		if success and data.has("answer"):
			answer = LLMSanitizer.clean_line(str(data["answer"]))
		if answer == "":
			answer = _heuristic_answer(captured, captured_mems)
		_answer(captured, question, answer, callback)
	, LLMManager.Priority.HIGH)


func _answer(agent: Node2D, question: String, answer: String, callback: Callable) -> void:
	# Being asked is itself an event worth remembering.
	agent.memory.add_observation("Someone asked %s: \"%s\"" % [agent.agent_name, question], 3.0)
	EventBus.interview_answered.emit(agent.agent_name, question, answer)
	if callback.is_valid():
		callback.call(answer)


func _heuristic_answer(agent: Node2D, mems: Array[MemoryEntry]) -> String:
	## Offline fallback: reflect back a real memory rather than inventing one.
	if not mems.is_empty():
		return "Honestly? %s That's what sticks with me." % mems[0].description
	var p: PersonalityProfile = agent.personality
	if p and p.neuroticism > 0.6:
		return "I'd rather not get into it, if that's alright."
	return "Not much to tell. It's been a normal week, mostly."


# --- 3. Plant a rumor -------------------------------------------------------

func plant_rumor(agent: Node2D, text: String, about: String = "") -> void:
	## Inject a memory. It need not be true — that is the point. The agent
	## treats it as something they know, and it colours later behaviour because
	## memories already feed the decision and conversation prompts.
	if agent == null or not is_instance_valid(agent) or agent.is_dead:
		return
	if text.strip_edges() == "":
		return

	var related: PackedStringArray = []
	if about != "":
		related.append(about)

	# Importance 6.5: high enough to surface in retrieval and survive
	# compaction pressure, below the 8+ reserved for things that actually
	# happened to them.
	var mem: MemoryEntry = agent.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION, text, 6.5, related)
	if about != "":
		# A planted rumour about someone is a smear, and the house-meeting
		# vote only counts hearsay with negative sentiment — at the default
		# 0.0 the player's one advertised counterplay scored zero points.
		# (Caught by a playtester; the harness had hidden it by patching
		# sentiment manually.)
		mem.sentiment = -0.4
	EventBus.rumor_planted.emit(agent.agent_name, text)
	EventBus.narrative_event.emit(
		"%s heard something: %s" % [agent.agent_name, text],
		[agent.agent_name] if about == "" else [agent.agent_name, about], 6.0
	)


func rumor_templates(subject: String) -> Array[String]:
	return [
		"%s has been talking about me behind my back." % subject,
		"%s is planning to leave." % subject,
		"%s broke the coffee machine and blamed someone else." % subject,
		"%s is up for a promotion." % subject,
		"%s doesn't think I belong here." % subject,
	]


# --- Helpers ----------------------------------------------------------------

func _get_world() -> Node:
	return get_tree().get_first_node_in_group("world")


func _find_object(types: Array) -> InteractableObject:
	var world := _get_world()
	if world == null or not world.has_method("get_all_objects"):
		return null
	var candidates: Array[InteractableObject] = []
	for obj in world.get_all_objects():
		if not is_instance_valid(obj):
			continue
		if obj.get_object_type() in types and obj.is_available():
			candidates.append(obj)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]


func _pick_social_target(agent: Node2D) -> Node2D:
	var pool: Array[Node2D] = []
	for other in AgentManager.agents:
		if other == agent or not is_instance_valid(other) or other.is_dead:
			continue
		if other.state == AgentState.Type.TALKING:
			continue
		pool.append(other)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]
