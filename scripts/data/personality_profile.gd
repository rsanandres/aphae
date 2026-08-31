class_name PersonalityProfile
extends RefCounted
## Loaded from JSON. Defines an agent's personality, backstory, and behavioral traits.

var agent_name: String = ""
var description: String = ""
var color: Color = Color.WHITE

# Big Five traits (0.0 - 1.0)
var openness: float = 0.5
var conscientiousness: float = 0.5
var extraversion: float = 0.5
var agreeableness: float = 0.5
var neuroticism: float = 0.5

var goals: Array[String] = []
var quirks: Array[String] = []
var speech_style: String = ""
var backstory: String = ""
# Optional few-shot lines in this character's register, for prompts. Empty
# for procedural agents — the voice block simply drops out of the template.
var voice_lines: Array[String] = []

# Need decay rate multipliers (personality affects how fast needs drain)
var need_decay_multipliers: Dictionary = {}


static func load_from_json(path: String) -> PersonalityProfile:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("PersonalityProfile: Failed to load '%s'" % path)
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("PersonalityProfile: JSON parse error in '%s'" % path)
		return null
	var data: Dictionary = json.data
	var profile := PersonalityProfile.new()

	profile.agent_name = data.get("name", "Unknown")
	profile.description = data.get("description", "")
	profile.backstory = data.get("backstory", "")
	profile.speech_style = data.get("speech_style", "")

	# Saves and JSON are untrusted here: a truncated or hand-edited file with
	# a short or non-numeric color array must not abort the whole agent load.
	profile.color = Color(0.5, 0.5, 0.5)
	var c: Variant = data.get("color")
	if c is Array and c.size() >= 3 and c[0] is float and c[1] is float and c[2] is float:
		profile.color = Color(c[0], c[1], c[2])

	var big5: Dictionary = data.get("big_five", {})
	profile.openness = big5.get("openness", 0.5)
	profile.conscientiousness = big5.get("conscientiousness", 0.5)
	profile.extraversion = big5.get("extraversion", 0.5)
	profile.agreeableness = big5.get("agreeableness", 0.5)
	profile.neuroticism = big5.get("neuroticism", 0.5)

	var goals_raw: Array = data.get("goals", [])
	for g in goals_raw:
		profile.goals.append(str(g))

	var quirks_raw: Array = data.get("quirks", [])
	for q in quirks_raw:
		profile.quirks.append(str(q))

	for v in data.get("voice_lines", []):
		profile.voice_lines.append(str(v))

	profile.need_decay_multipliers = data.get("need_decay_multipliers", {})

	return profile


func to_dict() -> Dictionary:
	return {
		"name": agent_name,
		"description": description,
		"backstory": backstory,
		"speech_style": speech_style,
		"color": [color.r, color.g, color.b],
		"big_five": {
			"openness": openness,
			"conscientiousness": conscientiousness,
			"extraversion": extraversion,
			"agreeableness": agreeableness,
			"neuroticism": neuroticism,
		},
		"goals": goals.duplicate(),
		"quirks": quirks.duplicate(),
		"voice_lines": voice_lines.duplicate(),
		"need_decay_multipliers": need_decay_multipliers.duplicate(),
	}


static func from_dict(data: Dictionary) -> PersonalityProfile:
	var profile := PersonalityProfile.new()
	profile.agent_name = data.get("name", "Unknown")
	profile.description = data.get("description", "")
	profile.backstory = data.get("backstory", "")
	profile.speech_style = data.get("speech_style", "")

	# Saves and JSON are untrusted here: a truncated or hand-edited file with
	# a short or non-numeric color array must not abort the whole agent load.
	profile.color = Color(0.5, 0.5, 0.5)
	var c: Variant = data.get("color")
	if c is Array and c.size() >= 3 and c[0] is float and c[1] is float and c[2] is float:
		profile.color = Color(c[0], c[1], c[2])

	var big5: Dictionary = data.get("big_five", {})
	profile.openness = big5.get("openness", 0.5)
	profile.conscientiousness = big5.get("conscientiousness", 0.5)
	profile.extraversion = big5.get("extraversion", 0.5)
	profile.agreeableness = big5.get("agreeableness", 0.5)
	profile.neuroticism = big5.get("neuroticism", 0.5)

	var goals_raw: Array = data.get("goals", [])
	for g in goals_raw:
		profile.goals.append(str(g))

	var quirks_raw: Array = data.get("quirks", [])
	for q in quirks_raw:
		profile.quirks.append(str(q))

	for v in data.get("voice_lines", []):
		profile.voice_lines.append(str(v))

	profile.need_decay_multipliers = data.get("need_decay_multipliers", {})
	return profile


