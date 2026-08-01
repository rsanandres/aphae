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
	lines.append("# Ayle — Episode Recap")
	lines.append("")
	lines.append("**Day %d** · %s · %s · %s" % [
		TimeManager.day,
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
	_append_confessionals(lines, confessionals)
	_append_cast(lines, cast)

	return "\n".join(lines)


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
		lines.append("_%s · drama %.1f/10_" % [sl.category, sl.drama_score])
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
		else:
			# Agent is gone (died and was removed); the name still earned a credit.
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
