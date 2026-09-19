extends Node
## Autoload: the producer meta-game spine. Seasons and episodes give sessions
## a shape; Influence (◆) is the currency drama earns and the Catalog spends.
##
## Two tiers of state:
##  - Per-save: influence balance, season/episode position, episode scoring
##    aggregates, purchased upgrades, temporary boosts. Travels with the save.
##  - Meta (user://producer.json, achievements.json pattern): lifetime
##    episodes, best score, lifetime earnings — unlock gates that persist
##    across sandboxes. Guarded by meta_persistence_enabled so test harnesses
##    (which emit day_changed by hand) can never pollute real progression.

const EPISODE_DAYS := 3
const PILOT_DAYS := 1  # S1E1 wraps after one game-day: the full drama → grade → payout → Catalog loop lands in the first sitting
const EPISODES_PER_SEASON := 5
const STARTING_INFLUENCE := 30
const META_PATH := "user://producer.json"
const SAMPLE_INTERVAL_MINUTES := 30.0
const TRICKLE_CAP_PER_DAY := 15  # 10 exactly equaled the active-play daily spend: engagement taxed to break-even

# Per-save
var influence: int = STARTING_INFLUENCE
var season: int = 1
var episode: int = 1
# Creative mode: the labeled economy bypass. Turning it on ever marks the
# save for good (creative_used) — show scores and free placement don't mix
# silently. Show mode routes ALL placement through Influence instead.
var creative_mode: bool = false
var creative_used: bool = false
var episode_start_day: int = 1
var purchased_upgrades: Array = []
var boosts: Dictionary = {}  # e.g. {"doc_day_until": game_minutes}
var last_episode_score: int = -1

# Episode scoring aggregates (persisted so mid-episode saves keep credit)
var _sample_sum: float = 0.0
var _sample_count: int = 0
var _peak_drama: float = 0.0
var _beats: int = 0
var last_breakdown: Dictionary = {"avg": 0.0, "peak": 0.0, "beats": 0, "resolutions": 0, "resolution_points": 0}

## Resolution scoring (finale night): stories that CONCLUDE inside the
## episode window score on top of raw drama — a goal landed, a romance
## begun, a secret blown open, a mole case closed. Interventions that
## finish stories are what pay, not interventions that merely stir.
const RESOLUTION_POINTS := {"goal": 3, "romance": 3, "exposure": 4, "case": 6, "case_caught": 8}
const RESOLUTION_CAP := 20
var _resolutions: Dictionary = {}  # kind -> count this episode

## "Next time on Aphae": at every wrap the card teases 2-3 live cliffhangers
## and the producer may stake Influence on ONE. The next wrap settles it
## against the episode ledger — the same signals that score resolutions,
## with identities kept. The one-more-day engine and the economy's sink.
const BET_STAKE := 5
const BET_PAYOUT := 15
const MAX_TEASERS := 3
var pending_bet: Dictionary = {}      # {kind, subject, other, text, placed_episode}
var last_teasers: Array = []          # generated at the wrap, shown on the card
var last_bet_result: Dictionary = {}  # {hit, text, payout} for the card, this session
var _ledger: Dictionary = {"goals": [], "exposures": [], "romances": [], "case_resolved": false, "case_caught": false}
var _sample_accum_minutes: float = 0.0
var _last_tick_minutes: float = 0.0
var _trickle_today: int = 0

# Meta (cross-save)
var meta_persistence_enabled: bool = true
var lifetime_episodes: int = 0
var best_episode_score: int = 0
var lifetime_influence_earned: int = 0
var lifetime_spent: int = 0


var _catalog: Array = []  # loaded from resources/catalog.json


