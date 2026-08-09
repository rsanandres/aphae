class_name AgentMemory
extends Node
## Per-agent memory stream with retrieval scoring, narrative threads, and reflection triggers.

const MAX_MEMORIES := 300
const MAX_MEMORIES_BACKGROUND := 100  # Reduced budget for background-tier agents
const REFLECTION_IMPORTANCE_THRESHOLD := 50.0
const COMPACTION_BATCH := 50
const LIFE_SUMMARY_INTERVAL := 50  # regenerate every N memories
var memory_budget: int = MAX_MEMORIES  # Can be reduced for background agents

var memories: Array[MemoryEntry] = []
var _importance_accumulator: float = 0.0
var _agent_name: String = ""
var _is_reflecting: bool = false
var _memory_count_since_summary: int = 0
var _life_summary: String = ""


func setup(agent_name: String) -> void:
	_agent_name = agent_name


func add_memory(type: MemoryEntry.MemoryType, description: String, importance: float = 3.0, related_agents: PackedStringArray = []) -> void:
	var entry := MemoryEntry.new(type, description, TimeManager.game_minutes, importance)
	entry.related_agents = related_agents
	memories.append(entry)
	_importance_accumulator += importance
	_memory_count_since_summary += 1

	# Trigger reflection if accumulated importance is high enough
	if _importance_accumulator >= REFLECTION_IMPORTANCE_THRESHOLD and not _is_reflecting:
		_trigger_reflection()

	# Regenerate life summary periodically
	if _memory_count_since_summary >= LIFE_SUMMARY_INTERVAL:
		_regenerate_life_summary()

	# Compact if too many memories
	if memories.size() > memory_budget:
		_compact()


func add_observation(description: String, importance: float = 2.0) -> void:
	add_memory(MemoryEntry.MemoryType.OBSERVATION, description, importance)


func add_action(description: String, importance: float = 3.0) -> void:
	add_memory(MemoryEntry.MemoryType.ACTION, description, importance)


func add_conversation(description: String, related_agent: String, importance: float = 5.0) -> void:
	add_memory(MemoryEntry.MemoryType.CONVERSATION, description, importance, PackedStringArray([related_agent]))


func add_reflection(description: String) -> void:
	add_memory(MemoryEntry.MemoryType.REFLECTION, description, 8.0)


func retrieve(query: String, count: int = 5) -> Array[MemoryEntry]:
	if memories.is_empty():
		return []
	var query_keywords := _extract_keywords(query)
	var scored: Array[Dictionary] = []
	var current_time := TimeManager.game_minutes

	for mem in memories:
		var score := _score_memory(mem, query_keywords, current_time)
		scored.append({"memory": mem, "score": score})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])

	var result: Array[MemoryEntry] = []
	var limit := mini(count, scored.size())
	for i in range(limit):
		result.append(scored[i]["memory"])
	return result


func get_secrets() -> Array[MemoryEntry]:
	## Everything this agent knows that someone meant to keep hidden —
	## their own secrets and leaked ones alike (thread "secret_*").
	var out: Array[MemoryEntry] = []
	for m in memories:
		if m.narrative_thread.begins_with("secret_"):
			out.append(m)
	return out


func get_recent(count: int = 10) -> Array[MemoryEntry]:
	var start := maxi(0, memories.size() - count)
	var result: Array[MemoryEntry] = []
	for i in range(start, memories.size()):
		result.append(memories[i])
	return result


func get_memories_about(agent_name: String, count: int = 10) -> Array[MemoryEntry]:
	var result: Array[MemoryEntry] = []
	# Iterate in reverse for recency
	for i in range(memories.size() - 1, -1, -1):
		var mem := memories[i]
		if agent_name in mem.related_agents or agent_name.to_lower() in mem.description.to_lower():
			result.append(mem)
			if result.size() >= count:
				break
	return result


func get_narrative_threads() -> Dictionary:
	## Returns {thread_name: Array[MemoryEntry]}
	var threads: Dictionary = {}
	for mem in memories:
		if mem.narrative_thread != "":
			if not threads.has(mem.narrative_thread):
				threads[mem.narrative_thread] = []
			threads[mem.narrative_thread].append(mem)
	return threads


func get_life_summary() -> String:
	if _life_summary == "":
		_regenerate_life_summary_sync()
	return _life_summary


func format_memories_for_prompt(mems: Array[MemoryEntry]) -> String:
	if mems.is_empty():
		return "(no memories yet)"
	var lines: PackedStringArray = []
	for mem in mems:
		var time_str := "%02d:%02d" % [int(mem.timestamp / 60.0) % 24, int(mem.timestamp) % 60]
		var emotion_tag := ""
		if mem.emotion != "":
			emotion_tag = " [%s]" % mem.emotion
		lines.append("- [%s]%s %s" % [time_str, emotion_tag, mem.description])
	return "\n".join(lines)


