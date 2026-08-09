extends InteractableObject
## Meditation pod: ten quiet minutes. Stress melts, and sometimes a grudge
## goes with it.


func _ready() -> void:
	super._ready()
	object_type = "meditation_pod"
	display_name = "Meditation Pod"
	interaction_duration = 20.0
	max_occupants = 1
	_need_effects = {
		NeedType.Type.ENERGY: 20.0,
		NeedType.Type.HEALTH: 5.0,
	}
	$Sprite2D.texture = SpriteFactory.create_meditation_pod_sprite()


func release(agent: Node2D) -> void:
	super.release(agent)
	if not is_instance_valid(agent) or agent.health_state == null:
		return
	agent.health_state.remove_condition("stress")
	# A calm mind loosens one grudge, sometimes.
	if randf() < 0.3 and agent.relationships:
		for other_name in agent.relationships.get_all_relationships():
			var rel: RelationshipEntry = agent.relationships.get_relationship(other_name)
			for tag in rel.tags.duplicate():
				if str(tag).begins_with("angry_at_"):
					rel.remove_tag(tag)
					agent.memory.add_observation(
						"%s left the meditation pod lighter. The grudge against %s just... mattered less." % [agent.agent_name, other_name],
						4.0
					)
					return
