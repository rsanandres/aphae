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
var _export_btn: Button
var _bet_result: Label
var _teasers_box: VBoxContainer


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

	# Last wrap's bet, settled. Hidden when there was none.
	_bet_result = Label.new()
	_bet_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bet_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bet_result.visible = false
	body.add_child(_bet_result)

	body.add_child(HSeparator.new())

	# "Next time on Aphae": the teasers, each with a stake button.
	var teasers_title := Label.new()
	teasers_title.theme_type_variation = "HeaderLabel"
	teasers_title.text = "Next time on Aphae"
	body.add_child(teasers_title)
	_teasers_box = VBoxContainer.new()
	_teasers_box.add_theme_constant_override("separation", 3)
	body.add_child(_teasers_box)

	_export_btn = Button.new()
	_export_btn.text = "Export episode recap"
	_export_btn.pressed.connect(func() -> void:
		var path := EpisodeRecap.export_to_file()
		_export_btn.text = "Saved to recaps folder" if path != "" else "Export failed"
		_export_btn.disabled = path != ""
	)
	body.add_child(_export_btn)

	EventBus.episode_ended.connect(_on_episode_ended)


func _on_episode_ended(ended_season: int, ended_episode: int, score: int, payout: int) -> void:
	_title_label.text = "Episode Wrap — S%dE%d" % [ended_season, ended_episode]
	_grade.text = ProducerEconomy.grade_for(score)
	_headline.text = "Ratings score: %d / 100" % score
	var b: Dictionary = ProducerEconomy.last_breakdown
	var resolved := int(b.get("resolutions", 0))
	var resolution_line: String
	if resolved > 0:
		resolution_line = "%d stor%s concluded (+%d)" % [resolved, "y" if resolved == 1 else "ies", int(b.get("resolution_points", 0))]
	else:
		resolution_line = "no stories concluded — a finale wants endings"
	_breakdown.text = "Average drama %.1f · peak %.1f · %s. The aggregates reset each episode; every wrap starts a fresh chase." % [b["avg"], b["peak"], resolution_line]
	var top := Narrator.get_top_storylines(1)
	if not top.is_empty() and top[0].title != "":
		_storyline.text = "The story of the episode: %s" % top[0].title
	else:
		_storyline.text = "The story of the episode is still being written."
	_payout.text = "+%d ¤ Influence" % payout
	_show_bet_result()
	_rebuild_teasers()
	_export_btn.text = "Export episode recap"
	_export_btn.disabled = false
	open()


func _show_bet_result() -> void:
	var result: Dictionary = ProducerEconomy.last_bet_result
	if result.is_empty():
		_bet_result.visible = false
		return
	_bet_result.visible = true
	if bool(result.get("hit", false)):
		_bet_result.text = "Your bet paid off: +%d ¤ — \"%s\"" % [int(result.get("payout", 0)), str(result.get("text", ""))]
		_bet_result.add_theme_color_override("font_color", UIPalette.ACCENT_POS)
	else:
		_bet_result.text = "Your bet missed — \"%s\"" % str(result.get("text", ""))
		_bet_result.add_theme_color_override("font_color", UIPalette.TEXT_DIM)


func _rebuild_teasers() -> void:
	for child in _teasers_box.get_children():
		child.queue_free()
	var teasers: Array = ProducerEconomy.last_teasers
	if teasers.is_empty():
		teasers = ProducerEconomy.generate_teasers()
	for teaser in teasers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_teasers_box.add_child(row)
		var text := Label.new()
		text.text = str(teaser.get("text", ""))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var bet := Button.new()
		bet.custom_minimum_size = Vector2(52, 0)
		row.add_child(bet)
		_style_bet_button(bet, teaser)
		var captured: Dictionary = teaser
		bet.pressed.connect(func() -> void:
			if ProducerEconomy.place_bet(captured):
				for other_row in _teasers_box.get_children():
					for node in other_row.get_children():
						if node is Button:
							_style_bet_button(node, {})
				bet.text = "Staked"
		)


func _style_bet_button(bet: Button, teaser: Dictionary) -> void:
	var pending: Dictionary = ProducerEconomy.pending_bet
	if not pending.is_empty():
		var mine := not teaser.is_empty() and str(pending.get("text", "")) == str(teaser.get("text", ""))
		bet.text = "Staked" if mine else "Bet ¤%d" % ProducerEconomy.BET_STAKE
		bet.disabled = true
		bet.tooltip_text = "One bet per episode — settles at the next wrap."
		return
	bet.text = "Bet ¤%d" % ProducerEconomy.BET_STAKE
	bet.disabled = not ProducerEconomy.can_afford(ProducerEconomy.BET_STAKE)
	bet.tooltip_text = "Stake ¤%d; pays ¤%d if it happens by the next wrap." % [ProducerEconomy.BET_STAKE, ProducerEconomy.BET_PAYOUT]
