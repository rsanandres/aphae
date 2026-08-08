extends Node
## Audio singleton: music crossfade, spatial SFX pool, volume control.
## Uses 3 audio buses: Music, SFX, Ambient.
## Falls back to procedural audio when WAV/OGG files are missing.

const CROSSFADE_DURATION := 2.0
const SFX_POOL_SIZE := 8

# Per-sound throttling: min seconds between plays and max simultaneous
# voices. Anything not listed plays unthrottled — add entries as sounds
# prove noisy, not preemptively.
const SFX_RULES := {
	"conversation_start": {"min_interval": 2.0, "max_concurrent": 2},
	"coffee_pour": {"min_interval": 4.0, "max_concurrent": 1},
	"typing": {"min_interval": 4.0, "max_concurrent": 1},
	"book_flip": {"min_interval": 4.0, "max_concurrent": 1},
	"select": {"min_interval": 0.15, "max_concurrent": 2},
	"speed_change": {"min_interval": 0.25, "max_concurrent": 1},
	"group_formed": {"min_interval": 2.0, "max_concurrent": 1},
	"achievement": {"min_interval": 1.0, "max_concurrent": 1},
	"death_sad": {"min_interval": 1.0, "max_concurrent": 1},
	"romance_chime": {"min_interval": 1.0, "max_concurrent": 1},
	"heartbreak": {"min_interval": 1.0, "max_concurrent": 1},
	"ui_click": {"min_interval": 0.05, "max_concurrent": 2},
}

# Music state switching on drama, with hysteresis so it doesn't flap.
const DRAMA_BUSY_THRESHOLD := 4.0
const DRAMA_CALM_THRESHOLD := 2.0
const DRAMA_SUSTAIN_SECONDS := 10.0

# Music tracks (loaded on demand, procedural fallback)
var _music_paths := {
	"calm": "res://assets/audio/music/office_calm.ogg",
	"busy": "res://assets/audio/music/office_busy.ogg",
	"menu": "res://assets/audio/music/menu_theme.ogg",
}

# SFX paths (file-based, with procedural fallback)
var _sfx_paths := {
	"footstep_1": "res://assets/audio/sfx/footstep_1.wav",
	"footstep_2": "res://assets/audio/sfx/footstep_2.wav",
	"ui_click": "res://assets/audio/sfx/ui_click.wav",
	"notification": "res://assets/audio/sfx/notification.wav",
	"conversation_start": "res://assets/audio/sfx/conversation_start.wav",
	"conversation_murmur": "res://assets/audio/sfx/conversation_murmur.wav",
	"conversation_end": "res://assets/audio/sfx/conversation_end.wav",
	"coffee_pour": "res://assets/audio/sfx/coffee_pour.wav",
	"typing": "res://assets/audio/sfx/typing.wav",
	"book_flip": "res://assets/audio/sfx/book_flip.wav",
	"death_sad": "res://assets/audio/sfx/death_sad.wav",
	"romance_chime": "res://assets/audio/sfx/romance_chime.wav",
	"group_formed": "res://assets/audio/sfx/group_formed.wav",
	"achievement": "res://assets/audio/sfx/achievement.wav",
	"heartbreak": "res://assets/audio/sfx/heartbreak.wav",
	"select": "res://assets/audio/sfx/select.wav",
	"pause": "res://assets/audio/sfx/pause.wav",
	"unpause": "res://assets/audio/sfx/unpause.wav",
	"speed_change": "res://assets/audio/sfx/speed_change.wav",
}

var _music_player_a: AudioStreamPlayer = null
var _music_player_b: AudioStreamPlayer = null
var _active_music_player: AudioStreamPlayer = null
var _current_track: String = ""
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_idx: int = 0
var _sfx_cache: Dictionary = {}  # name -> AudioStream
var _music_cache: Dictionary = {}
var _procedural_sfx: Dictionary = {}  # name -> AudioStreamWAV
var _procedural_music: Dictionary = {}  # name -> AudioStreamWAV
var _last_played: Dictionary = {}  # sfx name -> msec of last play
var _last_speed_index: int = 1
var _ambient_player: AudioStreamPlayer = null
var _active_conversations: int = 0
var _drama_timer: float = 0.0
var _drama_sustain: float = 0.0
var _duck_tween: Tween = null


func _ready() -> void:
	_setup_buses()
	SettingsManager.apply_audio()
	_setup_music_players()
	_setup_sfx_pool()
	_setup_ambient_player()
	_generate_procedural_fallbacks()
	_connect_signals()


