class_name ProducerPanel
extends BasePanel
## The player's control surface for a single agent: nudge, interview, plant a rumor.
##
## Deliberately separate from AgentInspector, which stays a read-only readout.
## This panel acts on whichever agent is currently selected; with none selected
## it says so rather than silently doing nothing.

var _agent: Node2D = null

var _subject: Label
var _result: Label
var _answer: Label
var _question: LineEdit
var _rumor_target: OptionButton
var _rumor_text: OptionButton
var _action_rows: VBoxContainer


func _ready() -> void:
	_setup_chrome("Producer", UIPalette.ACCENT_COOL)
	_build_ui()

	EventBus.agent_selected.connect(_on_agent_selected)
	EventBus.agent_deselected.connect(_on_agent_deselected)
	EventBus.nudge_answered.connect(_on_nudge_answered)
	EventBus.interview_answered.connect(_on_interview_answered)
	EventBus.rumor_planted.connect(_on_rumor_planted)

	_agent = GameManager.selected_agent
	_refresh_subject()


func _on_opened() -> void:
	_agent = GameManager.selected_agent
	_refresh_subject()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Without this the container hands children their natural width, which for
	# a two-button row exceeds the panel — the right column was clipped to
	# "Coffe" and "Mingl". Disabling horizontal scroll forces content to fit.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(outer)

	_subject = Label.new()
	_subject.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_subject)

	outer.add_child(HSeparator.new())

	# --- Nudges ---
	_action_rows = VBoxContainer.new()
	_action_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_action_rows)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_action_rows.add_child(row)
	var i := 0
	for kind in PlayerDirector.get_nudge_kinds():
		var spec: Dictionary = PlayerDirector.NUDGES[kind]
		var btn := _small_button(spec["label"])
		var captured: String = kind
		btn.pressed.connect(func() -> void: _do_nudge(captured))
		row.add_child(btn)
		i += 1
		if i % 2 == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 2)
			_action_rows.add_child(row)

	_result = Label.new()
	_result.theme_type_variation = "DimLabel"
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_result)

	outer.add_child(HSeparator.new())

	# --- Interview ---
	var ask_lbl := Label.new()
	ask_lbl.text = "Ask them something  ◆%d" % COST_INTERVIEW
	ask_lbl.add_theme_color_override("font_color", UIPalette.ACCENT_COOL)
	outer.add_child(ask_lbl)

	var ask_row := HBoxContainer.new()
	ask_row.add_theme_constant_override("separation", 2)
	outer.add_child(ask_row)

	_question = LineEdit.new()
	_question.placeholder_text = "How are you feeling?"
	_question.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_question.text_submitted.connect(func(_t: String) -> void: _do_interview())
	ask_row.add_child(_question)

	var ask_btn := _small_button("Ask")
	ask_btn.pressed.connect(_do_interview)
	ask_row.add_child(ask_btn)

	_answer = Label.new()
	_answer.add_theme_color_override("font_color", UIPalette.ACCENT_WARM)
	_answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_answer)

	outer.add_child(HSeparator.new())

	# --- Rumor ---
	var rumor_lbl := Label.new()
	rumor_lbl.text = "Plant a rumour  ◆%d" % COST_RUMOR
	rumor_lbl.add_theme_color_override("font_color", UIPalette.ACCENT_NEG)
	outer.add_child(rumor_lbl)

	# clip_text is essential: rumour lines are full sentences, and without it the
	# OptionButton demands enough width to show one, which propagates up and
	# drags the whole panel off the right of a 320px-wide screen.
	_rumor_target = OptionButton.new()
	_rumor_target.clip_text = true
	_rumor_target.item_selected.connect(func(_i: int) -> void: _rebuild_rumor_text())
	outer.add_child(_rumor_target)

	_rumor_text = OptionButton.new()
	_rumor_text.clip_text = true
	outer.add_child(_rumor_text)

	var plant := _small_button("Plant it")
	plant.pressed.connect(_do_rumor)
	outer.add_child(plant)


