extends Node
## AI Narrator: observes all narrative signals, clusters events into storylines,
## curates the most interesting stories, and provides summaries.

var storylines: Array[Storyline] = []
var feed: Array[StoryEntry] = []
var _event_buffer: Array[Dictionary] = []  # Buffered events for analysis
var _analyze_timer: float = 0.0
var _next_storyline_id: int = 0

const ANALYZE_INTERVAL := 120.0  # real seconds
const MAX_STORYLINES := 30
const MAX_FEED := 50


func _ready() -> void:
	# Subscribe to all narrative signals
	EventBus.narrative_event.connect(_on_narrative_event)
	EventBus.relationship_changed.connect(_on_relationship_changed)
	EventBus.conversation_ended.connect(_on_conversation_ended)
	EventBus.confession_made.connect(_on_confession_made)
	EventBus.agent_died.connect(_on_agent_died)
	EventBus.romance_started.connect(_on_romance_started)
	EventBus.group_formed.connect(_on_group_formed)
	EventBus.group_rivalry_detected.connect(_on_group_rivalry)


func _process(delta: float) -> void:
	_analyze_timer += delta
	if _analyze_timer >= ANALYZE_INTERVAL:
		_analyze_timer = 0.0
		_analyze_storylines()


func get_top_storylines(count: int = 5) -> Array[Storyline]:
	var sorted := storylines.duplicate()
	sorted.sort_custom(func(a: Storyline, b: Storyline) -> bool:
		return a.drama_score > b.drama_score
	)
	var result: Array[Storyline] = []
	var limit := mini(count, sorted.size())
	for i in range(limit):
		result.append(sorted[i])
	return result


func get_feed(count: int = 20) -> Array[StoryEntry]:
	var start := maxi(0, feed.size() - count)
	var result: Array[StoryEntry] = []
	for i in range(start, feed.size()):
		result.append(feed[i])
	return result


func _on_narrative_event(text: String, agents: Array, importance: float) -> void:
	if importance < 3.0:
		return  # Skip trivial events
	var agent_names: Array[String] = []
	for a in agents:
		agent_names.append(str(a))
	_event_buffer.append({
		"text": text,
		"agents": agent_names,
		"importance": importance,
		"day": TimeManager.day,
		"timestamp": TimeManager.time_string,
	})


func _on_relationship_changed(agent_name: String, target_name: String, _rel: RefCounted) -> void:
	_event_buffer.append({
		"text": "%s's relationship with %s changed significantly." % [agent_name, target_name],
		"agents": [agent_name, target_name] as Array[String],
		"importance": 4.0,
		"day": TimeManager.day,
		"timestamp": TimeManager.time_string,
	})


func _on_conversation_ended(agent_a: String, agent_b: String) -> void:
	_event_buffer.append({
		"text": "%s and %s finished a conversation." % [agent_a, agent_b],
		"agents": [agent_a, agent_b] as Array[String],
		"importance": 2.0,
		"day": TimeManager.day,
		"timestamp": TimeManager.time_string,
	})


func _on_confession_made(confessor: String, target: String, accepted: bool) -> void:
	var outcome := "accepted" if accepted else "rejected"
	_event_buffer.append({
		"text": "%s confessed feelings to %s and was %s." % [confessor, target, outcome],
		"agents": [confessor, target] as Array[String],
		"importance": 9.0,
		"day": TimeManager.day,
		"timestamp": TimeManager.time_string,
		"category_hint": "romance",
	})


func _on_agent_died(agent_name: String, cause: String) -> void:
	_event_buffer.append({
		"text": "%s has died (%s)." % [agent_name, cause],
		"agents": [agent_name] as Array[String],
		"importance": 10.0,
		"day": TimeManager.day,
		"timestamp": TimeManager.time_string,
		"category_hint": "tragedy",
	})


