class_name EpisodeRecap
## Builds a shareable Markdown recap of a run from the Narrator's storylines
## and the ConfessionalDirector's talking heads.
##
## Pure synchronous assembly: storylines already carry LLM-written summaries,
## so nothing here needs the LLM or an async callback. Reads only, never mutates.

const RECAP_DIR := "user://recaps/"
const MAX_STORYLINES := 5
const MAX_QUIPS := 12


static func build() -> String:
	var storylines: Array[Storyline] = Narrator.get_top_storylines(MAX_STORYLINES)
	var confessionals: Array[Confessional] = ConfessionalDirector.get_recent(
		ConfessionalDirector.MAX_CONFESSIONALS
	)
	var cast: Array[String] = _gather_cast(storylines, confessionals)

	var lines: PackedStringArray = []
	lines.append("# Aphae — Episode Recap")
	lines.append("")
	# Brand the byline the way the game brands itself: episodes and grades,
	# not bare day counts.
	var byline := "**%s · Day %d**" % [ProducerEconomy.episode_label(), TimeManager.day]
	if ProducerEconomy.last_episode_score >= 0:
		byline += " · last episode: Grade %s (score %d)" % [
			ProducerEconomy.grade_for(ProducerEconomy.last_episode_score),
			ProducerEconomy.last_episode_score]
	lines.append(byline)
	lines.append("%s · %s · %s" % [
		_plural(cast.size(), "character", "characters"),
		_plural(storylines.size(), "storyline", "storylines"),
		_plural(confessionals.size(), "confessional", "confessionals"),
	])
	lines.append("")

	if storylines.is_empty() and confessionals.is_empty():
		lines.append("_Nothing has happened yet. The office is still quiet._")
		lines.append("")
		return "\n".join(lines)

	_append_storylines(lines, storylines)
	_append_mole_case(lines)
	_append_goals(lines)
	_append_secrets(lines)
	_append_confessionals(lines, confessionals)
	_append_cast(lines, cast)

	return "\n".join(lines)


static func build_display() -> String:
	## The same recap as BBCode, for on-screen RichTextLabels. build() stays
	## Markdown because that is what gets written to a file — rendering the
	## export format directly showed players literal "##" and "**" markers.
	return _to_bbcode(build())


static func _to_bbcode(markdown: String) -> String:
	var out: PackedStringArray = []
	for raw_line in markdown.split("\n"):
		# Escape brackets first so quip text can never inject BBCode of its own.
		var line := raw_line.replace("[", "[lb]")
		if line == ">":
			continue  # blank quote separator; the indent already spaces them
		# Emphasis is applied to the line's CONTENT before the block tag wraps
		# it. Running it afterwards let the underscore inside [font_size=...]
		# be read as an italic marker, which mangled the tag itself.
		if line.begins_with("### "):
			out.append("[b]%s[/b]" % _emphasis(line.substr(4)))
		elif line.begins_with("## "):
			out.append("[color=#ffd966][b]%s[/b][/color]" % _emphasis(line.substr(3)))
		elif line.begins_with("# "):
			out.append("[font_size=13][color=#ffd966][b]%s[/b][/color][/font_size]" % _emphasis(line.substr(2)))
		elif line.begins_with("> "):
			out.append("[indent]%s[/indent]" % _emphasis(line.substr(2)))
		elif line.begins_with("- "):
			out.append("  • %s" % _emphasis(line.substr(2)))
		else:
			out.append(_emphasis(line))
	return "\n".join(out)


static func _emphasis(text: String) -> String:
	return _wrap_pairs(_wrap_pairs(text, "**", "[b]", "[/b]"), "_", "[i]", "[/i]")


static func _wrap_pairs(text: String, marker: String, open_tag: String, close_tag: String) -> String:
	## Wraps only matched pairs. An odd number of markers leaves the line
	## untouched rather than silently swallowing the stray one.
	var parts := text.split(marker)
	if parts.size() < 3 or parts.size() % 2 == 0:
		return text
	var out := ""
	for i in range(parts.size()):
		if i % 2 == 1 and i < parts.size() - 1:
			out += open_tag + parts[i] + close_tag
		else:
			out += parts[i]
	return out


