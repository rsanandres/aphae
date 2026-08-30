extends Node
## Autoload: M5 — The Mole. A social-deduction case on top of the simulation.
##
## One cast member is quietly sabotaging the office. Evidence accrues the
## only ways evidence already can: sabotage leaves witness speculation, a
## lucky bystander glimpses the actor, the RumorMill spreads what someone
## confided, and the booth may spill the truth straight to the player (M7
## admissions are player-only — knowing is not the same as proving).
##
## The win condition is a HOUSE MEETING: the player spends Influence to call
## a vote, every agent votes from the evidence they personally hold, and the
## plurality is accused. Catch the mole and the house celebrates; accuse an
## innocent and the office gets meaner while the mole gets bolder. Let it
## run too long and the mole finishes the season their way.
##
## The player's edge is the producer toolkit that already exists: interview
## suspects, plant rumours to sway voters, nudge people together so gossip
## flows. M5 is Phase 4 plus a win condition, not new machinery.

const OPEN_CHANCE_PER_DAY := 0.12   # gated by DramaDirector pacing on top
const MIN_CAST := 4                 # a whodunit needs a crowd
const MIN_QUIET_DAYS := 2           # no case in the opening chaos
const INCIDENT_INTERVAL_DAYS := 2   # emboldened: 1 after a wrongful vote
const MAX_INCIDENTS := 5            # this many and the mole wins
const WITNESS_CHANCE := 0.35        # someone glimpses the actor per incident
const MEETING_COST := 8             # Influence to call the house together
const CAUGHT_PAYOUT := 25
const MOLE_WON_PENALTY := 15

# Vote weights: what a voter's own evidence is worth.
const VOTE_KNOWS := 40.0            # they KNOW (confide/rumour chain reached them)
const VOTE_CASE_MEMORY := 20.0      # a case-thread memory naming the suspect
const VOTE_CASE_MEMORY_CAP := 3
const VOTE_HEARSAY := 8.0           # negative hearsay naming the suspect
const VOTE_HEARSAY_CAP := 2
const VOTE_PLANTED := 12.0          # a producer-planted rumour: louder than gossip, softer than a sighting
const VOTE_PLANTED_CAP := 2
const VOTE_GRUDGE_SCALE := 0.15     # disliking someone makes them look guilty
const VOTE_ABSTAIN_UNDER := 5.0     # with less suspicion than this, you shrug

const SABOTAGE_DEEDS := [
	["unplugged {victim}'s machine mid-save", "A day of work, gone", "the deleted work"],
	["swapped {victim}'s presentation with last quarter's", "The meeting was a disaster", "the switched slides"],
	["let {victim} take the blame for the outage", "Everyone stared at the wrong person", "the pinned blame"],
	["shredded {victim}'s notes and recycled the evidence", "Weeks of notes, confetti", "the shredded notes"],
	["reset {victim}'s chair, monitor, and password. All of it", "Petty. Precise. Personal", "the petty rampage"],
]

# Test seam, per the repo rule: any autoload acting on day_changed ships with
# one, off in every harness. Explicit calls (open_case, commit_incident,
# call_house_meeting) always work.
var auto_enabled: bool = true

var case: CaseState = null          # the active or most recently resolved case
var _cases_run: int = 0


func _ready() -> void:
	EventBus.day_changed.connect(_on_day_changed)


# --- Query -------------------------------------------------------------------

func has_open_case() -> bool:
	return case != null and case.is_open()


func meeting_available() -> bool:
	return has_open_case() and _living_cast().size() >= 3


# --- Lifecycle ---------------------------------------------------------------

func _on_day_changed(day: int) -> void:
	if not auto_enabled:
		return
	if has_open_case():
		var interval := 1 if case.wrongful_votes > 0 else INCIDENT_INTERVAL_DAYS
		if day - case.last_incident_day >= interval:
			commit_incident()
		return
	if day < MIN_QUIET_DAYS:
		return
	if randf() < OPEN_CHANCE_PER_DAY * DramaDirector.get_probability_modifier():
		open_case()


