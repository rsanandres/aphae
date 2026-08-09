class_name HeuristicBrain
extends Node
## Fallback decision-making: picks actions based on most urgent need
## AND personality traits (extraversion, openness, conscientiousness, etc.).

# Base need→object mapping (overridden by personality preferences)
var NEED_TO_OBJECT_TYPE := {
	NeedType.Type.ENERGY: "couch",
	NeedType.Type.HUNGER: "coffee_machine",
	NeedType.Type.SOCIAL: "",  # handled via talk_to_agent
	NeedType.Type.PRODUCTIVITY: "desk",
}

var _agent: Node2D


func _ready() -> void:
	_agent = get_parent()


func decide(needs: AgentNeeds, nearby_objects: Array, nearby_agents: Array) -> Dictionary:
	# If sick or very low health, prioritize rest
	if _agent.health_state and not _agent.health_state.conditions.is_empty():
		var couch := _find_available_object(nearby_objects, "couch")
		if couch:
			return {"action": ActionType.Type.GO_TO_OBJECT, "target": couch}
		var bed := _find_available_object(nearby_objects, "bed")
		if bed:
			return {"action": ActionType.Type.GO_TO_OBJECT, "target": bed}

	# Check for grief/avoidance modifiers
	if _agent.has_method("get_active_modifiers"):
		var mods: Array = _agent.get_active_modifiers()
		for mod in mods:
			if mod.get("type", "") == "avoidance":
				nearby_agents = nearby_agents.filter(func(a: Node2D) -> bool:
					return a.agent_name != mod.get("target", "")
				)

	var urgent_need := needs.get_most_urgent()
	var urgent_value := needs.get_value(urgent_need)
	var personality: PersonalityProfile = _agent.personality

	# If no needs are particularly pressing, personality drives behavior
	if urgent_value > 70.0:
		return _personality_idle_decision(personality, nearby_objects, nearby_agents)

	# Social need: personality affects who to talk to and willingness
	if urgent_need == NeedType.Type.SOCIAL and not nearby_agents.is_empty():
		return _social_decision(personality, nearby_agents)

	# Find an object that satisfies the need (personality biases object choice)
	var desired_type: String = _get_preferred_object(urgent_need, personality)
	if desired_type != "":
		var best_object: Node2D = _find_available_object(nearby_objects, desired_type)
		if best_object:
			return {"action": ActionType.Type.GO_TO_OBJECT, "target": best_object}
		# Fallback: try the default object type
		var default_type: String = NEED_TO_OBJECT_TYPE.get(urgent_need, "")
		if default_type != "" and default_type != desired_type:
			var fallback_obj: Node2D = _find_available_object(nearby_objects, default_type)
			if fallback_obj:
				return {"action": ActionType.Type.GO_TO_OBJECT, "target": fallback_obj}

	# Fallback: wander to find something
	return {"action": ActionType.Type.WANDER}


func _personality_idle_decision(personality: PersonalityProfile, nearby_objects: Array, nearby_agents: Array) -> Dictionary:
	## When needs are satisfied, personality determines what the agent does for fun.
	if not personality:
		if randf() < 0.3:
			return {"action": ActionType.Type.WANDER}
		return {"action": ActionType.Type.IDLE}

	var roll := randf()

	# High extraversion → seek social interaction even when not needy
	if personality.extraversion > 0.6 and not nearby_agents.is_empty() and roll < personality.extraversion * 0.5:
		var valid_agents: Array = nearby_agents.filter(func(a: Node2D) -> bool: return not a.is_dead)
		if not valid_agents.is_empty():
			# Prefer agents with high affinity
			var target: Node2D = _pick_preferred_social_target(valid_agents)
			return {"action": ActionType.Type.TALK_TO_AGENT, "target": target}

	# High openness → gravitates toward creative objects (whiteboard, bookshelf)
	if personality.openness > 0.6 and roll < 0.4:
		var creative_obj := _find_available_object(nearby_objects, "whiteboard")
		if not creative_obj:
			creative_obj = _find_available_object(nearby_objects, "bookshelf")
		if creative_obj:
			return {"action": ActionType.Type.GO_TO_OBJECT, "target": creative_obj}

	# High conscientiousness → works even when productivity is fine
	if personality.conscientiousness > 0.6 and roll < 0.35:
		var desk := _find_available_object(nearby_objects, "desk")
		if desk:
			return {"action": ActionType.Type.GO_TO_OBJECT, "target": desk}

	# Low extraversion (introvert) → prefers solitary objects
	if personality.extraversion < 0.4 and roll < 0.3:
		var solitary := _find_available_object(nearby_objects, "bookshelf")
		if not solitary:
			solitary = _find_available_object(nearby_objects, "plant")
		if solitary:
			return {"action": ActionType.Type.GO_TO_OBJECT, "target": solitary}

	# Default: wander or idle
	if randf() < 0.3:
		return {"action": ActionType.Type.WANDER}
	return {"action": ActionType.Type.IDLE}