func _small_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 18)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return btn


# --- Actions ---------------------------------------------------------------

const COST_NUDGE := 1
const COST_INTERVIEW := 2
const COST_RUMOR := 5


func _do_nudge(kind: String) -> void:
	if not _has_agent():
		return
	# Costs live here, not in PlayerDirector — the director API stays free
	# for tests and internal callers; only the panel charges the producer.
	if not ProducerEconomy.spend(COST_NUDGE, "nudge"):
		_result.text = "Not enough Influence (◆%d needed)." % COST_NUDGE
		_result.add_theme_color_override("font_color", UIPalette.ACCENT_NEG)
		return
	PlayerDirector.nudge(_agent, kind)


func _do_interview() -> void:
	if not _has_agent():
		return
	var q := _question.text.strip_edges()
	if q == "":
		return
	if not ProducerEconomy.spend(COST_INTERVIEW, "interview"):
		_answer.text = "Not enough Influence (◆%d needed)." % COST_INTERVIEW
		return
	_answer.text = "..."
	PlayerDirector.interview(_agent, q)
	_question.clear()


func _do_rumor() -> void:
	if not _has_agent():
		return
	if _rumor_text.item_count == 0:
		return
	var text := _rumor_text.get_item_text(_rumor_text.selected)
	var subject := ""
	if _rumor_target.item_count > 0:
		subject = _rumor_target.get_item_text(_rumor_target.selected)
	if not ProducerEconomy.spend(COST_RUMOR, "rumor"):
		_result.text = "Not enough Influence (◆%d needed)." % COST_RUMOR
		_result.add_theme_color_override("font_color", UIPalette.ACCENT_NEG)
		return
	PlayerDirector.plant_rumor(_agent, text, subject)


func _has_agent() -> bool:
	if _agent == null or not is_instance_valid(_agent) or _agent.is_dead:
		_result.text = "Select an agent first."
		return false
	return true


# --- State -----------------------------------------------------------------

func _on_agent_selected(agent: Node2D) -> void:
	_agent = agent
	_refresh_subject()


func _on_agent_deselected() -> void:
	_agent = null
	_refresh_subject()


func _refresh_subject() -> void:
	if _agent and is_instance_valid(_agent):
		_subject.text = "Directing: %s" % _agent.agent_name
	else:
		_subject.text = "No one selected — click an agent."
	_rebuild_rumor_targets()


func _rebuild_rumor_targets() -> void:
	if _rumor_target == null:
		return
	_rumor_target.clear()
	for other in AgentManager.agents:
		if not is_instance_valid(other) or other.is_dead:
			continue
		if _agent and other == _agent:
			continue  # a rumour about yourself is just a thought
		_rumor_target.add_item(other.agent_name)
	if _rumor_target.item_count > 0:
		_rumor_target.select(0)
	_rebuild_rumor_text()


func _rebuild_rumor_text() -> void:
	if _rumor_text == null:
		return
	_rumor_text.clear()
	if _rumor_target.item_count == 0:
		return
	var subject := _rumor_target.get_item_text(_rumor_target.selected)
	for line in PlayerDirector.rumor_templates(subject):
		_rumor_text.add_item(line)
	if _rumor_text.item_count > 0:
		_rumor_text.select(0)


func _on_nudge_answered(agent_name: String, request: String, complied: bool, reason: String) -> void:
	if complied:
		_result.text = "%s agrees to %s." % [agent_name, request]
		_result.add_theme_color_override("font_color", UIPalette.ACCENT_POS)
	else:
		_result.text = "%s %s." % [agent_name, reason]
		_result.add_theme_color_override("font_color", UIPalette.ACCENT_NEG)


func _on_interview_answered(agent_name: String, _question: String, answer: String) -> void:
	_answer.text = "%s: \"%s\"" % [agent_name, answer]


func _on_rumor_planted(agent_name: String, _text: String) -> void:
	_result.text = "%s heard it. Now we wait." % agent_name
	_result.add_theme_color_override("font_color", UIPalette.ACCENT_WARM)
