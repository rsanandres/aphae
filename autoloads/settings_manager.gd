extends Node
## Persists user settings to user://settings.cfg via ConfigFile.

signal settings_changed()
signal volume_changed(bus: String, value: float)

const SETTINGS_PATH := "user://settings.cfg"

# Audio
var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 0.8

# Display
var fullscreen: bool = false
var desktop_pet_mode: bool = false

# LLM
var llm_backend: String = "auto"  # "auto", "bundled", "ollama", "heuristic"
var ollama_url: String = "http://localhost:11434"
var ollama_model: String = "smollm2:1.7b"

# Game
var default_speed: int = 1
var auto_save_interval: int = 5  # game-days
var max_agents: int = 50
# Ambient by default: the office keeps living while you work. Players who
# want the old foreground behavior can turn auto-pause back on.
var auto_pause_on_focus_loss: bool = false
var low_power_when_unfocused: bool = true
var mute_when_unfocused: bool = true


func _ready() -> void:
	_migrate_from_ayle()
	load_settings()
	_apply_audio()
	# Apply game settings after all autoloads are initialized
	call_deferred("_apply_game_settings")


func _migrate_from_ayle() -> void:
	## 2026-08-28: the product was renamed Ayle -> Aphae. user:// derives from
	## config/name, so the rename orphaned every save, setting, achievement,
	## and the lifetime producer.json. Copy the old tree over exactly once —
	## this runs before anything reads user://, and never overwrites.
	if FileAccess.file_exists(SETTINGS_PATH) or DirAccess.dir_exists_absolute("user://saves"):
		return  # already migrated, or a genuinely fresh install with new data
	var old_root := ProjectSettings.globalize_path("user://").rstrip("/")
	old_root = old_root.substr(0, old_root.rfind("/")) + "/Ayle"
	if not DirAccess.dir_exists_absolute(old_root):
		return
	_copy_tree(old_root, ProjectSettings.globalize_path("user://"))
	print("[SettingsManager] Migrated user data from Ayle -> Aphae")


func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	var dir := DirAccess.open(from)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			if dir.current_is_dir():
				_copy_tree(from + "/" + entry, to + "/" + entry)
			elif not FileAccess.file_exists(to + "/" + entry):
				DirAccess.copy_absolute(from + "/" + entry, to + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return  # Use defaults

	# Audio
	master_volume = cfg.get_value("audio", "master_volume", 1.0)
	music_volume = cfg.get_value("audio", "music_volume", 0.7)
	sfx_volume = cfg.get_value("audio", "sfx_volume", 0.8)

	# Display
	fullscreen = cfg.get_value("display", "fullscreen", false)
	desktop_pet_mode = cfg.get_value("display", "desktop_pet_mode", false)

	# LLM
	llm_backend = cfg.get_value("llm", "backend", "auto")
	ollama_url = cfg.get_value("llm", "ollama_url", "http://localhost:11434")
	ollama_model = cfg.get_value("llm", "ollama_model", "smollm2:1.7b")

	# Game
	default_speed = cfg.get_value("game", "default_speed", 1)
	auto_save_interval = cfg.get_value("game", "auto_save_interval", 5)
	max_agents = cfg.get_value("game", "max_agents", 50)
	auto_pause_on_focus_loss = cfg.get_value("game", "auto_pause_on_focus_loss", false)
	low_power_when_unfocused = cfg.get_value("game", "low_power_when_unfocused", true)
	mute_when_unfocused = cfg.get_value("game", "mute_when_unfocused", true)


func save_settings() -> void:
	var cfg := ConfigFile.new()

	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)

	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "desktop_pet_mode", desktop_pet_mode)

	cfg.set_value("llm", "backend", llm_backend)
	cfg.set_value("llm", "ollama_url", ollama_url)
	cfg.set_value("llm", "ollama_model", ollama_model)

	cfg.set_value("game", "default_speed", default_speed)
	cfg.set_value("game", "auto_save_interval", auto_save_interval)
	cfg.set_value("game", "max_agents", max_agents)
	cfg.set_value("game", "auto_pause_on_focus_loss", auto_pause_on_focus_loss)
	cfg.set_value("game", "low_power_when_unfocused", low_power_when_unfocused)
	cfg.set_value("game", "mute_when_unfocused", mute_when_unfocused)

	cfg.save(SETTINGS_PATH)
	settings_changed.emit()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	volume_changed.emit("Master", master_volume)


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	volume_changed.emit("Music", music_volume)


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	volume_changed.emit("SFX", sfx_volume)


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_game_settings() -> void:
	## Apply game settings to other autoloads. Called deferred so all singletons exist.
	# Apply default speed to TimeManager
	TimeManager.set_speed(default_speed)

	# Apply auto-save interval to SaveManager
	SaveManager.AUTO_SAVE_INTERVAL_DAYS = auto_save_interval

	# Apply max agents to Config (used by AgentManager.spawn methods)
	Config.MAX_AGENTS_EXPANDED = max_agents


func apply_audio() -> void:
	## Public entry: AudioManager calls this once its buses exist, making this
	## file the single owner of volume-to-bus logic.
	_apply_audio()


func _apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	if linear <= 0.01:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
