class_name Agent
extends CharacterBody2D
## An AI agent that navigates the office, fulfills needs, and interacts with objects.

@export var agent_name: String = "Agent"
@export var agent_color: Color = Color.CORNFLOWER_BLUE
@export var personality_file: String = ""

var personality: PersonalityProfile = null
var procedural_personality_data: Dictionary = {}  # Set before _ready for procedural agents
var state: AgentState.Type = AgentState.Type.IDLE:
	set(value):
		if state == value:
			return
		var old := state
		state = value
		EventBus.agent_state_changed.emit(self, old, state)

var current_target: Node2D = null
var current_action: ActionType.Type = ActionType.Type.IDLE
var health_state: HealthState = null
var is_dead: bool = false
var _interact_timer: float = 0.0
var _interact_duration: float = 0.0
var _idle_frames: Array[ImageTexture] = []
var _walk_frames: Array[ImageTexture] = []
var _anim_timer: float = 0.0
var _anim_frame: int = 0
var _footstep_timer: float = 0.0
var _selection_ring: Node2D = null
var _is_selected: bool = false
var _interaction_particles: CPUParticles2D = null
var _death_particles: CPUParticles2D = null
var _mood_timer: Timer = null
var _current_mood: String = ""
var _hover_tooltip: PanelContainer = null
var _is_hovered: bool = false
var _behavior_modifiers: Array[Dictionary] = []  # {type, target, duration_days, days_remaining, source}

@onready var needs: AgentNeeds = $AgentNeeds
@onready var heuristic_brain: HeuristicBrain = $HeuristicBrain
@onready var smart_brain: AgentBrain = $AgentBrain
@onready var memory: AgentMemory = $AgentMemory
@onready var relationships: AgentRelationships = $AgentRelationships
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var label: Label = $NameLabel
@onready var thought_bubble: Label = $ThoughtBubble
@onready var speech_bubble: Label = $SpeechBubble
@onready var emotion_indicator: Label = $EmotionIndicator


func _ready() -> void:
	_load_personality()
	label.text = agent_name
	_setup_sprite()
	_setup_particles()
	_setup_selection_ring()
	memory.setup(agent_name)
	smart_brain.personality = personality
	smart_brain.thought_generated.connect(_on_thought)
	AgentManager.register(self)
	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = 4.0
	memory.add_observation("%s arrives at the office and starts their day." % agent_name, 3.0)
	# Initialize health
	health_state = HealthState.new()
	health_state.randomize_lifespan()
	# Mood indicator timer — updates every 2 seconds instead of every frame
	_mood_timer = Timer.new()
	_mood_timer.wait_time = 2.0
	_mood_timer.autostart = true
	_mood_timer.timeout.connect(_update_mood_indicator)
	add_child(_mood_timer)
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.agent_selected.connect(_on_global_agent_selected)
	EventBus.agent_deselected.connect(_on_global_agent_deselected)
	EventBus.confessional_recorded.connect(_on_confessional_recorded)
	_setup_hover_tooltip()


func _exit_tree() -> void:
	AgentManager.unregister(self)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	match state:
		AgentState.Type.IDLE:
			velocity = Vector2.ZERO
		AgentState.Type.WALKING:
			_process_walking(delta)
		AgentState.Type.INTERACTING:
			_process_interacting(delta)
	_animate(delta)
	_update_need_warning()


func request_think() -> void:
	if is_dead:
		return
	if state == AgentState.Type.INTERACTING or state == AgentState.Type.TALKING:
		return
	if state == AgentState.Type.WALKING:
		return
	# Check for mental break when needs are critically low
	if _check_mental_break():
		return
	_make_decision()


func show_speech(text: String, duration: float = 3.0) -> void:
	# Bubbles are screen-space now (SpeechBubbleLayer): fixed size regardless
	# of camera zoom, capped in number, clamped to the play area.
	var layer := get_tree().get_first_node_in_group("speech_bubbles")
	if layer:
		layer.show_bubble(self, text, duration)


