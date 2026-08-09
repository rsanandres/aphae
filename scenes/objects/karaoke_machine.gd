extends InteractableObject
## Karaoke machine: the social centerpiece. Two agents singing together is
## an instant scene — a conversation starts and the office notices.


func _ready() -> void:
	super._ready()
	object_type = "karaoke_machine"
	display_name = "Karaoke Machine"
	interaction_duration = 15.0
	max_occupants = 2
	_need_effects = {
		NeedType.Type.SOCIAL: 25.0,
		NeedType.Type.ENERGY: -5.0,
	}
	$Sprite2D.texture = SpriteFactory.create_karaoke_machine_sprite()


func occupy(agent: Node2D) -> void:
	super.occupy(agent)
	if _occupants.size() == 2:
		var a: Node2D = _occupants[0]
		var b: Node2D = _occupants[1]
		call_deferred("_duet", a, b)


func _duet(a: Node2D, b: Node2D) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	ConversationManager.start_conversation(a, b)
	EventBus.narrative_event.emit(
		"%s and %s grabbed the karaoke mic together. The office will not forget this." % [a.agent_name, b.agent_name],
		[a.agent_name, b.agent_name], 4.0
	)