func _score_memory(mem: MemoryEntry, query_keywords: PackedStringArray, current_time: float) -> float:
	# Recency: exponential decay, half-life of 120 game minutes
	var age := maxf(current_time - mem.timestamp, 0.0)
	var recency := exp(-0.00578 * age)  # ln(2)/120

	# Importance: normalized to 0-1
	var importance := mem.importance / 10.0

	# Relevance: keyword overlap
	var relevance := 0.0
	if not query_keywords.is_empty() and not mem.keywords.is_empty():
		var overlap := 0
		for kw in query_keywords:
			if kw in mem.keywords:
				overlap += 1
		relevance = float(overlap) / float(query_keywords.size())

	# Emotional resonance: memories matching current emotional state score higher
	var emotion_bonus := 0.0
	if mem.emotion != "" and mem.decay_protected:
		emotion_bonus = 0.2

	# Sentiment weight: high-sentiment memories are more memorable
	var sentiment_bonus := absf(mem.sentiment) * 0.15

	return recency + importance + relevance + emotion_bonus + sentiment_bonus


func _extract_keywords(text: String) -> PackedStringArray:
	var words := text.to_lower().split(" ", false)
	var result: PackedStringArray = []
	for word in words:
		var clean := word.strip_edges().trim_suffix(".").trim_suffix(",")
		if clean.length() > 2:
			result.append(clean)
	return result


func _trigger_reflection() -> void:
	_is_reflecting = true
	_importance_accumulator = 0.0

	if not LLMManager.is_available:
		# Heuristic reflection
		var recent_heur: Array[MemoryEntry] = get_recent(5)
		if not recent_heur.is_empty():
			add_reflection("%s reflects on recent events and feels %s about how things are going." % [
				_agent_name, ["good", "okay", "uncertain", "thoughtful"].pick_random()
			])
		_is_reflecting = false
		return

	var recent: Array[MemoryEntry] = get_recent(10)
	var recent_text := format_memories_for_prompt(recent)
	var agent := get_parent()
	var profile: PersonalityProfile = agent.personality if agent and agent.get("personality") else null

	var prompt := PromptBuilder.build("reflection", {
		"name": _agent_name,
		"description": profile.description if profile else "",
		"personality": profile.get_personality_summary() if profile else "",
		"recent_memories": recent_text,
	})

	var format_schema := {
		"type": "object",
		"properties": {
			"reflection": {"type": "string"},
			"emotion": {"type": "string"},
			"narrative_thread": {"type": "string"},
		},
		"required": ["reflection"],
	}

	LLMManager.request_chat(
		[
			{"role": "user", "content": prompt},
		],
		format_schema,
		func(success: bool, data: Dictionary, _error: String) -> void:
			_is_reflecting = false
			if success and data.has("reflection"):
				var reflection_text: String = str(data["reflection"])
				add_reflection(reflection_text)
				# Apply emotional metadata to the reflection
				if data.has("emotion"):
					memories[-1].emotion = str(data["emotion"])
				if data.has("narrative_thread"):
					memories[-1].narrative_thread = str(data["narrative_thread"])
			else:
				add_reflection("%s takes a moment to think about recent events." % _agent_name),
		LLMManager.Priority.LOW,
	)


func _regenerate_life_summary() -> void:
	_memory_count_since_summary = 0
	if not LLMManager.is_available:
		_regenerate_life_summary_sync()
		return
	# Collect key memories for summary
	var key_memories: Array[MemoryEntry] = []
	for mem in memories:
		if mem.importance >= 5.0 or mem.type == MemoryEntry.MemoryType.REFLECTION or mem.decay_protected:
			key_memories.append(mem)
	if key_memories.is_empty():
		return
	# Trim to last 20 key memories
	if key_memories.size() > 20:
		key_memories = key_memories.slice(key_memories.size() - 20)
	var mems_text := format_memories_for_prompt(key_memories)
	var prompt := "Summarize %s's life story so far in 2-3 sentences based on these key memories:\n%s" % [_agent_name, mems_text]
	var format_schema := {
		"type": "object",
		"properties": {"summary": {"type": "string"}},
		"required": ["summary"],
	}
	LLMManager.request_chat(
		[{"role": "user", "content": prompt}],
		format_schema,
		func(success: bool, data: Dictionary, _error: String) -> void:
			if success and data.has("summary"):
				_life_summary = str(data["summary"]),
		LLMManager.Priority.LOW,
	)


func _regenerate_life_summary_sync() -> void:
	# Simple heuristic life summary
	var reflections: Array[MemoryEntry] = []
	for mem in memories:
		if mem.type == MemoryEntry.MemoryType.REFLECTION:
			reflections.append(mem)
	if reflections.is_empty():
		_life_summary = "%s is settling into office life." % _agent_name
	else:
		_life_summary = reflections[-1].description


func _compact() -> void:
	# Keep reflections, high-importance, and decay-protected memories
	var to_remove: Array[int] = []
	for i in range(mini(COMPACTION_BATCH, memories.size())):
		var mem := memories[i]
		if mem.type != MemoryEntry.MemoryType.REFLECTION and mem.importance < 5.0 and not mem.decay_protected:
			to_remove.append(i)
	# Remove in reverse order to preserve indices
	to_remove.reverse()
	for idx in to_remove:
		memories.remove_at(idx)
