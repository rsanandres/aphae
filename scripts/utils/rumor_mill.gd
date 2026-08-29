class_name RumorMill
## Information moves between agents through conversation, distorting as it
## goes. This is what makes a secret able to LEAK — and a secret that cannot
## leak carries no tension. Called from ConversationInstance at wrap-up.

const BASE_CHANCE := 0.15
const SECRET_TRUST_GATE := 60.0  # you only whisper secrets to people you trust
const MIN_IMPORTANCE := 5.0


static func maybe_pass(speaker: Node2D, listener: Node2D) -> bool:
	## One roll: the speaker may pass their juiciest recent memory about a
	## third party to the listener, secondhand and slightly warped.
	## Returns true when something was passed.
	if not is_instance_valid(speaker) or not is_instance_valid(listener):
		return false
	var rel: RelationshipEntry = speaker.relationships.get_relationship(listener.agent_name)
	var chance: float = BASE_CHANCE * clampf(rel.trust / 60.0, 0.3, 1.2)
	if randf() > chance:
		return false

	var candidate: MemoryEntry = _juiciest_thirdparty_memory(speaker, listener, rel)
	if candidate == null:
		return false

	# Distortion: secondhand knowledge is attributed, weaker, and sometimes
	# warped in tone.
	var text := candidate.description
	# Strip the owner-name prefix convention ("Name: did a thing").
	var colon := text.find(": ")
	if colon > 0 and colon <= 24:
		text = text.substr(colon + 2)
	var warped := randf() < 0.2
	var retold := "%s heard from %s: %s%s" % [
		listener.agent_name, speaker.agent_name, text,
		" ...at least that's the story going around." if warped else "",
	]
	var mem: MemoryEntry = listener.memory.add_memory(
		MemoryEntry.MemoryType.OBSERVATION, retold,
		maxf(candidate.importance - 1.0, 1.0), candidate.related_agents)
	mem.emotion = "curiosity"
	mem.sentiment = candidate.sentiment * (0.6 if warped else 0.8)
	mem.narrative_thread = candidate.narrative_thread
	# SecretManager tracks which ears a secret has reached through this chain.
	EventBus.rumor_passed.emit(listener.agent_name, speaker.agent_name, candidate.narrative_thread)
	return true


static func _juiciest_thirdparty_memory(speaker: Node2D, listener: Node2D, rel: RelationshipEntry) -> MemoryEntry:
	var best: MemoryEntry = null
	var mems: Array = speaker.memory.memories
	var start: int = maxi(0, mems.size() - 20)
	for i in range(mems.size()):
		# Recent memories are the gossip pool — but secret-thread memories
		# never age out of it, or a confide gets buried under a day of
		# mundane observations before it can ever hop.
		if i < start and not (mems[i] as MemoryEntry).narrative_thread.begins_with("secret_"):
			continue
		var m: MemoryEntry = mems[i]
		if m.importance < MIN_IMPORTANCE:
			continue
		# Must be about a third party — not the listener, not just the speaker.
		var about_third := false
		var about_listener := false
		for related_name in m.related_agents:
			if related_name == listener.agent_name:
				about_listener = true
			elif related_name != speaker.agent_name:
				about_third = true
		if not about_third or about_listener:
			continue
		# Secrets only leak to confidants. Secondhand copies MAY re-leak —
		# blocking them outright meant every new ear needed its own
		# independent confide from the holder, and three-ear exposure was
		# effectively probability zero. Gossip gossips; that is the point.
		if m.narrative_thread.begins_with("secret_"):
			if rel.trust <= SECRET_TRUST_GATE:
				continue
			if "heard from" in m.description and randf() > 0.5:
				continue
		if best == null or m.importance > best.importance:
			best = m
	return best
