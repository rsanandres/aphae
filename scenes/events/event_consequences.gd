class_name ConsequenceEngine
## Applies declarative consequence payloads to agents. EventManager, arcs,
## cast churn, sabotage, and producer dilemmas all speak this one vocabulary,
## which is what lets new content be pure JSON.
##
## Payload keys (all optional):
##   need_effects          {"energy": -10, ...}  (string keys)
##   relationship_effects  [{from, to, affinity, trust, romantic_interest,
##                           add_tags, remove_tags, set_status}]
##   modifiers             [{type, target, days}]
##   conditions_add        ["flu"] / conditions_remove ["*"]
##   memory                {affected: {...}, second: {...},
##                          witness: {radius, text, importance, ...}}
##   trait_shifts          {"neuroticism": 0.03}  (clamped, capped ±0.05)
##   bystander_reactions   [{trait, below/above, affinity, add_tags, memory}]
##   script                "flu_contagion" | "exhaustion_collapse" | ...
##   narrative             {text, importance}
##   outcomes              [{weight, ...payload...}]  (picked once, applied on top)
##
## String fields substitute {target} and {second} with agent names.

const TRAIT_SHIFT_CAP := 0.05

const NEED_LOOKUP := {
	"energy": NeedType.Type.ENERGY,
	"hunger": NeedType.Type.HUNGER,
	"social": NeedType.Type.SOCIAL,
	"productivity": NeedType.Type.PRODUCTIVITY,
	"health": NeedType.Type.HEALTH,
}

const STATUS_LOOKUP := {
	"NONE": RelationshipEntry.Status.NONE,
	"CRUSHING": RelationshipEntry.Status.CRUSHING,
	"DATING": RelationshipEntry.Status.DATING,
	"PARTNERS": RelationshipEntry.Status.PARTNERS,
	"EX": RelationshipEntry.Status.EX,
}


static func apply_event(definition: EventDefinition, affected: Array) -> void:
	## Entry point for EventManager: resolves the second actor, applies the
	## definition's payload plus one weighted outcome variant if present.
	var target: Node2D = affected[0] if not affected.is_empty() and affected[0] is Node2D else null
	var second := _select_second(definition.second_actor, target)
	# A payload written for two actors is meaningless with one — mirror the
	# old hardcoded behavior and abort the consequence (need deltas from the
	# legacy top-level need_effects still applied upstream).
	if second == null and definition.second_actor not in ["", "none"]:
		return
	apply(definition.payload, target, second, {"affected": affected, "definition": definition})
	if not definition.outcomes.is_empty():
		var outcome := _pick_outcome(definition.outcomes)
		if not outcome.is_empty():
			apply(outcome, target, second, {"affected": affected, "definition": definition})


static func apply(payload: Dictionary, target: Node2D, second: Node2D = null, ctx: Dictionary = {}) -> void:
	if payload.is_empty():
		return
	var affected: Array = ctx.get("affected", [target] if target else [])

	if payload.has("need_effects"):
		for agent in affected:
			_apply_needs(payload["need_effects"], agent)

	for entry in payload.get("relationship_effects", []):
		_apply_relationship(entry, target, second)

	for entry in payload.get("modifiers", []):
		var who := _resolve_agent(entry.get("on", "target"), target, second)
		if who:
			var days: int = int(entry.get("days", 1))
			who.add_behavior_modifier({
				"type": str(entry.get("type", "")),
				"target": _sub(str(entry.get("target", "")), target, second),
				"duration_days": days,
				"days_remaining": days,
				"source": str(ctx.get("definition").event_id if ctx.get("definition") else entry.get("source", "consequence")),
			})

	if payload.has("conditions_add") or payload.has("conditions_remove"):
		for agent in affected:
			_apply_conditions(payload, agent)

	if payload.has("memory"):
		_apply_memories(payload["memory"], target, second, affected)

	if payload.has("trait_shifts"):
		for agent in affected:
			_apply_trait_shifts(payload["trait_shifts"], agent)

	if payload.has("bystander_reactions") and target:
		_apply_bystander_reactions(payload["bystander_reactions"], target)

	if payload.has("script"):
		_run_script(str(payload["script"]), target, second, affected)

	if payload.has("narrative"):
		var n: Dictionary = payload["narrative"]
		var names: Array = []
		for a in affected:
			if is_instance_valid(a):
				names.append(a.agent_name)
		if second and is_instance_valid(second) and second.agent_name not in names:
			names.append(second.agent_name)
		EventBus.narrative_event.emit(
			_sub(str(n.get("text", "")), target, second),
			names, float(n.get("importance", 5.0)))