func open_case(forced_mole: Node2D = null) -> CaseState:
	## Starts a case. The mole is chosen by the sabotage weighting the sim
	## already uses (grudges, low agreeableness, prior form) unless forced.
	if has_open_case():
		return null
	var cast := _living_cast()
	if cast.size() < MIN_CAST:
		return null
	var mole: Node2D = forced_mole
	if mole == null:
		# Borrow the existing saboteur weighting, aimed at nobody specific:
		# weight against a random colleague to keep grudges relevant.
		mole = ConsequenceEngine._pick_saboteur(cast[randi() % cast.size()])
	if mole == null or not is_instance_valid(mole):
		return null

	_cases_run += 1
	case = CaseState.new()
	case.case_number = _cases_run
	case.mole_name = mole.agent_name
	case.opened_day = TimeManager.day
	case.last_incident_day = TimeManager.day

	# The mole's truth rides the whole M7 stack: deniable on the floor,
	# confide-able, admissible to camera. One secret per agent holds — a
	# mole who already had a secret keeps it, and the case still works
	# through incident evidence alone.
	SecretManager.assign_custom(mole, case.secret_id(),
		"is the one sabotaging the office")

	EventBus.case_opened.emit()
	EventBus.narrative_event.emit(
		"Something is off in the office. Small things, wrong places, bad luck that isn't.",
		[], 5.0)
	# The host smells a storyline. This is the player's cue.
	ConfessionalDirector._record("host",
		"Between us? Someone in this office is not who they say they are. Keep your eyes open.",
		null, true)
	return case


func commit_incident(force_witness: Node2D = null) -> void:
	## The mole strikes. Reuses the sabotage script with the actor forced and
	## the memories threaded to this case, so evidence stacks on one person.
	if not has_open_case():
		return
	var mole := AgentManager.get_agent_by_name(case.mole_name)
	if mole == null or not is_instance_valid(mole) or mole.is_dead:
		_resolve_gone()
		return
	var victims := _living_cast().filter(func(a: Node2D) -> bool: return a != mole)
	if victims.is_empty():
		return
	# Grudges pick the victim: the mole hits who they like least.
	var victim: Node2D = victims[0]
	var worst := INF
	for candidate: Node2D in victims:
		var affinity: float = mole.relationships.get_relationship(candidate.agent_name).affinity
		if affinity < worst:
			worst = affinity
			victim = candidate
	var deed: Array = SABOTAGE_DEEDS[randi() % SABOTAGE_DEEDS.size()]
	ConsequenceEngine._script_sabotage(victim, str(deed[0]), str(deed[1]), str(deed[2]),
		mole, case.thread())

	# A lucky glimpse: one bystander catches something they can gossip about.
	# This memory names the mole AND is about a third party, so the RumorMill
	# can carry it — organic evidence, no oracle.
	var witness: Node2D = force_witness
	if witness == null and randf() < WITNESS_CHANCE:
		var bystanders := victims.filter(func(a: Node2D) -> bool: return a != victim)
		if not bystanders.is_empty():
			witness = bystanders[randi() % bystanders.size()]
	if witness != null and is_instance_valid(witness) and witness != mole:
		var seen: MemoryEntry = witness.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
			"%s saw %s near %s's desk right before it happened. Probably nothing. Probably." % [
				witness.agent_name, case.mole_name, victim.agent_name],
			5.0, PackedStringArray([case.mole_name]))
		seen.narrative_thread = case.thread()
		seen.emotion = "suspicion"
		seen.sentiment = -0.3

	case.incidents += 1
	case.last_incident_day = TimeManager.day
	EventBus.case_incident.emit(victim.agent_name)

	if case.incidents >= MAX_INCIDENTS:
		_resolve_mole_won(mole)


# --- The house meeting -------------------------------------------------------

