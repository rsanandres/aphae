class_name PersonalityGenerator
## Generates unique personalities at runtime without JSON files.

# Name pools (diverse, international)
const FIRST_NAMES := [
	"Ada", "Akira", "Amara", "Anya", "Ash", "Atlas", "Basil", "Blair",
	"Cade", "Calla", "Cedar", "Cyrus", "Dara", "Dex", "Elio", "Elara",
	"Faye", "Felix", "Flora", "Gideon", "Greta", "Hana", "Hugo", "Ida",
	"Iris", "Juno", "Kai", "Kira", "Lane", "Leona", "Luca", "Luna",
	"Maren", "Milo", "Nadia", "Nico", "Noor", "Opal", "Orion", "Pax",
	"Quinn", "Rae", "Remy", "River", "Rowan", "Rue", "Sage", "Sable",
	"Seren", "Sol", "Suki", "Tara", "Thea", "Uri", "Vale", "Vera",
	"Wren", "Yara", "Zara", "Zeke", "Indigo", "Marlowe", "Hazel", "Ember",
]

const GOALS_POOL := [
	"become the most productive member of the office",
	"make a genuine friend in the office",
	"find creative inspiration every day",
	"maintain perfect work-life balance",
	"learn something new from each colleague",
	"create a welcoming atmosphere for everyone",
	"prove they are the most reliable person here",
	"find meaning in the everyday routine",
	"build trust with every colleague",
	"discover a hidden talent",
	"organize the best office events",
	"keep the peace between feuding coworkers",
	"become the go-to person for advice",
	"finish a secret personal project",
	"find love in the office",
]

const QUIRKS_POOL := [
	"hums while working", "talks to plants", "always carries a notebook",
	"taps their foot rhythmically", "collects office supplies",
	"names all the equipment", "sketches during meetings",
	"quotes old movies", "stress-bakes imaginary cakes",
	"reorganizes things compulsively", "speaks in metaphors",
	"naps with eyes open", "whistles off-key", "makes lists for everything",
	"narrates their own actions quietly", "gives everyone nicknames",
	"counts ceiling tiles when bored", "does finger guns unironically",
	"writes haikus about coworkers", "always offers to share food",
]

const SPEECH_STYLES := [
	"speaks in short, direct sentences",
	"uses flowery, poetic language",
	"peppers speech with workplace jargon",
	"talks fast and excitedly",
	"speaks slowly and deliberately",
	"uses lots of questions",
	"tends to ramble and go on tangents",
	"speaks softly and carefully",
	"uses humor and sarcasm",
	"speaks formally and precisely",
	"mixes in words from other languages",
	"uses a lot of analogies",
]

const BACKSTORIES := [
	"grew up in a small town and moved to the city for new opportunities",
	"was a star student who chose a quiet office life over ambition",
	"came from a big family and craves both solitude and connection",
	"switched careers midlife and is still finding their footing",
	"has always been the reliable one in every group",
	"is secretly an artist who took this job to pay the bills",
	"moved here from far away and is still adjusting to a new culture",
	"was once a competitive athlete who now channels energy into work",
	"has traveled the world and settled down to build roots",
	"was raised by their grandparents and values tradition",
	"is a self-taught expert in their field",
	"left a stressful job to find a calmer work environment",
]

const HAIR_TONES := [
	Color("#1a1c2c"), Color("#3a4466"), Color("#5a3a28"), Color("#8b5e3c"),
	Color("#b86f50"), Color("#d4a574"), Color("#e4c690"), Color("#2a1a0e"),
	Color("#6b3a2a"), Color("#c4956a"),
]

static var _used_names: Array[String] = []
static var _rng := RandomNumberGenerator.new()


static func generate_heuristic(spawn_index: int) -> PersonalityProfile:
	_rng.seed = hash(spawn_index + Time.get_ticks_msec())

	var profile := PersonalityProfile.new()

	# Unique name
	profile.agent_name = _pick_unique_name()

	# Big Five from beta-like distribution centered on 0.5
	profile.openness = _beta_random()
	profile.conscientiousness = _beta_random()
	profile.extraversion = _beta_random()
	profile.agreeableness = _beta_random()
	profile.neuroticism = _beta_random()

	# Curated palette ramp: distinct, saturated, and consistent with the
	# hand-authored cast (uniform HSV pastels made everyone near-identical).
	profile.color = Palette.CLOTHING_COLORS[spawn_index % Palette.CLOTHING_COLORS.size()]

	# Description from dominant trait
	profile.description = _generate_description(profile)

	# Goals (1-2 based on personality)
	var num_goals := 1 + (_rng.randi() % 2)
	var shuffled_goals := GOALS_POOL.duplicate()
	shuffled_goals.shuffle()
	for i in range(num_goals):
		profile.goals.append(shuffled_goals[i])

	# Quirks (1-2)
	var num_quirks := 1 + (_rng.randi() % 2)
	var shuffled_quirks := QUIRKS_POOL.duplicate()
	shuffled_quirks.shuffle()
	for i in range(num_quirks):
		profile.quirks.append(shuffled_quirks[i])

	# Speech style
	profile.speech_style = SPEECH_STYLES[_rng.randi() % SPEECH_STYLES.size()]

	# Backstory
	profile.backstory = BACKSTORIES[_rng.randi() % BACKSTORIES.size()]

	# Need decay multipliers based on personality
	profile.need_decay_multipliers = _generate_decay_multipliers(profile)

	return profile