# --- Individual appliers ---------------------------------------------------

static func _apply_needs(effects: Dictionary, agent: Node2D) -> void:
	if not is_instance_valid(agent) or not agent.has_node("AgentNeeds"):
		return
	for key in effects:
		if NEED_LOOKUP.has(key):
			agent.needs.restore(NEED_LOOKUP[key], float(effects[key]))


static func _apply_relationship(entry: Dictionary, target: Node2D, second: Node2D) -> void:
	var from := _resolve_agent(entry.get("from", "target"), target, second)
	var to := _resolve_agent(entry.get("to", "second"), target, second)
	if not from or not to or from == to:
		return
	var rel: RelationshipEntry = from.relationships.get_relationship(to.agent_name)
	if entry.has("affinity"):
		rel.affinity = clampf(rel.affinity + float(entry["affinity"]), -100.0, 100.0)
	if entry.has("trust"):
		rel.trust = clampf(rel.trust + float(entry["trust"]), 0.0, 100.0)
	if entry.has("romantic_interest"):
		rel.romantic_interest = clampf(rel.romantic_interest + float(entry["romantic_interest"]), 0.0, 100.0)
	for tag in entry.get("add_tags", []):
		rel.add_tag(_sub(str(tag), target, second))
	for tag in entry.get("remove_tags", []):
		rel.remove_tag(_sub(str(tag), target, second))
	if entry.has("set_status") and STATUS_LOOKUP.has(entry["set_status"]):
		rel.relationship_status = STATUS_LOOKUP[entry["set_status"]]
	EventBus.relationship_changed.emit(from.agent_name, to.agent_name, rel)


static func _apply_conditions(payload: Dictionary, agent: Node2D) -> void:
	if not is_instance_valid(agent) or agent.health_state == null:
		return
	for cond in payload.get("conditions_add", []):
		agent.health_state.add_condition(str(cond))
	for cond in payload.get("conditions_remove", []):
		if str(cond) == "*":
			agent.health_state.conditions.clear()
		else:
			agent.health_state.remove_condition(str(cond))


static func _apply_memories(spec: Dictionary, target: Node2D, second: Node2D, affected: Array) -> void:
	if spec.has("affected"):
		for agent in affected:
			_add_memory(spec["affected"], agent, target, second)
	if spec.has("second") and second:
		_add_memory(spec["second"], second, target, second)
	if spec.has("witness") and target and is_instance_valid(target):
		var w: Dictionary = spec["witness"]
		var radius_value = w.get("radius", 160.0)
		var witnesses: Array
		if str(radius_value) == "all":
			witnesses = AgentManager.agents.duplicate()
		else:
			witnesses = AgentManager.get_agents_near(target.global_position, float(radius_value), target)
		for agent in witnesses:
			if agent in affected or agent == second:
				continue
			_add_memory(w, agent, target, second)


static func _add_memory(spec: Dictionary, agent: Node2D, target: Node2D, second: Node2D) -> void:
	if not is_instance_valid(agent) or agent.memory == null:
		return
	var related := PackedStringArray()
	if target and is_instance_valid(target) and target != agent:
		related.append(target.agent_name)
	if second and is_instance_valid(second) and second != agent:
		related.append(second.agent_name)
	var mem: MemoryEntry = agent.memory.add_memory(
		MemoryEntry.MemoryType.OBSERVATION,
		"%s: %s" % [agent.agent_name, _sub(str(spec.get("text", "")), target, second)],
		float(spec.get("importance", 5.0)), related)
	mem.emotion = str(spec.get("emotion", ""))
	mem.sentiment = float(spec.get("sentiment", 0.0))
	mem.decay_protected = bool(spec.get("protected", false))
	mem.narrative_thread = _sub(str(spec.get("thread", "")), target, second)