func _ready() -> void:
	_load_catalog()
	_load_meta()
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.time_tick.connect(_on_time_tick)
	EventBus.narrative_event.connect(_on_narrative_event)
	EventBus.romance_started.connect(func(a: String, b: String) -> void:
		_trickle(3, "romance")
		_resolution("romance")
		(_ledger["romances"] as Array).append([a, b]))
	EventBus.confession_made.connect(func(_a: String, _b: String, _ok: bool) -> void: _trickle(3, "confession"))
	EventBus.agent_died.connect(func(_n: String, _c: String) -> void: _trickle(5, "tragedy"))
	EventBus.event_triggered.connect(func(_id: String, _n: Array) -> void: _trickle(1, "event"))
	EventBus.goal_achieved.connect(func(a: String, _t: String, _k: int) -> void:
		_resolution("goal")
		(_ledger["goals"] as Array).append(a))
	EventBus.secret_exposed.connect(func(h: String, _t: String) -> void:
		_resolution("exposure")
		(_ledger["exposures"] as Array).append(h))
	EventBus.case_resolved.connect(func(caught: bool, _m: String) -> void:
		_resolution("case_caught" if caught else "case")
		_ledger["case_resolved"] = true
		_ledger["case_caught"] = _ledger["case_caught"] or caught)


func _on_narrative_event(text: String, agents: Array, importance: float) -> void:
	if importance >= 7.0:
		_trickle(2, "big moment")
	if importance < 5.0:
		return
	# Produced beats: a beat that lands inside one of the producer's open
	# attribution windows (ImpactLog) counts double and says so. Before this,
	# a nudge announced itself at 3.5 and could never clear the 5.0 beat bar —
	# producing the show was mechanically worthless to the ratings. Read-only
	# against the log; nothing here writes back into the simulation.
	if ImpactLog.is_attributed(agents):
		_beats += 2
		EventBus.produced_beat.emit(text)
	else:
		_beats += 1


# --- Currency ----------------------------------------------------------------

func can_afford(cost: int) -> bool:
	return influence >= cost


func spend(cost: int, reason: String) -> bool:
	if cost > 0 and not can_afford(cost):
		return false
	influence -= cost
	lifetime_spent += cost
	_save_meta()
	EventBus.influence_changed.emit(influence, -cost, reason)
	return true


func grant(amount: int, reason: String) -> void:
	if amount == 0:
		return
	influence += amount
	lifetime_influence_earned += maxi(amount, 0)
	_save_meta()
	EventBus.influence_changed.emit(influence, amount, reason)


func _trickle(amount: int, reason: String) -> void:
	if _trickle_today >= TRICKLE_CAP_PER_DAY:
		return
	amount = mini(amount, TRICKLE_CAP_PER_DAY - _trickle_today)
	_trickle_today += amount
	grant(amount, reason)


# --- Episode machinery -------------------------------------------------------

func episode_length_days() -> int:
	## The pilot is one day; every later episode is three. Derived from the
	## season/episode position, so it survives save/load with no extra state.
	return PILOT_DAYS if season == 1 and episode == 1 else EPISODE_DAYS


func days_into_episode() -> int:
	return clampi(TimeManager.day - episode_start_day + 1, 1, episode_length_days())


func episode_label() -> String:
	return "S%dE%d" % [season, episode]


func is_finale_day() -> bool:
	## True on the episode's last day (the pilot's only day counts). Finale
	## night raises the pressure elsewhere: booth admissions come easier and
	## an open mole case strikes nightly — endings cluster where the score is.
	return days_into_episode() >= episode_length_days()


func _resolution(kind: String) -> void:
	_resolutions[kind] = int(_resolutions.get(kind, 0)) + 1


func resolution_points() -> int:
	var pts := 0
	for kind in _resolutions:
		pts += int(RESOLUTION_POINTS.get(kind, 0)) * int(_resolutions[kind])
	return mini(pts, RESOLUTION_CAP)


func resolution_count() -> int:
	var n := 0
	for kind in _resolutions:
		n += int(_resolutions[kind])
	return n


const OVERNIGHT_BASE := 3
const OVERNIGHT_CAP := 8

