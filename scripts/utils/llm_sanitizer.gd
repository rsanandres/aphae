class_name LLMSanitizer
## Last line of defense between raw LLM output and the screen. Small models
## leak JSON scaffolding into their dialogue values — `know?"} [{"` was
## visible in shipped screenshots — so every line that reaches a bubble,
## feed, or memory passes through clean_line() first.

const MAX_LINE_LENGTH := 220

# The earliest of these marks where dialogue ends and leaked scaffold begins.
const _JSON_ARTIFACTS: Array[String] = ["\"}", "{\"", "[{", "}]", "\"]", "\",\"", "”}"]


static func clean_line(text: String) -> String:
	var s := text.strip_edges()

	# Normalize typographic quotes so artifact matching and quote stripping work.
	s = s.replace("“", "\"").replace("”", "\"")

	# Schema echo ("line": "...") — keep only what follows. Must run before
	# the artifact cut, or a whole echoed object gets cut to nothing at its
	# own opening brace.
	for key in ["\"line\":", "\"answer\":", "\"thought\":"]:
		var echo := s.find(key)
		if echo != -1:
			s = s.substr(echo + key.length())
			break

	# Cut at the first JSON artifact.
	var cut := s.length()
	for artifact in _JSON_ARTIFACTS:
		var idx := s.find(artifact)
		if idx != -1 and idx < cut:
			cut = idx
	s = s.substr(0, cut)

	# Strip wrapping quotes and stray brackets/braces at the edges.
	s = s.strip_edges()
	while s.length() > 0 and s[0] in ["\"", "'", "{", "[", "}", "]", ":"]:
		s = s.substr(1).strip_edges()
	while s.length() > 0 and s[s.length() - 1] in ["\"", "'", "{", "[", "}", "]", ",", "\\"]:
		s = s.substr(0, s.length() - 1).strip_edges()

	# A speaker prefix the model added on its own ("Alice: hi") duplicates the
	# name tag the UI already draws. Only strip short single-word prefixes so
	# in-character colons ("Plan: coffee first") survive.
	var colon := s.find(": ")
	if colon > 0 and colon <= 16 and not " " in s.substr(0, colon):
		s = s.substr(colon + 2)

	# Collapse literal escapes and whitespace runs.
	s = s.replace("\\n", " ").replace("\\\"", "\"").replace("\\t", " ")
	while "  " in s:
		s = s.replace("  ", " ")
	s = s.strip_edges()

	# Hard cap at a word boundary.
	if s.length() > MAX_LINE_LENGTH:
		var head := s.substr(0, MAX_LINE_LENGTH)
		var space := head.rfind(" ")
		if space > MAX_LINE_LENGTH / 2:
			head = head.substr(0, space)
		s = head.strip_edges() + "..."

	return s
