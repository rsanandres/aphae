extends Node
## Async LLM inference manager with backend abstraction.
## Tries: bundled (GDLlama) → Ollama → heuristic fallback.

signal ollama_status_changed(available: bool)
signal active_backend_changed(backend_name: String)
signal model_loading(is_loading: bool)

const HEALTH_RETRY_INTERVAL := 30.0

enum Priority { LOW = 0, NORMAL = 1, HIGH = 2 }

var is_available: bool = false
var active_backend_name: String = "none"

var _bundled_backend: LLMBackendBundled = null
var _ollama_backend: LLMBackendOllama = null
var _active_backend: Node = null  # Current backend in use
var _health_timer: float = 0.0


var _preferred_backend: String = "auto"  # "auto", "bundled", "ollama", "heuristic"


func _ready() -> void:
	# Create bundled backend
	_bundled_backend = LLMBackendBundled.new()
	_bundled_backend.name = "BundledBackend"
	add_child(_bundled_backend)
	_bundled_backend.status_changed.connect(_on_bundled_status_changed)

	# Create Ollama backend
	_ollama_backend = LLMBackendOllama.new()
	_ollama_backend.name = "OllamaBackend"
	add_child(_ollama_backend)
	_ollama_backend.status_changed.connect(_on_ollama_status_changed)

	# Read LLM settings from SettingsManager (loaded before LLMManager)
	var ollama_url: String = SettingsManager.ollama_url
	var ollama_model: String = SettingsManager.ollama_model
	_preferred_backend = SettingsManager.llm_backend

	# Configure Ollama with user settings
	_ollama_backend.configure({
		"name": "ollama",
		"url": ollama_url,
		"model": ollama_model,
		"temperature": 0.7,
		"num_predict": 150,
	})

	# Connect to SettingsManager so changes are applied at runtime
	SettingsManager.settings_changed.connect(_on_settings_changed)

	# Try to load bundled model (unless user explicitly chose ollama/heuristic)
	if _preferred_backend == "heuristic":
		# Skip all LLM backends, stay offline (heuristic fallback in AgentBrain)
		print("[LLMManager] Backend preference: heuristic — skipping LLM backends")
	elif _preferred_backend == "ollama":
		# Skip bundled, go straight to Ollama
		_ollama_backend.check_health()
	else:
		# "auto" or "bundled": try bundled first, then Ollama
		var bundled_path := _get_bundled_model_path()
		if bundled_path != "":
			model_loading.emit(true)
			_bundled_backend.load_model(bundled_path)
		else:
			# No bundled model, go straight to Ollama check
			_ollama_backend.check_health()


func _process(delta: float) -> void:
	_health_timer += delta
	if _health_timer >= HEALTH_RETRY_INTERVAL:
		_health_timer = 0.0
		if not is_available:
			_check_backends()


func request_chat(messages: Array, format: Dictionary, callback: Callable, priority: int = Priority.NORMAL, options: Dictionary = {}) -> void:
	## options carries per-task sampling overrides ({"temperature": 0.4} for
	## decisions, 0.9 for dialogue); the backend's configured values fill in
	## whatever a call site does not override.
	if not is_available or _active_backend == null:
		# Queue locally, drain as failures if no backend comes up
		callback.call(false, {}, "No LLM backend available")
		return

	# Priority insertion into backend queue
	_active_backend.request_chat(messages, format, callback, priority, options)


func get_queue_size() -> int:
	if _active_backend and _active_backend.has_method("get_queue_size"):
		return _active_backend.get_queue_size()
	return 0


func get_status_text() -> String:
	if _active_backend and _active_backend.has_method("get_status_text"):
		return _active_backend.get_status_text()
	if not is_available:
		return "LLM: Offline"
	return "LLM: %s" % active_backend_name


func retry_health_check() -> void:
	_check_backends()


func configure_ollama(url: String, model_name: String) -> void:
	_ollama_backend.configure({
		"name": "ollama",
		"url": url,
		"model": model_name,
		"temperature": 0.7,
		"num_predict": 200,
	})
	_ollama_backend.check_health()


func _check_backends() -> void:
	if not _bundled_backend.is_available:
		var bundled_path := _get_bundled_model_path()
		if bundled_path != "" and not _bundled_backend._is_loading:
			_bundled_backend.load_model(bundled_path)
	_ollama_backend.check_health()


func _update_active_backend() -> void:
	var was_available := is_available
	var old_name := active_backend_name

	# Respect user backend preference
	if _preferred_backend == "heuristic":
		# User wants heuristic only — no LLM backend
		_active_backend = null
		active_backend_name = "heuristic"
		is_available = false
	elif _preferred_backend == "bundled":
		# Only use bundled
		if _bundled_backend.is_available:
			_active_backend = _bundled_backend
			active_backend_name = "bundled"
			is_available = true
		else:
			_active_backend = null
			active_backend_name = "none"
			is_available = false
	elif _preferred_backend == "ollama":
		# Only use Ollama
		if _ollama_backend.is_available:
			_active_backend = _ollama_backend
			active_backend_name = "ollama"
			is_available = true
		else:
			_active_backend = null
			active_backend_name = "none"
			is_available = false
	else:
		# "auto": priority bundled > ollama
		if _bundled_backend.is_available:
			_active_backend = _bundled_backend
			active_backend_name = "bundled"
			is_available = true
		elif _ollama_backend.is_available:
			_active_backend = _ollama_backend
			active_backend_name = "ollama"
			is_available = true
		else:
			_active_backend = null
			active_backend_name = "none"
			is_available = false

	if is_available != was_available:
		ollama_status_changed.emit(is_available)
	if active_backend_name != old_name:
		active_backend_changed.emit(active_backend_name)
		if is_available:
			print("[LLMManager] Active backend: %s" % active_backend_name)


func _on_bundled_status_changed(available: bool) -> void:
	model_loading.emit(false)
	if available:
		print("[LLMManager] Bundled model ready")
	_update_active_backend()


func _on_ollama_status_changed(_available: bool) -> void:
	_update_active_backend()


func _on_settings_changed() -> void:
	var new_url: String = SettingsManager.ollama_url
	var new_model: String = SettingsManager.ollama_model
	var new_backend: String = SettingsManager.llm_backend

	_preferred_backend = new_backend
	configure_ollama(new_url, new_model)
	_update_active_backend()


func _get_bundled_model_path() -> String:
	# Check multiple possible locations
	var paths := [
		"res://models/smollm2-1.7b-instruct-q4_k_m.gguf",
		"user://models/smollm2-1.7b-instruct-q4_k_m.gguf",
		OS.get_executable_path().get_base_dir().path_join("models/smollm2-1.7b-instruct-q4_k_m.gguf"),
	]
	for path in paths:
		if FileAccess.file_exists(path):
			return path
	return ""