func _on_day_changed(day: int) -> void:
	_trickle_today = 0
	if day < episode_start_day:
		# Loaded an older save or a harness jumped backward — re-anchor.
		episode_start_day = day
		return
	if day - episode_start_day >= episode_length_days():
		_finish_episode()
		episode_start_day = day
		return
	# Overnight ratings: a small payday every day the episode is still
	# running, scaled by how dramatic the day actually was. The first real
	# payout used to land 72 real minutes in (playtest finding) — the
	# producer now sees income every game-day, and drama visibly pays.
	var avg: float = (_sample_sum / _sample_count) if _sample_count > 0 else 0.0
	var overnight: int = clampi(OVERNIGHT_BASE + roundi(avg), OVERNIGHT_BASE, OVERNIGHT_CAP)
	grant(overnight, "overnight ratings")


func _finish_episode() -> void:
	var avg: float = (_sample_sum / _sample_count) if _sample_count > 0 else 0.0
	var score: int = clampi(roundi(avg * 8.0 + _peak_drama * 3.0 + minf(_beats, 10) * 1.0) + resolution_points(), 0, 100)
	var payout: int = 20 + score
	last_episode_score = score
	last_breakdown = {
		"avg": avg, "peak": _peak_drama, "beats": _beats,
		"resolutions": resolution_count(), "resolution_points": resolution_points(),
	}

	# Settle last wrap's bet against this episode's ledger, then tease the
	# next one — both before the signal so the card sees them.
	_settle_bet()

	var finished_season := season
	var finished_episode := episode
	episode += 1
	if episode > EPISODES_PER_SEASON:
		episode = 1
		season += 1

	_sample_sum = 0.0
	_sample_count = 0
	_peak_drama = 0.0
	_beats = 0
	_resolutions = {}
	_ledger = {"goals": [], "exposures": [], "romances": [], "case_resolved": false, "case_caught": false}
	last_teasers = generate_teasers()

	lifetime_episodes += 1
	best_episode_score = maxi(best_episode_score, score)
	grant(payout, "episode payout")

	EventBus.narrative_event.emit(
		"That's a wrap on %s! The episode scored %d." % ["S%dE%d" % [finished_season, finished_episode], score],
		[], 5.0
	)
	EventBus.episode_ended.emit(finished_season, finished_episode, score, payout)


func _on_time_tick(game_minutes: float) -> void:
	# Sample drama on a game-minute cadence, tolerant of jumps.
	var delta: float = game_minutes - _last_tick_minutes
	_last_tick_minutes = game_minutes
	if delta <= 0.0 or delta > 600.0:
		return
	_sample_accum_minutes += delta
	if _sample_accum_minutes >= SAMPLE_INTERVAL_MINUTES:
		_sample_accum_minutes = 0.0
		var level: float = DramaDirector.drama_level
		_sample_sum += level
		_sample_count += 1
		_peak_drama = maxf(_peak_drama, level)


func score_breakdown() -> Dictionary:
	return {
		"avg": (_sample_sum / _sample_count) if _sample_count > 0 else 0.0,
		"peak": _peak_drama,
		"beats": _beats,
	}


static func grade_for(score: int) -> String:
	if score >= 80:
		return "S"
	elif score >= 60:
		return "A"
	elif score >= 40:
		return "B"
	elif score >= 20:
		return "C"
	return "D"


# --- Next time on Aphae: teasers and bets ------------------------------------

