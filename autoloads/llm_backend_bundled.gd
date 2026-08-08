class_name LLMBackendBundled
extends Node
## Bundled LLM backend using GDLlama GDExtension.
## Wraps a local GGUF model for inference without external dependencies.

signal status_changed(available: bool)
signal model_load_progress(percent: float)

var is_available: bool = false
var model_path: String = ""
var _gdllama: Node = null  # GDLlama node (dynamic to avoid hard dependency)
var _queue: Array[Dictionary] = []
var _is_generating: bool = false
var _is_loading: bool = false


func _ready() -> void:
	pass


func load_model(path: String) -> void:
	model_path = path
	if not FileAccess.file_exists(path):
		push_warning("[BundledLLM] Model not found at: %s" % path)
		is_available = false
		status_changed.emit(false)
		return

	# Try to instantiate GDLlama
	_gdllama = _create_gdllama()
	if not _gdllama:
		push_warning("[BundledLLM] GDLlama not available. Install the GDLlama GDExtension.")
		is_available = false
		status_changed.emit(false)
		return

	_is_loading = true
	add_child(_gdllama)

	# Configure GDLlama
	_gdllama.model_path = path
	_gdllama.n_ctx = 2048
	_gdllama.n_predict = 200
	_gdllama.temperature = 0.7

	# Connect signals
	if _gdllama.has_signal("model_loaded"):
		_gdllama.model_loaded.connect(_on_model_loaded)
	if _gdllama.has_signal("generate_text_finished"):
		_gdllama.generate_text_finished.connect(_on_generate_finished)

	# Load the model
	if _gdllama.has_method("load_model"):
		_gdllama.load_model()
	else:
		# Some versions auto-load on ready
		_on_model_loaded()


func check_health() -> void:
	# Bundled backend is available once model is loaded
	pass


func request_chat(messages: Array, format: Dictionary, callback: Callable, _priority: int = 0) -> void:
	if not is_available:
		callback.call(false, {}, "Bundled model not loaded")
		return

	_queue.append({
		"messages": messages,
		"format": format,
		"callback": callback,
	})
	_process_next()


func get_queue_size() -> int:
	return _queue.size()


func get_status_text() -> String:
	if _is_loading:
		return "AI: Loading model..."
	if not is_available:
		return "AI: No bundled model"
	return "AI: Bundled (SmolLM2)"


func drain_queue() -> void:
	while not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		entry["callback"].call(false, {}, "Backend switched")


func _process_next() -> void:
	if _queue.is_empty() or _is_generating or not is_available:
		return

	_is_generating = true
	var entry: Dictionary = _queue.pop_front()

	# Build prompt from messages
	var prompt := _format_messages(entry["messages"])

	# Add JSON schema instruction if format provided
	if not entry["format"].is_empty():
		prompt += "\n\nRespond with valid JSON matching this schema: " + JSON.stringify(entry["format"])

	# Store callback for when generation completes
	_gdllama.set_meta("current_callback", entry["callback"])
	_gdllama.set_meta("expects_json", not entry["format"].is_empty())

	if _gdllama.has_method("generate_text"):
		_gdllama.generate_text(prompt)
	elif _gdllama.has_method("run_generate_text"):
		_gdllama.run_generate_text(prompt)
	else:
		_is_generating = false
		entry["callback"].call(false, {}, "GDLlama generate method not found")


func _format_messages(messages: Array) -> String:
	var parts: PackedStringArray = []
	for msg in messages:
		var role: String = msg.get("role", "user")
		var content: String = msg.get("content", "")
		match role:
			"system":
				parts.append("<|system|>\n%s<|end|>" % content)
			"user":
				parts.append("<|user|>\n%s<|end|>" % content)
			"assistant":
				parts.append("<|assistant|>\n%s<|end|>" % content)
	parts.append("<|assistant|>")
	return "\n".join(parts)


func _on_model_loaded() -> void:
	_is_loading = false
	is_available = true
	status_changed.emit(true)
	print("[BundledLLM] Model loaded successfully: %s" % model_path)
	_process_next()


func _on_generate_finished(result: String) -> void:
	_is_generating = false
	if not _gdllama.has_meta("current_callback"):
		return

	var callback: Callable = _gdllama.get_meta("current_callback")
	var expects_json: bool = _gdllama.get_meta("expects_json")

	if expects_json:
		# Try to parse JSON from the response
		var json_str := _extract_json(result)
		var json := JSON.new()
		if json.parse(json_str) == OK:
			callback.call(true, json.data, "")
		else:
			# A {"raw"} success here let unparsed scaffolding reach dialogue;
			# a real failure routes callers to their heuristic fallback.
			callback.call(false, {}, "unparseable model output")
	else:
		callback.call(true, {"raw": result}, "")

	_process_next()


func _extract_json(text: String) -> String:
	# Try to find JSON object in the response
	var start := text.find("{")
	var end := text.rfind("}")
	if start >= 0 and end > start:
		return text.substr(start, end - start + 1)
	return text


func _create_gdllama() -> Node:
	# Dynamically check if GDLlama class exists
	if ClassDB.class_exists("GDLlama"):
		return ClassDB.instantiate("GDLlama")
	# Try loading as a script-based class
	var gdllama_script := load("res://addons/gdllama/gdllama.gd") as GDScript
	if gdllama_script:
		return gdllama_script.new()
	return null
