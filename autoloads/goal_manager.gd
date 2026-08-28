extends Node
## Autoload: makes PersonalityProfile.goals real.
##
## Goals used to be decoration — interpolated into prompts and arc text, never
## pursued. Here each goal becomes a GoalState with a kind, live progress, and a
## deadline. Progress accrues only from things that actually happened in the
## simulation (interactions finished, conversations held, romances confessed,
## days survived in good shape), so a goal cannot advance on narration alone.
##
## Resolution runs through ConsequenceEngine.apply, the same payload vocabulary
## events and arcs speak, so an achieved goal leaves the same kind of mark on an
## agent that any other consequence does.

const DEADLINE_DAYS := 10
const EXTENSION_DAYS := 3
const EXTENSION_THRESHOLD := 75.0  # a near-miss earns one stay of execution
const MAX_TRACKED_PER_AGENT := 3

# Progress weights, tuned so a committed agent lands a goal in roughly a week.
const WORK_STEP := 12.0
const CREATIVE_STEP := 14.0
const CREATIVE_PARTNER_STEP := 10.0  # "learn something new from each colleague"
const SOCIAL_NEW_PARTNER := 25.0
const SOCIAL_REPEAT := 6.0
const ROMANCE_CONVERSATION := 8.0
const ROMANCE_CONFESSION := 60.0
const BALANCE_GOOD_DAY := 25.0
const BALANCE_BAD_DAY := -10.0
const BALANCE_NEED_FLOOR := 55.0
const BALANCE_CRITICAL := 20.0

const KIND_OBJECTS := {
	GoalState.Kind.WORK: ["desk", "whiteboard"],
	GoalState.Kind.CREATIVE: ["whiteboard", "bookshelf"],
	GoalState.Kind.BALANCE: ["couch", "plant", "meditation_pod"],
}

# Landing a goal bends the trait that earned it, within the engine's cap.
const KIND_TRAIT_REWARD := {
	GoalState.Kind.SOCIAL: {"extraversion": 0.03},
	GoalState.Kind.WORK: {"conscientiousness": 0.03},
	GoalState.Kind.CREATIVE: {"openness": 0.03},
	GoalState.Kind.ROMANCE: {"agreeableness": 0.03},
	GoalState.Kind.BALANCE: {"neuroticism": -0.03},
}

const ACHIEVED_INFLUENCE := 6

# Test seam, same convention as ArcManager.auto_start_enabled and the
# SecretManager seams. Off, this autoload goes deaf to simulation signals —
# necessary because a goal resolving mid-harness narrates at >= 6.5, which
# consumes the ConfessionalDirector cooldown and silently swallows the quip
# a harness was actually testing for (this broke confessional_test at ~20%).
# Explicit calls (assign_for, advance, the sweeps) still work.
var auto_enabled: bool = true

var _goals: Dictionary = {}  # agent_name -> Array[GoalState]
var achieved_total: int = 0
var failed_total: int = 0


func _ready() -> void:
	EventBus.agent_spawned.connect(_on_agent_spawned)
	EventBus.agent_removed.connect(_on_agent_removed)
	EventBus.agent_died.connect(_on_agent_died)
	EventBus.agent_action_completed.connect(_on_action_completed)
	EventBus.conversation_ended.connect(_on_conversation_ended)
	EventBus.confession_made.connect(_on_confession_made)
	EventBus.romance_started.connect(_on_romance_started)
	EventBus.day_changed.connect(_on_day_changed)


# --- Query -------------------------------------------------------------------

func get_goals(agent_name: String) -> Array[GoalState]:
	var out: Array[GoalState] = []
	for goal: GoalState in _goals.get(agent_name, []):
		out.append(goal)
	return out


func get_active_goals(agent_name: String) -> Array[GoalState]:
	var out: Array[GoalState] = []
	for goal: GoalState in _goals.get(agent_name, []):
		if goal.is_active():
			out.append(goal)
	return out


func get_focus_goal(agent_name: String) -> GoalState:
	## The goal an agent is actually pushing on: the active one closest to
	## landing. Ties go to the first assigned, which keeps focus stable.
	var best: GoalState = null
	for goal: GoalState in _goals.get(agent_name, []):
		if not goal.is_active():
			continue
		if best == null or goal.progress > best.progress:
			best = goal
	return best


func preferred_object_types(kind: GoalState.Kind) -> Array:
	return KIND_OBJECTS.get(kind, [])


func format_for_prompt(agent_name: String) -> String:
	## Goals reach the model with their standing, so it can write an agent who
	## knows they are close, or stalling, or out of time.
	var goals := get_goals(agent_name)
	if goals.is_empty():
		return "none"
	var today: int = TimeManager.day
	var lines: PackedStringArray = []
	for goal: GoalState in goals:
		match goal.status:
			GoalState.Status.ACHIEVED:
				lines.append("%s (achieved)" % goal.text)
			GoalState.Status.FAILED:
				lines.append("%s (given up on)" % goal.text)
			_:
				lines.append("%s (%d%% there, %d days left)" % [
					goal.text, int(goal.progress), maxi(0, goal.days_left(today))])
	return "\n".join(lines)