func generate_teasers() -> Array:
	## Up to MAX_TEASERS cliffhangers read off live autoload state, most
	## specific first; generic fallbacks fill to two so the card always has a
	## bet to offer. Each: {kind, subject, other, text}.
	var out: Array = []
	if WhodunitDirector.has_open_case():
		out.append({"kind": "mole", "subject": "", "other": "",
			"text": "Someone is still sabotaging the office. Does the house catch them?"})
	# The secret closest to exposure: hidden, and already in some ears.
	var best_secret: SecretState = null
	for secret: SecretState in SecretManager._secrets.values():
		if not secret.is_hidden() or secret.known_by.is_empty():
			continue
		if best_secret == null or secret.known_by.size() > best_secret.known_by.size():
			best_secret = secret
	if best_secret != null and out.size() < MAX_TEASERS:
		out.append({"kind": "exposure", "subject": best_secret.agent_name, "other": "",
			"text": "%s's secret has reached %d ear%s. Does it get out?" % [
				best_secret.agent_name, best_secret.known_by.size(),
				"" if best_secret.known_by.size() == 1 else "s"]})
	# A crush nobody has acted on.
	if out.size() < MAX_TEASERS:
		for agent in AgentManager.agents:
			if not is_instance_valid(agent) or agent.is_dead or agent.relationships == null:
				continue
			var found := false
			for other_name in agent.relationships.get_all_relationships():
				var rel: RelationshipEntry = agent.relationships.get_relationship(str(other_name))
				if rel.relationship_status == RelationshipEntry.Status.CRUSHING:
					out.append({"kind": "romance", "subject": agent.agent_name, "other": str(other_name),
						"text": "%s keeps looking at %s. Do they make a move?" % [agent.agent_name, other_name]})
					found = true
					break
			if found:
				break
	# A goal close enough to land — or to lose.
	if out.size() < MAX_TEASERS:
		var best_goal: GoalState = null
		for agent in AgentManager.agents:
			if not is_instance_valid(agent) or agent.is_dead:
				continue
			for goal: GoalState in GoalManager.get_goals(agent.agent_name):
				if goal.status != GoalState.Status.ACTIVE or goal.progress < 40.0:
					continue
				if best_goal == null or goal.progress > best_goal.progress:
					best_goal = goal
		if best_goal != null:
			out.append({"kind": "goal", "subject": best_goal.agent_name, "other": "",
				"text": "%s is %d%% of the way to \"%s\". Do they land it?" % [
					best_goal.agent_name, roundi(best_goal.progress), best_goal.text]})
	# Fallbacks: the card always has something to bet on.
	if out.size() < 2:
		out.append({"kind": "exposure", "subject": "", "other": "",
			"text": "Does anyone's secret slip this episode?"})
	if out.size() < 2:
		out.append({"kind": "romance", "subject": "", "other": "",
			"text": "Does a romance bloom this episode?"})
	return out.slice(0, MAX_TEASERS)


func can_place_bet() -> bool:
	return pending_bet.is_empty() and can_afford(BET_STAKE)


func place_bet(teaser: Dictionary) -> bool:
	## Stake BET_STAKE on one teaser. One open bet at a time; settled at the
	## next wrap. The stake is gone either way — that is what makes it a bet.
	if not can_place_bet() or not teaser.has("kind"):
		return false
	if not spend(BET_STAKE, "bet"):
		return false
	pending_bet = {
		"kind": str(teaser.get("kind", "")),
		"subject": str(teaser.get("subject", "")),
		"other": str(teaser.get("other", "")),
		"text": str(teaser.get("text", "")),
		"placed_episode": episode_label(),
	}
	EventBus.bet_placed.emit(pending_bet["text"])
	return true


func _bet_hit(bet: Dictionary) -> bool:
	var subject := str(bet.get("subject", ""))
	var other := str(bet.get("other", ""))
	match str(bet.get("kind", "")):
		"mole":
			return bool(_ledger["case_caught"])
		"exposure":
			var exposures: Array = _ledger["exposures"]
			return (not exposures.is_empty()) if subject == "" else (subject in exposures)
		"romance":
			var romances: Array = _ledger["romances"]
			if subject == "":
				return not romances.is_empty()
			for pair in romances:
				if (pair[0] == subject and pair[1] == other) or (pair[0] == other and pair[1] == subject):
					return true
			return false
		"goal":
			return subject in (_ledger["goals"] as Array)
	return false