static func generate_with_llm(existing_names: Array, spawn_index: int, callback: Callable) -> void:
	if not LLMManager.is_available or LLMManager.get_queue_size() > 4:
		var fallback := generate_heuristic(spawn_index)
		callback.call(fallback)
		return

	var prompt_text := PromptBuilder.build("generate_personality", {
		"existing_names": ", ".join(existing_names) if not existing_names.is_empty() else "none yet",
	})

	var format := {
		"type": "object",
		"properties": {
			"name": {"type": "string"},
			"description": {"type": "string"},
			"backstory": {"type": "string"},
			"speech_style": {"type": "string"},
			"openness": {"type": "number"},
			"conscientiousness": {"type": "number"},
			"extraversion": {"type": "number"},
			"agreeableness": {"type": "number"},
			"neuroticism": {"type": "number"},
			"goals": {"type": "array", "items": {"type": "string"}},
			"quirks": {"type": "array", "items": {"type": "string"}},
		},
		"required": ["name", "description", "openness", "conscientiousness", "extraversion", "agreeableness", "neuroticism"],
	}

	var messages := [
		{"role": "system", "content": "You are a creative character designer for an office simulation game."},
		{"role": "user", "content": prompt_text},
	]

	LLMManager.request_chat(messages, format, func(success: bool, data: Dictionary, _error: String) -> void:
		if not success:
			var fallback := generate_heuristic(spawn_index)
			callback.call(fallback)
			return

		var profile := PersonalityProfile.new()
		var name_candidate: String = data.get("name", "")
		if name_candidate == "" or name_candidate in _used_names or name_candidate in existing_names:
			name_candidate = _pick_unique_name()
		profile.agent_name = name_candidate
		_used_names.append(name_candidate)

		profile.description = data.get("description", "a mysterious newcomer")
		profile.backstory = data.get("backstory", "")
		profile.speech_style = data.get("speech_style", "speaks normally")
		profile.openness = clampf(float(data.get("openness", 0.5)), 0.0, 1.0)
		profile.conscientiousness = clampf(float(data.get("conscientiousness", 0.5)), 0.0, 1.0)
		profile.extraversion = clampf(float(data.get("extraversion", 0.5)), 0.0, 1.0)
		profile.agreeableness = clampf(float(data.get("agreeableness", 0.5)), 0.0, 1.0)
		profile.neuroticism = clampf(float(data.get("neuroticism", 0.5)), 0.0, 1.0)

		var raw_goals: Array = data.get("goals", [])
		for g in raw_goals:
			profile.goals.append(str(g))
		var raw_quirks: Array = data.get("quirks", [])
		for q in raw_quirks:
			profile.quirks.append(str(q))

		# Curated palette ramp (see generate_profile)
		profile.color = Palette.CLOTHING_COLORS[spawn_index % Palette.CLOTHING_COLORS.size()]
		profile.need_decay_multipliers = _generate_decay_multipliers(profile)
		callback.call(profile)
	, LLMManager.Priority.LOW)


static func get_hair_color_for_index(spawn_index: int) -> Color:
	return HAIR_TONES[spawn_index % HAIR_TONES.size()]


static func reset_names() -> void:
	_used_names.clear()


static func _pick_unique_name() -> String:
	var available: Array[String] = []
	for n in FIRST_NAMES:
		if n not in _used_names:
			available.append(n)
	if available.is_empty():
		# Fallback: generate numbered name
		var idx := _used_names.size() + 1
		var name := "Agent_%d" % idx
		_used_names.append(name)
		return name
	var name: String = available[_rng.randi() % available.size()]
	_used_names.append(name)
	return name


static func _beta_random() -> float:
	# Approximate beta(2,2) distribution: centered on 0.5, avoids extremes
	var u1 := _rng.randf()
	var u2 := _rng.randf()
	return clampf((u1 + u2) / 2.0, 0.05, 0.95)


static func _generate_description(profile: PersonalityProfile) -> String:
	var traits: PackedStringArray = []
	# Pick 2-3 dominant trait descriptors
	if profile.openness > 0.65:
		traits.append("imaginative and curious")
	elif profile.openness < 0.35:
		traits.append("practical and grounded")
	if profile.conscientiousness > 0.65:
		traits.append("organized and diligent")
	elif profile.conscientiousness < 0.35:
		traits.append("laid-back and spontaneous")
	if profile.extraversion > 0.65:
		traits.append("outgoing and talkative")
	elif profile.extraversion < 0.35:
		traits.append("quiet and introspective")
	if profile.agreeableness > 0.65:
		traits.append("warm and empathetic")
	elif profile.agreeableness < 0.35:
		traits.append("independent and assertive")
	if profile.neuroticism > 0.65:
		traits.append("sensitive and emotional")
	elif profile.neuroticism < 0.35:
		traits.append("calm and unflappable")

	if traits.is_empty():
		traits.append("well-balanced")
	return "a %s office worker" % ", ".join(traits)


static func _generate_decay_multipliers(profile: PersonalityProfile) -> Dictionary:
	return {
		"energy": 0.8 + profile.neuroticism * 0.4,  # Neurotic = tires faster
		"hunger": 0.9 + profile.conscientiousness * 0.2,
		"social": 0.7 + profile.extraversion * 0.6,  # Extraverts need social more
		"productivity": 0.8 + profile.conscientiousness * 0.4,
	}
