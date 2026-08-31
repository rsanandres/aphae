extends Node
## Autoload: M7 — secrets & lies.
##
## The Confessional Cam gave the sim a truth channel; this uses it. Some
## agents arrive holding a private truth. On the floor they deny it; in the
## booth they eventually admit it — so the player knows more than the cast,
## which is dramatic irony, the actual engine of reality TV.
##
## Propagation is the part that has to be earned. A holder never gossips
## their own secret, so nothing spreads until they CONFIDE in someone they
## trust. The confidant's memory of that is about a third party, which is
## exactly what RumorMill passes on — from there the existing gossip chain
## does the rest, distortion and all. Enough ears and the secret is EXPOSED.
##
## Mechanics live here and run at conversation end, LLM or not; the spoken
## lines (deflections, probes) are flavor on top.

const SECRET_CHANCE := 0.35        # of arriving with a secret at all
const CONFIDE_TRUST_GATE := 40.0   # a few good talks earn a confide (60 took game-weeks)
const CONFIDE_CHANCE := 0.25       # per qualifying conversation
const PROBE_CHANCE := 0.4          # a knower needles the holder
const PROBE_TRUST_COST := 3.0      # being needled corrodes the pair (6 outpaced trust growth and killed the chain)
const EXPOSURE_COUNT := 3          # this many ears and it is not a secret
const ADMIT_CHANCE_PER_DAY := 0.3  # booth admission pacing

## Solo truths only: relational secrets need a target that may not exist at
## spawn time. Phrased mid-sentence, same convention as goal text.
const POOL := [
	{"id": "job_hunt", "text": "is quietly interviewing at a rival company"},
	{"id": "broke_it", "text": "is the one who broke the coffee machine and let everyone blame the intern"},
	{"id": "resume", "text": "embellished half the resume that got them this job"},
	{"id": "moonlight", "text": "is secretly moonlighting a second job on company time"},
	{"id": "fired_before", "text": "was fired from the last job and told everyone they quit"},
	{"id": "novel", "text": "has been writing a novel about the office, and nobody in it comes off well"},
	{"id": "savings", "text": "is one bad month from broke, whatever the car says"},
	{"id": "lottery", "text": "won a small lottery prize and never told a soul"},
]

# Test seam, same convention as EventManager.auto_resolve_dilemmas and
# ArcManager.auto_start_enabled: harnesses drive assignment and admission
# explicitly and must not race the spawn/day rolls.
var auto_assign_enabled: bool = true
var auto_admit_enabled: bool = true

var _secrets: Dictionary = {}  # agent_name -> SecretState (one each; a second secret is a sequel, not a feature)


func _ready() -> void:
	EventBus.agent_spawned.connect(_on_agent_spawned)
	EventBus.agent_removed.connect(func(agent_name: String) -> void: _secrets.erase(agent_name))
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.rumor_passed.connect(_on_rumor_passed)


# --- Query -------------------------------------------------------------------

func get_secret(agent_name: String) -> SecretState:
	return _secrets.get(agent_name)


func has_hidden_secret(agent_name: String) -> bool:
	var secret: SecretState = _secrets.get(agent_name)
	return secret != null and secret.is_hidden()


func knows(observer: String, holder: String) -> bool:
	var secret: SecretState = _secrets.get(holder)
	return secret != null and observer in secret.known_by


## What the conversation prompt tells a holder. Empty when there is nothing
## to hide, so the placeholder always resolves.
func denial_prompt_line(agent_name: String) -> String:
	var secret: SecretState = _secrets.get(agent_name)
	if secret == null or not secret.is_hidden():
		return ""
	return "You are hiding something: you %s. If the conversation drifts anywhere near it, deflect or change the subject. Never admit it here." % secret.text


## What the prompt tells someone who has heard the rumour about the listener.
func gossip_prompt_line(speaker_name: String, listener_name: String) -> String:
	var secret: SecretState = _secrets.get(listener_name)
	if secret == null or not secret.is_hidden() or speaker_name not in secret.known_by:
		return ""
	return "You have heard a rumor that %s %s. You might hint that you know, but you are not certain it is true." % [listener_name, secret.text]


# --- Assignment --------------------------------------------------------------

