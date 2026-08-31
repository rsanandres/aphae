class_name EventNotification
extends CanvasLayer
## Floating notification feed for key game events. Shows stacking notifications
## at the top-right that auto-dismiss after a few seconds.

const MAX_VISIBLE := 4
const DISPLAY_DURATION := 4.0
const NOTIFICATION_HEIGHT := 18

var _container: VBoxContainer = null


func _ready() -> void:
	layer = 85

	_container = VBoxContainer.new()
	_container.anchor_left = 1.0
	_container.anchor_right = 1.0
	_container.offset_left = -200
	_container.offset_right = -8
	_container.offset_top = 4
	_container.offset_bottom = 100
	_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_container.add_theme_constant_override("separation", 2)
	add_child(_container)

	# Connect to key events
	EventBus.confession_made.connect(_on_confession)
	EventBus.romance_started.connect(_on_romance)
	EventBus.agent_died.connect(_on_death)
	EventBus.group_formed.connect(_on_group_formed)
	EventBus.group_rivalry_detected.connect(_on_rivalry)
	EventBus.event_triggered.connect(_on_event)
	EventBus.agent_life_stage_changed.connect(_on_life_stage)
	EventBus.produced_beat.connect(_on_produced_beat)


func _add_notification(text: String, color: Color) -> void:
	# Cap visible notifications
	while _container.get_child_count() >= MAX_VISIBLE:
		var oldest := _container.get_child(0)
		oldest.queue_free()

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0.05, 0.05, 0.08, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(0, NOTIFICATION_HEIGHT)
	_container.add_child(lbl)

	# Fade in, wait, fade out, remove
	lbl.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(lbl, "modulate:a", 1.0, 0.2)
	tween.tween_interval(DISPLAY_DURATION)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func() -> void:
		lbl.queue_free()
	)


func _on_confession(confessor: String, target: String, accepted: bool) -> void:
	if accepted:
		_add_notification("%s & %s are now dating!" % [confessor, target], Color(1.0, 0.5, 0.6))
	else:
		_add_notification("%s was rejected by %s" % [confessor, target], Color(0.7, 0.5, 0.7))


func _on_romance(agent_a: String, agent_b: String) -> void:
	_add_notification("%s & %s fell in love" % [agent_a, agent_b], Color(1.0, 0.45, 0.55))


func _on_death(agent_name: String, cause: String) -> void:
	_add_notification("%s passed away (%s)" % [agent_name, cause], Color(0.6, 0.6, 0.65))


func _on_group_formed(group: RefCounted) -> void:
	var group_name: String = group.get("name") if group.has_method("get") else "a group"
	_add_notification("New group formed: %s" % group_name, Color(0.5, 0.7, 0.9))


func _on_rivalry(group_a: RefCounted, group_b: RefCounted) -> void:
	var name_a: String = group_a.get("name") if group_a.has_method("get") else "Group A"
	var name_b: String = group_b.get("name") if group_b.has_method("get") else "Group B"
	_add_notification("%s vs %s rivalry!" % [name_a, name_b], Color(0.9, 0.5, 0.3))


func _on_event(event_id: String, _affected_agents: Array) -> void:
	# Format event ID to readable name
	var readable := event_id.replace("_", " ").capitalize()
	_add_notification("Event: %s" % readable, Color(0.8, 0.75, 0.5))


func _on_produced_beat(_text: String) -> void:
	# Ratings gold: the producer's intervention just paid off on screen.
	_add_notification("Viewers loved that — your beat counts double", Color(1.0, 0.85, 0.4))


func _on_life_stage(agent_name: String, stage: int) -> void:
	var stage_name: String
	match stage:
		LifeStage.Type.ADULT: stage_name = "reached adulthood"
		LifeStage.Type.SENIOR: stage_name = "became a senior"
		LifeStage.Type.DYING: stage_name = "is in decline"
		_: return  # Don't notify for young or dead
	_add_notification("%s %s" % [agent_name, stage_name], Color(0.7, 0.7, 0.75))
