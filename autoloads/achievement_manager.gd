extends Node
## Tracks, persists, and emits achievement events. Subscribes to EventBus signals.

const ACHIEVEMENTS_PATH := "user://achievements.json"

var _definitions: Dictionary = {}  # id -> {name, description, category}
var _unlocked: Dictionary = {}  # id -> true
var _objects_placed: int = 0
var _conversations_today: Dictionary = {}  # agent_name -> Array[String] of partners today
var _confessionals_recorded: int = 0
var _confessional_speakers: Dictionary = {}  # agent_name -> true, this session only


func _ready() -> void:
	_load_definitions()
	_load_progress()
	_connect_signals()


func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.has(achievement_id)


func get_all() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in _definitions:
		var def: Dictionary = _definitions[id]
		result.append({
			"id": id,
			"name": def.get("name", id),
			"description": def.get("description", ""),
			"category": def.get("category", ""),
			"unlocked": _unlocked.has(id),
		})
	return result


func get_unlocked_count() -> int:
	return _unlocked.size()


func get_total_count() -> int:
	return _definitions.size()


func unlock(achievement_id: String) -> void:
	if _unlocked.has(achievement_id):
		return
	if not _definitions.has(achievement_id):
		return
	_unlocked[achievement_id] = true
	var def: Dictionary = _definitions[achievement_id]
	var achievement_name: String = def.get("name", achievement_id)
	print("[Achievement] Unlocked: %s" % achievement_name)
	# AudioManager listens for achievement_unlocked; playing here as well
	# stacked the sting twice on the same frame.
	EventBus.achievement_unlocked.emit(achievement_id, achievement_name)
	_save_progress()

	# Steam sync
	if has_node("/root/SteamManager") and get_node("/root/SteamManager").has_method("set_achievement"):
		get_node("/root/SteamManager").set_achievement(achievement_id)