func _on_romance_started(agent_a: String, agent_b: String) -> void:
	_event_buffer.append({
		"text": "%s and %s started a romance." % [agent_a, agent_b],
		"agents": [agent_a, agent_b] as Array[String],
		"importance": 8.0,
		"day": TimeManager.day,
		"timestamp": TimeManager.time_string,
		"category_hint": "romance",
	})


func _on_group_formed(group: RefCounted) -> void:
	var sg: SocialGroup = group as SocialGroup
	if not sg:
		return
	_event_buffer.append({
		"text": "A new group formed: %s (%s)" % [sg.group_name, ", ".join(sg.members)],
		"agents": sg.members.duplicate() as Array[String],
		"importance": 5.0,
		"day": TimeManager.day,
		"timestamp": TimeManager.time_string,
	})


func _on_group_rivalry(group_a: RefCounted, group_b: RefCounted) -> void:
	var a: SocialGroup = group_a as SocialGroup
	var b: SocialGroup = group_b as SocialGroup
	if not a or not b:
		return
	var all_agents: Array[String] = []
	for m in a.members:
		all_agents.append(m)
	for m in b.members:
		if m not in all_agents:
			all_agents.append(m)
	_event_buffer.append({
		"text": "Rivalry detected between %s and %s." % [a.group_name, b.group_name],
		"agents": all_agents,
		"importance": 6.0,
		"day": TimeManager.day,
		"timestamp": TimeManager.time_string,
		"category_hint": "rivalry",
	})


func _analyze_storylines() -> void:
	if _event_buffer.is_empty():
		return

	# Cluster buffered events by shared agents (2+ shared agents = same storyline)
	var clusters: Array[Array] = []
	var assigned: Array[bool] = []
	assigned.resize(_event_buffer.size())
	assigned.fill(false)

	for i in range(_event_buffer.size()):
		if assigned[i]:
			continue
		var cluster: Array[Dictionary] = [_event_buffer[i]]
		assigned[i] = true
		var cluster_agents: Array[String] = []
		for a in _event_buffer[i].get("agents", []):
			if a not in cluster_agents:
				cluster_agents.append(a)

		for j in range(i + 1, _event_buffer.size()):
			if assigned[j]:
				continue
			var ev_agents: Array = _event_buffer[j].get("agents", [])
			var shared := 0
			for a in ev_agents:
				if a in cluster_agents:
					shared += 1
			if shared >= 1:  # At least 1 shared agent
				cluster.append(_event_buffer[j])
				assigned[j] = true
				for a in ev_agents:
					if a not in cluster_agents:
						cluster_agents.append(a)

		if cluster.size() >= 1:
			clusters.append(cluster)

	# Match clusters to existing storylines or create new ones
	for cluster in clusters:
		var cluster_agents: Array[String] = []
		for ev in cluster:
			for a in ev.get("agents", []):
				if a not in cluster_agents:
					cluster_agents.append(a)

		var best_match: Storyline = null
		var best_overlap: float = 0.0
		for sl in storylines:
			var overlap := _agent_overlap(cluster_agents, sl.involved_agents)
			if overlap > best_overlap:
				best_overlap = overlap
				best_match = sl

		if best_match and best_overlap > 0.3:
			# Add events to existing storyline
			for ev in cluster:
				best_match.add_event(ev.get("text", ""), ev.get("day", 0), ev.get("importance", 1.0), ev.get("timestamp", ""))
			# Update involved agents
			for a in cluster_agents:
				if a not in best_match.involved_agents:
					best_match.involved_agents.append(a)
			# Update category from hints
			for ev in cluster:
				if ev.has("category_hint"):
					best_match.category = ev["category_hint"]
			best_match.recalculate_drama_score()
			EventBus.storyline_updated.emit(best_match)
		else:
			# Create new storyline
			var sl := Storyline.new()
			sl.title = _generate_title(cluster, cluster_agents)
			sl.involved_agents = cluster_agents
			for ev in cluster:
				sl.events.append(ev)
				if ev.has("category_hint"):
					sl.category = ev["category_hint"]
			sl.recalculate_drama_score()
			storylines.append(sl)
			_next_storyline_id += 1
			EventBus.storyline_updated.emit(sl)

		# Add to feed
		for ev in cluster:
			var entry := StoryEntry.new()
			entry.text = ev.get("text", "")
			entry.day = ev.get("day", 0)
			entry.drama_level = ev.get("importance", 1.0)
			feed.append(entry)

	# Clear buffer
	_event_buffer.clear()

	# Prune old storylines
	while storylines.size() > MAX_STORYLINES:
		# Remove lowest drama score
		var min_idx := 0
		var min_score: float = storylines[0].drama_score
		for i in range(1, storylines.size()):
			if storylines[i].drama_score < min_score:
				min_score = storylines[i].drama_score
				min_idx = i
		storylines[min_idx].is_active = false
		storylines.remove_at(min_idx)

	# Prune feed
	while feed.size() > MAX_FEED:
		feed.pop_front()

	# Request LLM summaries for top storylines (LOW priority)
	_request_summaries()