static func _apply_trait_shifts(shifts: Dictionary, agent: Node2D) -> void:
	## Lasting marks: events may permanently bend a personality, a little.
	if not is_instance_valid(agent) or agent.personality == null:
		return
	var p: PersonalityProfile = agent.personality
	for trait_name in shifts:
		var delta: float = clampf(float(shifts[trait_name]), -TRAIT_SHIFT_CAP, TRAIT_SHIFT_CAP)
		match trait_name:
			"openness": p.openness = clampf(p.openness + delta, 0.0, 1.0)
			"conscientiousness": p.conscientiousness = clampf(p.conscientiousness + delta, 0.0, 1.0)
			"extraversion": p.extraversion = clampf(p.extraversion + delta, 0.0, 1.0)
			"agreeableness": p.agreeableness = clampf(p.agreeableness + delta, 0.0, 1.0)
			"neuroticism": p.neuroticism = clampf(p.neuroticism + delta, 0.0, 1.0)


static func _apply_bystander_reactions(reactions: Array, target: Node2D) -> void:
	## Everyone else reacts according to the first entry whose trait condition
	## they match; an entry with no trait condition matches anyone (use last,
	## as the default — this is what fixes promotion's silent middle band).
	for agent in AgentManager.agents:
		if not is_instance_valid(agent) or agent == target or agent.personality == null:
			continue
		for entry in reactions:
			if not _bystander_matches(entry, agent):
				continue
			if entry.has("affinity") or entry.has("add_tags") or entry.has("trust"):
				var rel: RelationshipEntry = agent.relationships.get_relationship(target.agent_name)
				if entry.has("affinity"):
					rel.affinity = clampf(rel.affinity + float(entry["affinity"]), -100.0, 100.0)
				if entry.has("trust"):
					rel.trust = clampf(rel.trust + float(entry["trust"]), 0.0, 100.0)
				for tag in entry.get("add_tags", []):
					rel.add_tag(_sub(str(tag), target, null))
				EventBus.relationship_changed.emit(agent.agent_name, target.agent_name, rel)
			if entry.has("memory"):
				_add_memory(entry["memory"], agent, target, null)
			break


static func _bystander_matches(entry: Dictionary, agent: Node2D) -> bool:
	if not entry.has("trait"):
		return true
	var value: float = agent.personality.get(str(entry["trait"]))
	if entry.has("below") and value >= float(entry["below"]):
		return false
	if entry.has("above") and value <= float(entry["above"]):
		return false
	return true


# --- Named scripts (irreducibly procedural consequences) --------------------

static func _run_script(script_name: String, target: Node2D, second: Node2D, affected: Array) -> void:
	match script_name:
		"flu_contagion":
			_script_flu_contagion(affected)
		"exhaustion_collapse":
			_script_exhaustion_collapse(affected)
		"new_hire":
			_script_new_hire()
		"departure_poached":
			_script_departure(target, "poached by a rival company")
		"departure_quit":
			_script_departure(target, "quit in a blaze of glory")
		"returning_ex":
			_script_returning_ex()
		"sabotage_lunch":
			_script_sabotage(target, "stole {victim}'s lunch from the fridge",
				"someone stole my lunch right out of the fridge", "lunch theft")
		"sabotage_note":
			_script_sabotage(target, "left an anonymous note on {victim}'s desk calling their work sloppy",
				"someone left a nasty anonymous note on my desk", "the anonymous note")
		"leak_secret":
			_script_leak_secret(target)
		"expose_saboteur":
			_script_expose_saboteur(target)
		"sabotage_work":
			_script_sabotage(target, "quietly deleted part of {victim}'s project files",
				"part of my project files just vanished — that was no accident", "the deleted files")
		_:
			push_warning("ConsequenceEngine: unknown script '%s'" % script_name)