func call_house_meeting() -> Dictionary:
	## The player's move. Costs Influence; every living agent votes from the
	## evidence they personally hold; plurality is accused. Returns the tally
	## (empty on refusal) — {votes: {voter: suspect}, accused, was_mole}.
	if not meeting_available():
		return {}
	if not ProducerEconomy.spend(MEETING_COST, "house meeting"):
		return {}
	var cast := _living_cast()
	var votes: Dictionary = {}   # voter_name -> suspect_name
	var tally: Dictionary = {}   # suspect_name -> count
	for voter: Node2D in cast:
		var suspect := _vote_of(voter, cast)
		if suspect == "":
			continue
		votes[voter.agent_name] = suspect
		tally[suspect] = int(tally.get(suspect, 0)) + 1

	var accused := ""
	var best := 0
	for name: String in tally.keys():
		if tally[name] > best:
			best = tally[name]
			accused = name
	if accused == "":
		# The house shrugged: nobody had enough suspicion to point. Half the
		# cost comes back, nobody is scarred, the case continues.
		ProducerEconomy.grant(MEETING_COST / 2, "inconclusive house meeting")
		ConfessionalDirector._record("host",
			"House meeting. A lot of stared-at shoes. Nobody pointed. The producers ate half the catering bill.",
			null, true)
		EventBus.house_meeting_held.emit("", false, votes)
		return {"votes": votes, "accused": "", "was_mole": false, "inconclusive": true}

	var was_mole := accused == case.mole_name
	EventBus.house_meeting_held.emit(accused, was_mole, votes)
	ConfessionalDirector._record("host",
		"House meeting. Fingers pointed. The house says: %s. %s" % [
			accused, "And the house is RIGHT." if was_mole else "The house is wrong."],
		null, true)

	if was_mole:
		_resolve_caught(accused, votes)
	else:
		_punish_wrongful(accused, votes)
	return {"votes": votes, "accused": accused, "was_mole": was_mole}


func _vote_of(voter: Node2D, cast: Array) -> String:
	## One agent's honest read of the evidence THEY hold. The mole votes
	## strategically: never self, always their most plausible scapegoat.
	var scores: Dictionary = {}
	for suspect: Node2D in cast:
		if suspect == voter:
			continue
		scores[suspect.agent_name] = _suspicion(voter, suspect)
	if scores.is_empty():
		return ""
	if voter.agent_name == case.mole_name:
		scores.erase(case.mole_name)
	var best_name := ""
	var best_score := -INF
	for name: String in scores.keys():
		if scores[name] > best_score:
			best_score = scores[name]
			best_name = name
	# Nobody credible? Abstain. Without this, all-zero scores resolved by
	# dictionary insertion order and every blind meeting deterministically
	# lynched whoever spawned first.
	if best_score < VOTE_ABSTAIN_UNDER:
		return ""
	return best_name


func _suspicion(voter: Node2D, suspect: Node2D) -> float:
	var score := 0.0
	# They KNOW: the confide/rumour chain reached this voter.
	if suspect.agent_name == case.mole_name \
			and SecretManager.knows(voter.agent_name, case.mole_name):
		score += VOTE_KNOWS
	# Case evidence they personally hold that names the suspect.
	var case_hits := 0
	var hearsay_hits := 0
	var planted_hits := 0
	for m: MemoryEntry in voter.memory.memories:
		if suspect.agent_name not in m.related_agents:
			continue
		if m.narrative_thread == "planted_rumor" and m.sentiment < 0.0:
			planted_hits += 1
			continue
		if m.narrative_thread == case.thread() and m.emotion in ["suspicion", "curiosity"]:
			# Only SIGHTINGS implicate: the witness glimpse ("suspicion") and
			# its rumour-mill copies ("curiosity"). Without the emotion gate,
			# the mole's own deed memory and bystander speculation — which
			# name the VICTIM — counted as evidence against the victim, and
			# the house reliably voted out whoever had been sabotaged.
			# Being a target is not being a suspect.
			case_hits += 1
		elif m.sentiment < 0.0:
			# Negative hearsay about the suspect — including rumours the
			# player planted. This is the lever the producer toolkit pulls.
			hearsay_hits += 1
	score += VOTE_CASE_MEMORY * mini(case_hits, VOTE_CASE_MEMORY_CAP)
	score += VOTE_HEARSAY * mini(hearsay_hits, VOTE_HEARSAY_CAP)
	score += VOTE_PLANTED * mini(planted_hits, VOTE_PLANTED_CAP)
	# Grudges make people look guilty. Unfair. Very human.
	var affinity: float = voter.relationships.get_relationship(suspect.agent_name).affinity
	score += maxf(0.0, -affinity) * VOTE_GRUDGE_SCALE
	return score


# --- Resolutions -------------------------------------------------------------

