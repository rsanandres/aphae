class_name InteractableObject
extends StaticBody2D
## Base class for all office objects agents can interact with.

@export var object_type: String = "generic"
@export var interaction_duration: float = 30.0  # game minutes
@export var display_name: String = "Object"
@export var max_occupants: int = 1
@export var passive_effect_radius: float = 0.0  # 0 = no passive effect
@export var passive_need_effects: Dictionary = {}  # NeedType.Type -> float per tick

var _occupants: Array[Node2D] = []
var _need_effects: Dictionary = {}  # NeedType.Type -> float
var _use_indicator: Node2D = null
var _hover_tooltip: PanelContainer = null
var _is_hovered: bool = false


func _ready() -> void:
	if passive_effect_radius > 0.0:
		EventBus.time_tick.connect(_on_passive_tick)
	_setup_use_indicator()
	_setup_hover_tooltip()
	_setup_shadow()
	# Subclasses assign their sprite texture in their own _ready, which runs
	# after this one — defer so the fit sees the real texture.
	call_deferred("_fit_collision_to_sprite")


func _setup_shadow() -> void:
	var shadow := Node2D.new()
	shadow.show_behind_parent = true
	add_child(shadow)
	shadow.draw.connect(func() -> void:
		var sp: Sprite2D = get_node_or_null("Sprite2D")
		var half_w: float = (sp.texture.get_width() / 2.0) if sp and sp.texture else 10.0
		var half_h: float = (sp.texture.get_height() / 2.0) if sp and sp.texture else 6.0
		shadow.draw_set_transform(Vector2(0, half_h - 1.0), 0.0, Vector2(1.0, 0.3))
		shadow.draw_circle(Vector2.ZERO, half_w * 0.9, Color(0, 0, 0, 0.18))
	)
	shadow.queue_redraw()


func _fit_collision_to_sprite() -> void:
	## Runtime-spawned objects historically got a hardcoded 24x16 box no
	## matter the sprite (a couch is 32 wide, a plant 10). Derive it instead.
	var sp: Sprite2D = get_node_or_null("Sprite2D")
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if sp and sp.texture and cs and cs.shape is RectangleShape2D:
		var shape: RectangleShape2D = cs.shape.duplicate()
		shape.size = sp.texture.get_size()
		cs.shape = shape


func get_object_type() -> String:
	return object_type


func get_interaction_duration() -> float:
	return interaction_duration


func get_need_effects() -> Dictionary:
	return _need_effects


func is_available() -> bool:
	_prune_occupants()
	return _occupants.size() < max_occupants


func get_occupant_count() -> int:
	_prune_occupants()
	return _occupants.size()


func _prune_occupants() -> void:
	## Belt to the agent-side braces: an occupant that no longer exists must
	## never keep a seat. Without this, one death at a desk retired that desk
	## for the rest of the run.
	var pruned := false
	for i in range(_occupants.size() - 1, -1, -1):
		if not is_instance_valid(_occupants[i]):
			_occupants.remove_at(i)
			pruned = true
	if pruned:
		_update_use_indicator()


func occupy(agent: Node2D) -> void:
	_prune_occupants()
	if not is_instance_valid(agent):
		return
	if agent not in _occupants and _occupants.size() < max_occupants:
		_occupants.append(agent)
		_update_use_indicator()


func release(agent: Node2D) -> void:
	_occupants.erase(agent)
	_update_use_indicator()


func get_occupant() -> Node2D:
	_prune_occupants()
	return _occupants[0] if not _occupants.is_empty() else null


func get_all_occupants() -> Array[Node2D]:
	_prune_occupants()
	return _occupants


func _on_passive_tick(_game_minutes: float) -> void:
	if passive_need_effects.is_empty():
		return
	# Apply passive effects to agents within radius
	var nearby := AgentManager.get_agents_near(global_position, passive_effect_radius)
	for agent in nearby:
		for need in passive_need_effects:
			var amount: float = passive_need_effects[need]
			agent.needs.restore(need, amount)


func _setup_use_indicator() -> void:
	_use_indicator = Node2D.new()
	_use_indicator.visible = false
	# In front: the old 1px arc at z -1 was invisible behind the sprite.
	_use_indicator.z_index = 1
	add_child(_use_indicator)
	_use_indicator.draw.connect(_draw_use_indicator)


func _draw_use_indicator() -> void:
	if _use_indicator:
		var pulse := 0.55 + sin(Time.get_ticks_msec() * 0.004) * 0.25
		var sp: Sprite2D = get_node_or_null("Sprite2D")
		var top: float = -((sp.texture.get_height() / 2.0) if sp and sp.texture else 8.0) - 3.0
		_use_indicator.draw_circle(Vector2(0, top), 1.6, Color(1.0, 0.8, 0.45, pulse))


func _update_use_indicator() -> void:
	if not _use_indicator:
		return
	_use_indicator.visible = not _occupants.is_empty()


func _process(_delta: float) -> void:
	if _use_indicator and _use_indicator.visible:
		_use_indicator.queue_redraw()
	if _is_hovered and _hover_tooltip and _hover_tooltip.visible:
		_hover_tooltip.global_position = global_position + Vector2(12, -30)


func _setup_hover_tooltip() -> void:
	_hover_tooltip = PanelContainer.new()
	_hover_tooltip.visible = false
	_hover_tooltip.z_index = 50
	_hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	style.border_color = Color(0.3, 0.35, 0.4, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(3)
	_hover_tooltip.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.name = "TooltipLabel"
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.88, 0.8))
	_hover_tooltip.add_child(lbl)
	add_child(_hover_tooltip)

	# Connect mouse events — we need an Area2D. Look for one or create one.
	var area: Area2D = null
	for child in get_children():
		if child is Area2D:
			area = child
			break
	if not area:
		# Create a small detection area for mouse hover
		area = Area2D.new()
		area.name = "HoverArea"
		area.input_pickable = true
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(24, 16)
		shape.shape = rect
		area.add_child(shape)
		add_child(area)
	area.mouse_entered.connect(_on_obj_mouse_entered)
	area.mouse_exited.connect(_on_obj_mouse_exited)


func _on_obj_mouse_entered() -> void:
	_is_hovered = true
	_update_obj_tooltip()
	_hover_tooltip.visible = true


func _on_obj_mouse_exited() -> void:
	_is_hovered = false
	_hover_tooltip.visible = false


func _update_obj_tooltip() -> void:
	var lbl: Label = _hover_tooltip.get_node("TooltipLabel")
	if not lbl:
		return
	var text := display_name
	# Occupancy
	text += " (%d/%d)" % [_occupants.size(), max_occupants]
	# Effects
	if not _need_effects.is_empty():
		var effects: PackedStringArray = []
		for need in _need_effects:
			var val: float = _need_effects[need]
			var name_str: String = NeedType.to_string_name(need).to_lower()
			effects.append("%s %+.0f" % [name_str, val])
		text += "\n" + ", ".join(effects)
	# Active synergies this object is part of (Breakfast Corner, Noise
	# Complaint...) — the zone system explains itself where you look.
	var zones: PackedStringArray = SynergyManager.zone_labels_for(self)
	if not zones.is_empty():
		text += "\n» " + ", ".join(zones)
	lbl.text = text