func enter_talking_state() -> void:
	state = AgentState.Type.TALKING
	velocity = Vector2.ZERO


func exit_talking_state() -> void:
	if state == AgentState.Type.TALKING:
		state = AgentState.Type.IDLE


func die(cause: String = "natural causes") -> void:
	if is_dead:
		return
	is_dead = true
	state = AgentState.Type.IDLE
	velocity = Vector2.ZERO
	# Death particles
	if _death_particles:
		_death_particles.emitting = true
	# Fade out sprite
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 2.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void:
		EventBus.agent_died.emit(agent_name, cause)
		EventBus.narrative_event.emit(
			"%s has passed away (%s)." % [agent_name, cause],
			[agent_name], 10.0
		)
		# Notify nearby agents for grief
		var nearby := AgentManager.get_agents_near(global_position, 300.0, self)
		for other in nearby:
			if other.has_method("witness_death"):
				other.witness_death(agent_name, cause)
		queue_free()
	)


func _on_confessional_recorded(confessional: RefCounted) -> void:
	## Remember what I said to camera.
	##
	## Without this the confessional is a dead end — the agent vents and forgets.
	## Storing it as a REFLECTION puts it in the retrieval pool the brain already
	## queries, so an agent who trash-talked someone on camera carries that into
	## later decisions instead of contradicting themselves an hour later.
	var c: Confessional = confessional as Confessional
	if not c or c.is_host or c.speaker != agent_name or is_dead:
		return

	var importance := 4.0
	var emotion := "candid"
	var sentiment := 0.0
	var protect := false
	match c.kind:
		"romance":
			importance = 6.0
			emotion = "vulnerable"
			sentiment = 0.5
		"tragedy":
			importance = 7.0
			emotion = "grief"
			sentiment = -0.8
			protect = true  # what you said about a death is a landmark
		"rivalry":
			importance = 5.0
			emotion = "defiance"
			sentiment = -0.5

	memory.add_memory(
		MemoryEntry.MemoryType.REFLECTION,
		"%s said this to the confessional camera: \"%s\"" % [agent_name, c.line],
		importance
	)
	var last: MemoryEntry = memory.memories[-1]
	last.emotion = emotion
	last.sentiment = sentiment
	last.decay_protected = protect
	last.narrative_thread = "confessional_%s" % c.kind


func witness_death(dead_name: String, cause: String) -> void:
	## Full grief response: memory, mourning modifier, relationship-scaled impact.
	var rel: RelationshipEntry = relationships.get_relationship(dead_name)
	var closeness: float = clampf((rel.affinity + rel.familiarity) / 150.0, 0.0, 1.0)

	# Core grief memory (protected from decay)
	memory.add_memory(
		MemoryEntry.MemoryType.OBSERVATION,
		"%s witnessed %s passing away from %s. This is deeply sad." % [agent_name, dead_name, cause],
		10.0, PackedStringArray([dead_name])
	)
	memory.memories[-1].emotion = "grief"
	memory.memories[-1].sentiment = -0.9
	memory.memories[-1].decay_protected = true

	# Scale grief impact by relationship closeness
	var social_penalty: float = -15.0 - closeness * 35.0  # -15 to -50
	needs.restore(NeedType.Type.SOCIAL, social_penalty)
	needs.restore(NeedType.Type.ENERGY, -10.0 * closeness)

	# Close friends/partners enter mourning (behavior modifier)
	if closeness > 0.3:
		var mourning_days: int = 2 + int(closeness * 5.0)  # 2-7 days of mourning
		add_behavior_modifier({
			"type": "mourning",
			"target": dead_name,
			"duration_days": mourning_days,
			"days_remaining": mourning_days,
			"source": "grief",
		})

		# Partners get extra memories
		if rel.relationship_status == RelationshipEntry.Status.DATING or rel.relationship_status == RelationshipEntry.Status.PARTNERS:
			memory.add_memory(
				MemoryEntry.MemoryType.OBSERVATION,
				"%s lost their partner %s. The grief is overwhelming." % [agent_name, dead_name],
				10.0, PackedStringArray([dead_name])
			)
			memory.memories[-1].emotion = "devastation"
			memory.memories[-1].sentiment = -1.0
			memory.memories[-1].decay_protected = true
			rel.relationship_status = RelationshipEntry.Status.EX
			rel.add_tag("deceased")