static func export_to_file() -> String:
	## Writes the recap to user://recaps/ and returns the path, or "" on failure.
	if not DirAccess.dir_exists_absolute(RECAP_DIR):
		DirAccess.make_dir_recursive_absolute(RECAP_DIR)

	var path := RECAP_DIR + "recap_day%d_%s.md" % [TimeManager.day, _file_stamp()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("EpisodeRecap: could not write %s" % path)
		return ""
	file.store_string(build())
	file.close()
	return path


# --- Sections --------------------------------------------------------------

static func _append_storylines(lines: PackedStringArray, storylines: Array[Storyline]) -> void:
	if storylines.is_empty():
		return
	lines.append("## The Story So Far")
	lines.append("")
	for sl in storylines:
		var title: String = sl.title if sl.title != "" else "Untitled Story"
		lines.append("### %s" % title)
		lines.append("_%s · drama %.1f/10 · %s_" % [sl.category, sl.drama_score,
			"ongoing" if sl.is_active else "concluded"])
		lines.append("")
		if sl.summary != "":
			lines.append(sl.summary)
		else:
			# No LLM summary yet — fall back to the events themselves.
			for ev in sl.events:
				lines.append("- Day %d — %s" % [int(ev.get("day", 0)), str(ev.get("text", ""))])
		if not sl.involved_agents.is_empty():
			lines.append("")
			lines.append("**Featuring:** %s" % ", ".join(sl.involved_agents))
		lines.append("")


static func _append_mole_case(lines: PackedStringArray) -> void:
	## The season's whodunit. A run where the mole was unmasked used to export
	## identically to one where nothing happened.
	var case: CaseState = WhodunitDirector.case
	if case == null or (case.is_open() and case.incidents == 0):
		return
	lines.append("## The Mole")
	lines.append("")
	if case.is_open():
		lines.append("_An open case: %s and counting. The culprit walks among the cast._" % 			_plural(case.incidents, "incident", "incidents"))
	elif case.status == CaseState.Status.CAUGHT:
		lines.append("**%s** was the mole — %s of sabotage before the house voted them out%s." % [
			case.mole_name, _plural(case.incidents, "incident", "incidents"),
			(", after %s pointed the wrong way" % _plural(case.wrongful_votes, "meeting", "meetings")) if case.wrongful_votes > 0 else ""])
	else:
		lines.append("**%s** was the mole — and got away with all %s of it." % [
			case.mole_name, _plural(case.incidents, "incident", "incidents")])
	lines.append("")


static func _append_goals(lines: PackedStringArray) -> void:
	## Dreams landed and dreams abandoned — including a dead agent's
	## unfinished business, which PLAN.md always promised this would show.
	var resolved: PackedStringArray = []
	for agent_name in GoalManager._goals.keys():
		for goal: GoalState in GoalManager._goals[agent_name]:
			if goal.status == GoalState.Status.ACHIEVED:
				resolved.append("- **%s** made it: %s" % [goal.agent_name, goal.phrase()])
			elif goal.status == GoalState.Status.FAILED:
				resolved.append("- **%s** let it go: %s (reached %d%%)" % [
					goal.agent_name, goal.phrase(), int(goal.progress)])
	if resolved.is_empty():
		return
	lines.append("## Dreams, Kept and Broken")
	lines.append("")
	for row in resolved:
		lines.append(row)
	lines.append("")


static func _append_secrets(lines: PackedStringArray) -> void:
	## Only what the office already knows. Hidden secrets stay hidden — the
	## recap is shareable, not an oracle.
	var out: PackedStringArray = []
	for secret: SecretState in SecretManager._secrets.values():
		if secret.exposed:
			out.append("- Everyone found out **%s** %s." % [secret.agent_name, secret.text])
	if out.is_empty():
		return
	lines.append("## Secrets Out")
	lines.append("")
	for row in out:
		lines.append(row)
	lines.append("")


static func _append_confessionals(lines: PackedStringArray, confessionals: Array[Confessional]) -> void:
	if confessionals.is_empty():
		return
	lines.append("## From the Confessional Booth")
	lines.append("")
	# Newest first, capped — the tail of a long run is the interesting part.
	var shown := 0
	for i in range(confessionals.size() - 1, -1, -1):
		if shown >= MAX_QUIPS:
			break
		var c: Confessional = confessionals[i]
		if c.line == "":
			continue
		if c.is_host:
			# Host recaps already name the day; eulogies don't. Only add it if missing.
			var host_line := "> _%s_" % c.line
			if not ("Day %d" % c.day) in c.line:
				host_line += " — Day %d" % c.day
			lines.append(host_line)
		else:
			lines.append("> **%s** (Day %d): \"%s\"" % [c.speaker, c.day, c.line])
		lines.append(">")
		shown += 1
	lines.append("")


static func _append_cast(lines: PackedStringArray, cast: Array[String]) -> void:
	if cast.is_empty():
		return
	lines.append("## The Cast")
	lines.append("")
	for agent_name in cast:
		var agent := AgentManager.get_agent_by_name(agent_name)
		if agent and agent.personality:
			var status := " _(deceased)_" if agent.is_dead else ""
			lines.append("- **%s**%s — %s" % [
				agent_name, status, agent.personality.get_personality_summary()
			])
		elif AgentManager.cast_fates.has(agent_name):
			# Gone, but not forgotten: the fate cache keeps who they were and
			# how they left.
			var fate: Dictionary = AgentManager.cast_fates[agent_name]
			var who := str(fate.get("personality", ""))
			lines.append("- **%s** — %s _(%s, day %d)_" % [
				agent_name,
				who if who != "" else "one of the cast",
				str(fate.get("fate", "gone")), int(fate.get("day", 0))])
		else:
			# Agent is gone and predates the fate cache; the name still earned a credit.
			lines.append("- **%s**" % agent_name)
	lines.append("")


# --- Helpers ---------------------------------------------------------------

static func _gather_cast(storylines: Array[Storyline], confessionals: Array[Confessional]) -> Array[String]:
	## Names from live agents, storylines, and confessionals, deduped and stable.
	## Storylines/confessionals outlive their agents, so a recap still has a cast
	## after everyone has died.
	var cast: Array[String] = []
	for agent in AgentManager.agents:
		if is_instance_valid(agent) and agent.agent_name not in cast:
			cast.append(agent.agent_name)
	for sl in storylines:
		for n in sl.involved_agents:
			if n != "" and n not in cast:
				cast.append(n)
	for c in confessionals:
		# Require a real line: a restored-but-empty entry shouldn't earn a credit.
		if not c.is_host and c.speaker != "" and c.line != "" and c.speaker not in cast:
			cast.append(c.speaker)
	return cast


static func _plural(count: int, singular: String, plural: String) -> String:
	return "%d %s" % [count, singular if count == 1 else plural]


static func _file_stamp() -> String:
	## Colons are illegal in Windows filenames, so flatten the timestamp.
	return Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