static func _script_flu_contagion(affected: Array) -> void:
	var newly_infected: Array = []
	for sick_agent in affected:
		if not is_instance_valid(sick_agent):
			continue
		var nearby := AgentManager.get_agents_near(sick_agent.global_position, 80.0, sick_agent)
		for other in nearby:
			if not is_instance_valid(other) or other in affected or other in newly_infected:
				continue
			if not other.health_state:
				continue
			if randf() < 0.3:
				other.health_state.add_condition("flu")
				other.needs.restore(NeedType.Type.ENERGY, -15.0)
				other.needs.restore(NeedType.Type.HEALTH, -10.0)
				newly_infected.append(other)
				_add_memory({
					"text": "caught the flu from being near %s." % sick_agent.agent_name,
					"importance": 5.0, "emotion": "discomfort", "sentiment": -0.5,
				}, other, sick_agent, null)
	if not newly_infected.is_empty():
		var names: Array = []
		for a in newly_infected:
			names.append(a.agent_name)
		EventBus.narrative_event.emit(
			"The flu is spreading! %s also caught it." % ", ".join(PackedStringArray(names)),
			names, 6.0)


static func _script_exhaustion_collapse(affected: Array) -> void:
	for agent in affected:
		if not is_instance_valid(agent):
			continue
		agent.needs.set_value(NeedType.Type.ENERGY, 0.0)
		if agent.health_state and not agent.health_state.conditions.has("exhaustion"):
			agent.health_state.add_condition("exhaustion")
		var bed: Node2D = _find_nearest_object(agent.global_position, "bed")
		if bed:
			# The sanctioned external control API — same path PlayerDirector uses.
			agent._execute_decision({"action": ActionType.Type.GO_TO_OBJECT, "target": bed})
			_add_memory({
				"text": "collapsed from exhaustion and is stumbling toward the bed.",
				"importance": 7.0, "emotion": "exhaustion", "sentiment": -0.8,
			}, agent, agent, null)
		else:
			agent.state = AgentState.Type.IDLE
			_add_memory({
				"text": "collapsed from exhaustion with nowhere to rest.",
				"importance": 8.0, "emotion": "despair", "sentiment": -0.9,
			}, agent, agent, null)
		EventBus.narrative_event.emit(
			"%s collapsed from exhaustion!" % agent.agent_name, [agent.agent_name], 8.0)


static func _script_leak_secret(holder: Node2D) -> void:
	## Producer leaks the target's secret to the whole office. Anonymous —
	## nobody knows where the story came from, but everybody knows the story.
	if holder == null or not is_instance_valid(holder) or holder.memory == null:
		return
	var secrets: Array[MemoryEntry] = holder.memory.get_secrets()
	if secrets.is_empty():
		return
	var secret: MemoryEntry = secrets[0]
	for agent in AgentManager.agents:
		if not is_instance_valid(agent) or agent == holder:
			continue
		_add_memory({
			"text": "a story is suddenly everywhere: %s" % secret.description,
			"importance": 6.0, "emotion": "shock", "sentiment": -0.3,
			"thread": secret.narrative_thread,
		}, agent, holder, null)
	_add_memory({
		"text": "the secret is out. Everyone knows. Someone leaked it — but who?",
		"importance": 9.0, "emotion": "shock", "sentiment": -0.8, "protected": true,
	}, holder, holder, null)
	holder.needs.restore(NeedType.Type.SOCIAL, -20.0)
	# Keep the M7 state honest: a leaked secret is an exposed secret, or the
	# holder goes on denying a thing the whole office already heard.
	SecretManager.mark_exposed_by_thread(secret.narrative_thread)
	EventBus.narrative_event.emit(
		"A secret about %s just went public. The office is buzzing." % holder.agent_name,
		[holder.agent_name], 8.0)


