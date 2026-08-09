class_name EventDefinition
extends RefCounted
## Defines a single event type with probability, prerequisites, effects, and duration.

var event_id: String = ""
var event_name: String = ""
var description: String = ""
var probability: float = 0.1  # per day
var category: String = ""  # social, work, health, environment, personal
var target_mode: String = "random"  # random, most_productive, most_social, global, specific
var duration_minutes: float = 0.0
var cooldown_days: int = 1
var need_effects: Dictionary = {}  # NeedType.Type -> float delta for affected agents
var global_effect: String = ""  # special effect name like "disable_objects"

# Data-driven consequence layer (see ConsequenceEngine for the vocabulary).
var prerequisites: Dictionary = {}  # gates the daily roll only; trigger_event() bypasses
var second_actor: String = "none"  # nearby / rival / friend / crush / random / none
var payload: Dictionary = {}  # relationship_effects, modifiers, memory, ...
var outcomes: Array = []  # weighted payload variants, one picked per firing
var dilemma: Dictionary = {}  # {title, situation, choices:[{label, payload}], timeout_sec, default_choice}

const PAYLOAD_KEYS: Array[String] = [
	"relationship_effects", "modifiers", "conditions_add", "conditions_remove",
	"memory", "trait_shifts", "bystander_reactions", "script", "narrative",
]


static func from_dict(data: Dictionary) -> EventDefinition:
	var ed := EventDefinition.new()
	ed.event_id = data.get("id", "")
	ed.event_name = data.get("name", "")
	ed.description = data.get("description", "")
	ed.probability = data.get("probability", 0.1)
	ed.category = data.get("category", "")
	ed.target_mode = data.get("target_mode", "random")
	ed.duration_minutes = data.get("duration_minutes", 0.0)
	ed.cooldown_days = data.get("cooldown_days", 1)
	ed.need_effects = {}
	var raw_effects: Dictionary = data.get("need_effects", {})
	for key in raw_effects:
		var need_type: NeedType.Type
		match key:
			"energy": need_type = NeedType.Type.ENERGY
			"hunger": need_type = NeedType.Type.HUNGER
			"social": need_type = NeedType.Type.SOCIAL
			"productivity": need_type = NeedType.Type.PRODUCTIVITY
			"health": need_type = NeedType.Type.HEALTH
			_: continue
		ed.need_effects[need_type] = float(raw_effects[key])
	ed.global_effect = data.get("global_effect", "")
	ed.prerequisites = data.get("prerequisites", {})
	ed.second_actor = data.get("second_actor", "none")
	ed.outcomes = data.get("outcomes", [])
	ed.dilemma = data.get("dilemma", {})
	for key in PAYLOAD_KEYS:
		if data.has(key):
			ed.payload[key] = data[key]
	return ed
