extends Node
## Autoload: multi-slot save system with backup and corruption recovery.
## V3: 5 save slots, .bak backup, corruption recovery.
## V4: confessionals persisted alongside storylines.

const SAVE_DIR := "user://saves/"
var AUTO_SAVE_INTERVAL_DAYS: int = 5
const SAVE_VERSION := 7
const MAX_SLOTS := 5
const LEGACY_PATH := "user://ayle_save.json"
const LAST_SLOT_PATH := "user://last_slot.cfg"

var _last_auto_save_day: int = 0
var current_slot: int = 0  # Active save slot
var last_used_slot: int = 0  # Most recently used slot (persisted)
var skip_auto_load: bool = false  # Set by main menu for "New Sandbox"


func _ready() -> void:
	EventBus.day_changed.connect(_on_day_changed)
	_ensure_save_dir()
	_migrate_legacy_save()
	_load_last_used_slot()


func save_game(slot: int = -1) -> bool:
	if slot < 0:
		slot = current_slot
	_ensure_save_dir()
	var path := _slot_path(slot)

	# Backup existing save before writing
	if FileAccess.file_exists(path):
		var bak_path := path + ".bak"
		var existing := FileAccess.open(path, FileAccess.READ)
		if existing:
			var content := existing.get_as_text()
			existing.close()
			var bak := FileAccess.open(bak_path, FileAccess.WRITE)
			if bak:
				bak.store_string(content)
				bak.close()

	var data := _serialize_world()
	data["slot"] = slot
	data["save_time"] = Time.get_datetime_string_from_system()
	var json_str := JSON.stringify(data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: Failed to open save file for writing: %s" % path)
		EventBus.narrative_event.emit("Save failed!", [], 1.0)
		return false
	file.store_string(json_str)
	file.close()
	current_slot = slot
	last_used_slot = slot
	_save_last_used_slot()
	print("[SaveManager] Game saved to slot %d (v%d)" % [slot, SAVE_VERSION])
	EventBus.narrative_event.emit("Game saved (slot %d)." % (slot + 1), [], 1.0)
	return true


func load_game(slot: int = -1) -> bool:
	if slot < 0:
		slot = current_slot
	var path := _slot_path(slot)
	var data := _try_load_file(path)

	# Try backup if main file fails
	if data.is_empty():
		var bak_path := path + ".bak"
		data = _try_load_file(bak_path)
		if not data.is_empty():
			push_warning("SaveManager: Loaded from backup for slot %d" % slot)
			EventBus.narrative_event.emit("Loaded from backup save.", [], 3.0)

	if data.is_empty():
		push_warning("SaveManager: No valid save for slot %d" % slot)
		return false

	_deserialize_world(data)
	current_slot = slot
	last_used_slot = slot
	_save_last_used_slot()
	var version: int = data.get("version", 1)
	print("[SaveManager] Game loaded from slot %d (v%d)" % [slot, version])
	EventBus.narrative_event.emit("Game loaded (slot %d)." % (slot + 1), [], 1.0)
	return true


func has_save(slot: int = -1) -> bool:
	if slot < 0:
		# Check any slot
		for i in range(MAX_SLOTS):
			if FileAccess.file_exists(_slot_path(i)):
				return true
		return false
	return FileAccess.file_exists(_slot_path(slot))


func get_slot_info(slot: int) -> Dictionary:
	## Returns {exists, save_time, day, agent_count} or empty dict
	var path := _slot_path(slot)
	var data := _try_load_file(path)
	if data.is_empty():
		return {"exists": false}
	return {
		"exists": true,
		"save_time": data.get("save_time", "unknown"),
		"day": int(data.get("game_time", 480.0) / 1440.0),
		"agent_count": (data.get("agents", []) as Array).size(),
		"version": data.get("version", 1),
	}


func delete_save(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var bak_path := path + ".bak"
	if FileAccess.file_exists(bak_path):
		DirAccess.remove_absolute(bak_path)


func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _migrate_legacy_save() -> void:
	# Move old single-file save to slot 0 if it exists
	if FileAccess.file_exists(LEGACY_PATH) and not FileAccess.file_exists(_slot_path(0)):
		var old_file := FileAccess.open(LEGACY_PATH, FileAccess.READ)
		if old_file:
			var content := old_file.get_as_text()
			old_file.close()
			_ensure_save_dir()
			var new_file := FileAccess.open(_slot_path(0), FileAccess.WRITE)
			if new_file:
				new_file.store_string(content)
				new_file.close()
				print("[SaveManager] Migrated legacy save to slot 0")


func _try_load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("SaveManager: JSON parse error in %s" % path)
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


func _on_day_changed(day: int) -> void:
	if day - _last_auto_save_day >= AUTO_SAVE_INTERVAL_DAYS:
		_last_auto_save_day = day
		save_game()


func _serialize_world() -> Dictionary:
	var data := {
		"version": SAVE_VERSION,
		"game_time": TimeManager.game_minutes,
		"speed_index": TimeManager.speed_index,
		"agents": [],
		"objects": [],
		"narrative_log": [],
		"groups": [],
		"storylines": [],
		"story_feed": [],
		"confessionals": [],
		"event_state": EventManager.get_save_state(),
		"drama_state": DramaDirector.get_save_state(),
		"arcs": ArcManager.get_save_state(),
		"goals": GoalManager.get_save_state(),
		"secrets": SecretManager.get_save_state(),
		"departed_agents": AgentManager.departed_agents.duplicate(true),
		"producer": ProducerEconomy.get_save_state(),
	}

	for agent in AgentManager.agents:
		var agent_data := {
			"name": agent.agent_name,
			"personality_file": agent.personality_file,
			"position": {"x": agent.position.x, "y": agent.position.y},
			"needs": {},
			"relationships": {},
			"memories": [],
			"health": null,
		}

		# Persist personality for every agent, not just procedural ones:
		# events can permanently shift traits, and file-based agents would
		# silently revert to their JSON profile on load otherwise.
		if agent.personality:
			agent_data["personality_data"] = agent.personality.to_dict()

		agent_data["behavior_modifiers"] = agent.get_modifiers_data()

		var needs_values: Dictionary = agent.needs.get_all_values()
		for need in needs_values:
			agent_data["needs"][NeedType.to_string_name(need)] = needs_values[need]

		if agent.relationships:
			var rels: Dictionary = agent.relationships.get_all_relationships()
			for other_name in rels:
				var rel: RelationshipEntry = rels[other_name]
				agent_data["relationships"][other_name] = rel.to_dict()

		var recent_mems: Array[MemoryEntry] = agent.memory.get_recent(50)
		for mem in recent_mems:
			agent_data["memories"].append(mem.to_dict())

		if agent.health_state:
			agent_data["health"] = agent.health_state.to_dict()

		data["agents"].append(agent_data)

	data["last_auto_save_day"] = _last_auto_save_day

	var world := get_tree().get_first_node_in_group("world")
	if world:
		for obj in world.get_all_objects():
			var obj_data := {
				"type": obj.object_type,
				"display_name": obj.display_name,
				"position": {"x": obj.position.x, "y": obj.position.y},
			}
			# Serialize object-specific state
			if obj.object_type == "radio":
				obj_data["playing"] = obj._playing
			data["objects"].append(obj_data)

	for group in GroupManager.groups:
		data["groups"].append(group.to_dict())

	for sl in Narrator.storylines:
		data["storylines"].append(sl.to_dict())

	for entry in Narrator.feed:
		data["story_feed"].append(entry.to_dict())

	for c in ConfessionalDirector.confessionals:
		data["confessionals"].append(c.to_dict())

	return data


func _deserialize_world(data: Dictionary) -> void:
	var version: int = data.get("version", 1)

	TimeManager.game_minutes = data.get("game_time", 480.0)
	TimeManager.set_speed(data.get("speed_index", 1))

	var agent_datas: Array = data.get("agents", [])
	var restored_names: Array[String] = []

	for agent_data in agent_datas:
		if not agent_data is Dictionary:
			continue  # corrupt entry; skip rather than abort the whole load
		var agent_name: String = agent_data.get("name", "")
		var personality_file: String = agent_data.get("personality_file", "")
		var agent := AgentManager.get_agent_by_name(agent_name)

		if not agent and personality_file == "__procedural__":
			var personality_data: Dictionary = agent_data.get("personality_data", {})
			if not personality_data.is_empty():
				var pos_data: Dictionary = agent_data.get("position", {})
				var pos := Vector2(pos_data.get("x", 100.0), pos_data.get("y", 100.0))
				agent = AgentManager.spawn_procedural_agent(pos, personality_data)

		if not agent:
			continue

		restored_names.append(agent_name)

		var needs_data: Dictionary = agent_data.get("needs", {})
		for need_key in needs_data:
			var need_type: NeedType.Type
			match need_key:
				"energy": need_type = NeedType.Type.ENERGY
				"hunger": need_type = NeedType.Type.HUNGER
				"social": need_type = NeedType.Type.SOCIAL
				"productivity": need_type = NeedType.Type.PRODUCTIVITY
				"health": need_type = NeedType.Type.HEALTH
				_: continue
			agent.needs.set_value(need_type, float(needs_data[need_key]))

		var pos_data: Dictionary = agent_data.get("position", {})
		agent.position = Vector2(pos_data.get("x", agent.position.x), pos_data.get("y", agent.position.y))

		var rels_data: Dictionary = agent_data.get("relationships", {})
		for other_name in rels_data:
			var rel_dict: Dictionary = rels_data[other_name]
			var rel := RelationshipEntry.from_dict(rel_dict)
			agent.relationships._relationships[other_name] = rel

		var mems_data: Array = agent_data.get("memories", [])
		agent.memory.memories.clear()
		for mem_dict in mems_data:
			var mem := MemoryEntry.from_dict(mem_dict)
			agent.memory.memories.append(mem)

		var health_data = agent_data.get("health", null)
		if health_data is Dictionary:
			agent.health_state = HealthState.from_dict(health_data)
			agent.health_state.owner_name = agent.agent_name

		# Personality overlay (v5+, outside the gate — absent key is a no-op).
		# File-based agents load their JSON profile first; saved trait shifts
		# are applied on top so lasting marks actually last.
		var personality_data: Dictionary = agent_data.get("personality_data", {})
		if not personality_data.is_empty() and personality_file != "__procedural__" and agent.personality:
			var saved_profile := PersonalityProfile.from_dict(personality_data)
			if saved_profile:
				agent.personality = saved_profile
				agent.smart_brain.personality = saved_profile
				agent._refresh_decay_rates()

		agent.load_modifiers_data(agent_data.get("behavior_modifiers", []))

	if version >= 2:
		var groups_data: Array = data.get("groups", [])
		GroupManager.groups.clear()
		for gd in groups_data:
			var group := SocialGroup.from_dict(gd)
			GroupManager.groups.append(group)

		var storylines_data: Array = data.get("storylines", [])
		Narrator.storylines.clear()
		for sld in storylines_data:
			var sl := Storyline.from_dict(sld)
			Narrator.storylines.append(sl)

		var feed_data: Array = data.get("story_feed", [])
		Narrator.feed.clear()
		for fd in feed_data:
			var entry := StoryEntry.from_dict(fd)
			Narrator.feed.append(entry)

	# Confessionals (v4+). Deliberately outside the version gate: an absent key
	# restores as empty, so pre-v4 saves stay valid instead of failing to load.
	var confessionals_data: Array = data.get("confessionals", [])
	ConfessionalDirector.confessionals.clear()
	for cd in confessionals_data:
		if cd is Dictionary:
			ConfessionalDirector.confessionals.append(Confessional.from_dict(cd))
	# Drop oldest if a save predates a lower cap.
	while ConfessionalDirector.confessionals.size() > ConfessionalDirector.MAX_CONFESSIONALS:
		ConfessionalDirector.confessionals.pop_front()

	# Event cooldowns / in-flight timed events / drama pacing (v5+, outside
	# the gate — absent keys restore as empty defaults).
	EventManager.load_save_state(data.get("event_state", {}))
	DramaDirector.load_save_state(data.get("drama_state", {}))
	ArcManager.load_save_state(data.get("arcs", []))
	# Outside the version gate, like confessionals: a pre-v6 save simply has no
	# goal block, and the agents re-derive theirs from personality on spawn.
	GoalManager.load_save_state(data.get("goals", {}))
	# Same deal for v7 secrets: absent block means the roll already happened at
	# spawn, and the loaded state below simply replaces it.
	SecretManager.load_save_state(data.get("secrets", {}))
	AgentManager.departed_agents.clear()
	for entry in data.get("departed_agents", []):
		if entry is Dictionary:
			AgentManager.departed_agents.append(entry)
	ProducerEconomy.load_save_state(data.get("producer", {}))
	CatalogPanel.apply_upgrades_from_save()

	# Restore _last_auto_save_day from save data
	_last_auto_save_day = int(data.get("last_auto_save_day", 0))

	# Restore objects
	var objects_data: Array = data.get("objects", [])
	var world := get_tree().get_first_node_in_group("world")
	if world and not objects_data.is_empty():
		# Remove existing objects
		var existing_objects: Array = world.get_all_objects().duplicate()
		for obj in existing_objects:
			world.remove_object(obj)

		# Recreate objects from save data
		for obj_data in objects_data:
			if not obj_data is Dictionary:
				continue  # corrupt entry; skip rather than abort the whole load
			var obj_type: String = obj_data.get("type", "")
			if obj_type == "":
				continue
			var obj := _create_object_from_type(obj_type)
			if not obj:
				push_warning("SaveManager: Failed to create object type: %s" % obj_type)
				continue
			var pos_data: Dictionary = obj_data.get("position", {})
			var pos := Vector2(pos_data.get("x", 100.0), pos_data.get("y", 100.0))
			world.add_object(obj, pos)
			# Restore object-specific state
			if obj_type == "radio" and obj_data.has("playing"):
				var playing: bool = obj_data.get("playing", true)
				obj._playing = playing
				if playing:
					obj.passive_need_effects = {NeedType.Type.SOCIAL: 0.5}
				else:
					obj.passive_need_effects = {}

	if world and world.has_method("resize_for_agents"):
		world.resize_for_agents(AgentManager.agents.size())


func _create_object_from_type(obj_type: String) -> InteractableObject:
	return ObjectFactory.create(obj_type)


func get_most_recent_slot() -> int:
	## Returns the slot with the newest save file modification time.
	var best_slot: int = 0
	var best_time: String = ""
	for i in range(MAX_SLOTS):
		var path := _slot_path(i)
		if not FileAccess.file_exists(path):
			continue
		var data := _try_load_file(path)
		if data.is_empty():
			continue
		var save_time: String = data.get("save_time", "")
		if save_time > best_time:
			best_time = save_time
			best_slot = i
	return best_slot


func _save_last_used_slot() -> void:
	var config := ConfigFile.new()
	config.set_value("save", "last_used_slot", last_used_slot)
	config.save(LAST_SLOT_PATH)


func _load_last_used_slot() -> void:
	var config := ConfigFile.new()
	if config.load(LAST_SLOT_PATH) == OK:
		last_used_slot = config.get_value("save", "last_used_slot", 0)
		current_slot = last_used_slot


func get_load_summary(slot: int = -1) -> String:
	## Returns a "While you were away..." summary of the save state.
	if slot < 0:
		slot = current_slot
	var data := _try_load_file(_slot_path(slot))
	if data.is_empty():
		return ""

	var lines: PackedStringArray = []

	# Day count
	var game_time: float = data.get("game_time", 480.0)
	var day: int = int(game_time / 1440.0)
	lines.append("Day %d" % day)

	# Agent count
	var agents_data: Array = data.get("agents", [])
	lines.append("%d agents in the office" % agents_data.size())

	# Groups
	var groups_data: Array = data.get("groups", [])
	if not groups_data.is_empty():
		var group_names: PackedStringArray = []
		for gd in groups_data:
			var gname: String = gd.get("group_name", gd.get("name", ""))
			if gname != "":
				group_names.append(gname)
		if not group_names.is_empty():
			lines.append("Groups: %s" % ", ".join(group_names))

	# Active storylines
	var storylines_data: Array = data.get("storylines", [])
	var active_stories: int = 0
	var top_story: String = ""
	for sld in storylines_data:
		if sld.get("is_active", false):
			active_stories += 1
			if top_story == "" or sld.get("drama_score", 0.0) > 5.0:
				top_story = sld.get("title", "")
	if active_stories > 0:
		var story_text := "%d active storyline%s" % [active_stories, "s" if active_stories > 1 else ""]
		if top_story != "":
			story_text += " — \"%s\"" % top_story
		lines.append(story_text)

	# Scan for interesting relationship states
	var dating_pairs: int = 0
	for agent_data in agents_data:
		var rels: Dictionary = agent_data.get("relationships", {})
		for other_name in rels:
			var rel_data: Dictionary = rels[other_name]
			var status: int = int(rel_data.get("relationship_status", 0))
			if status == 3 or status == 4:  # DATING or PARTNERS
				dating_pairs += 1
	dating_pairs = dating_pairs / 2  # Each pair counted twice
	if dating_pairs > 0:
		lines.append("%d romantic couple%s" % [dating_pairs, "s" if dating_pairs > 1 else ""])

	# Leave off with the last thing someone said to camera.
	var saved_confessionals: Array = data.get("confessionals", [])
	if not saved_confessionals.is_empty():
		var last = saved_confessionals[saved_confessionals.size() - 1]
		if last is Dictionary:
			var who: String = last.get("speaker", "")
			var quip: String = last.get("line", "")
			if who != "" and quip != "":
				lines.append("Last confessional — %s: \"%s\"" % [who, quip])

	return "\n".join(lines)
