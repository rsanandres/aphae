extends Node
## Autoload: tracks active conversations, prevents double-booking agents.

var _active_conversations: Array[ConversationInstance] = []
var _agents_in_conversation: Dictionary = {}  # agent_name -> bool


func start_conversation(agent_a: Node2D, agent_b: Node2D) -> bool:
	# A two-seat object can hand us an occupant that has since been freed.
	if not is_instance_valid(agent_a) or not is_instance_valid(agent_b) or agent_a == agent_b:
		return false
	if is_agent_busy(agent_a.agent_name) or is_agent_busy(agent_b.agent_name):
		# One of them is already in a conversation
		agent_a.needs.restore(NeedType.Type.SOCIAL, 5.0)
		if agent_a.state == AgentState.Type.WALKING or agent_a.state == AgentState.Type.DECIDING:
			agent_a.state = AgentState.Type.IDLE
		return false
	if agent_b.is_dead or agent_b.state == AgentState.Type.INTERACTING:
		agent_a.needs.restore(NeedType.Type.SOCIAL, 5.0)
		if agent_a.state != AgentState.Type.IDLE:
			agent_a.state = AgentState.Type.IDLE
		return false

	_agents_in_conversation[agent_a.agent_name] = true
	_agents_in_conversation[agent_b.agent_name] = true

	var instance := ConversationInstance.new()
	add_child(instance)
	_active_conversations.append(instance)
	instance.conversation_finished.connect(_on_conversation_finished)
	instance.start(agent_a, agent_b)
	return true


func start_confession(agent_a: Node2D, agent_b: Node2D) -> bool:
	if is_agent_busy(agent_a.agent_name) or is_agent_busy(agent_b.agent_name):
		if agent_a.state != AgentState.Type.IDLE:
			agent_a.state = AgentState.Type.IDLE
		return false

	_agents_in_conversation[agent_a.agent_name] = true
	_agents_in_conversation[agent_b.agent_name] = true

	var instance := ConversationInstance.new()
	add_child(instance)
	_active_conversations.append(instance)
	instance.conversation_finished.connect(_on_conversation_finished)
	instance.start(agent_a, agent_b, true)
	return true


func is_agent_busy(agent_name: String) -> bool:
	return _agents_in_conversation.get(agent_name, false)


func _on_conversation_finished(agent_a_name: String, agent_b_name: String) -> void:
	_agents_in_conversation.erase(agent_a_name)
	_agents_in_conversation.erase(agent_b_name)
	# Clean up finished instances
	var to_remove: Array[ConversationInstance] = []
	for inst in _active_conversations:
		if not is_instance_valid(inst):
			to_remove.append(inst)
	for inst in to_remove:
		_active_conversations.erase(inst)