func get_trait_lines() -> String:
	## Big Five verbalized for prompts, mid-range included. Small models act
	## on words, not scales — "Openness: 0.63" steers nothing at all.
	var lines: PackedStringArray = []
	lines.append(_trait_line(openness,
		"You chase new ideas and wander off on tangents.",
		"You will try a new idea once it has earned it.",
		"You like the proven way and distrust novelty."))
	lines.append(_trait_line(conscientiousness,
		"You are meticulous; loose ends genuinely bother you.",
		"You keep things roughly in order, most days.",
		"You improvise, procrastinate, and wing it."))
	lines.append(_trait_line(extraversion,
		"You seek people out and think out loud.",
		"You enjoy company in doses, then need quiet.",
		"You keep to yourself and crowds drain you."))
	lines.append(_trait_line(agreeableness,
		"You smooth conflicts over and give ground easily.",
		"You are fair with people but no pushover.",
		"You are blunt, competitive, and slow to yield."))
	lines.append(_trait_line(neuroticism,
		"You worry quickly and feel every setback hard.",
		"You wobble under pressure but recover fast.",
		"Almost nothing rattles you."))
	return "\n".join(lines)


static func _trait_line(value: float, high: String, mid: String, low: String) -> String:
	if value > 0.65:
		return "- " + high
	if value < 0.35:
		return "- " + low
	return "- " + mid


func get_voice_block() -> String:
	## Few-shot register examples for dialogue prompts; "" when unauthored so
	## the block vanishes from the template instead of leaving a bare header.
	if voice_lines.is_empty():
		return ""
	var out := "Lines in your voice (the register, never to be repeated verbatim):\n"
	for line in voice_lines:
		out += "- \"%s\"\n" % line
	return out


func get_personality_summary() -> String:
	var traits: PackedStringArray = []
	if openness > 0.7: traits.append("creative and curious")
	elif openness < 0.3: traits.append("practical and conventional")
	if conscientiousness > 0.7: traits.append("organized and disciplined")
	elif conscientiousness < 0.3: traits.append("spontaneous and flexible")
	if extraversion > 0.7: traits.append("outgoing and energetic")
	elif extraversion < 0.3: traits.append("quiet and reserved")
	if agreeableness > 0.7: traits.append("friendly and cooperative")
	elif agreeableness < 0.3: traits.append("competitive and blunt")
	if neuroticism > 0.7: traits.append("anxious and sensitive")
	elif neuroticism < 0.3: traits.append("calm and emotionally stable")
	return ", ".join(traits) if not traits.is_empty() else "balanced personality"


func get_mood(needs: Dictionary) -> String:
	var moods: PackedStringArray = []
	if needs.get(NeedType.Type.ENERGY, 100.0) < 30.0:
		moods.append("exhausted" if neuroticism > 0.5 else "tired")
	if needs.get(NeedType.Type.HUNGER, 100.0) < 30.0:
		moods.append("starving" if neuroticism > 0.5 else "hungry")
	if needs.get(NeedType.Type.SOCIAL, 100.0) < 30.0:
		moods.append("lonely" if extraversion > 0.5 else "withdrawn")
	if needs.get(NeedType.Type.PRODUCTIVITY, 100.0) < 30.0:
		moods.append("guilty about slacking" if conscientiousness > 0.5 else "unproductive")
	if moods.is_empty():
		moods.append("content" if agreeableness > 0.5 else "fine")
	return ", ".join(moods)
