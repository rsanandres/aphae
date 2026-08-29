class_name ObjectFactory
## The one place office objects are built at runtime. This body previously
## existed in three identical copies (god_toolbar, save_manager,
## headless_sim); the catalog made it a fourth caller, so it became a class.


static func create(obj_type: String) -> InteractableObject:
	# obj_type reaches this from save files, so it is untrusted input into a
	# load() path. Without this check, "../../autoloads/whatever" in a crafted
	# or corrupted save would set an arbitrary project script on the object.
	# Every real type is a plain identifier (desk, coffee_machine, ...).
	if not obj_type.is_valid_identifier():
		push_warning("ObjectFactory: rejected object type '%s'" % obj_type)
		return null
	var script_path := "res://scenes/objects/%s.gd" % obj_type
	var from_catalog := false
	if not FileAccess.file_exists(script_path):
		# No bespoke script — the data catalog (resources/objects.json) may
		# define it. Bespoke always wins so special behavior stays special.
		if DataObject.get_def(obj_type).is_empty():
			push_warning("ObjectFactory: unknown object type '%s'" % obj_type)
			return null
		script_path = "res://scenes/objects/data_object.gd"
		from_catalog = true
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

	if from_catalog and not (obj as DataObject).configure(obj_type):
		obj.free()
		return null
	return obj