func _settle_bet() -> void:
	if pending_bet.is_empty():
		last_bet_result = {}
		return
	var hit := _bet_hit(pending_bet)
	last_bet_result = {"hit": hit, "text": str(pending_bet.get("text", "")), "payout": BET_PAYOUT if hit else 0}
	if hit:
		grant(BET_PAYOUT, "bet won")
	EventBus.bet_settled.emit(hit, str(pending_bet.get("text", "")), BET_PAYOUT if hit else 0)
	pending_bet = {}


# --- Creative mode and show-mode placement -----------------------------------

## Non-catalog placeables price and unlock by CATEGORY; a catalog entry's own
## price/unlock gates always win (specific over generic). "classic" is the
## bespoke thirteen. Tiers are lifetime episodes — cross-save meta, so a
## veteran's fresh save starts with their toolbox open.
const CATEGORY_PRICE := {
	"classic": 10, "food": 10, "comfort": 12, "decor": 6,
	"work": 14, "fun": 18, "wellness": 16, "tech": 18, "weird": 22,
}
const CATEGORY_UNLOCK_EPISODES := {
	"classic": 0, "food": 0, "comfort": 0, "decor": 0,
	"work": 1, "fun": 1, "wellness": 2, "tech": 2, "weird": 4,
}


func set_creative_mode(on: bool) -> void:
	creative_mode = on
	if on:
		creative_used = true
	EventBus.creative_mode_changed.emit(on)


func placement_price(object_id: String) -> int:
	var item := get_item(object_id)
	if not item.is_empty():
		return int(item.get("price", 10))
	return int(CATEGORY_PRICE.get(_category_of(object_id), 12))


func is_placement_unlocked(object_id: String) -> bool:
	var item := get_item(object_id)
	if not item.is_empty():
		return is_item_unlocked(object_id)
	return lifetime_episodes >= int(CATEGORY_UNLOCK_EPISODES.get(_category_of(object_id), 0))


func placement_unlock_text(object_id: String) -> String:
	var item := get_item(object_id)
	if not item.is_empty():
		return unlock_description(object_id)
	var needed := int(CATEGORY_UNLOCK_EPISODES.get(_category_of(object_id), 0))
	return "Locked — complete %d episode%s" % [needed, "" if needed == 1 else "s"]


static func _category_of(object_id: String) -> String:
	if SynergyManager.BESPOKE_TAGS.has(object_id):
		return "classic"
	return str(DataObject.get_def(object_id).get("category", "decor"))


# --- Catalog -----------------------------------------------------------------

func get_catalog() -> Array:
	return _catalog


func get_item(item_id: String) -> Dictionary:
	for item in _catalog:
		if item.get("id", "") == item_id:
			return item
	return {}


func is_item_unlocked(item_id: String) -> bool:
	## Unlock gates are OR-combined: meeting ANY listed condition unlocks.
	## An empty unlock block means available from the start.
	var item := get_item(item_id)
	if item.is_empty():
		return false
	var unlock: Dictionary = item.get("unlock", {})
	if unlock.is_empty():
		return true
	if unlock.has("episodes") and lifetime_episodes >= int(unlock["episodes"]):
		return true
	if unlock.has("best_score") and best_episode_score >= int(unlock["best_score"]):
		return true
	if unlock.has("achievement") and AchievementManager.is_unlocked(str(unlock["achievement"])):
		return true
	return false


func unlock_description(item_id: String) -> String:
	var unlock: Dictionary = get_item(item_id).get("unlock", {})
	var parts: Array[String] = []
	if unlock.has("episodes"):
		parts.append("complete %d episodes" % int(unlock["episodes"]))
	if unlock.has("best_score"):
		parts.append("score %d in an episode" % int(unlock["best_score"]))
	if unlock.has("achievement"):
		var defs := AchievementManager.get_all()
		var achievement_name: String = str(unlock["achievement"])
		for d in defs:
			if d.get("id", "") == unlock["achievement"]:
				achievement_name = d.get("name", achievement_name)
		parts.append("earn \"%s\"" % achievement_name)
	return "Locked — " + " or ".join(parts) if not parts.is_empty() else "Locked"


