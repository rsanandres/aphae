extends Node2D
## Functional test harness for the producer meta-game (dev tool).
##
## Covers: episode rollover under manual day jumps (both directions), score
## formula bounds, spend/afford/refuse, catalog unlock gating against
## injected meta, per-save round-trip, the object factory for every type,
## and the meta-persistence kill-switch.
##
## Run: godot --headless --path . --audio-driver Dummy res://scenes/main/economy_test.tscn

var _results: Array[String] = []


func _ready() -> void:
	ProducerEconomy.meta_persistence_enabled = false
	# M7 seams off: the spawn-roll must not plant secret memories under the
	# assertions, and the day-roll must not inject booth admissions mid-test.
	GoalManager.auto_enabled = false
	WhodunitDirector.auto_enabled = false
	ImpactLog.auto_enabled = false
	SecretManager.auto_assign_enabled = false
	SecretManager.auto_admit_enabled = false
	TimeManager.is_paused = true
	SaveManager._last_auto_save_day = 999999
	for definition in EventManager.get_available_events():
		definition.probability = 0.0
	_build_world()
	await get_tree().create_timer(0.5).timeout
	await _run()
	_report()
	get_tree().quit()


func _build_world() -> void:
	var world := Node2D.new()
	world.add_to_group("world")
	world.set_script(load("res://scenes/world/office.gd"))
	var objects_node := Node2D.new()
	objects_node.name = "Objects"
	world.add_child(objects_node)
	var agents_node := Node2D.new()
	agents_node.name = "Agents"
	world.add_child(agents_node)
	var nav_region := NavigationRegion2D.new()
	nav_region.name = "NavigationRegion2D"
	var poly := NavigationPolygon.new()
	poly.add_outline(PackedVector2Array([
		Vector2(10, 10), Vector2(300, 10), Vector2(300, 200), Vector2(10, 200),
	]))
	poly.make_polygons_from_outlines()
	nav_region.navigation_polygon = poly
	world.add_child(nav_region)
	add_child(world)