func _process(delta: float) -> void:
	# Music follows the drama level: busy above 4 (sustained), calm below 2.
	_drama_timer += delta
	if _drama_timer < 2.0:
		return
	_drama_timer = 0.0
	if _current_track != "calm" and _current_track != "busy":
		return  # menu / silence: not ours to change
	var level: float = DramaDirector.drama_level
	if _current_track == "calm" and level >= DRAMA_BUSY_THRESHOLD:
		_drama_sustain += 2.0
		if _drama_sustain >= DRAMA_SUSTAIN_SECONDS:
			_drama_sustain = 0.0
			play_music("busy")
	elif _current_track == "busy" and level < DRAMA_CALM_THRESHOLD:
		_drama_sustain += 2.0
		if _drama_sustain >= DRAMA_SUSTAIN_SECONDS:
			_drama_sustain = 0.0
			play_music("calm")
	else:
		_drama_sustain = 0.0


func play_music(track_name: String, fade: bool = true) -> void:
	if track_name == _current_track:
		return

	var stream: AudioStream = _get_music_stream(track_name)
	if not stream:
		return

	_current_track = track_name

	if fade and _active_music_player and _active_music_player.playing:
		# Crossfade
		var old_player := _active_music_player
		var new_player := _music_player_b if _active_music_player == _music_player_a else _music_player_a
		_active_music_player = new_player
		new_player.stream = stream
		new_player.volume_db = -40.0
		new_player.play()

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(old_player, "volume_db", -40.0, CROSSFADE_DURATION)
		tween.tween_property(new_player, "volume_db", 0.0, CROSSFADE_DURATION)
		tween.set_parallel(false)
		tween.tween_callback(func() -> void: old_player.stop())
	else:
		_active_music_player.stream = stream
		_active_music_player.volume_db = 0.0
		_active_music_player.play()


func stop_music(fade: bool = true) -> void:
	_current_track = ""
	if not _active_music_player or not _active_music_player.playing:
		return
	if fade:
		var tween := create_tween()
		var player := _active_music_player
		tween.tween_property(player, "volume_db", -40.0, CROSSFADE_DURATION)
		tween.tween_callback(func() -> void: player.stop())
	else:
		_active_music_player.stop()


func play_sfx(sfx_name: String, volume_db: float = 0.0) -> void:
	var rules: Dictionary = SFX_RULES.get(sfx_name, {})
	if not rules.is_empty():
		var now := Time.get_ticks_msec()
		var min_interval: float = rules.get("min_interval", 0.0)
		if now - int(_last_played.get(sfx_name, -100000)) < int(min_interval * 1000.0):
			return
		var max_concurrent: int = rules.get("max_concurrent", SFX_POOL_SIZE)
		var active := 0
		for p in _sfx_pool:
			if p.playing and p.get_meta("sfx_name", "") == sfx_name:
				active += 1
		if active >= max_concurrent:
			return
		_last_played[sfx_name] = now
	var stream: AudioStream = _get_sfx_stream(sfx_name)
	if not stream:
		return
	var player := _sfx_pool[_sfx_pool_idx]
	player.stream = stream
	player.volume_db = volume_db
	player.set_meta("sfx_name", sfx_name)
	player.play()
	_sfx_pool_idx = (_sfx_pool_idx + 1) % SFX_POOL_SIZE


func _get_sfx_stream(sfx_name: String) -> AudioStream:
	# Check cache first
	if _sfx_cache.has(sfx_name):
		return _sfx_cache[sfx_name]
	# Try file-based
	var path: String = _sfx_paths.get(sfx_name, "")
	if path != "" and ResourceLoader.exists(path):
		var stream := load(path) as AudioStream
		if stream:
			_sfx_cache[sfx_name] = stream
			return stream
	# Fall back to procedural
	if _procedural_sfx.has(sfx_name):
		_sfx_cache[sfx_name] = _procedural_sfx[sfx_name]
		return _procedural_sfx[sfx_name]
	return null


func _get_music_stream(track_name: String) -> AudioStream:
	if _music_cache.has(track_name):
		return _music_cache[track_name]
	var path: String = _music_paths.get(track_name, "")
	if path != "" and ResourceLoader.exists(path):
		var stream := load(path) as AudioStream
		if stream:
			_music_cache[track_name] = stream
			return stream
	# Procedural fallback
	if _procedural_music.has(track_name):
		_music_cache[track_name] = _procedural_music[track_name]
		return _procedural_music[track_name]
	return null


func _generate_procedural_fallbacks() -> void:
	_procedural_sfx = AudioGenerator.generate_all_sfx()
	# Three genuinely different loops — "calm" doubling as busy and menu meant
	# the same 8-second drone played forever regardless of game state.
	_procedural_music["calm"] = AudioGenerator.generate_music_track("calm")
	_procedural_music["busy"] = AudioGenerator.generate_music_track("busy")
	_procedural_music["menu"] = AudioGenerator.generate_music_track("menu")