func assign_secret(agent: Node2D, secret_id: String = "") -> SecretState:
	## Explicit assignment (tests, events). Random from the pool when no id.
	if not is_instance_valid(agent) or _secrets.has(agent.agent_name):
		return null
	var entry: Dictionary = {}
	if secret_id == "":
		entry = POOL[randi() % POOL.size()]
	else:
		for candidate in POOL:
			if candidate["id"] == secret_id:
				entry = candidate
				break
	if entry.is_empty():
		return null
	var secret := SecretState.new()
	secret.agent_name = agent.agent_name
	secret.id = str(entry["id"])
	secret.text = str(entry["text"])
	secret.created_day = TimeManager.day
	_secrets[agent.agent_name] = secret
	# The substance: a protected memory on the holder. No related_agents —
	# RumorMill must never pass a holder's own secret out of their head.
	var mem: MemoryEntry = agent.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
		"%s %s. Nobody here can find out." % [agent.agent_name, secret.text], 8.0)
	mem.narrative_thread = secret.thread()
	mem.decay_protected = true
	mem.emotion = "guarded"
	mem.sentiment = -0.3
	return secret


func assign_custom(agent: Node2D, secret_id: String, text: String) -> SecretState:
	## Bespoke secrets from other systems (the mole case, future events) —
	## same machinery as the pool: backing memory, confide/probe/expose,
	## booth admission. One secret per agent still holds.
	if not is_instance_valid(agent) or _secrets.has(agent.agent_name):
		return null
	if secret_id.strip_edges() == "" or text.strip_edges() == "":
		return null
	var secret := SecretState.new()
	secret.agent_name = agent.agent_name
	secret.id = secret_id
	secret.text = text
	secret.created_day = TimeManager.day
	_secrets[agent.agent_name] = secret
	var mem: MemoryEntry = agent.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
		"%s %s. Nobody here can find out." % [agent.agent_name, secret.text], 8.0)
	mem.narrative_thread = secret.thread()
	mem.decay_protected = true
	mem.emotion = "guarded"
	mem.sentiment = -0.3
	return secret


func _on_agent_spawned(agent: Node2D) -> void:
	if auto_assign_enabled and randf() < SECRET_CHANCE:
		assign_secret(agent)


# --- The floor: confide, probe, expose --------------------------------------

func process_conversation_end(agent_a: Node2D, agent_b: Node2D) -> void:
	## Called from ConversationInstance alongside RumorMill. Mechanics only —
	## whatever was said out loud was flavor.
	if not is_instance_valid(agent_a) or not is_instance_valid(agent_b):
		return
	_maybe_confide(agent_a, agent_b)
	_maybe_confide(agent_b, agent_a)
	_maybe_probe(agent_a, agent_b)
	_maybe_probe(agent_b, agent_a)


func _maybe_confide(holder: Node2D, confidant: Node2D) -> void:
	var secret: SecretState = _secrets.get(holder.agent_name)
	if secret == null or not secret.is_hidden() or confidant.agent_name in secret.known_by:
		return
	var rel: RelationshipEntry = holder.relationships.get_relationship(confidant.agent_name)
	# The right corner loosens tongues: a SynergyManager zone with a confide
	# modifier scales the roll at the pair's midpoint (set design as a verb).
	var mid: Vector2 = (holder.global_position + confidant.global_position) / 2.0
	var chance: float = CONFIDE_CHANCE * SynergyManager.social_multiplier(mid, "confide")
	if rel.trust <= CONFIDE_TRUST_GATE or randf() > chance:
		return
	secret.known_by.append(confidant.agent_name)
	# The confidant's memory is ABOUT the holder — a third party from anyone
	# else's seat — so from here the RumorMill can carry it onward. That is
	# the entire propagation chain: confide once, and gossip does the rest.
	var mem: MemoryEntry = confidant.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
		"%s confided in %s: %s %s." % [holder.agent_name, confidant.agent_name, holder.agent_name, secret.text],
		7.0, PackedStringArray([holder.agent_name]))
	mem.narrative_thread = secret.thread()
	mem.emotion = "conspiratorial"
	mem.sentiment = -0.2
	var own: MemoryEntry = holder.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
		"%s finally told %s the thing. It felt lighter for about a minute." % [holder.agent_name, confidant.agent_name],
		6.0, PackedStringArray([confidant.agent_name]))
	own.narrative_thread = secret.thread()
	own.emotion = "relief"
	rel.trust = clampf(rel.trust + 5.0, -100.0, 100.0)
	EventBus.secret_confided.emit(holder.agent_name, confidant.agent_name)
	_check_exposure(secret)


