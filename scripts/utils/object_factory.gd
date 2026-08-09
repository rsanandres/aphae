class_name ObjectFactory
## The one place office objects are built at runtime. This body previously
## existed in three identical copies (god_toolbar, save_manager,
## headless_sim); the catalog made it a fourth caller, so it became a class.


static func create(obj_type: String) -> InteractableObject:
	var script_path := "res://scenes/objects/%s.gd" % obj_type
	if not FileAccess.file_exists(script_path):
		push_warning("ObjectFactory: unknown object type '%s'" % obj_type)
		return null
	var obj := StaticBody2D.new()
	obj.collision_layer = 4
	obj.collision_mask = 0
	obj.set_script(load(script_path))

	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	obj.add_child(sprite)

	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	# Placeholder box; InteractableObject._fit_collision_to_sprite corrects it
	# to the real sprite size once the texture lands.
	rect.size = Vector2(24, 16)
	shape.shape = rect
	obj.add_child(shape)

	return obj