func _setup_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
		AudioServer.set_bus_send(AudioServer.get_bus_index("Music"), "Master")
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_send(AudioServer.get_bus_index("SFX"), "Master")
	if AudioServer.get_bus_index("Ambient") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Ambient")
		AudioServer.set_bus_send(AudioServer.get_bus_index("Ambient"), "Master")


func _setup_music_players() -> void:
	_music_player_a = AudioStreamPlayer.new()
	_music_player_a.bus = "Music"
	add_child(_music_player_a)

	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.bus = "Music"
	add_child(_music_player_b)

	_active_music_player = _music_player_a


func _setup_sfx_pool() -> void:
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_sfx_pool.append(player)


func _setup_ambient_player() -> void:
	# The Ambient bus existed from day one but nothing ever played on it.
	# It now carries the conversation murmur — the one sound designed to
	# say "people are talking" — looping softly while conversations run.
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "Ambient"
	_ambient_player.volume_db = -18.0
	add_child(_ambient_player)


func _update_murmur() -> void:
	if _active_conversations > 0 and not _ambient_player.playing:
		var stream: AudioStream = _get_sfx_stream("conversation_murmur")
		if stream is AudioStreamWAV:
			var looped: AudioStreamWAV = stream.duplicate()
			looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
			looped.loop_begin = 0
			looped.loop_end = looped.data.size() / 2
			_ambient_player.stream = looped
			_ambient_player.volume_db = -40.0
			_ambient_player.play()
			create_tween().tween_property(_ambient_player, "volume_db", -18.0, 0.8)
	elif _active_conversations <= 0 and _ambient_player.playing:
		var tween := create_tween()
		tween.tween_property(_ambient_player, "volume_db", -40.0, 0.8)
		tween.tween_callback(func() -> void:
			if _active_conversations <= 0:
				_ambient_player.stop()
		)


func _connect_signals() -> void:
	EventBus.conversation_started.connect(func(_a: String, _b: String) -> void:
		_active_conversations += 1
		play_sfx("conversation_start", -8.0)
		_update_murmur()
	)
	# No end sting: the start cue plus the murmur fading out says it already.
	EventBus.conversation_ended.connect(func(_a: String, _b: String) -> void:
		_active_conversations = maxi(0, _active_conversations - 1)
		_update_murmur()
	)
	EventBus.agent_died.connect(func(_name: String, _cause: String) -> void:
		play_sfx("death_sad", -6.0)
	)
	EventBus.confession_made.connect(func(_a: String, _b: String, accepted: bool) -> void:
		if accepted:
			play_sfx("romance_chime", -6.0)
		else:
			play_sfx("heartbreak", -6.0)
	)
	EventBus.group_formed.connect(func(_g: RefCounted) -> void:
		# The 60s analyze pass can report several new groups in one frame;
		# the cooldown in SFX_RULES collapses the stack to a single arpeggio.
		play_sfx("group_formed", -8.0)
	)
	EventBus.object_occupied.connect(func(obj: Node2D, _agent: Node2D) -> void:
		var obj_type: String = obj.get("object_type") if obj.get("object_type") else ""
		match obj_type:
			"coffee_machine": play_sfx("coffee_pour", -10.0)
			"desk": play_sfx("typing", -12.0)
			"bookshelf": play_sfx("book_flip", -10.0)
	)
	EventBus.agent_selected.connect(func(_agent: Node2D) -> void:
		play_sfx("select", -10.0)
	)
	EventBus.time_paused.connect(func() -> void:
		play_sfx("pause", -8.0)
	)
	EventBus.time_resumed.connect(func() -> void:
		play_sfx("unpause", -8.0)
	)
	EventBus.time_speed_changed.connect(func(speed: int) -> void:
		# set_speed() also fires pause/resume signals on the same call; only
		# play the tick for speed-to-speed changes so pausing isn't a chord.
		if _last_speed_index > 0 and speed > 0:
			play_sfx("speed_change", -10.0)
		_last_speed_index = speed
	)
	EventBus.achievement_unlocked.connect(func(_id: String, _name: String) -> void:
		play_sfx("achievement", -6.0)
	)
	EventBus.confessional_recorded.connect(func(_c: RefCounted) -> void:
		_duck_music()
	)
	EventBus.game_ready.connect(func() -> void:
		play_music("calm")
	)


func _duck_music() -> void:
	## Dip the music -6dB while a confessional cutaway is on screen.
	if not _active_music_player or not _active_music_player.playing:
		return
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(_active_music_player, "volume_db", -6.0, 0.3)
	_duck_tween.tween_interval(5.5)
	_duck_tween.tween_property(_active_music_player, "volume_db", 0.0, 0.8)