func _maybe_probe(knower: Node2D, holder: Node2D) -> void:
	var secret: SecretState = _secrets.get(holder.agent_name)
	if secret == null or not secret.is_hidden() or knower.agent_name not in secret.known_by:
		return
	if randf() > PROBE_CHANCE:
		return
	# Being needled about the thing you are hiding corrodes the pair both
	# ways: the holder resents the probe, the knower resents the denial.
	var rel_hk: RelationshipEntry = holder.relationships.get_relationship(knower.agent_name)
	var rel_kh: RelationshipEntry = knower.relationships.get_relationship(holder.agent_name)
	rel_hk.trust = clampf(rel_hk.trust - PROBE_TRUST_COST, -100.0, 100.0)
	rel_kh.trust = clampf(rel_kh.trust - PROBE_TRUST_COST * 0.5, -100.0, 100.0)
	var mem: MemoryEntry = holder.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
		"%s hinted they know what %s is hiding. Denied everything. Heart rate says otherwise." % [knower.agent_name, holder.agent_name],
		6.0, PackedStringArray([knower.agent_name]))
	mem.narrative_thread = secret.thread()
	mem.emotion = "anxious"
	mem.sentiment = -0.5
	EventBus.secret_confronted.emit(holder.agent_name, knower.agent_name)
	# A denial to someone who KNOWS is the drama the booth exists for.
	EventBus.narrative_event.emit(
		"%s asked %s a pointed question and got a very smooth answer." % [knower.agent_name, holder.agent_name],
		[holder.agent_name, knower.agent_name], 6.0)


func _on_rumor_passed(listener_name: String, _speaker_name: String, mem_thread: String) -> void:
	## The gossip chain reached a new ear.
	if not mem_thread.begins_with("secret_"):
		return
	for secret: SecretState in _secrets.values():
		if secret.thread() != mem_thread or not secret.is_hidden():
			continue
		if listener_name == secret.agent_name or listener_name in secret.known_by:
			continue
		secret.known_by.append(listener_name)
		_check_exposure(secret)


func mark_exposed_by_thread(mem_thread: String) -> void:
	## The producer's leak dilemma floods the office with the secret's memory
	## directly, bypassing the confide/gossip chain. The M7 state must follow,
	## or the holder keeps denying a thing everyone already knows. Quiet: the
	## leak script narrates on its own, so no second headline here.
	for secret: SecretState in _secrets.values():
		if secret.thread() == mem_thread and not secret.exposed:
			secret.exposed = true
			EventBus.secret_exposed.emit(secret.agent_name, secret.text)


func _check_exposure(secret: SecretState) -> void:
	if secret.exposed or secret.known_by.size() < EXPOSURE_COUNT:
		return
	secret.exposed = true
	var holder := AgentManager.get_agent_by_name(secret.agent_name)
	if holder != null and is_instance_valid(holder):
		var mem: MemoryEntry = holder.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
			"It's out. Everyone knows %s %s. The looks in the kitchen say so." % [holder.agent_name, secret.text],
			9.0)
		mem.narrative_thread = secret.thread()
		mem.decay_protected = true
		mem.emotion = "exposed"
		mem.sentiment = -0.7
		holder.needs.restore(NeedType.Type.SOCIAL, -15.0)
	EventBus.secret_exposed.emit(secret.agent_name, secret.text)
	EventBus.narrative_event.emit(
		"The whispers caught up with %s — apparently they %s." % [secret.agent_name, secret.text],
		[secret.agent_name], 7.5)


# --- The booth: where the truth goes ----------------------------------------

func _on_day_changed(_day: int) -> void:
	if not auto_admit_enabled or randf() > ADMIT_CHANCE_PER_DAY:
		return
	var candidates: Array[SecretState] = []
	for secret: SecretState in _secrets.values():
		if secret.is_hidden() and not secret.admitted_on_camera:
			var holder := AgentManager.get_agent_by_name(secret.agent_name)
			if holder != null and is_instance_valid(holder) and not holder.is_dead:
				candidates.append(secret)
	if candidates.is_empty():
		return
	admit_on_camera(candidates[randi() % candidates.size()])


func admit_on_camera(secret: SecretState) -> void:
	## The dramatic-irony beat: the booth hears what the floor never will.
	## Only the player sees it — confessionals feed back into the SPEAKER's
	## memory alone, so the cast stays in the dark.
	var holder := AgentManager.get_agent_by_name(secret.agent_name)
	if holder == null or not is_instance_valid(holder):
		return
	secret.admitted_on_camera = true
	ConfessionalDirector.request_secret_admission(holder, secret.text)
	EventBus.secret_admitted.emit(secret.agent_name, secret.text)


# --- Persistence -------------------------------------------------------------

func get_save_state() -> Dictionary:
	var rows: Array = []
	for secret: SecretState in _secrets.values():
		rows.append(secret.to_dict())
	return {"secrets": rows}


func load_save_state(data: Dictionary) -> void:
	_secrets.clear()
	for row in data.get("secrets", []):
		if row is Dictionary and str(row.get("agent_name", "")) != "":
			var secret := SecretState.from_dict(row)
			_secrets[secret.agent_name] = secret
