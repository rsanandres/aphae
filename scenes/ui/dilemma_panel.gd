class_name DilemmaPanel
extends BasePanel
## Producer dilemma modal: a big event pauses the show and hands you the
## decision. A countdown runs in real time; walking away picks the default,
## so an unattended sandbox never blocks.

var _situation: Label
var _choice_box: VBoxContainer
var _countdown: ProgressBar
var _timeout_total: float = 25.0


func _ready() -> void:
	_setup_chrome("Producer Decision", UIPalette.ACCENT_WARM)
	custom_minimum_size = Vector2(280, 0)

	_situation = Label.new()
	_situation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_situation)

	body.add_child(HSeparator.new())

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 4)
	body.add_child(_choice_box)

	_countdown = ProgressBar.new()
	_countdown.custom_minimum_size = Vector2(0, 6)
	_countdown.show_percentage = false
	_countdown.max_value = 1.0
	body.add_child(_countdown)

	var hint := Label.new()
	hint.theme_type_variation = "DimLabel"
	hint.text = "No choice? The default happens when the clock runs out."
	body.add_child(hint)

	EventBus.dilemma_offered.connect(_on_offered)
	EventBus.dilemma_resolved.connect(_on_resolved)
	# Dismissing the panel (X / Esc) is a decision too: take the default.
	closed.connect(func() -> void:
		if EventManager.has_pending_dilemma():
			EventManager.resolve_dilemma(
				int((EventManager._pending_dilemma["definition"] as EventDefinition).dilemma.get("default_choice", 0))
			)
	)


func _process(_delta: float) -> void:
	if visible and EventManager.has_pending_dilemma() and _timeout_total > 0.0:
		_countdown.value = clampf(float(EventManager._pending_dilemma.get("timeout_left", 0.0)) / _timeout_total, 0.0, 1.0)


func _on_offered(definition: RefCounted, target_names: Array) -> void:
	var d: Dictionary = (definition as EventDefinition).dilemma
	_title_label.text = str(d.get("title", "Producer Decision"))
	var situation := str(d.get("situation", ""))
	if not target_names.is_empty():
		situation = situation.replace("{target}", str(target_names[0]))
	_situation.text = situation
	_timeout_total = float(d.get("timeout_sec", 25.0))

	for child in _choice_box.get_children():
		child.queue_free()
	var choices: Array = d.get("choices", [])
	for i in range(choices.size()):
		var btn := Button.new()
		var label := str(choices[i].get("label", "Choice %d" % (i + 1)))
		if not target_names.is_empty():
			label = label.replace("{target}", str(target_names[0]))
		btn.text = label
		var idx := i
		btn.pressed.connect(func() -> void:
			EventManager.resolve_dilemma(idx)
		)
		_choice_box.add_child(btn)

	open()


func _on_resolved(_event_id: String, _choice_idx: int, _by_timeout: bool) -> void:
	if visible:
		close()