func add_behavior_modifier(modifier: Dictionary) -> void:
	_behavior_modifiers.append(modifier)


func get_active_modifiers() -> Array[Dictionary]:
	return _behavior_modifiers


func _tick_behavior_modifiers() -> void:
	## Called once per day — decrement modifier durations.
	var to_remove: Array[int] = []
	for i in range(_behavior_modifiers.size()):
		_behavior_modifiers[i]["days_remaining"] = _behavior_modifiers[i]["days_remaining"] - 1
		if _behavior_modifiers[i]["days_remaining"] <= 0:
			to_remove.append(i)
	# Remove expired (reverse order to preserve indices)
	to_remove.reverse()
	for idx in to_remove:
		var mod: Dictionary = _behavior_modifiers[idx]
		if mod.get("type", "") == "mourning":
			memory.add_observation(
				"%s feels the grief lifting, though they'll never forget %s." % [agent_name, mod.get("target", "someone")],
				3.0
			)
		_behavior_modifiers.remove_at(idx)


func _make_decision() -> void:
	state = AgentState.Type.DECIDING
	var nearby_objects := _get_nearby_objects()
	var nearby_agents := AgentManager.get_agents_near(global_position, 200.0, self)
	var decision: Dictionary = smart_brain.decide(needs, nearby_objects, nearby_agents)
	if decision.get("waiting_for_llm", false):
		state = AgentState.Type.IDLE
		return
	_execute_decision(decision)


func _execute_decision(decision: Dictionary) -> void:
	current_action = decision.get("action", ActionType.Type.IDLE)
	current_target = decision.get("target", null)

	match current_action:
		ActionType.Type.IDLE:
			state = AgentState.Type.IDLE
		ActionType.Type.WANDER:
			_start_wander()
			memory.add_action("%s decides to wander around the office." % agent_name, 1.0)
		ActionType.Type.GO_TO_OBJECT:
			if current_target:
				_navigate_to(current_target.global_position)
				memory.add_action("%s heads to the %s." % [agent_name, current_target.display_name], 2.0)
				EventBus.agent_action_started.emit(self, current_action, current_target)
			else:
				state = AgentState.Type.IDLE
		ActionType.Type.TALK_TO_AGENT:
			if current_target:
				_navigate_to(current_target.global_position)
				memory.add_action("%s goes to talk to %s." % [agent_name, current_target.agent_name], 3.0)
				EventBus.agent_action_started.emit(self, current_action, current_target)
			else:
				state = AgentState.Type.IDLE
		ActionType.Type.CONFESS_FEELINGS:
			if current_target:
				_navigate_to(current_target.global_position)
				memory.add_action("%s gathers courage to confess feelings to %s." % [agent_name, current_target.agent_name], 7.0)
				EventBus.agent_action_started.emit(self, current_action, current_target)
			else:
				state = AgentState.Type.IDLE


func _start_wander() -> void:
	var wander_offset := Vector2(randf_range(-80, 80), randf_range(-80, 80))
	_navigate_to(global_position + wander_offset)


func _navigate_to(target_pos: Vector2) -> void:
	nav_agent.target_position = target_pos
	state = AgentState.Type.WALKING


