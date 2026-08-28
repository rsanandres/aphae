class_name AgentBrain
extends Node
## LLM-powered decision-making with heuristic fallback.

signal thought_generated(thought: String)

var personality: PersonalityProfile
var force_heuristic: bool = false  # Set by AgentManager for background agents
var _agent: Node2D
var _heuristic: HeuristicBrain
var _memory: AgentMemory
var _relationships: AgentRelationships
var _waiting_for_llm: bool = false

# JSON schema for Ollama structured output
var _decision_format := {
	"type": "object",
	"properties": {
		"action": {
			"type": "string",
			"enum": ["go_to_object", "talk_to_agent", "idle", "wander", "confess_feelings"],
		},
		"target": {
			"type": "string",
			"description": "Name of the object or agent to interact with",
		},
		"thought": {
			"type": "string",
			"description": "Brief inner thought explaining the decision",
		},
	},
	"required": ["action", "thought"],
}


func _ready() -> void:
	_agent = get_parent()
	_heuristic = _agent.get_node("HeuristicBrain")
	_memory = _agent.get_node("AgentMemory")
	_relationships = _agent.get_node("AgentRelationships")


func decide(needs: AgentNeeds, nearby_objects: Array, nearby_agents: Array) -> Dictionary:
	# Background agents always use heuristic for performance
	if force_heuristic:
		return _heuristic.decide(needs, nearby_objects, nearby_agents)

	# If LLM is available and we're not already waiting, use it
	if LLMManager.is_available and not _waiting_for_llm and LLMManager.get_queue_size() < Config.LLM_QUEUE_MAX:
		_request_llm_decision(needs, nearby_objects, nearby_agents)
		return {"action": ActionType.Type.IDLE, "waiting_for_llm": true}

	# Fallback to heuristic
	return _heuristic.decide(needs, nearby_objects, nearby_agents)


func _request_llm_decision(needs: AgentNeeds, nearby_objects: Array, nearby_agents: Array) -> void:
	_waiting_for_llm = true

	var objects_text := _format_objects(nearby_objects)
	var agents_text := _format_agents(nearby_agents)
	var needs_values: Dictionary = needs.get_all_values()
	var relevant_memories: Array[MemoryEntry] = _memory.retrieve(_build_context_query(needs, nearby_objects, nearby_agents), 7)
	var memories_text := _memory.format_memories_for_prompt(relevant_memories)
	var relationships_text: String = _relationships.get_all_as_summary() if _relationships else "(none)"

	var system_prompt := PromptBuilder.build("system", {
		"name": personality.agent_name if personality else _agent.agent_name,
		"description": personality.description if personality else "",
		"openness": personality.openness if personality else 0.5,
		"conscientiousness": personality.conscientiousness if personality else 0.5,
		"extraversion": personality.extraversion if personality else 0.5,
		"agreeableness": personality.agreeableness if personality else 0.5,
		"neuroticism": personality.neuroticism if personality else 0.5,
		"speech_style": personality.speech_style if personality else "",
		"quirks": ", ".join(personality.quirks) if personality else "",
	})

	var health_val: float = needs_values.get(NeedType.Type.HEALTH, 100.0)
	var groups_text := "(none)"
	if GroupManager:
		groups_text = GroupManager.get_agent_group_names(_agent.agent_name)
	var user_prompt := PromptBuilder.build("decision", {
		"name": personality.agent_name if personality else _agent.agent_name,
		"description": personality.description if personality else "",
		"personality": personality.get_personality_summary() if personality else "",
		"mood": personality.get_mood(needs_values) if personality else "neutral",
		# Goals carry their live standing (progress, days left) so the model can
		# write someone who knows they are close, or out of time.
		"goals": GoalManager.format_for_prompt(_agent.agent_name),
		"time": TimeManager.time_string,
		"energy": "%.0f" % needs_values.get(NeedType.Type.ENERGY, 50.0),
		"hunger": "%.0f" % needs_values.get(NeedType.Type.HUNGER, 50.0),
		"social": "%.0f" % needs_values.get(NeedType.Type.SOCIAL, 50.0),
		"productivity": "%.0f" % needs_values.get(NeedType.Type.PRODUCTIVITY, 50.0),
		"health": "%.0f" % health_val,
		"objects": objects_text,
		"agents": agents_text,
		"relationships": relationships_text,
		"groups": groups_text,
		"memories": memories_text,
	})

	var messages := [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt},
	]

	LLMManager.request_chat(
		messages,
		_decision_format,
		_on_llm_response.bind(nearby_objects, nearby_agents),
		LLMManager.Priority.NORMAL,
	)