# --- Assignment --------------------------------------------------------------

func assign_for(agent: Node2D) -> void:
	if not is_instance_valid(agent) or agent.personality == null:
		return
	if _goals.has(agent.agent_name):
		return  # already tracked (a load restored them, or a departed agent returned)
	var states: Array[GoalState] = []
	var day: int = TimeManager.day
	for goal_text: String in agent.personality.goals:
		if states.size() >= MAX_TRACKED_PER_AGENT:
			break
		if goal_text.strip_edges().is_empty():
			continue
		states.append(GoalState.create(agent.agent_name, goal_text, day, DEADLINE_DAYS))
	if not states.is_empty():
		_goals[agent.agent_name] = states


func _on_agent_spawned(agent: Node2D) -> void:
	if not auto_enabled:
		return
	assign_for(agent)


func _on_agent_removed(agent_name: String) -> void:
	_goals.erase(agent_name)


func _on_agent_died(agent_name: String, _cause: String) -> void:
	# Unfinished business is kept, not deleted: a recap can still say what they
	# were three days short of. Death is drama enough, so this resolution is
	# silent — no narrative event, no confessional.
	for goal: GoalState in _goals.get(agent_name, []):
		if goal.is_active():
			goal.status = GoalState.Status.FAILED
			goal.resolved_day = TimeManager.day


# --- Progress sources --------------------------------------------------------

func advance(goal: GoalState, amount: float, _reason: String = "") -> void:
	if goal == null or not goal.is_active() or is_zero_approx(amount):
		return
	goal.progress = clampf(goal.progress + amount, 0.0, 100.0)
	EventBus.goal_progressed.emit(goal.agent_name, goal.text, goal.progress)
	if goal.progress >= 100.0:
		_achieve(goal)


func _on_action_completed(agent: Node2D, _action: ActionType.Type, target: Node2D) -> void:
	if not auto_enabled:
		return
	if not is_instance_valid(agent) or not is_instance_valid(target):
		return
	if not target.has_method("get_object_type"):
		return
	var object_type: String = target.get_object_type()
	for goal: GoalState in get_active_goals(agent.agent_name):
		if object_type not in preferred_object_types(goal.kind):
			continue
		match goal.kind:
			GoalState.Kind.WORK:
				advance(goal, WORK_STEP, "used the %s" % object_type)
			GoalState.Kind.CREATIVE:
				advance(goal, CREATIVE_STEP, "used the %s" % object_type)
			_:
				pass  # BALANCE earns its progress at day end, not per use


func _on_conversation_ended(agent_a: String, agent_b: String) -> void:
	if not auto_enabled:
		return
	_credit_conversation(agent_a, agent_b)
	_credit_conversation(agent_b, agent_a)


func _credit_conversation(agent_name: String, partner: String) -> void:
	if agent_name == partner:
		return
	for goal: GoalState in get_active_goals(agent_name):
		var is_new: bool = partner not in goal.partners
		match goal.kind:
			GoalState.Kind.SOCIAL:
				if is_new:
					goal.partners.append(partner)
					advance(goal, SOCIAL_NEW_PARTNER, "met %s" % partner)
				else:
					advance(goal, SOCIAL_REPEAT, "talked with %s again" % partner)
			GoalState.Kind.CREATIVE:
				if is_new:
					goal.partners.append(partner)
					advance(goal, CREATIVE_PARTNER_STEP, "learned from %s" % partner)
			GoalState.Kind.ROMANCE:
				if _is_romantic_toward(agent_name, partner):
					advance(goal, ROMANCE_CONVERSATION, "time with %s" % partner)
			_:
				pass


func _is_romantic_toward(agent_name: String, partner: String) -> bool:
	var agent := AgentManager.get_agent_by_name(agent_name)
	if agent == null or not is_instance_valid(agent) or agent.relationships == null:
		return false
	var rel: RelationshipEntry = agent.relationships.get_relationship(partner)
	return rel != null and rel.romantic_interest > 0.0


func _on_confession_made(confessor: String, target: String, accepted: bool) -> void:
	if not auto_enabled:
		return
	if not accepted:
		return
	for goal: GoalState in get_active_goals(confessor):
		if goal.kind == GoalState.Kind.ROMANCE:
			advance(goal, ROMANCE_CONFESSION, "confessed to %s" % target)


func _on_romance_started(agent_a: String, agent_b: String) -> void:
	if not auto_enabled:
		return
	for agent_name: String in [agent_a, agent_b]:
		for goal: GoalState in get_active_goals(agent_name):
			if goal.kind == GoalState.Kind.ROMANCE:
				advance(goal, 100.0, "fell in love")