func _load_definitions() -> void:
	var file := FileAccess.open("res://resources/achievements.json", FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	var achievements: Array = data.get("achievements", [])
	for a in achievements:
		var id: String = a.get("id", "")
		if id != "":
			_definitions[id] = a


func _load_progress() -> void:
	var file := FileAccess.open(ACHIEVEMENTS_PATH, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	var unlocked_list: Array = data.get("unlocked", [])
	for id in unlocked_list:
		_unlocked[str(id)] = true
	_objects_placed = data.get("objects_placed", 0)
	_confessionals_recorded = data.get("confessionals_recorded", 0)


func _save_progress() -> void:
	var unlocked_list: Array = []
	for id in _unlocked:
		unlocked_list.append(id)
	var data := {
		"unlocked": unlocked_list,
		"objects_placed": _objects_placed,
		"confessionals_recorded": _confessionals_recorded,
	}
	var file := FileAccess.open(ACHIEVEMENTS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func _connect_signals() -> void:
	EventBus.episode_ended.connect(func(_s: int, ep: int, score: int, _p: int) -> void:
		unlock("thats_a_wrap")
		if score >= 60:
			unlock("ratings_gold")
		if ep >= ProducerEconomy.EPISODES_PER_SEASON:
			unlock("season_finale")
	)
	EventBus.catalog_purchased.connect(func(item_id: String) -> void:
		unlock("retail_therapy")
		if FileAccess.file_exists("res://scenes/objects/%s.gd" % item_id):
			unlock("patron_of_the_arts")
	)
	EventBus.game_ready.connect(func() -> void:
		unlock("new_beginnings")
	)

	EventBus.goal_achieved.connect(func(agent_name: String, _text: String, _kind: int) -> void:
		unlock("goal_getter")
		if GoalManager.achieved_total >= 3:
			unlock("driven")
		# Every goal they arrived with, landed. Checked here rather than on a
		# counter because agents differ in how many goals they carry.
		var goals: Array[GoalState] = GoalManager.get_goals(agent_name)
		if not goals.is_empty():
			var all_done := true
			for goal: GoalState in goals:
				if goal.status != GoalState.Status.ACHIEVED:
					all_done = false
					break
			if all_done:
				unlock("self_actualized")
	)

	EventBus.goal_failed.connect(func(_agent_name: String, _text: String, _kind: int) -> void:
		unlock("unfinished_business")
	)

	EventBus.secret_admitted.connect(func(_holder: String, _text: String) -> void:
		unlock("true_confessions")
	)
	EventBus.rumor_passed.connect(func(_listener: String, _speaker: String, mem_thread: String) -> void:
		if mem_thread.begins_with("secret_"):
			unlock("loose_lips")
	)
	EventBus.secret_exposed.connect(func(_holder: String, _text: String) -> void:
		unlock("cover_blown")
	)

	EventBus.conversation_started.connect(func(a: String, b: String) -> void:
		unlock("small_talk")
		# Track conversations per agent per day
		if not _conversations_today.has(a):
			_conversations_today[a] = []
		if b not in _conversations_today[a]:
			_conversations_today[a].append(b)
		if _conversations_today[a].size() >= 3:
			unlock("social_butterfly")
		if not _conversations_today.has(b):
			_conversations_today[b] = []
		if a not in _conversations_today[b]:
			_conversations_today[b].append(a)
		if _conversations_today[b].size() >= 3:
			unlock("social_butterfly")
	)

	EventBus.day_changed.connect(func(day: int) -> void:
		_conversations_today.clear()
		if day >= 1:
			unlock("office_regular")
		if day >= 7:
			unlock("one_week")
		if day >= 50:
			unlock("long_haul")
		if day >= 100:
			unlock("century")
	)

	EventBus.object_occupied.connect(func(obj: Node2D, _agent: Node2D) -> void:
		var obj_type: String = obj.get("object_type") if obj.get("object_type") else ""
		if obj_type == "coffee_machine":
			unlock("caffeine_fix")
	)

	EventBus.relationship_changed.connect(func(_a: String, _b: String, rel: RefCounted) -> void:
		if not (rel is RelationshipEntry):
			return
		var entry: RelationshipEntry = rel as RelationshipEntry
		if entry.affinity >= 80.0:
			unlock("best_friends")
		elif entry.affinity <= -50.0:
			unlock("enemies")
		# Check for love triangle: 3+ agents each with romantic_interest > 40 toward another in the set
		if entry.romantic_interest > 40.0 and not is_unlocked("love_triangle"):
			_check_love_triangle()
	)

	EventBus.confession_made.connect(func(_a: String, _b: String, accepted: bool) -> void:
		if accepted:
			unlock("office_romance")
		else:
			unlock("heartbreak")
	)

	EventBus.group_formed.connect(func(_g: RefCounted) -> void:
		unlock("inner_circle")
	)

	EventBus.group_rivalry_detected.connect(func(_a: RefCounted, _b: RefCounted) -> void:
		unlock("office_politics")
	)

	EventBus.agent_died.connect(func(_name: String, cause: String) -> void:
		if cause == "old age":
			unlock("rest_in_peace")
	)

	EventBus.object_placed.connect(func(_obj: Node2D, _pos: Vector2) -> void:
		_objects_placed += 1
		if _objects_placed >= 5:
			unlock("the_architect")
		else:
			_save_progress()  # Persist counter even before achievement unlocks
	)

	EventBus.storyline_updated.connect(func(sl: RefCounted) -> void:
		var score = sl.get("drama_score") if sl.has_method("get") else null
		if score != null and float(score) >= 8.0:
			unlock("drama_queen")
	)

	EventBus.confessional_recorded.connect(func(c: RefCounted) -> void:
		var conf: Confessional = c as Confessional
		if not conf:
			return
		unlock("caught_on_camera")

		_confessionals_recorded += 1
		if _confessionals_recorded >= 25:
			unlock("press_tour")
		elif not is_unlocked("press_tour"):
			_save_progress()  # persist the counter between unlocks

		if conf.is_host:
			if DramaDirector.drama_level >= 7.0:
				unlock("sweeps_week")
			return

		if conf.speaker != "":
			_confessional_speakers[conf.speaker] = true
			_check_ensemble_cast()
	)

	# Agent count checks (deferred to not fire on initial load)
	EventBus.agent_spawned.connect(func(_agent: Node2D) -> void:
		call_deferred("_check_agent_count")
	)


func _check_ensemble_cast() -> void:
	## Unlocks once every living agent has faced the camera. Speakers are tracked
	## per session, not persisted: the roster changes as agents are born and die,
	## so a name carried over from a previous run would unlock this falsely.
	var living: Array[String] = []
	for agent in AgentManager.agents:
		if is_instance_valid(agent) and not agent.is_dead:
			living.append(agent.agent_name)
	if living.size() < 3:
		return  # a duo is not an ensemble
	for agent_name in living:
		if not _confessional_speakers.has(agent_name):
			return
	unlock("ensemble_cast")


func _check_agent_count() -> void:
	var count := AgentManager.agents.size()
	if count >= 20:
		unlock("full_house")
	if count >= 50:
		unlock("metropolis")


func _check_love_triangle() -> void:
	# Find agents who have romantic_interest > 40 toward at least one other agent
	# Build a set of agents with outgoing romantic interest > 40
	var romantic_agents: Dictionary = {}  # agent_name -> Array of target names
	for agent in AgentManager.agents:
		if not agent.has_node("AgentRelationships"):
			continue
		var rels: Dictionary = agent.get_node("AgentRelationships").get_all_relationships()
		var targets: Array[String] = []
		for target_name in rels:
			var rel: RelationshipEntry = rels[target_name]
			if rel.romantic_interest > 40.0:
				targets.append(target_name)
		if not targets.is_empty():
			romantic_agents[agent.agent_name] = targets
	# Check if there exist 3 agents in the romantic set where each has romantic interest
	# toward at least one other in the set of 3
	var names: Array = romantic_agents.keys()
	if names.size() < 3:
		return
	# For small populations, brute force check all triples
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			for k in range(j + 1, names.size()):
				var a: String = names[i]
				var b: String = names[j]
				var c: String = names[k]
				var trio: Array[String] = [a, b, c]
				# Each must have romantic interest toward at least one other in the trio
				var all_connected := true
				for member in trio:
					var has_link := false
					var member_targets: Array = romantic_agents[member]
					for other in trio:
						if other != member and other in member_targets:
							has_link = true
							break
					if not has_link:
						all_connected = false
						break
				if all_connected:
					unlock("love_triangle")
					return
