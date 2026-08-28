class_name GoalState
extends RefCounted
## One pursued goal belonging to one agent.
##
## The text comes from PersonalityProfile.goals — authored JSON or the
## procedural pool. The *kind* is inferred from that text once, at assignment,
## and decides which simulation signals feed the goal's progress. Nothing else
## reads the prose, so a new goal string needs no code change.

enum Kind { SOCIAL, WORK, CREATIVE, ROMANCE, BALANCE }
enum Status { ACTIVE, ACHIEVED, FAILED }

var agent_name: String = ""
var text: String = ""
var kind: Kind = Kind.WORK
var status: Status = Status.ACTIVE
var progress: float = 0.0  # 0-100
var started_day: int = 0
var deadline_day: int = 0
var extended: bool = false  # a near-miss buys one extension, once
var resolved_day: int = -1
var partners: PackedStringArray = []  # SOCIAL: who they have already connected with


# Keyword→kind, most specific first. A goal matching nothing is WORK, which is
# the safe default: office sims give everyone a desk.
const _KIND_KEYWORDS := [
	[Kind.ROMANCE, ["love", "romance", "romantic", "crush", "date ", "appreciates"]],
	[Kind.BALANCE, ["work-life", "balance", "routine", "meaning", "wellbeing", "calm"]],
	[Kind.CREATIVE, ["creative", "inspiration", "inspiring", "learn", "discover", "talent",
		"beautiful", "truth", "idea", "curious"]],
	[Kind.SOCIAL, ["friend", "connect", "everyone", "welcoming", "trust", "advice", "liked",
		"relationship", "colleague", "keep the peace", "team", "help"]],
]


static func infer_kind(goal_text: String) -> Kind:
	var lower := goal_text.to_lower()
	for entry in _KIND_KEYWORDS:
		var candidate: Kind = entry[0]
		for keyword in entry[1]:
			if keyword in lower:
				return candidate
	return Kind.WORK


static func kind_name(k: Kind) -> String:
	match k:
		Kind.SOCIAL: return "social"
		Kind.WORK: return "work"
		Kind.CREATIVE: return "creative"
		Kind.ROMANCE: return "romance"
		Kind.BALANCE: return "balance"
	return "work"


static func create(p_agent: String, p_text: String, day: int, deadline_days: int) -> GoalState:
	var goal := GoalState.new()
	goal.agent_name = p_agent
	goal.text = p_text
	goal.kind = infer_kind(p_text)
	goal.started_day = day
	goal.deadline_day = day + deadline_days
	return goal


func is_active() -> bool:
	return status == Status.ACTIVE


func days_left(today: int) -> int:
	return deadline_day - today


## Goal prose is authored as a sentence fragment ("Prove she deserves a
## promotion"), so narrative lines splice it mid-sentence and need it uncapped.
func phrase() -> String:
	if text.is_empty():
		return ""
	return text[0].to_lower() + text.substr(1)


func to_dict() -> Dictionary:
	return {
		"agent_name": agent_name,
		"text": text,
		"kind": int(kind),
		"status": int(status),
		"progress": progress,
		"started_day": started_day,
		"deadline_day": deadline_day,
		"extended": extended,
		"resolved_day": resolved_day,
		"partners": Array(partners),
	}


static func from_dict(data: Dictionary) -> GoalState:
	var goal := GoalState.new()
	goal.agent_name = str(data.get("agent_name", ""))
	goal.text = str(data.get("text", ""))
	goal.kind = int(data.get("kind", Kind.WORK)) as Kind
	goal.status = int(data.get("status", Status.ACTIVE)) as Status
	goal.progress = float(data.get("progress", 0.0))
	goal.started_day = int(data.get("started_day", 0))
	goal.deadline_day = int(data.get("deadline_day", 0))
	goal.extended = bool(data.get("extended", false))
	goal.resolved_day = int(data.get("resolved_day", -1))
	for p in data.get("partners", []):
		goal.partners.append(str(p))
	return goal