func _process_walking(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		_on_navigation_finished()
		return
	var next_pos := nav_agent.get_next_path_position()
	var direction := global_position.direction_to(next_pos)
	velocity = direction * Config.AGENT_MOVE_SPEED
	move_and_slide()
	if velocity.x != 0:
		sprite.flip_h = velocity.x < 0

	# Footstep SFX
	_footstep_timer += delta
	if _footstep_timer >= AudioManager.FOOTSTEP_INTERVAL:
		_footstep_timer = 0.0
		var sfx_name := "footstep_1" if randi() % 2 == 0 else "footstep_2"
		AudioManager.play_sfx(sfx_name, -12.0)


func _process_interacting(delta: float) -> void:
	_interact_timer += delta * TimeManager.current_speed
	if _interact_timer >= _interact_duration:
		_finish_interaction()


func _on_navigation_finished() -> void:
	velocity = Vector2.ZERO
	if current_action == ActionType.Type.GO_TO_OBJECT and current_target:
		_start_interaction()
	elif current_action == ActionType.Type.TALK_TO_AGENT and current_target:
		if current_target and not current_target.is_dead:
			ConversationManager.start_conversation(self, current_target)
		else:
			needs.restore(NeedType.Type.SOCIAL, 15.0)
			state = AgentState.Type.IDLE
	elif current_action == ActionType.Type.CONFESS_FEELINGS and current_target:
		if current_target and not current_target.is_dead:
			ConversationManager.start_confession(self, current_target)
		else:
			state = AgentState.Type.IDLE
	else:
		state = AgentState.Type.IDLE


func _start_interaction() -> void:
	if not current_target or not current_target.has_method("occupy"):
		state = AgentState.Type.IDLE
		return
	if not current_target.is_available():
		memory.add_observation("%s found the %s was occupied." % [agent_name, current_target.display_name], 1.0)
		state = AgentState.Type.IDLE
		return
	current_target.occupy(self)
	_interact_duration = current_target.get_interaction_duration()
	_interact_timer = 0.0
	state = AgentState.Type.INTERACTING
	EventBus.object_occupied.emit(current_target, self)
	# Interaction sparkles
	if _interaction_particles:
		_interaction_particles.emitting = true


func _finish_interaction() -> void:
	if current_target and current_target.has_method("release"):
		var effects: Dictionary = current_target.get_need_effects()
		for need in effects:
			needs.restore(need, effects[need])
		memory.add_action(
			"%s finished using the %s." % [agent_name, current_target.display_name], 2.0
		)
		current_target.release(self)
		EventBus.object_freed.emit(current_target, self)
		EventBus.agent_action_completed.emit(self, current_action, current_target)
	if _interaction_particles:
		_interaction_particles.emitting = false
	current_target = null
	state = AgentState.Type.IDLE


func _get_nearby_objects() -> Array:
	var objects: Array = []
	var bodies := interaction_area.get_overlapping_bodies()
	for body in bodies:
		if body is InteractableObject:
			objects.append(body)
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_method("get_all_objects"):
		for obj in world.get_all_objects():
			if obj not in objects:
				objects.append(obj)
	return objects


func _load_personality() -> void:
	if personality_file == "__procedural__" and not procedural_personality_data.is_empty():
		personality = PersonalityProfile.from_dict(procedural_personality_data)
	elif personality_file != "" and personality_file != "__procedural__":
		var path := "res://resources/personalities/%s.json" % personality_file
		personality = PersonalityProfile.load_from_json(path)
	else:
		return
	if personality:
		agent_name = personality.agent_name
		agent_color = personality.color
		_apply_personality_decay_rates()


func _apply_personality_decay_rates() -> void:
	for need_key in personality.need_decay_multipliers:
		var need_enum: NeedType.Type
		match need_key:
			"energy": need_enum = NeedType.Type.ENERGY
			"hunger": need_enum = NeedType.Type.HUNGER
			"social": need_enum = NeedType.Type.SOCIAL
			"productivity": need_enum = NeedType.Type.PRODUCTIVITY
			_: continue
		var base_rate: float = Config.NEED_DECAY_BASE.get(need_enum, 0.1)
		var multiplier: float = personality.need_decay_multipliers[need_key]
		needs.set_decay_rate(need_enum, base_rate * multiplier)


func _on_thought(thought: String) -> void:
	thought_bubble.text = thought
	thought_bubble.visible = true
	EventBus.narrative_event.emit(
		"%s thinks: \"%s\"" % [agent_name, thought],
		[agent_name], 2.0
	)
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(thought_bubble, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void:
		thought_bubble.visible = false
		thought_bubble.modulate.a = 1.0
	)


func _setup_sprite() -> void:
	match personality_file:
		"alice": _set_sprite_frames(SpriteFactory.create_alice())
		"bob": _set_sprite_frames(SpriteFactory.create_bob())
		"clara": _set_sprite_frames(SpriteFactory.create_clara())
		"dave": _set_sprite_frames(SpriteFactory.create_dave())
		"emma": _set_sprite_frames(SpriteFactory.create_emma())
		_:
			if personality:
				_set_sprite_frames(SpriteFactory.create_from_color(personality.color))
			else:
				_set_sprite_frames(SpriteFactory.create_character(
					Color(agent_color), Color(agent_color.darkened(0.3)), Palette.WOOD_DARK))
	if not _idle_frames.is_empty():
		sprite.texture = _idle_frames[0]


func _set_sprite_frames(all_frames: Array[ImageTexture]) -> void:
	# SpriteFactory now returns [idle_0, idle_1, walk_0, walk_1, walk_2, walk_3]
	if all_frames.size() >= 6:
		_idle_frames = [all_frames[0], all_frames[1]]
		_walk_frames = [all_frames[2], all_frames[3], all_frames[4], all_frames[5]]
	elif all_frames.size() >= 2:
		_idle_frames = [all_frames[0], all_frames[1]]
		_walk_frames = [all_frames[0], all_frames[1]]  # Fallback to idle
	elif all_frames.size() == 1:
		_idle_frames = [all_frames[0]]
		_walk_frames = [all_frames[0]]


func _animate(delta: float) -> void:
	_anim_timer += delta
	if state == AgentState.Type.WALKING and _walk_frames.size() >= 2:
		# Walk animation: faster cycle
		if _anim_timer >= 0.2:
			_anim_timer -= 0.2
			_anim_frame = (_anim_frame + 1) % _walk_frames.size()
			sprite.texture = _walk_frames[_anim_frame]
	elif _idle_frames.size() >= 2:
		# Idle bob: slower cycle
		if _anim_timer >= 0.8:
			_anim_timer -= 0.8
			_anim_frame = (_anim_frame + 1) % _idle_frames.size()
			sprite.texture = _idle_frames[_anim_frame]


func _setup_particles() -> void:
	# Interaction sparkles
	_interaction_particles = CPUParticles2D.new()
	_interaction_particles.emitting = false
	_interaction_particles.amount = 6
	_interaction_particles.lifetime = 0.6
	_interaction_particles.one_shot = false
	_interaction_particles.explosiveness = 0.3
	_interaction_particles.direction = Vector2(0, -1)
	_interaction_particles.spread = 60.0
	_interaction_particles.initial_velocity_min = 10.0
	_interaction_particles.initial_velocity_max = 25.0
	_interaction_particles.gravity = Vector2(0, 20)
	_interaction_particles.scale_amount_min = 0.5
	_interaction_particles.scale_amount_max = 1.0
	_interaction_particles.color = Color(1.0, 0.9, 0.4, 0.8)
	_interaction_particles.position = Vector2(0, -8)
	add_child(_interaction_particles)

	# Death particles
	_death_particles = CPUParticles2D.new()
	_death_particles.emitting = false
	_death_particles.amount = 12
	_death_particles.lifetime = 2.0
	_death_particles.one_shot = true
	_death_particles.explosiveness = 0.8
	_death_particles.direction = Vector2(0, -1)
	_death_particles.spread = 180.0
	_death_particles.initial_velocity_min = 5.0
	_death_particles.initial_velocity_max = 15.0
	_death_particles.gravity = Vector2(0, -5)
	_death_particles.scale_amount_min = 0.5
	_death_particles.scale_amount_max = 1.5
	_death_particles.color = Color(0.3, 0.3, 0.4, 0.6)
	add_child(_death_particles)


func _setup_selection_ring() -> void:
	_selection_ring = Node2D.new()
	_selection_ring.visible = false
	_selection_ring.z_index = -1
	add_child(_selection_ring)
	_selection_ring.draw.connect(_draw_selection_ring)


func _draw_selection_ring() -> void:
	if _selection_ring:
		var pulse := 0.6 + sin(Time.get_ticks_msec() * 0.005) * 0.2
		_selection_ring.draw_arc(Vector2(0, 2), 10.0, 0, TAU, 24, Color(1.0, 0.9, 0.3, pulse), 1.0)


func _on_global_agent_selected(agent: Node2D) -> void:
	_is_selected = (agent == self)
	_selection_ring.visible = _is_selected
	if _is_selected and _hover_tooltip:
		_hover_tooltip.visible = false


func _on_global_agent_deselected() -> void:
	_is_selected = false
	_selection_ring.visible = false


func _update_need_warning() -> void:
	# Flash name label red when any need is critical
	var any_critical := false
	var all_values: Dictionary = needs.get_all_values()
	for need in all_values:
		if need == NeedType.Type.HEALTH:
			continue
		var val: float = all_values[need]
		if val < Config.NEED_CRITICAL_THRESHOLD:
			any_critical = true
			break

	if any_critical:
		var pulse := 0.5 + sin(Time.get_ticks_msec() * 0.008) * 0.5
		label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, pulse))
	else:
		label.remove_theme_color_override("font_color")


