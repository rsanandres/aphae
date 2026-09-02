class_name AgentRelationships
extends Node
## Per-agent relationship tracker. Dictionary of agent_name -> RelationshipEntry.

var _relationships: Dictionary = {}
var _agent: Node2D
var _proximity_tick_count: int = 0


func _ready() -> void:
	_agent = get_parent()
	EventBus.time_tick.connect(_on_time_tick)


func get_relationship(agent_name: String) -> RelationshipEntry:
	if not _relationships.has(agent_name):
		_relationships[agent_name] = RelationshipEntry.new()
	return _relationships[agent_name]


func update_after_interaction(other_name: String, context: String, positive: bool = true) -> void:
	var rel: RelationshipEntry = get_relationship(other_name)
	rel.interaction_count += 1
	rel.last_interaction_time = TimeManager.game_minutes

	# Affinity shift based on interaction quality
	var affinity_delta: float = 3.0 if positive else -5.0
	# Personality compatibility bonus
	affinity_delta += _compatibility_bonus(other_name)
	rel.affinity = clampf(rel.affinity + affinity_delta, -100.0, 100.0)

	# Trust grows slowly with positive interactions
	if positive:
		rel.trust = clampf(rel.trust + 1.5, 0.0, 100.0)
	else:
		rel.trust = clampf(rel.trust - 3.0, 0.0, 100.0)

	# Familiarity always grows with interaction
	rel.familiarity = clampf(rel.familiarity + 2.0, 0.0, 100.0)

	# Update tags based on thresholds
	_update_tags(rel)

	EventBus.relationship_changed.emit(_agent.agent_name, other_name, rel)


func update_romance(other_name: String, positive: bool = true, growth_scale: float = 1.0) -> void:
	## Grow romantic interest after a good conversation. Until this existed,
	## romantic_interest was never incremented anywhere in the codebase, so
	## confessions (which require > 40) could never organically succeed.
	if not positive:
		return
	var rel: RelationshipEntry = get_relationship(other_name)
	if rel.affinity <= 10.0:
		return
	# No slow-burn crushes on someone already committed — affairs become
	# deliberate content later, not an accident of the growth curve.
	if _is_committed_elsewhere(other_name):
		return
	var other := AgentManager.get_agent_by_name(other_name)
	if other == null or other.relationships == null:
		return
	if other.relationships._is_committed_elsewhere(_agent.agent_name):
		return
	var growth: float = Config.ROMANCE_GROWTH_BASE + maxf(_compatibility_bonus(other_name), 0.0) * 2.0
	if _agent.personality:
		growth += (_agent.personality.extraversion - 0.5) * 0.6
		growth += (_agent.personality.openness - 0.5) * 0.4
	if growth <= 0.0:
		return
	# The location's social modifier (SynergyManager zones): romance kindles
	# faster in the right corner of the office.
	growth *= growth_scale
	rel.romantic_interest = clampf(rel.romantic_interest + growth, 0.0, 100.0)
	rel.last_romantic_event_day = TimeManager.day
	if rel.romantic_interest > Config.ROMANCE_CRUSH_THRESHOLD \
			and rel.relationship_status == RelationshipEntry.Status.NONE:
		rel.relationship_status = RelationshipEntry.Status.CRUSHING
		EventBus.narrative_event.emit(
			"%s has developed a crush on %s." % [_agent.agent_name, other_name],
			[_agent.agent_name, other_name], 5.0
		)
	EventBus.relationship_changed.emit(_agent.agent_name, other_name, rel)


func _is_committed_elsewhere(exclude_name: String) -> bool:
	for other_name in _relationships:
		if other_name == exclude_name:
			continue
		var status: RelationshipEntry.Status = _relationships[other_name].relationship_status
		if status == RelationshipEntry.Status.DATING or status == RelationshipEntry.Status.PARTNERS:
			return true
	return false


func update_proximity(other_name: String, _delta: float) -> void:
	var rel: RelationshipEntry = get_relationship(other_name)
	# Small familiarity gain from being nearby
	rel.familiarity = clampf(rel.familiarity + 0.02, 0.0, 100.0)


func get_closest_friends(count: int = 3) -> Array[String]:
	var sorted_names: Array[String] = []
	var sorted_entries: Array[Dictionary] = []
	for agent_name in _relationships:
		var rel: RelationshipEntry = _relationships[agent_name]
		sorted_entries.append({"name": agent_name, "affinity": rel.affinity})
	sorted_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["affinity"] > b["affinity"]
	)
	var limit := mini(count, sorted_entries.size())
	for i in range(limit):
		if sorted_entries[i]["affinity"] > 0:
			sorted_names.append(sorted_entries[i]["name"])
	return sorted_names


func get_rivals() -> Array[String]:
	var result: Array[String] = []
	for agent_name in _relationships:
		var rel: RelationshipEntry = _relationships[agent_name]
		if rel.affinity < -30.0 or rel.has_tag("rival"):
			result.append(agent_name)
	return result


func get_all_as_summary() -> String:
	if _relationships.is_empty():
		return "(no established relationships)"
	var lines: PackedStringArray = []
	for agent_name in _relationships:
		var rel: RelationshipEntry = _relationships[agent_name]
		if rel.familiarity > 5.0:  # Only show if they've actually met
			lines.append("- %s: %s" % [agent_name, rel.get_summary()])
	return "\n".join(lines) if not lines.is_empty() else "(no established relationships)"


func get_all_relationships() -> Dictionary:
	return _relationships


func _compatibility_bonus(other_name: String) -> float:
	if not _agent.personality:
		return 0.0
	# Find other agent's personality
	for agent in AgentManager.agents:
		if agent.agent_name == other_name and agent.personality:
			return _calculate_compatibility(_agent.personality, agent.personality)
	return 0.0


func _calculate_compatibility(a: PersonalityProfile, b: PersonalityProfile) -> float:
	# Complementary traits create attraction, extreme differences create friction
	var bonus: float = 0.0
	# Agreeableness similarity → good
	bonus += (1.0 - absf(a.agreeableness - b.agreeableness)) * 0.5
	# Extraversion complementarity → interesting dynamics
	bonus += absf(a.extraversion - b.extraversion) * 0.3
	# Openness similarity → shared interests
	bonus += (1.0 - absf(a.openness - b.openness)) * 0.3
	# High neuroticism on both → friction
	if a.neuroticism > 0.6 and b.neuroticism > 0.6:
		bonus -= 0.5
	return bonus


func _update_tags(rel: RelationshipEntry) -> void:
	# Friend/rival tags
	if rel.affinity > 40.0 and rel.familiarity > 30.0:
		rel.add_tag("friend")
		rel.remove_tag("rival")
	elif rel.affinity < -40.0:
		rel.add_tag("rival")
		rel.remove_tag("friend")
	# Acquaintance
	if rel.familiarity > 10.0 and rel.familiarity < 30.0:
		rel.add_tag("acquaintance")
	elif rel.familiarity >= 30.0:
		rel.remove_tag("acquaintance")
	# Crush tag (handled by romance system in Phase 8)
	if rel.romantic_interest > 50.0:
		rel.add_tag("crush")
	else:
		rel.remove_tag("crush")


func _on_time_tick(_game_minutes: float) -> void:
	# Throttle proximity updates to every 5th tick (5x reduction)
	_proximity_tick_count += 1
	if _proximity_tick_count % 5 != 0:
		return
	var nearby := AgentManager.get_agents_near(_agent.global_position, 60.0, _agent)
	for other in nearby:
		update_proximity(other.agent_name, 1.0)