func _on_llm_response(success: bool, data: Dictionary, error: String, nearby_objects: Array, nearby_agents: Array) -> void:
	_waiting_for_llm = false

	if not success:
		push_warning("AgentBrain LLM error for %s: %s" % [_agent.agent_name, error])
		# Fallback: trigger a heuristic decision
		_agent.request_think()
		return

	# Emit thought
	var thought_text: String = LLMSanitizer.clean_line(str(data.get("thought", "")))
	if thought_text != "":
		thought_generated.emit(thought_text)
		_memory.add_observation("Thought: %s" % thought_text, 2.0)

	# Parse action
	var action_str: String = data.get("action", "idle")
	var target_str: String = data.get("target", "")

	var decision := _parse_llm_decision(action_str, target_str, nearby_objects, nearby_agents)
	_agent._execute_decision(decision)


func _parse_llm_decision(action_str: String, target_str: String, nearby_objects: Array, nearby_agents: Array) -> Dictionary:
	match action_str:
		"go_to_object":
			var target := _find_object_by_name(target_str, nearby_objects)
			if target:
				return {"action": ActionType.Type.GO_TO_OBJECT, "target": target}
			# Couldn't find the object, fallback
			return {"action": ActionType.Type.WANDER}
		"talk_to_agent":
			var target := _find_agent_by_name(target_str, nearby_agents)
			if target:
				return {"action": ActionType.Type.TALK_TO_AGENT, "target": target}
			return {"action": ActionType.Type.WANDER}
		"confess_feelings":
			var target := _find_agent_by_name(target_str, nearby_agents)
			if target:
				return {"action": ActionType.Type.CONFESS_FEELINGS, "target": target}
			return {"action": ActionType.Type.WANDER}
		"wander":
			return {"action": ActionType.Type.WANDER}
		_:
			return {"action": ActionType.Type.IDLE}


func _find_object_by_name(name: String, objects: Array) -> Node2D:
	var name_lower := name.to_lower()
	for obj in objects:
		if obj is InteractableObject:
			if obj.display_name.to_lower() in name_lower or obj.object_type in name_lower or name_lower in obj.display_name.to_lower():
				if obj.is_available():
					return obj
	# If exact match failed, try partial match on any available object
	for obj in objects:
		if obj is InteractableObject and obj.is_available():
			if obj.object_type in name_lower or name_lower in obj.object_type:
				return obj
	return null


func _find_agent_by_name(name: String, agents: Array) -> Node2D:
	var name_lower := name.to_lower()
	for agent in agents:
		if agent.agent_name.to_lower() == name_lower or name_lower in agent.agent_name.to_lower():
			return agent
	return null


func _format_objects(objects: Array) -> String:
	if objects.is_empty():
		return "(none nearby)"
	var lines: PackedStringArray = []
	for obj in objects:
		if obj is InteractableObject:
			var status := "available" if obj.is_available() else "occupied"
			lines.append("- %s (%s) [%s]" % [obj.display_name, obj.object_type, status])
	return "\n".join(lines) if not lines.is_empty() else "(none nearby)"


func _format_agents(agents: Array) -> String:
	if agents.is_empty():
		return "(nobody nearby)"
	var lines: PackedStringArray = []
	for agent in agents:
		var state_name := "idle"
		match agent.state:
			AgentState.Type.WALKING: state_name = "walking"
			AgentState.Type.INTERACTING: state_name = "busy"
			AgentState.Type.TALKING: state_name = "talking"
		lines.append("- %s (%s)" % [agent.agent_name, state_name])
	return "\n".join(lines)


func _build_context_query(needs: AgentNeeds, _objects: Array, agents: Array) -> String:
	var parts: PackedStringArray = []
	var urgent := needs.get_most_urgent()
	parts.append(NeedType.to_string_name(urgent))
	for agent in agents:
		parts.append(agent.agent_name)
	return " ".join(parts)