func _update_mood_indicator() -> void:
	if is_dead or not health_state:
		return
	var new_mood := _determine_mood()
	if new_mood == _current_mood:
		return
	_current_mood = new_mood
	if new_mood == "":
		emotion_indicator.visible = false
		return
	emotion_indicator.text = new_mood
	emotion_indicator.add_theme_color_override("font_color", _get_mood_color(new_mood))
	emotion_indicator.visible = true
	emotion_indicator.modulate.a = 1.0
	# Pulse animation: scale up then back to normal
	emotion_indicator.pivot_offset = emotion_indicator.size * 0.5
	var tween := create_tween()
	tween.tween_property(emotion_indicator, "scale", Vector2(1.4, 1.4), 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(emotion_indicator, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_IN)


func _determine_mood() -> String:
	# Priority-ordered mood checks
	# 0. Mourning (grief)
	for mod in _behavior_modifiers:
		if mod.get("type", "") == "mourning":
			return "T_T"
	# 1. Sick conditions
	if not health_state.conditions.is_empty():
		return "~"
	# 2. Dying
	if health_state.life_stage == LifeStage.Type.DYING:
		return "..."
	# 3. Exhausted
	var energy: float = needs.get_value(NeedType.Type.ENERGY)
	if energy < 25.0:
		return "zzZ"
	# 4. Angry (has "angry_at" relationship tag or very low social with rival)
	if _has_angry_relationship():
		return "##"
	# 5. Hungry
	var hunger: float = needs.get_value(NeedType.Type.HUNGER)
	if hunger < 25.0:
		return "!"
	# 6. Stressed
	var productivity: float = needs.get_value(NeedType.Type.PRODUCTIVITY)
	if productivity < 20.0:
		return "!!"
	# 7. Romantic (dating/partners or high romantic interest)
	if _has_romantic_bond():
		return "♥"
	# 8. Happy (high social + energy)
	var social: float = needs.get_value(NeedType.Type.SOCIAL)
	if social > 70.0 and energy > 60.0:
		return "♪"
	# 9. Neutral — no indicator
	return ""


func _has_angry_relationship() -> bool:
	var all_rels: Dictionary = relationships.get_all_relationships()
	for rel_name in all_rels:
		var rel: RelationshipEntry = all_rels[rel_name]
		if rel.has_tag("angry_at"):
			return true
		# Very negative affinity with a rival counts as angry
		if rel.affinity < -60.0 and rel.has_tag("rival"):
			return true
	return false


func _has_romantic_bond() -> bool:
	var all_rels: Dictionary = relationships.get_all_relationships()
	for rel_name in all_rels:
		var rel: RelationshipEntry = all_rels[rel_name]
		if rel.relationship_status == RelationshipEntry.Status.DATING or rel.relationship_status == RelationshipEntry.Status.PARTNERS:
			return true
		if rel.romantic_interest > 50.0:
			return true
	return false


func _get_mood_color(mood: String) -> Color:
	match mood:
		"T_T": return Color(0.5, 0.5, 0.7, 0.9)       # blue-grey — mourning
		"♪": return Color(0.4, 0.9, 0.4, 0.95)       # green — happy
		"♥": return Color(1.0, 0.45, 0.55, 0.95)      # pink-red — lovestruck
		"zzZ": return Color(0.6, 0.65, 0.8, 0.85)     # blue-grey — tired
		"!": return Color(1.0, 0.75, 0.2, 0.95)        # amber — hungry
		"!!": return Color(1.0, 0.3, 0.3, 0.95)        # red — stressed
		"##": return Color(1.0, 0.2, 0.2, 0.95)        # red — angry
		"~": return Color(0.55, 0.8, 0.35, 0.85)       # sickly green — sick
		"...": return Color(0.7, 0.7, 0.7, 0.8)        # grey — dying
		_: return Color(0.9, 0.9, 0.9, 0.9)


func _on_day_changed(day: int) -> void:
	if is_dead or not health_state:
		return
	health_state.advance_day()
	_tick_behavior_modifiers()
	if health_state.health <= 0.0 or health_state.life_stage == LifeStage.Type.DEAD:
		die("old age")
	if health_state.life_stage == LifeStage.Type.SENIOR:
		needs.set_decay_rate(NeedType.Type.ENERGY, Config.NEED_DECAY_BASE.get(NeedType.Type.ENERGY, 0.15) * 1.5)
	if not health_state.conditions.is_empty():
		for condition in health_state.conditions:
			EventBus.agent_sick.emit(agent_name, condition)


func _on_input_event(viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		EventBus.agent_selected.emit(self)
		viewport.set_input_as_handled()


func _check_mental_break() -> bool:
	## Returns true if a mental break occurred (consuming the think tick).
	var all_values: Dictionary = needs.get_all_values()
	var any_below_10 := false
	for need in all_values:
		if need == NeedType.Type.HEALTH:
			continue
		var val: float = all_values[need]
		if val < 10.0:
			any_below_10 = true
			break
	if not any_below_10:
		return false
	# 20% chance per think tick
	if randf() >= 0.2:
		return false

	# Find the agent we like least
	var least_liked_name: String = ""
	var least_affinity: float = INF
	var all_rels: Dictionary = relationships.get_all_relationships()
	for other_name in all_rels:
		var rel: RelationshipEntry = all_rels[other_name]
		if rel.affinity < least_affinity:
			least_affinity = rel.affinity
			least_liked_name = other_name

	# If no relationships yet, pick a random nearby agent
	if least_liked_name == "":
		var nearby := AgentManager.get_agents_near(global_position, 200.0, self)
		if not nearby.is_empty():
			var target: Node2D = nearby[randi() % nearby.size()]
			least_liked_name = target.agent_name

	# Reduce affinity with all nearby agents by 5
	var nearby_agents := AgentManager.get_agents_near(global_position, 120.0, self)
	for other in nearby_agents:
		if not is_instance_valid(other):
			continue
		var rel: RelationshipEntry = relationships.get_relationship(other.agent_name)
		rel.affinity = clampf(rel.affinity - 5.0, -100.0, 100.0)
		EventBus.relationship_changed.emit(agent_name, other.agent_name, rel)

	# Add memory about the outburst
	var outburst_desc: String
	if least_liked_name != "":
		outburst_desc = "%s had a mental breakdown and lashed out at %s." % [agent_name, least_liked_name]
	else:
		outburst_desc = "%s had a mental breakdown and lashed out at everyone nearby." % agent_name
	memory.add_memory(
		MemoryEntry.MemoryType.OBSERVATION,
		outburst_desc,
		8.0, PackedStringArray([least_liked_name]) if least_liked_name != "" else PackedStringArray()
	)
	memory.memories[-1].emotion = "rage"
	memory.memories[-1].sentiment = -0.9
	memory.memories[-1].decay_protected = true

	# Nearby agents also remember this
	for other in nearby_agents:
		if not is_instance_valid(other):
			continue
		other.memory.add_memory(
			MemoryEntry.MemoryType.OBSERVATION,
			"%s witnessed %s having a mental breakdown." % [other.agent_name, agent_name],
			6.0, PackedStringArray([agent_name])
		)
		other.memory.memories[-1].emotion = "shock"
		other.memory.memories[-1].sentiment = -0.4

	# Emit narrative event
	var narrative_agents: Array = [agent_name]
	if least_liked_name != "":
		narrative_agents.append(least_liked_name)
	EventBus.narrative_event.emit(
		outburst_desc,
		narrative_agents, 8.0
	)

	# Show speech bubble
	show_speech("I can't take this anymore!", 4.0)
	state = AgentState.Type.IDLE
	return true


func _process(_delta: float) -> void:
	# Redraw selection ring for pulse animation
	if _is_selected and _selection_ring:
		_selection_ring.queue_redraw()
	# Update hover tooltip position
	if _is_hovered and _hover_tooltip and _hover_tooltip.visible:
		_hover_tooltip.global_position = global_position + Vector2(12, -40)


func _setup_hover_tooltip() -> void:
	_hover_tooltip = PanelContainer.new()
	_hover_tooltip.visible = false
	_hover_tooltip.z_index = 50
	_hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	style.border_color = Color(0.35, 0.35, 0.4, 0.8)
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
	# Connect mouse hover on ClickArea
	var click_area: Area2D = $ClickArea
	click_area.mouse_entered.connect(_on_mouse_entered)
	click_area.mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	if is_dead or _is_selected:
		return
	_is_hovered = true
	_update_hover_tooltip()
	_hover_tooltip.visible = true


func _on_mouse_exited() -> void:
	_is_hovered = false
	_hover_tooltip.visible = false


func _update_hover_tooltip() -> void:
	var lbl: Label = _hover_tooltip.get_node("TooltipLabel")
	if not lbl:
		return
	var state_names := ["Idle", "Deciding", "Walking", "Using object", "Talking"]
	var state_text: String = state_names[state] if state < state_names.size() else "?"
	# Find lowest need
	var lowest_need_name := ""
	var lowest_val: float = 999.0
	var all_values: Dictionary = needs.get_all_values()
	for need in all_values:
		if need == NeedType.Type.HEALTH:
			continue
		var val: float = all_values[need]
		if val < lowest_val:
			lowest_val = val
			lowest_need_name = NeedType.to_string_name(need)
	var text := "%s | %s" % [agent_name, state_text]
	if lowest_val < 50.0:
		text += "\nNeeds %s (%.0f%%)" % [lowest_need_name.to_lower(), lowest_val]
	if _current_mood != "":
		text += " %s" % _current_mood
	lbl.text = text
