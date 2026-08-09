extends InteractableObject
## Arcade cabinet: two players, one high score. Friendship accelerator.


func _ready() -> void:
	super._ready()
	object_type = "arcade_cabinet"
	display_name = "Arcade Cabinet"
	interaction_duration = 12.0
	max_occupants = 2
	_need_effects = {
		NeedType.Type.SOCIAL: 15.0,
		NeedType.Type.ENERGY: 10.0,
		NeedType.Type.PRODUCTIVITY: -5.0,
	}
	$Sprite2D.texture = SpriteFactory.create_arcade_cabinet_sprite()


func occupy(agent: Node2D) -> void:
	super.occupy(agent)
	if _occupants.size() == 2:
		var a: Node2D = _occupants[0]
		var b: Node2D = _occupants[1]
		call_deferred("_versus", a, b)


func _versus(a: Node2D, b: Node2D) -> void:
	if is_instance_valid(a) and is_instance_valid(b):
		ConversationManager.start_conversation(a, b)