func _agent_overlap(agents_a: Array[String], agents_b: Array[String]) -> float:
	if agents_a.is_empty() or agents_b.is_empty():
		return 0.0
	var shared := 0
	for a in agents_a:
		if a in agents_b:
			shared += 1
	return float(shared) / max(agents_a.size(), agents_b.size())


func _generate_title(cluster: Array, agents: Array[String]) -> String:
	## Placeholder until the LLM writes a real one. Naming the cast beats quoting
	## the first event: a hard character cut produced titles that ended mid-word,
	## like "Maya's relationship with Devon chan...".
	if not agents.is_empty():
		match agents.size():
			1:
				return "%s's Story" % agents[0]
			2:
				return "%s & %s" % [agents[0], agents[1]]
			_:
				return "%s, %s & %d more" % [agents[0], agents[1], agents.size() - 2]

	if cluster.is_empty():
		return "Untitled Story"
	var first_text := str(cluster[0].get("text", "")).strip_edges()
	if first_text.is_empty():
		return "Untitled Story"
	return _truncate_on_word(first_text, 40)


func _truncate_on_word(text: String, limit: int) -> String:
	## Cuts at the last whole word inside the limit, so titles never end mid-word.
	if text.length() <= limit:
		return text
	var cut := text.substr(0, limit)
	var space := cut.rfind(" ")
	if space > limit / 2:
		cut = cut.substr(0, space)
	return cut.strip_edges().trim_suffix(".").trim_suffix(",") + "…"


func _request_summaries() -> void:
	if not LLMManager.is_available or LLMManager.get_queue_size() > 8:
		return
	var top := get_top_storylines(3)
	for sl in top:
		if sl.summary != "" and sl.events.size() < 5:
			continue  # Already summarized and not many new events
		var events_text: PackedStringArray = []
		for ev in sl.events:
			events_text.append("[Day %d] %s" % [ev.get("day", 0), ev.get("text", "")])

		var prompt := PromptBuilder.build("narrator_summary", {
			"agents": ", ".join(sl.involved_agents),
			"events": "\n".join(events_text),
			"category": sl.category,
		})

		var messages := [
			{"role": "system", "content": "You are a narrator for an office simulation. Write engaging, concise story summaries."},
			{"role": "user", "content": prompt},
		]

		var format := {
			"type": "object",
			"properties": {
				"title": {"type": "string"},
				"summary": {"type": "string"},
				"drama": {"type": "number"},
			},
			"required": ["title", "summary"],
		}

		var storyline_ref: Storyline = sl
		LLMManager.request_chat(messages, format, func(success: bool, data: Dictionary, _error: String) -> void:
			if success:
				if data.has("title") and data["title"] != "":
					storyline_ref.title = data["title"]
				if data.has("summary"):
					storyline_ref.summary = data["summary"]
				if data.has("drama"):
					storyline_ref.drama_score = clampf(float(data["drama"]), 0.0, 10.0)
				EventBus.storyline_updated.emit(storyline_ref)
		, LLMManager.Priority.LOW)
