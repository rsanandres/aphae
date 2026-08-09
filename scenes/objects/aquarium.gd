extends InteractableObject
## Aquarium: a calming presence. Nobody uses it; everybody feels it.


func _ready() -> void:
	super._ready()
	object_type = "aquarium"
	display_name = "Aquarium"
	interaction_duration = 0.0
	max_occupants = 0
	passive_effect_radius = 70.0
	passive_need_effects = {
		NeedType.Type.SOCIAL: 0.4,
	}
	$Sprite2D.texture = SpriteFactory.create_aquarium_sprite()


func is_available() -> bool:
	return false
