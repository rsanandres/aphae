class_name EpisodeCard
extends BasePanel
## End-of-episode reward card: grade, score breakdown, payout, the episode's
## top storyline. Auto-opens on episode_ended; never pauses — it's a reward,
## not a decision.

var _grade: Label
var _headline: Label
var _breakdown: Label
var _payout: Label
var _storyline: Label


func _ready() -> void:
	_setup_chrome("Episode Wrap", UIPalette.ACCENT_WARM)
	custom_minimum_size = Vector2(260, 0)

	_grade = Label.new()
	_grade.theme_type_variation = "HeaderLabel"
	_grade.add_theme_font_size_override("font_size", 26)
	_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_grade)

	_headline = Label.new()
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_headline)

	body.add_child(HSeparator.new())

	_breakdown = Label.new()
	_breakdown.theme_type_variation = "DimLabel"
	_breakdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_breakdown)

	_storyline = Label.new()
	_storyline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_storyline)

	body.add_child(HSeparator.new())

	_payout = Label.new()
	_payout.add_theme_color_override("font_color", UIPalette.ACCENT_POS)
	_payout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_payout)

	EventBus.episode_ended.connect(_on_episode_ended)


func _on_episode_ended(ended_season: int, ended_episode: int, score: int, payout: int) -> void:
	_title_label.text = "Episode Wrap — S%dE%d" % [ended_season, ended_episode]
	_grade.text = ProducerEconomy.grade_for(score)
	_headline.text = "Ratings score: %d / 100" % score
	var b: Dictionary = ProducerEconomy.last_breakdown
	_breakdown.text = "Average drama %.1f · peak %.1f — the aggregates reset each episode, so every wrap starts a fresh chase." % [b["avg"], b["peak"]]
	var top := Narrator.get_top_storylines(1)
	if not top.is_empty() and top[0].title != "":
		_storyline.text = "The story of the episode: %s" % top[0].title
	else:
		_storyline.text = "The story of the episode is still being written."
	_payout.text = "+%d ◆ Influence" % payout
	open()