func purchase_consumable(item_id: String, cost: int) -> bool:
	## Payment for instant items; effect application is the caller's job
	## (CatalogPanel knows the pickers/targets). Placeables pay on placement.
	if not spend(cost, item_id):
		return false
	EventBus.catalog_purchased.emit(item_id)
	return true


func _load_catalog() -> void:
	var file := FileAccess.open("res://resources/catalog.json", FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.get("items") is Array:
		_catalog = parsed["items"]


# --- Boost/upgrade hooks (consumers arrive with the Catalog) -----------------

func event_probability_multiplier() -> float:
	if boosts.has("doc_day_until") and TimeManager.game_minutes < float(boosts["doc_day_until"]):
		return 2.0
	return 1.0


func has_upgrade(upgrade_id: String) -> bool:
	return upgrade_id in purchased_upgrades


# --- Persistence -------------------------------------------------------------

func get_save_state() -> Dictionary:
	return {
		"influence": influence,
		"season": season,
		"episode": episode,
		"episode_start_day": episode_start_day,
		"purchased_upgrades": purchased_upgrades.duplicate(),
		"boosts": boosts.duplicate(),
		"last_episode_score": last_episode_score,
		"creative_mode": creative_mode,
		"creative_used": creative_used,
		"sample_sum": _sample_sum,
		"sample_count": _sample_count,
		"peak_drama": _peak_drama,
		"beats": _beats,
		"resolutions": _resolutions.duplicate(),
		"pending_bet": pending_bet.duplicate(),
		"ledger": _ledger.duplicate(true),
	}


func load_save_state(data: Dictionary) -> void:
	influence = int(data.get("influence", STARTING_INFLUENCE))
	season = int(data.get("season", 1))
	episode = int(data.get("episode", 1))
	episode_start_day = int(data.get("episode_start_day", TimeManager.day))
	purchased_upgrades = data.get("purchased_upgrades", []).duplicate()
	boosts = data.get("boosts", {}).duplicate()
	last_episode_score = int(data.get("last_episode_score", -1))
	creative_mode = bool(data.get("creative_mode", false))
	creative_used = bool(data.get("creative_used", false))
	_sample_sum = float(data.get("sample_sum", 0.0))
	_sample_count = int(data.get("sample_count", 0))
	_peak_drama = float(data.get("peak_drama", 0.0))
	_beats = int(data.get("beats", 0))
	_resolutions = data.get("resolutions", {}).duplicate() if data.get("resolutions") is Dictionary else {}
	pending_bet = data.get("pending_bet", {}).duplicate() if data.get("pending_bet") is Dictionary else {}
	_ledger = {"goals": [], "exposures": [], "romances": [], "case_resolved": false, "case_caught": false}
	var saved_ledger: Variant = data.get("ledger")
	if saved_ledger is Dictionary:
		for key in _ledger:
			if (saved_ledger as Dictionary).has(key):
				_ledger[key] = (saved_ledger as Dictionary)[key]
	_last_tick_minutes = TimeManager.game_minutes
	EventBus.influence_changed.emit(influence, 0, "loaded")


func _load_meta() -> void:
	var file := FileAccess.open(META_PATH, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	lifetime_episodes = int(data.get("lifetime_episodes", 0))
	best_episode_score = int(data.get("best_episode_score", 0))
	lifetime_influence_earned = int(data.get("lifetime_influence_earned", 0))
	lifetime_spent = int(data.get("lifetime_spent", 0))


func _save_meta() -> void:
	if not meta_persistence_enabled:
		return
	var file := FileAccess.open(META_PATH, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify({
		"lifetime_episodes": lifetime_episodes,
		"best_episode_score": best_episode_score,
		"lifetime_influence_earned": lifetime_influence_earned,
		"lifetime_spent": lifetime_spent,
	}, "\t"))
