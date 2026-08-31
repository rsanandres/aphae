extends Node
## Autoload: object-to-object synergies.
##
## 113 placeable objects means 6,000+ possible pairs — so pairs are never
## authored. Objects carry TAGS (in resources/objects.json, plus a map here
## for the bespoke thirteen), and ~20 RULES in resources/synergies.json match
## tag pairs within a radius. Two matching objects form a ZONE:
##   kind "use"  — finishing an interaction with either member grants the
##                 rule's bonus effects (with an occasional flavor memory),
##   kind "aura" — agents inside the zone feel a passive per-minute effect,
##                 exactly like decor auras,
##   kind "both" — both of the above.
## Rules can be negative: a jukebox beside the focus booth is a Noise
## Complaint, party lights near the desks are a Distraction Field.
##
## Zones rebuild from placement alone (object_placed/removed — which the
## save-loader also fires), announce themselves once, and appear in member
## objects' hover tooltips. Adding object #114 to the web costs one tag;
## a new combo costs one rule. No pair is ever written by hand.

const RULES_PATH := "res://resources/synergies.json"
const ANNOUNCE_IMPORTANCE := 3.5   # visible in the log, below the booth's bar
const USE_FLAVOR_CHANCE := 0.2     # how often a use-bonus also leaves a memory
const MAX_ZONES := 40              # a fully-carpeted office stays sane

const _NEED_LOOKUP := {
	"energy": NeedType.Type.ENERGY,
	"hunger": NeedType.Type.HUNGER,
	"social": NeedType.Type.SOCIAL,
	"productivity": NeedType.Type.PRODUCTIVITY,
	"health": NeedType.Type.HEALTH,
}

## The bespoke thirteen live outside objects.json; their tags live here.
const BESPOKE_TAGS := {
	"desk": ["work"], "couch": ["rest", "seat"], "coffee_machine": ["food", "caffeine"],
	"water_cooler": ["food", "social"], "whiteboard": ["work", "creative"],
	"bookshelf": ["quiet", "creative"], "plant": ["decor", "plant"],
	"radio": ["music"], "bed": ["rest"], "karaoke_machine": ["music", "party", "social"],
	"arcade_cabinet": ["game", "social"], "meditation_pod": ["calm", "wellness", "quiet"],
	"aquarium": ["decor", "calm", "water"],
}

# Test seam, per the repo rule: this autoload reacts to placement and ticks.
var auto_enabled: bool = true

var _rules: Array[Dictionary] = []
var _zones: Array[Dictionary] = []  # {rule: Dictionary, a: Node2D, b: Node2D, center: Vector2}
var _announced: Dictionary = {}     # "rule_id|a_path|b_path" -> true, this session
var _dirty: bool = false


func _ready() -> void:
	_load_rules()
	EventBus.object_placed.connect(func(_o: Node2D, _p: Vector2) -> void: _dirty = true)
	EventBus.object_removed.connect(func(_o: Node2D) -> void: _dirty = true)
	EventBus.agent_action_completed.connect(_on_action_completed)
	EventBus.time_tick.connect(_on_time_tick)


func _process(_delta: float) -> void:
	if _dirty and auto_enabled:
		_dirty = false
		rebuild()


# --- Query -------------------------------------------------------------------

func get_zones() -> Array[Dictionary]:
	return _zones


func zone_names_for(obj: Node2D) -> PackedStringArray:
	## For tooltips: which synergies this object is currently part of.
	var out := PackedStringArray()
	for zone in _zones:
		if zone["a"] == obj or zone["b"] == obj:
			var name := str((zone["rule"] as Dictionary).get("name", ""))
			if name not in out:
				out.append(name)
	return out


func zone_labels_for(obj: Node2D) -> PackedStringArray:
	## Tooltip labels WITH the social modifier spelled out. A hidden 1.6x on
	## a rare roll is invisible; a stated promise ("gossip +60%") is a plan
	## the player builds toward — the panel's condition for this feature.
	var out := PackedStringArray()
	for zone in _zones:
		if zone["a"] != obj and zone["b"] != obj:
			continue
		var rule: Dictionary = zone["rule"]
		var label := str(rule.get("name", ""))
		var suffix := _social_suffix(rule.get("social", {}))
		if suffix != "":
			label += " (%s)" % suffix
		if label not in out:
			out.append(label)
	return out


const _SOCIAL_WORDS := {"gossip": "gossip", "confide": "secrets", "romance": "romance"}

static func _social_suffix(social: Dictionary) -> String:
	var parts: Array[String] = []
	for channel in ["gossip", "confide", "romance"]:
		if not social.has(channel):
			continue
		var pct := roundi((float(social[channel]) - 1.0) * 100.0)
		if pct != 0:
			parts.append("%s %+d%%" % [_SOCIAL_WORDS[channel], pct])
	return ", ".join(parts)