func _resolve_caught(accused: String, votes: Dictionary) -> void:
	case.status = CaseState.Status.CAUGHT
	case.resolved_day = TimeManager.day
	SecretManager.mark_exposed_by_thread("secret_" + case.secret_id())
	ProducerEconomy.grant(CAUGHT_PAYOUT, "the house caught the mole")
	EventBus.narrative_event.emit(
		"The house voted, and the house was right: %s was behind it all." % accused,
		[accused], 9.0)
	var mole := AgentManager.get_agent_by_name(accused)
	if mole != null and is_instance_valid(mole):
		for voter_name: String in votes.keys():
			if votes[voter_name] != accused or voter_name == accused:
				continue
			var voter := AgentManager.get_agent_by_name(voter_name)
			if voter != null and is_instance_valid(voter):
				var rel: RelationshipEntry = mole.relationships.get_relationship(voter_name)
				rel.trust = clampf(rel.trust - 20.0, -100.0, 100.0)
		AgentManager.depart_agent(mole, "voted out by the house")
	EventBus.case_resolved.emit(true, case.mole_name)


func _punish_wrongful(accused: String, votes: Dictionary) -> void:
	case.wrongful_votes += 1
	var innocent := AgentManager.get_agent_by_name(accused)
	if innocent != null and is_instance_valid(innocent):
		var hurt: MemoryEntry = innocent.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
			"The whole house pointed at %s. For something %s didn't do. Unforgettable." % [accused, accused],
			9.0, PackedStringArray())
		hurt.decay_protected = true
		hurt.emotion = "betrayal"
		hurt.sentiment = -0.9
		innocent.needs.restore(NeedType.Type.SOCIAL, -20.0)
		for voter_name: String in votes.keys():
			if votes[voter_name] != accused or voter_name == accused:
				continue
			var rel: RelationshipEntry = innocent.relationships.get_relationship(voter_name)
			rel.trust = clampf(rel.trust - 15.0, -100.0, 100.0)
			rel.affinity = clampf(rel.affinity - 10.0, -100.0, 100.0)
	EventBus.narrative_event.emit(
		"The house turned on %s — and the house was wrong. Somewhere, the real culprit smiled." % accused,
		[accused], 7.5)
	# The consolation prize is INFORMATION: a wrong vote that teaches nothing
	# is a pure gamble; this makes meetings purchasable deduction.
	var any_sighting := false
	for agent in _living_cast():
		for m: MemoryEntry in agent.memory.memories:
			if m.narrative_thread == case.thread() and m.emotion == "suspicion":
				any_sighting = true
				break
		if any_sighting:
			break
	var tip := "Production reviewed the tapes: SOMEBODY in this house saw something. Get people talking." 		if any_sighting else 		"Production reviewed the tapes: no witnesses. Whoever it is, they're careful. Watch who benefits."
	# _emit, not _record: the meeting verdict just consumed the confessional
	# cooldown, and _record would silently drop the one line the player paid
	# for (the cooldown-swallow class, third sighting this codebase).
	ConfessionalDirector._emit("host", tip, null)


func _resolve_mole_won(mole: Node2D) -> void:
	case.status = CaseState.Status.MOLE_WON
	case.resolved_day = TimeManager.day
	ProducerEconomy.spend(mini(MOLE_WON_PENALTY, ProducerEconomy.influence), "the mole got away with it")
	EventBus.narrative_event.emit(
		"%s cleared out their desk, smiled at the cameras, and walked. Every incident this season? Them. Nobody proved a thing." % case.mole_name,
		[case.mole_name], 9.0)
	if is_instance_valid(mole):
		ConfessionalDirector.request_farewell(mole, "got away with all of it")
		AgentManager.depart_agent(mole, "left before anyone could prove anything")
	EventBus.case_resolved.emit(false, case.mole_name)


func _resolve_gone() -> void:
	## The mole died or departed mid-case; the case dissolves without a winner.
	case.status = CaseState.Status.MOLE_WON
	case.resolved_day = TimeManager.day
	EventBus.case_resolved.emit(false, case.mole_name)


func _living_cast() -> Array:
	var out: Array = []
	for agent in AgentManager.agents:
		if is_instance_valid(agent) and not agent.is_dead:
			out.append(agent)
	return out


# --- Persistence -------------------------------------------------------------

func get_save_state() -> Dictionary:
	return {
		"cases_run": _cases_run,
		"case": case.to_dict() if case != null else {},
	}


func load_save_state(data: Dictionary) -> void:
	_cases_run = int(data.get("cases_run", 0))
	var case_data: Dictionary = data.get("case", {})
	case = CaseState.from_dict(case_data) if not case_data.is_empty() else null