static func _script_expose_saboteur(saboteur: Node2D) -> void:
	## The footage airs: the whole cast learns who did it.
	if saboteur == null or not is_instance_valid(saboteur):
		return
	for agent in AgentManager.agents:
		if not is_instance_valid(agent) or agent == saboteur:
			continue
		var rel: RelationshipEntry = agent.relationships.get_relationship(saboteur.agent_name)
		rel.affinity = clampf(rel.affinity - 15.0, -100.0, 100.0)
		rel.trust = clampf(rel.trust - 20.0, 0.0, 100.0)
		_add_memory({
			"text": "saw the proof: %s was behind the sabotage all along." % saboteur.agent_name,
			"importance": 7.0, "emotion": "shock", "sentiment": -0.6,
		}, agent, saboteur, null)
		EventBus.relationship_changed.emit(agent.agent_name, saboteur.agent_name, rel)
	_add_memory({
		"text": "was exposed as the saboteur in front of everyone. There is no coming back from this.",
		"importance": 9.0, "emotion": "shame", "sentiment": -0.9, "protected": true,
	}, saboteur, saboteur, null)
	EventBus.narrative_event.emit(
		"%s was exposed as the office saboteur!" % saboteur.agent_name,
		[saboteur.agent_name], 9.0)


static func _script_sabotage(victim: Node2D, deed: String, victim_line: String, incident: String,
		forced_actor: Node2D = null, thread: String = "secret_sabotage") -> void:
	## Hidden-actor mystery: the actor knows, the victim seethes at no one,
	## nearby agents speculate. The truth can only travel via the RumorMill —
	## or a confessional slip, since secrets score high in retrieval.
	## The mole case forces the SAME actor across incidents (forced_actor) and
	## threads them to the case, so evidence accumulates against one person.
	if victim == null or not is_instance_valid(victim):
		return
	var actor := forced_actor if forced_actor != null else _pick_saboteur(victim)
	if actor == null:
		return

	# The actor's secret: protected, threaded, high-importance.
	_add_memory({
		"text": deed.replace("{victim}", victim.agent_name) + ". Nobody saw. Nobody can know.",
		"importance": 8.0, "emotion": "defiance", "sentiment": -0.3,
		"protected": true, "thread": thread,
	}, actor, victim, null)

	# The victim's anger names NO ONE.
	_add_memory({
		"text": victim_line + ". Someone in this office did this.",
		"importance": 7.0, "emotion": "anger", "sentiment": -0.7, "protected": true,
	}, victim, victim, null)
	victim.needs.restore(NeedType.Type.SOCIAL, -10.0)

	# Bystanders speculate — the actor keeps a straight face (no memory).
	for agent in AgentManager.get_agents_near(victim.global_position, 140.0, victim):
		if agent == actor or not is_instance_valid(agent):
			continue
		_add_memory({
			"text": "heard about %s targeting %s. Who in this office would do that?" % [incident, victim.agent_name],
			"importance": 4.0, "emotion": "curiosity", "sentiment": -0.3,
		}, agent, victim, null)

	EventBus.narrative_event.emit(
		"Sabotage in the office: %s hit %s. The culprit is unknown." % [incident, victim.agent_name],
		[victim.agent_name], 6.5)


static func _pick_saboteur(victim: Node2D) -> Node2D:
	var weights: Dictionary = {}
	for agent in AgentManager.agents:
		if not is_instance_valid(agent) or agent == victim or agent.is_dead:
			continue
		var w := 0.5
		var rel: RelationshipEntry = agent.relationships.get_relationship(victim.agent_name)
		if rel.affinity < -20.0 or rel.has_tag("rival"):
			w += 3.0
		if agent.personality and agent.personality.agreeableness < 0.4:
			w += 2.0
		for m in agent.memory.get_secrets():
			if m.narrative_thread == "secret_sabotage":
				w += 3.0  # repeat offenders stay in character
				break
		weights[agent] = w
	if weights.is_empty():
		return null
	var total := 0.0
	for agent in weights:
		total += weights[agent]
	var roll := randf() * total
	for agent in weights:
		roll -= weights[agent]
		if roll <= 0.0:
			return agent
	return weights.keys()[-1]


