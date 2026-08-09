class_name HealthState
extends RefCounted
## Tracks an agent's age, health, life stage, and conditions.

var owner_name: String = ""  # set by the owning agent; not serialized
var age_days: int = 0
var life_stage: LifeStage.Type = LifeStage.Type.YOUNG
var health: float = 100.0  # 0-100
var conditions: Array[String] = []  # "flu", "exhaustion", etc.
var max_lifespan_days: int = 100  # randomized per agent
var _young_threshold: int = 20
var _adult_threshold: int = 60
var _senior_threshold: int = 80


func randomize_lifespan() -> void:
	max_lifespan_days = randi_range(80, 120)
	_young_threshold = int(max_lifespan_days * 0.2)
	_adult_threshold = int(max_lifespan_days * 0.6)
	_senior_threshold = int(max_lifespan_days * 0.8)


func advance_day() -> void:
	if life_stage == LifeStage.Type.DEAD:
		return
	age_days += 1
	_update_life_stage()
	_apply_aging_decay()
	_process_conditions()


func add_condition(condition: String) -> void:
	if condition not in conditions:
		conditions.append(condition)


func remove_condition(condition: String) -> void:
	conditions.erase(condition)


func _update_life_stage() -> void:
	var old_stage := life_stage
	if health <= 0.0:
		life_stage = LifeStage.Type.DEAD
	elif age_days >= _senior_threshold:
		if health < 20.0:
			life_stage = LifeStage.Type.DYING
		else:
			life_stage = LifeStage.Type.SENIOR
	elif age_days >= _adult_threshold:
		life_stage = LifeStage.Type.ADULT
	else:
		life_stage = LifeStage.Type.YOUNG
	if life_stage != old_stage:
		# owner_name was "" here for the signal's entire life — every listener
		# received an anonymous stage change.
		EventBus.agent_life_stage_changed.emit(owner_name, life_stage)


func _apply_aging_decay() -> void:
	match life_stage:
		LifeStage.Type.SENIOR:
			health = maxf(health - 1.5, 0.0)
		LifeStage.Type.DYING:
			health = maxf(health - 3.0, 0.0)
	# Conditions reduce health
	for condition in conditions:
		match condition:
			"flu": health = maxf(health - 2.0, 0.0)
			"exhaustion": health = maxf(health - 1.0, 0.0)
			"stress": health = maxf(health - 1.0, 0.0)


func _process_conditions() -> void:
	# Conditions can naturally resolve
	var to_remove: Array[String] = []
	for condition in conditions:
		match condition:
			"flu":
				if randf() < 0.3:  # 30% chance to recover each day
					to_remove.append(condition)
			"exhaustion":
				if randf() < 0.5:
					to_remove.append(condition)
			"stress":
				if randf() < 0.4:
					to_remove.append(condition)
	for c in to_remove:
		conditions.erase(c)


func to_dict() -> Dictionary:
	return {
		"age_days": age_days,
		"life_stage": life_stage,
		"health": health,
		"conditions": conditions.duplicate(),
		"max_lifespan_days": max_lifespan_days,
		"_young_threshold": _young_threshold,
		"_adult_threshold": _adult_threshold,
		"_senior_threshold": _senior_threshold,
	}


static func from_dict(data: Dictionary) -> HealthState:
	var hs := HealthState.new()
	hs.age_days = data.get("age_days", 0)
	hs.life_stage = data.get("life_stage", LifeStage.Type.YOUNG)
	hs.health = data.get("health", 100.0)
	var raw_cond: Array = data.get("conditions", [])
	for c in raw_cond:
		hs.conditions.append(str(c))
	hs.max_lifespan_days = data.get("max_lifespan_days", 100)
	# Restore saved thresholds if present; otherwise recalculate from max_lifespan_days
	if data.has("_young_threshold") and data.has("_adult_threshold") and data.has("_senior_threshold"):
		hs._young_threshold = data["_young_threshold"]
		hs._adult_threshold = data["_adult_threshold"]
		hs._senior_threshold = data["_senior_threshold"]
	else:
		# Backward compat: derive thresholds deterministically from saved max_lifespan_days
		hs._young_threshold = int(hs.max_lifespan_days * 0.2)
		hs._adult_threshold = int(hs.max_lifespan_days * 0.6)
		hs._senior_threshold = int(hs.max_lifespan_days * 0.8)
	return hs
