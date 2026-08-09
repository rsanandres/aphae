extends Node
## Global signal bus decoupling all systems.

# Agent signals
signal agent_spawned(agent: Node2D)
signal agent_state_changed(agent: Node2D, old_state: AgentState.Type, new_state: AgentState.Type)
signal agent_need_changed(agent: Node2D, need: NeedType.Type, value: float)
signal agent_need_critical(agent: Node2D, need: NeedType.Type)
signal agent_action_started(agent: Node2D, action: ActionType.Type, target: Node2D)
signal agent_action_completed(agent: Node2D, action: ActionType.Type, target: Node2D)
signal agent_selected(agent: Node2D)
signal agent_deselected()
signal agent_spawned_dynamic(agent: Node2D)
signal agent_removed(agent_name: String)

# Relationship signals
signal relationship_changed(agent_name: String, target_name: String, relationship: RefCounted)

# Conversation signals
signal conversation_started(agent_a: String, agent_b: String)
signal conversation_ended(agent_a: String, agent_b: String)
signal conversation_line(speaker: String, line: String)

# Object signals
signal object_occupied(object: Node2D, agent: Node2D)
signal object_freed(object: Node2D, agent: Node2D)
signal object_placed(object: Node2D, position: Vector2)
signal object_removed(object: Node2D)

# Time signals
signal time_tick(game_minutes: float)
signal day_changed(day: int)
signal time_speed_changed(speed_index: int)
signal time_paused()
signal time_resumed()

# Health & Life signals
signal agent_died(agent_name: String, cause: String)
signal agent_departed(agent_name: String, reason: String)
signal dilemma_offered(definition: RefCounted, target_names: Array)
signal dilemma_resolved(event_id: String, choice_idx: int, by_timeout: bool)
signal influence_changed(balance: int, delta: int, reason: String)
signal episode_ended(season: int, episode: int, score: int, payout: int)
signal catalog_purchased(item_id: String)
signal agent_sick(agent_name: String, condition: String)
signal agent_life_stage_changed(agent_name: String, stage: int)

# Event signals
signal event_triggered(event_id: String, affected_agents: Array)
signal event_ended(event_id: String)

# Romance signals
signal romance_started(agent_a: String, agent_b: String)
signal confession_made(confessor: String, target: String, accepted: bool)

# Narrative signals
signal narrative_event(text: String, agents: Array, importance: float)

# Group signals
signal group_formed(group: RefCounted)
signal group_dissolved(group: RefCounted)
signal group_rivalry_detected(group_a: RefCounted, group_b: RefCounted)

# Narrator signals
signal storyline_updated(storyline: RefCounted)

# Confessional signals
signal confessional_recorded(confessional: RefCounted)

# Player director signals ("producer" controls)
signal nudge_answered(agent_name: String, request: String, complied: bool, reason: String)
signal interview_answered(agent_name: String, question: String, answer: String)
signal rumor_planted(agent_name: String, text: String)

# Achievement signals
signal achievement_unlocked(id: String, name: String)

# All agents dead
signal all_agents_dead()

# Game signals
signal game_ready()
signal god_mode_toggled(enabled: bool)