func _run() -> void:
	# --- Episode rollover, forward ---
	var ended: Array = []
	EventBus.episode_ended.connect(func(s: int, e: int, score: int, payout: int) -> void:
		ended.append({"s": s, "e": e, "score": score, "payout": payout}))

	ProducerEconomy.load_save_state({})  # reset to defaults
	var start_influence: int = ProducerEconomy.influence
	_check("fresh state starts at the configured balance", start_influence == ProducerEconomy.STARTING_INFLUENCE)

	DramaDirector.drama_level = 5.0
	# Feed the sampler
	for m in range(0, 300, 30):
		EventBus.time_tick.emit(480.0 + m)
	TimeManager.game_minutes = 3.0 * 1440.0 + 480.0  # day 4
	EventBus.day_changed.emit(TimeManager.day)
	_check("episode ends after EPISODE_DAYS", ended.size() == 1)
	_check("payout floor holds (>= 20)", ended.size() == 1 and ended[0]["payout"] >= 20)
	_check("payout landed in the balance", ProducerEconomy.influence > start_influence)
	_check("episode counter advanced", ProducerEconomy.episode == 2)

	# --- Backward jump re-anchors instead of ending an episode ---
	var ended_before: int = ended.size()
	TimeManager.game_minutes = 480.0  # back to day 1
	EventBus.day_changed.emit(TimeManager.day)
	_check("backward day jump re-anchors silently", ended.size() == ended_before)

	# --- Score bounds ---
	_check("grade thresholds", ProducerEconomy.grade_for(85) == "S" and ProducerEconomy.grade_for(60) == "A" \
		and ProducerEconomy.grade_for(40) == "B" and ProducerEconomy.grade_for(5) == "D")

	# --- Spend / afford / refuse ---
	ProducerEconomy.influence = 10
	_check("can_afford true at balance", ProducerEconomy.can_afford(10))
	_check("spend succeeds and deducts", ProducerEconomy.spend(10, "test") and ProducerEconomy.influence == 0)
	_check("spend refuses when broke", not ProducerEconomy.spend(1, "test"))

	# --- Unlock gating vs injected meta ---
	ProducerEconomy.lifetime_episodes = 0
	ProducerEconomy.best_episode_score = 0
	_check("start item unlocked", ProducerEconomy.is_item_unlocked("anonymous_gift"))
	_check("gated item locked at zero meta", not ProducerEconomy.is_item_unlocked("karaoke_machine"))
	ProducerEconomy.lifetime_episodes = 3
	_check("episode gate opens", ProducerEconomy.is_item_unlocked("karaoke_machine"))
	ProducerEconomy.best_episode_score = 60
	_check("score gate opens documentary_day", ProducerEconomy.is_item_unlocked("documentary_day"))
	_check("unlock text names the requirement", "episodes" in ProducerEconomy.unlock_description("better_cameras"))

	# --- Boost expiry ---
	TimeManager.game_minutes = 480.0
	ProducerEconomy.boosts["doc_day_until"] = 1440.0
	_check("documentary multiplier active", absf(ProducerEconomy.event_probability_multiplier() - 2.0) < 0.01)
	TimeManager.game_minutes = 2000.0
	_check("documentary multiplier expires", absf(ProducerEconomy.event_probability_multiplier() - 1.0) < 0.01)

	# --- Save round-trip ---
	ProducerEconomy.influence = 77
	ProducerEconomy.season = 2
	ProducerEconomy.episode = 4
	ProducerEconomy.purchased_upgrades = ["better_cameras"]
	var snapshot: Dictionary = ProducerEconomy.get_save_state()
	ProducerEconomy.load_save_state({})
	_check("reset clears balance to default", ProducerEconomy.influence == ProducerEconomy.STARTING_INFLUENCE)
	ProducerEconomy.load_save_state(snapshot)
	_check("round-trip restores balance/season/episode",
		ProducerEconomy.influence == 77 and ProducerEconomy.season == 2 and ProducerEconomy.episode == 4)
	_check("round-trip restores upgrades", ProducerEconomy.has_upgrade("better_cameras"))
	CatalogPanel.apply_upgrades_from_save()
	_check("upgrade re-applies on load", absf(ConfessionalDirector.cooldown_scale - 0.5) < 0.01)
	ConfessionalDirector.cooldown_scale = 1.0

	# --- Object factory covers every type ---
	var all_types := ["desk", "couch", "coffee_machine", "water_cooler", "whiteboard",
		"bookshelf", "plant", "radio", "bed", "karaoke_machine", "arcade_cabinet",
		"meditation_pod", "aquarium"]
	var all_created := true
	for obj_type in all_types:
		var obj := ObjectFactory.create(obj_type)
		if obj == null:
			all_created = false
			print("      factory failed: %s" % obj_type)
		else:
			obj.free()
	_check("factory builds all %d object types" % all_types.size(), all_created)
	_check("factory refuses unknown types", ObjectFactory.create("hot_tub") == null)
	# obj_type comes from save files: a traversal must not reach load().
	_check("factory refuses path traversal",
		ObjectFactory.create("../../autoloads/config") == null)
	_check("factory refuses empty type", ObjectFactory.create("") == null)

	# --- Malformed save data must degrade, not abort ---
	var bad_color := PersonalityProfile.from_dict({"name": "Mallory", "color": [1.0]})
	_check("short color array falls back to default",
		bad_color != null and bad_color.color.is_equal_approx(Color(0.5, 0.5, 0.5)))
	var wrong_type := PersonalityProfile.from_dict({"name": "Mallory", "color": "red"})
	_check("non-array color falls back to default",
		wrong_type != null and wrong_type.color.is_equal_approx(Color(0.5, 0.5, 0.5)))

	# --- Ambient mode: low power + digest gating ---
	AmbientMode.low_power_enabled = true
	AmbientMode.mute_when_unfocused = false  # keep the audio bus out of it
	AmbientMode.enter_background()
	_check("backgrounding sets low power on AgentManager", AgentManager.low_power)
	_check("low power stretches think intervals",
		AgentManager.think_interval_for(AgentManager.ThinkTier.NORMAL) > Config.THINK_TIER_NORMAL_INTERVAL)

	# A quick glance away with nothing happening yields no popup.
	var quick: Array = AmbientMode.exit_background()
	_check("quick alt-tab produces no digest", quick.is_empty())
	_check("returning clears low power", not AgentManager.low_power)

	# A real absence with real drama yields a digest.
	AmbientMode.enter_background()
	AmbientMode._away_started_msec = Time.get_ticks_msec() - 120000  # pretend 2 min away
	EventBus.narrative_event.emit("Something enormous happened.", [], 9.0)
	EventBus.narrative_event.emit("And then something else did.", [], 8.0)
	EventBus.narrative_event.emit("Trivial background noise.", [], 2.0)
	var digest: Array = AmbientMode.exit_background()
	_check("real absence produces a digest", digest.size() == 2)
	_check("digest ignores low-importance noise",
		digest.size() == 2 and not ("Trivial" in str(digest)))
	_check("digest entries carry day and time", digest.size() > 0 and digest[0].has("day") and digest[0].has("time"))

	# Nothing is collected while focused.
	EventBus.narrative_event.emit("Happened while watching.", [], 9.0)
	AmbientMode.enter_background()
	AmbientMode._away_started_msec = Time.get_ticks_msec() - 120000
	var focused_digest: Array = AmbientMode.exit_background()
	_check("events while focused are not collected", focused_digest.is_empty())

	# --- Meta kill-switch ---
	var meta_path: String = ProducerEconomy.META_PATH
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(meta_path))
	ProducerEconomy.grant(5, "test")
	_check("meta kill-switch blocks producer.json writes", not FileAccess.file_exists(meta_path))


func _check(test_name: String, ok: bool) -> void:
	_results.append("%s  %s" % ["PASS" if ok else "FAIL", test_name])
	print("  %s  %s" % ["PASS" if ok else "FAIL", test_name])


func _report() -> void:
	var passed := 0
	var failed := 0
	for r in _results:
		if r.begins_with("PASS"):
			passed += 1
		else:
			failed += 1
	print("=========================================")
	if passed + failed == 0:
		# A broken build reaches here having asserted nothing. Without this the
		# report reads "0 passed, 0 failed", which any grep for "0 failed"
		# treats as success — that is how a compile error ships unnoticed.
		print("  NO ASSERTIONS RAN — treat this as a FAILURE")
	print("  %d passed, %d failed" % [passed, failed])
	print("=========================================")