func social_multiplier(pos: Vector2, channel: String) -> float:
	## The strongest social-roll modifier covering pos for one channel:
	## "gossip" (RumorMill), "confide" (SecretManager), "romance" (growth).
	## 1.0 when no zone applies. Strongest = furthest from 1.0, so a future
	## suppressing corner (0.7x) is not shadowed by a mild boost.
	if not auto_enabled:
		return 1.0
	var best := 1.0
	for zone in _zones:
		var rule: Dictionary = zone["rule"]
		var social: Dictionary = rule.get("social", {})
		if not social.has(channel):
			continue
		if (zone["center"] as Vector2).distance_to(pos) > float(rule.get("radius", 60.0)):
			continue
		var mult := float(social[channel])
		if absf(mult - 1.0) > absf(best - 1.0):
			best = mult
	return best


static func tags_of(obj: Node2D) -> Array:
	if not is_instance_valid(obj) or not obj is InteractableObject:
		return []
	var id: String = (obj as InteractableObject).object_type
	if BESPOKE_TAGS.has(id):
		return BESPOKE_TAGS[id]
	return DataObject.get_def(id).get("tags", [])


# --- Zone building -----------------------------------------------------------

func rebuild() -> void:
	_zones.clear()
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("get_all_objects"):
		return
	var objects: Array = world.get_all_objects()
	for i in range(objects.size()):
		for j in range(i + 1, objects.size()):
			if _zones.size() >= MAX_ZONES:
				return
			var a: Node2D = objects[i]
			var b: Node2D = objects[j]
			if not is_instance_valid(a) or not is_instance_valid(b):
				continue
			var rule := _match_rule(a, b)
			if rule.is_empty():
				continue
			var zone := {
				"rule": rule, "a": a, "b": b,
				"center": (a.global_position + b.global_position) / 2.0,
			}
			_zones.append(zone)
			_maybe_announce(rule, a, b)


func _match_rule(a: Node2D, b: Node2D) -> Dictionary:
	var tags_a := tags_of(a)
	var tags_b := tags_of(b)
	if tags_a.is_empty() or tags_b.is_empty():
		return {}
	var dist: float = a.global_position.distance_to(b.global_position)
	# Rules match in FILE ORDER and the first hit wins — keep specific rules
	# (sport+sport) above generic ones (game+game) in synergies.json, or the
	# generic rule shadows the specific one for objects carrying both tags.
	for rule in _rules:
		if dist > float(rule.get("radius", 60.0)):
			continue
		var want: Array = rule.get("tags", [])
		if want.size() != 2:
			continue
		var t1 := str(want[0])
		var t2 := str(want[1])
		if t1 == t2:
			# Same-tag rule (game+game): both must carry it.
			if t1 in tags_a and t1 in tags_b:
				return rule
		elif (t1 in tags_a and t2 in tags_b) or (t2 in tags_a and t1 in tags_b):
			return rule
	return {}


func _maybe_announce(rule: Dictionary, a: Node2D, b: Node2D) -> void:
	# Once per pair per session: the office notices the corner exists, then
	# shuts up about it.
	var key := "%s|%s|%s" % [rule.get("id", ""), a.get_instance_id(), b.get_instance_id()]
	if _announced.has(key):
		return
	_announced[key] = true
	if str(rule.get("line", "")) != "":
		EventBus.narrative_event.emit(str(rule["line"]), [], ANNOUNCE_IMPORTANCE)


# --- The effects -------------------------------------------------------------

func _on_action_completed(agent: Node2D, _action: ActionType.Type, target: Node2D) -> void:
	if not auto_enabled or not is_instance_valid(agent) or not is_instance_valid(target):
		return
	for zone in _zones:
		if zone["a"] != target and zone["b"] != target:
			continue
		var rule: Dictionary = zone["rule"]
		var kind := str(rule.get("kind", "use"))
		if kind != "use" and kind != "both":
			continue
		var effects := _parse_effects(rule.get("effects", {}))
		for need in effects:
			agent.needs.restore(need, effects[need])
		if randf() < USE_FLAVOR_CHANCE and agent.memory:
			agent.memory.add_observation("%s made use of the %s. That corner just works." % [
				agent.agent_name, str(rule.get("name", "corner")).to_lower()], 2.0)
		return  # one zone bonus per use; overlapping corners don't stack


func _on_time_tick(_game_minutes: float) -> void:
	if not auto_enabled or _zones.is_empty():
		return
	for zone in _zones:
		var rule: Dictionary = zone["rule"]
		var kind := str(rule.get("kind", "use"))
		if kind != "aura" and kind != "both":
			continue
		var aura := _parse_effects(rule.get("aura", {}))
		if aura.is_empty():
			continue
		var radius := float(rule.get("radius", 60.0))
		for agent in AgentManager.get_agents_near(zone["center"], radius, null):
			if not is_instance_valid(agent) or agent.is_dead:
				continue
			for need in aura:
				agent.needs.restore(need, aura[need])


static func _parse_effects(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in raw:
		if _NEED_LOOKUP.has(str(key)):
			out[_NEED_LOOKUP[str(key)]] = float(raw[key])
	return out


func _load_rules() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if not file:
		push_warning("SynergyManager: could not load %s" % RULES_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for entry in parsed:
			if entry is Dictionary and entry.has("tags"):
				_rules.append(entry)