static func _script_new_hire() -> void:
	var tree := Engine.get_main_loop()
	if not tree is SceneTree:
		return
	var world: Node2D = (tree as SceneTree).get_first_node_in_group("world")
	if not world:
		return
	var bounds: Rect2 = world.get_bounds()
	var pos := Vector2(
		randf_range(bounds.position.x + 20, bounds.end.x - 20),
		randf_range(bounds.position.y + 20, bounds.end.y - 20)
	)
	var hire := AgentManager.spawn_procedural_agent(pos)
	if hire == null:
		return
	# First impressions both ways: compatibility-seeded, so the newcomer has
	# texture instead of a flat zero matrix.
	for other in AgentManager.agents:
		if not is_instance_valid(other) or other == hire:
			continue
		var compat := 0.0
		if hire.personality and other.personality:
			compat = hire.relationships._calculate_compatibility(hire.personality, other.personality)
		var seed_affinity := compat * 12.0 - 3.0
		var rel_a: RelationshipEntry = hire.relationships.get_relationship(other.agent_name)
		rel_a.affinity = clampf(seed_affinity, -15.0, 15.0)
		var rel_b: RelationshipEntry = other.relationships.get_relationship(hire.agent_name)
		rel_b.affinity = clampf(seed_affinity, -15.0, 15.0)
		_add_memory({
			"text": "met the new hire, %s. First impressions were made." % hire.agent_name,
			"importance": 4.0, "emotion": "", "sentiment": clampf(seed_affinity / 15.0, -0.5, 0.5),
		}, other, hire, null)
	ConfessionalDirector.request_intro(hire,
		"You just joined this office mid-season. Introduce yourself to the audience in one line, in your own voice.")


static func _script_departure(target: Node2D, reason: String) -> void:
	if target and is_instance_valid(target):
		AgentManager.depart_agent(target, reason)


static func _script_returning_ex() -> void:
	var returned := AgentManager.respawn_departed()
	if returned == null:
		return
	EventBus.narrative_event.emit(
		"%s just walked back into the office. Everyone remembers." % returned.agent_name,
		[returned.agent_name], 8.0)
	ConfessionalDirector.request_intro(returned,
		"You left this office once and now you're back. One line to camera about your return, in your own voice.")


static func _find_nearest_object(pos: Vector2, obj_type: String) -> Node2D:
	var world: Node2D = null
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		world = tree.get_first_node_in_group("world")
	if not world or not world.has_method("get_all_objects"):
		return null
	var best: Node2D = null
	var best_dist: float = INF
	for obj in world.get_all_objects():
		if obj.object_type == obj_type:
			var dist: float = pos.distance_to(obj.global_position)
			if dist < best_dist:
				best_dist = dist
				best = obj
	return best


# --- Helpers ----------------------------------------------------------------

static func _select_second(mode: String, target: Node2D) -> Node2D:
	if target == null or not is_instance_valid(target) or mode == "none" or mode == "":
		return null
	match mode:
		"nearby":
			var nearby := AgentManager.get_agents_near(target.global_position, 120.0, target)
			return nearby[randi() % nearby.size()] if not nearby.is_empty() else null
		"rival":
			return _find_by_relation(target, func(rel: RelationshipEntry) -> bool:
				return rel.affinity < -20.0 or rel.has_tag("rival"))
		"friend":
			return _find_by_relation(target, func(rel: RelationshipEntry) -> bool:
				return rel.has_tag("friend") or rel.affinity > 30.0)
		"crush":
			return _find_by_relation(target, func(rel: RelationshipEntry) -> bool:
				return rel.romantic_interest > 25.0 or rel.has_tag("crush"))
		"random":
			var others: Array = []
			for a in AgentManager.agents:
				if is_instance_valid(a) and a != target and not a.is_dead:
					others.append(a)
			return others[randi() % others.size()] if not others.is_empty() else null
		"grudge":
			# Someone the target is actively angry at (argument fallout).
			var rels: Dictionary = target.relationships.get_all_relationships()
			for other_name in rels:
				for tag in (rels[other_name] as RelationshipEntry).tags:
					if str(tag).begins_with("angry_at_"):
						var other := AgentManager.get_agent_by_name(other_name)
						if other and is_instance_valid(other) and not other.is_dead:
							return other
			return null
	return null