func _social_decision(personality: PersonalityProfile, nearby_agents: Array) -> Dictionary:
	## Personality affects social target selection.
	var valid_agents: Array = nearby_agents.filter(func(a: Node2D) -> bool: return not a.is_dead)
	if valid_agents.is_empty():
		return {"action": ActionType.Type.WANDER}

	# Introverts: lower chance of initiating, but still do when social need is urgent
	if personality and personality.extraversion < 0.3 and randf() < 0.3:
		# Introvert hesitates — wander instead sometimes
		return {"action": ActionType.Type.WANDER}

	var target: Node2D = _pick_preferred_social_target(valid_agents)
	return {"action": ActionType.Type.TALK_TO_AGENT, "target": target}


func _pick_preferred_social_target(agents: Array) -> Node2D:
	## Pick a social target weighted by relationship affinity.
	if not _agent.relationships or agents.size() == 1:
		return agents[randi() % agents.size()]

	# Build weighted pool: higher affinity → more likely to approach
	var weights: Array[float] = []
	var total_weight: float = 0.0
	for a in agents:
		var rel: RelationshipEntry = _agent.relationships.get_relationship(a.agent_name)
		# Base weight 10, plus affinity (can be negative). Minimum 1.
		var w: float = maxf(1.0, 10.0 + rel.affinity * 0.2)
		# Romantic interest bonus
		if rel.romantic_interest > 30.0:
			w += 5.0
		weights.append(w)
		total_weight += w

	# Weighted random selection
	var pick := randf() * total_weight
	var cumulative: float = 0.0
	for i in range(agents.size()):
		cumulative += weights[i]
		if pick <= cumulative:
			return agents[i]
	return agents[-1]


func _get_preferred_object(need: NeedType.Type, personality: PersonalityProfile) -> String:
	## Personality biases which object fulfills a need.
	if not personality:
		return NEED_TO_OBJECT_TYPE.get(need, "")

	match need:
		NeedType.Type.ENERGY:
			# Anxious minds seek the pod, slackers the arcade, introverts the
			# bed, extraverts the couch (catalog objects may not exist yet —
			# _find_available_object falls back to the default type).
			if personality.neuroticism > 0.6 and randf() < 0.4:
				return "meditation_pod"
			if personality.conscientiousness < 0.4 and randf() < 0.3:
				return "arcade_cabinet"
			if personality.extraversion < 0.4:
				return "bed"
			return "couch"
		NeedType.Type.HUNGER:
			return "coffee_machine"
		NeedType.Type.PRODUCTIVITY:
			# Creative types prefer whiteboard, methodical types prefer desk
			if personality.openness > 0.7 and randf() < 0.4:
				return "whiteboard"
			return "desk"
		NeedType.Type.SOCIAL:
			# High extraversion → karaoke if the office has one, else the
			# water cooler (group chat)
			if personality.extraversion > 0.7 and randf() < 0.35:
				return "karaoke_machine"
			if personality.extraversion > 0.6:
				return "water_cooler"
			return ""
		_:
			return NEED_TO_OBJECT_TYPE.get(need, "")


func _find_available_object(objects: Array, object_type: String) -> Node2D:
	var candidates: Array[Node2D] = []
	for obj in objects:
		if not is_instance_valid(obj):
			continue
		if obj.has_method("get_object_type") and obj.get_object_type() == object_type:
			if obj.has_method("is_available") and obj.is_available():
				candidates.append(obj)
	if candidates.is_empty():
		return null
	# Pick the closest one
	var closest: Node2D = null
	var closest_dist := INF
	for c in candidates:
		var dist: float = _agent.global_position.distance_squared_to(c.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = c
	return closest
