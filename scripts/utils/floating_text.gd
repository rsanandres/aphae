class_name FloatingText
## Small world-space text that rises and fades — relationship deltas, hearts,
## clashes. The one-line feedback that makes a conversation's outcome
## readable without opening a panel.


static func spawn(world: Node, world_pos: Vector2, text: String, color: Color) -> void:
	if world == null:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.z_index = 20
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.13, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = world_pos + Vector2(-30, -18)
	lbl.custom_minimum_size = Vector2(60, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(lbl)

	var tween := lbl.create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 14.0, 1.6)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(lbl.queue_free)