static func _find_by_relation(target: Node2D, predicate: Callable) -> Node2D:
	var candidates: Array = []
	var rels: Dictionary = target.relationships.get_all_relationships()
	for other_name in rels:
		if predicate.call(rels[other_name]):
			var other := AgentManager.get_agent_by_name(other_name)
			if other and is_instance_valid(other) and not other.is_dead:
				candidates.append(other)
	return candidates[randi() % candidates.size()] if not candidates.is_empty() else null


static func _resolve_agent(who: String, target: Node2D, second: Node2D) -> Node2D:
	match who:
		"target":
			return target if target and is_instance_valid(target) else null
		"second":
			return second if second and is_instance_valid(second) else null
		_:
			return AgentManager.get_agent_by_name(who)


static func _pick_outcome(outcomes: Array) -> Dictionary:
	var total := 0.0
	for o in outcomes:
		total += float(o.get("weight", 1.0))
	var roll := randf() * total
	for o in outcomes:
		roll -= float(o.get("weight", 1.0))
		if roll <= 0.0:
			return o
	return outcomes[-1] if not outcomes.is_empty() else {}


static func _sub(text: String, target: Node2D, second: Node2D) -> String:
	var out := text
	if target and is_instance_valid(target):
		out = out.replace("{target}", target.agent_name)
	if second and is_instance_valid(second):
		out = out.replace("{second}", second.agent_name)
	return out


# --- Prerequisites (shared with ArcManager later) ---------------------------

static func prerequisites_met_global(prereq: Dictionary) -> bool:
	if prereq.is_empty():
		return true
	if prereq.has("min_drama") and DramaDirector.drama_level < float(prereq["min_drama"]):
		return false
	if prereq.has("max_drama") and DramaDirector.drama_level > float(prereq["max_drama"]):
		return false
	if prereq.has("min_day") and TimeManager.day < int(prereq["min_day"]):
		return false
	if prereq.has("min_agents") and AgentManager.agents.size() < int(prereq["min_agents"]):
		return false
	if prereq.has("max_agents") and AgentManager.agents.size() > int(prereq["max_agents"]):
		return false
	return true


static func prerequisites_met_target(prereq: Dictionary, target: Node2D) -> bool:
	if prereq.is_empty():
		return true
	if not is_instance_valid(target):
		return false
	for need_key in prereq.get("needs", {}):
		if not NEED_LOOKUP.has(need_key):
			continue
		var value: float = target.needs.get_value(NEED_LOOKUP[need_key])
		var bounds: Dictionary = prereq["needs"][need_key]
		if bounds.has("below") and value >= float(bounds["below"]):
			return false
		if bounds.has("above") and value <= float(bounds["above"]):
			return false
	if prereq.has("requires_tag_prefix"):
		var found_prefix := false
		for rel in target.relationships.get_all_relationships().values():
			for tag in (rel as RelationshipEntry).tags:
				if str(tag).begins_with(str(prereq["requires_tag_prefix"])):
					found_prefix = true
					break
			if found_prefix:
				break
		if not found_prefix:
			return false
	if prereq.has("requires_tag"):
		var found_tag := false
		for rel in target.relationships.get_all_relationships().values():
			if (rel as RelationshipEntry).has_tag(str(prereq["requires_tag"])):
				found_tag = true
				break
		if not found_tag:
			return false
	if prereq.get("has_secret", false):
		if target.memory == null or target.memory.get_secrets().is_empty():
			return false
	if prereq.has("has_secret_thread"):
		var found_thread := false
		if target.memory:
			for m in target.memory.get_secrets():
				if m.narrative_thread == str(prereq["has_secret_thread"]):
					found_thread = true
					break
		if not found_thread:
			return false
	if prereq.has("requires_status"):
		var wanted: RelationshipEntry.Status = STATUS_LOOKUP.get(str(prereq["requires_status"]), RelationshipEntry.Status.NONE)
		var found_status := false
		for rel in target.relationships.get_all_relationships().values():
			if (rel as RelationshipEntry).relationship_status == wanted:
				found_status = true
				break
		if not found_status:
			return false
	return true
