class_name DialoguePools
## The voice pipeline's read side. String pools live in
## resources/dialogue/<domain>.json as kind -> bucket -> lines; consumers
## draw through fill(), which interpolates {tokens} and silently skips any
## line whose token is missing or empty — so a pool can safely mix plain
## lines with detail-threaded ones. Growing a pool is a JSON edit (or a
## tools/generate_dialogue.py run against a local model); no code changes.

static var _cache: Dictionary = {}


static func domain_data(domain: String) -> Dictionary:
	if _cache.has(domain):
		return _cache[domain]
	var parsed: Dictionary = {}
	var file := FileAccess.open("res://resources/dialogue/%s.json" % domain, FileAccess.READ)
	if file:
		var raw: Variant = JSON.parse_string(file.get_as_text())
		if raw is Dictionary:
			parsed = raw
	else:
		push_warning("DialoguePools: no pool file for domain '%s'" % domain)
	_cache[domain] = parsed
	return parsed


static func fill(domain: String, kind: String, bucket: String, tokens: Dictionary) -> Array[String]:
	## All lines of one bucket with {tokens} interpolated. A line that needs
	## a token the caller didn't supply (or supplied empty) is dropped from
	## this draw rather than shipped with a hole in it.
	var out: Array[String] = []
	var kinds: Dictionary = domain_data(domain)
	var buckets: Variant = kinds.get(kind, {})
	if not buckets is Dictionary:
		return out
	var lines: Variant = (buckets as Dictionary).get(bucket, [])
	if not lines is Array:
		return out
	for raw in lines:
		var line := str(raw)
		var ok := true
		for token_name in _tokens_in(line):
			var value := str(tokens.get(token_name, ""))
			if value.strip_edges() == "":
				ok = false
				break
			line = line.replace("{%s}" % token_name, value)
		if ok:
			out.append(line)
	return out


static func lint(domain: String, expected: Dictionary) -> PackedStringArray:
	## Coverage check: expected is {kind: {bucket: min_count}}. Returns one
	## message per hole — empty means the pool covers everything the code
	## draws. Harnesses assert on this so a pool edit cannot silently strand
	## a personality bucket.
	var problems := PackedStringArray()
	var kinds: Dictionary = domain_data(domain)
	for kind in expected:
		var buckets: Variant = kinds.get(kind, {})
		if not buckets is Dictionary:
			problems.append("%s/%s: kind missing" % [domain, kind])
			continue
		for bucket in expected[kind]:
			var need := int(expected[kind][bucket])
			var lines: Variant = (buckets as Dictionary).get(bucket, [])
			var have := (lines as Array).size() if lines is Array else 0
			if have < need:
				problems.append("%s/%s/%s: %d lines, need %d" % [domain, kind, bucket, have, need])
	return problems


static func _tokens_in(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var i := 0
	while true:
		var open := line.find("{", i)
		if open == -1:
			break
		var close := line.find("}", open + 1)
		if close == -1:
			break
		var token := line.substr(open + 1, close - open - 1)
		if token != "" and token not in out:
			out.append(token)
		i = close + 1
	return out
