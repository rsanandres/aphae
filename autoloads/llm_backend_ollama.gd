class_name LLMBackendOllama
extends Node
## Ollama HTTP backend for LLM inference. Extracted from LLMManager.

signal status_changed(available: bool)

const CHAT_ENDPOINT := "/api/chat"
const TIMEOUT_SEC := 30.0
const POOL_SIZE := 3

var backend_name: String = "local"
var url: String = "http://localhost:11434"
var model: String = "smollm2:1.7b"
var temperature: float = 0.7
var num_predict: int = 150
var is_available: bool = false

var _pool: Array[HTTPRequest] = []
var _pool_busy: Array[bool] = []
var _queue: Array[Dictionary] = []


func _ready() -> void:
	for i in range(POOL_SIZE):
		var http := HTTPRequest.new()
		http.timeout = TIMEOUT_SEC
		add_child(http)
		http.request_completed.connect(_on_pool_request_completed.bind(i))
		_pool.append(http)
		_pool_busy.append(false)


func configure(config: Dictionary) -> void:
	backend_name = config.get("name", "local")
	url = config.get("url", "http://localhost:11434")
	model = config.get("model", "smollm2:1.7b")
	temperature = config.get("temperature", 0.7)
	num_predict = config.get("num_predict", 150)


func check_health() -> void:
	var check_http := HTTPRequest.new()
	check_http.timeout = 5.0
	add_child(check_http)
	check_http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		var was_available := is_available
		is_available = (code == 200)
		check_http.queue_free()
		if is_available != was_available:
			status_changed.emit(is_available)
		if is_available:
			_process_next()
	)
	check_http.request(url, [], HTTPClient.METHOD_GET)


func request_chat(messages: Array, format: Dictionary, callback: Callable, _priority: int = 0) -> void:
	_queue.append({
		"messages": messages,
		"format": format,
		"callback": callback,
	})
	_process_next()


func get_queue_size() -> int:
	return _queue.size()


func get_status_text() -> String:
	if not is_available:
		return "Ollama: Offline"
	return "Ollama: %s (%s)" % [backend_name.capitalize(), model]


func _process_next() -> void:
	if _queue.is_empty() or not is_available:
		return
	var pool_idx := _get_idle_pool_index()
	if pool_idx == -1:
		return
	_pool_busy[pool_idx] = true
	var http: HTTPRequest = _pool[pool_idx]
	var entry: Dictionary = _queue.pop_front()
	var body := {
		"model": model,
		"messages": entry["messages"],
		"stream": false,
		"keep_alive": "30m",
		"options": {
			"temperature": temperature,
			"num_predict": num_predict,
		},
	}
	if not entry["format"].is_empty():
		body["format"] = entry["format"]
	var json_body := JSON.stringify(body)
	var headers := ["Content-Type: application/json"]
	http.set_meta("current_callback", entry["callback"])
	http.request(url + CHAT_ENDPOINT, headers, HTTPClient.METHOD_POST, json_body)


func _get_idle_pool_index() -> int:
	for i in range(POOL_SIZE):
		if not _pool_busy[i]:
			return i
	return -1


func _on_pool_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, pool_idx: int) -> void:
	var http: HTTPRequest = _pool[pool_idx]
	_pool_busy[pool_idx] = false
	var callback: Callable = http.get_meta("current_callback")

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var error_msg := "Ollama HTTP error: result=%d, code=%d" % [result, response_code]
		is_available = false
		status_changed.emit(false)
		callback.call(false, {}, error_msg)
		_process_next()
		return

	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		callback.call(false, {}, "JSON parse error")
		_process_next()
		return

	var data: Dictionary = json.data
	var message: Dictionary = data.get("message", {})
	var content_str: String = message.get("content", "")

	var content_json := JSON.new()
	if content_json.parse(content_str) == OK:
		callback.call(true, content_json.data, "")
	else:
		# Try to salvage it before giving up — see _repair_json.
		var repaired := _repair_json(content_str)
		if repaired != content_str and content_json.parse(repaired) == OK:
			callback.call(true, content_json.data, "")
		else:
			# Models sometimes append junk after a valid object
			# ({"line":"..."} [{...}]) — recover the object alone.
			var first_obj := _extract_first_object(content_str)
			if first_obj != "" and content_json.parse(first_obj) == OK:
				callback.call(true, content_json.data, "")
			else:
				# Reporting success with {"raw": ...} here let unparsed
				# scaffolding flow into dialogue; a real failure routes every
				# caller to its heuristic fallback instead.
				callback.call(false, {}, "unparseable model output")

	_process_next()


func _repair_json(raw: String) -> String:
	## Small models routinely close a JSON string with a typographic quote (”)
	## instead of ", and pad the tail with non-breaking spaces:
	##
	##     { "answer": "Oh, it's lovely! ... ”}
	##
	## The content is fine but the payload will not parse, so every caller
	## silently falls back to its canned text — measured on gemma3, this failed
	## identically at num_predict 150 and 300, so it is not truncation.
	##
	## Only ever runs after a parse has already failed, so a well-formed
	## response can never be altered by this.
	var s := raw.replace("“", "\"").replace("”", "\"")
	s = s.replace("‘", "'").replace("’", "'")
	s = s.replace(" ", " ")
	# Drop any trailing padding after the final closing brace.
	var last := s.rfind("}")
	if last != -1:
		s = s.substr(0, last + 1)
	return s.strip_edges()


func _extract_first_object(raw: String) -> String:
	## Return the first balanced {...} object in the text, or "" if none.
	## Quote-aware so braces inside string values don't unbalance the scan.
	var start := raw.find("{")
	if start == -1:
		return ""
	var depth := 0
	var in_string := false
	var i := start
	while i < raw.length():
		var c := raw[i]
		if in_string:
			if c == "\\":
				i += 2
				continue
			if c == "\"":
				in_string = false
		else:
			if c == "\"":
				in_string = true
			elif c == "{":
				depth += 1
			elif c == "}":
				depth -= 1
				if depth == 0:
					return raw.substr(start, i - start + 1)
		i += 1
	return ""


func drain_queue() -> void:
	## Fail all queued requests (used when switching backends)
	while not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		entry["callback"].call(false, {}, "Backend switched")