func _on_day_changed(day: int) -> void:
	if not auto_enabled:
		return
	_score_balance_goals()
	_sweep_deadlines(day)


func _score_balance_goals() -> void:
	## A balance goal is the only kind measured by a state rather than an act:
	## did they end the day whole?
	for agent_name: String in _goals.keys():
		var balance: Array[GoalState] = []
		for goal: GoalState in get_active_goals(agent_name):
			if goal.kind == GoalState.Kind.BALANCE:
				balance.append(goal)
		if balance.is_empty():
			continue
		var agent := AgentManager.get_agent_by_name(agent_name)
		if agent == null or not is_instance_valid(agent) or agent.needs == null:
			continue
		var lowest: float = 100.0
		for value: float in agent.needs.get_all_values().values():
			lowest = minf(lowest, value)
		var delta: float = BALANCE_GOOD_DAY if lowest >= BALANCE_NEED_FLOOR else 0.0
		if lowest < BALANCE_CRITICAL:
			delta = BALANCE_BAD_DAY
		for goal: GoalState in balance:
			advance(goal, delta, "day ended at %.0f" % lowest)


func _sweep_deadlines(day: int) -> void:
	for agent_name: String in _goals.keys():
		for goal: GoalState in get_active_goals(agent_name):
			if day < goal.deadline_day:
				continue
			if not goal.extended and goal.progress >= EXTENSION_THRESHOLD:
				goal.extended = true
				goal.deadline_day = day + EXTENSION_DAYS
				continue
			_fail(goal)


# --- Resolution --------------------------------------------------------------

func _achieve(goal: GoalState) -> void:
	goal.status = GoalState.Status.ACHIEVED
	goal.progress = 100.0
	goal.resolved_day = TimeManager.day
	achieved_total += 1
	_apply_resolution(goal, true)
	EventBus.goal_achieved.emit(goal.agent_name, goal.text, int(goal.kind))


func _fail(goal: GoalState) -> void:
	goal.status = GoalState.Status.FAILED
	goal.resolved_day = TimeManager.day
	failed_total += 1
	_apply_resolution(goal, false)
	EventBus.goal_failed.emit(goal.agent_name, goal.text, int(goal.kind))


func _apply_resolution(goal: GoalState, achieved: bool) -> void:
	var agent := AgentManager.get_agent_by_name(goal.agent_name)
	if agent == null or not is_instance_valid(agent):
		return
	var memory_text: String = "I did it. I set out to %s, and I got there." % goal.phrase()
	var narrative_text: String = "%s finally managed it — %s." % [goal.agent_name, goal.phrase()]
	if not achieved:
		memory_text = "I wanted to %s. I am letting it go." % goal.phrase()
		narrative_text = "%s quietly gave up trying to %s." % [goal.agent_name, goal.phrase()]
	var payload: Dictionary = {
		# ConsequenceEngine keys memory specs by role — "affected", "second",
		# "witness". There is no "target" role; a payload using one is dropped
		# without complaint.
		"memory": {
			"affected": {
				"text": memory_text,
				"importance": 9.0 if achieved else 7.0,
				"emotion": "proud" if achieved else "resigned",
				"sentiment": 0.8 if achieved else -0.5,
				"protected": true,
				"thread": "goal_%s" % GoalState.kind_name(goal.kind),
			},
		},
		"trait_shifts": KIND_TRAIT_REWARD.get(goal.kind, {}) if achieved else {"neuroticism": 0.02},
		"narrative": {
			"text": narrative_text,
			# Both clear ConfessionalDirector's importance-6 bar: a goal landing
			# or dying is exactly what the booth exists for.
			"importance": 7.5 if achieved else 6.5,
		},
	}
	ConsequenceEngine.apply(payload, agent, null, {"affected": [agent]})
	if achieved:
		ProducerEconomy.grant(ACHIEVED_INFLUENCE, "%s achieved a goal" % goal.agent_name)


# --- Persistence -------------------------------------------------------------

func get_save_state() -> Dictionary:
	var goals: Dictionary = {}
	for agent_name: String in _goals.keys():
		var rows: Array = []
		for goal: GoalState in _goals[agent_name]:
			rows.append(goal.to_dict())
		goals[agent_name] = rows
	return {"goals": goals, "achieved_total": achieved_total, "failed_total": failed_total}


func load_save_state(data: Dictionary) -> void:
	_goals.clear()
	achieved_total = int(data.get("achieved_total", 0))
	failed_total = int(data.get("failed_total", 0))
	var goals: Dictionary = data.get("goals", {})
	for agent_name: String in goals.keys():
		var states: Array[GoalState] = []
		for row in goals[agent_name]:
			if row is Dictionary:
				states.append(GoalState.from_dict(row))
		if not states.is_empty():
			_goals[str(agent_name)] = states
