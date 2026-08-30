class_name CatalogPanel
extends BasePanel
## The Producer's Catalog: spend Influence on objects, interventions, and
## studio upgrades. Item availability unlocks from lifetime (cross-save)
## progression; purchases spend per-save Influence.
##
## Placeable objects enter placement mode on buy: the next click on the
## world places them (screen coords converted to world), and Influence is
## deducted only on successful placement — Esc cancels free.

var _tab_bar: HBoxContainer
var _balance: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _status: Label
var _active_tab: String = "objects"
var _placing_item: Dictionary = {}
var _gift_target: OptionButton = null
var _gift_from: OptionButton = null

const TABS: Array[Array] = [["objects", "Objects"], ["interventions", "Interventions"], ["studio", "Studio"]]


func _ready() -> void:
	_setup_chrome("Producer's Catalog", UIPalette.ACCENT_COOL)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	body.add_child(top)

	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 2)
	_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_tab_bar)
	for tab in TABS:
		var btn := Button.new()
		btn.text = tab[1]
		btn.toggle_mode = true
		var tab_id: String = tab[0]
		btn.pressed.connect(func() -> void:
			_active_tab = tab_id
			_rebuild()
		)
		_tab_bar.add_child(btn)

	_balance = Label.new()
	_balance.add_theme_color_override("font_color", UIPalette.ACCENT_WARM)
	top.add_child(_balance)
	EventBus.influence_changed.connect(func(_b: int, _d: int, _r: String) -> void:
		_balance.text = "¤ %d" % ProducerEconomy.influence
		if visible:
			_rebuild()
	)

	body.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

	_status = Label.new()
	_status.theme_type_variation = "DimLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)


func _on_opened() -> void:
	_balance.text = "¤ %d" % ProducerEconomy.influence
	_status.text = ""
	_rebuild()


func _rebuild() -> void:
	for tab_idx in range(_tab_bar.get_child_count()):
		(_tab_bar.get_child(tab_idx) as Button).set_pressed_no_signal(TABS[tab_idx][0] == _active_tab)
	for child in _list.get_children():
		child.queue_free()
	for item in ProducerEconomy.get_catalog():
		if item.get("tab", "") != _active_tab:
			continue
		# Object items only appear once their script exists in the build.
		if _active_tab == "objects" and not FileAccess.file_exists("res://scenes/objects/%s.gd" % item["id"]):
			continue
		_list.add_child(_make_row(item))
	if _list.get_child_count() == 0:
		var empty := Label.new()
		empty.theme_type_variation = "DimLabel"
		empty.text = "Nothing here yet. Keep producing."
		_list.add_child(empty)


func _make_row(item: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)

	var header := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = str(item["name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var unlocked: bool = ProducerEconomy.is_item_unlocked(item["id"])
	var owned: bool = item.get("tab") == "studio" and ProducerEconomy.has_upgrade(item["id"])
	var price: int = int(item.get("price", 0))

	var buy := Button.new()
	if owned:
		buy.text = "Owned"
		buy.disabled = true
	elif not unlocked:
		buy.text = "¤ %d" % price
		buy.disabled = true
	else:
		buy.text = "Buy  ¤ %d" % price
		buy.disabled = not ProducerEconomy.can_afford(price)
		var captured := item
		buy.pressed.connect(func() -> void: _buy(captured))
	header.add_child(buy)
	row.add_child(header)

	var desc := Label.new()
	desc.theme_type_variation = "DimLabel"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.text = str(item["description"]) if unlocked else ProducerEconomy.unlock_description(item["id"])
	row.add_child(desc)

	if not unlocked:
		row.modulate = Color(1, 1, 1, 0.55)
	row.add_child(HSeparator.new())
	return row


# --- Purchases ---------------------------------------------------------------

func _buy(item: Dictionary) -> void:
	var item_id := str(item["id"])
	var price: int = int(item.get("price", 0))
	match item.get("tab", ""):
		"objects":
			# Pay on placement, not on click.
			_placing_item = item
			_status.text = "Click anywhere in the office to place the %s (Esc cancels)." % item["name"]
			close()
		"studio":
			if ProducerEconomy.spend(price, item_id):
				ProducerEconomy.purchased_upgrades.append(item_id)
				_apply_upgrade(item_id)
				EventBus.catalog_purchased.emit(item_id)
				_status.text = "%s installed." % item["name"]
				_rebuild()
		"interventions":
			_run_intervention(item_id, price)


static func apply_upgrades_from_save() -> void:
	## Called after load: re-apply permanent upgrade effects.
	for upgrade_id in ProducerEconomy.purchased_upgrades:
		_apply_upgrade_static(upgrade_id)


func _apply_upgrade(upgrade_id: String) -> void:
	_apply_upgrade_static(upgrade_id)


static func _apply_upgrade_static(upgrade_id: String) -> void:
	match upgrade_id:
		"better_cameras":
			ConfessionalDirector.cooldown_scale = 0.5


func _run_intervention(item_id: String, price: int) -> void:
	match item_id:
		"anonymous_gift":
			_open_gift_picker(price)
		"leaked_memo":
			if not ProducerEconomy.purchase_consumable(item_id, price):
				_status.text = "Not enough Influence."
				return
			var memo := "a leaked memo says management is watching performance very closely this quarter"
			for agent in AgentManager.agents:
				if is_instance_valid(agent) and not agent.is_dead:
					agent.memory.add_memory(MemoryEntry.MemoryType.OBSERVATION,
						"%s read the memo everyone is talking about: %s." % [agent.agent_name, memo], 6.5)
			EventBus.narrative_event.emit("A memo leaked to the whole office at once. Chaos.", [], 6.0)
			_status.text = "The memo is on every desk."
		"documentary_day":
			if not ProducerEconomy.purchase_consumable(item_id, price):
				_status.text = "Not enough Influence."
				return
			var next_midnight: float = ceilf(TimeManager.game_minutes / 1440.0) * 1440.0
			ProducerEconomy.boosts["doc_day_until"] = next_midnight
			DramaDirector._add_drama(1.0)
			EventBus.narrative_event.emit("A documentary crew is shadowing the office today. Everyone is ON.", [], 5.0)
			_status.text = "Cameras rolling until midnight — events fire twice as often."


func _open_gift_picker(price: int) -> void:
	for child in _list.get_children():
		child.queue_free()
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Who receives the gift, and who should they suspect sent it?"
	_list.add_child(info)

	_gift_target = OptionButton.new()
	_gift_target.clip_text = true
	_gift_from = OptionButton.new()
	_gift_from.clip_text = true
	for agent in AgentManager.agents:
		if is_instance_valid(agent) and not agent.is_dead:
			_gift_target.add_item(agent.agent_name)
			_gift_from.add_item(agent.agent_name)
	var row1 := HBoxContainer.new()
	row1.add_child(_label_for("To:"))
	_gift_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(_gift_target)
	_list.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_child(_label_for("From (suspected):"))
	_gift_from.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_gift_from)
	_list.add_child(row2)

	var send := Button.new()
	send.text = "Send it  ¤ %d" % price
	send.pressed.connect(func() -> void: _send_gift(price))
	_list.add_child(send)


func _label_for(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(96, 0)
	return l


func _send_gift(price: int) -> void:
	if _gift_target.item_count == 0:
		return
	var target := AgentManager.get_agent_by_name(_gift_target.get_item_text(_gift_target.selected))
	var second := AgentManager.get_agent_by_name(_gift_from.get_item_text(_gift_from.selected))
	if target == null or second == null or target == second:
		_status.text = "Pick two different people."
		return
	if not ProducerEconomy.purchase_consumable("anonymous_gift", price):
		_status.text = "Not enough Influence."
		return
	ConsequenceEngine.apply({
		"relationship_effects": [
			{"from": "target", "to": "second", "romantic_interest": 10, "affinity": 5}
		],
		"memory": {"affected": {"text": "found a thoughtful anonymous gift on their desk. The wrapping looks like {second}'s style...",
			"importance": 6, "emotion": "candid", "sentiment": 0.6}},
		"narrative": {"text": "{target} received a mysterious gift. The office has theories.", "importance": 5},
	}, target, second, {"affected": [target]})
	_status.text = "Delivered. Let the speculation begin."
	_rebuild()


# --- Object placement mode ---------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _placing_item.is_empty():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_placing_item = {}
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world := get_tree().get_first_node_in_group("world")
		if world == null:
			_placing_item = {}
			return
		var price: int = int(_placing_item.get("price", 0))
		if not ProducerEconomy.spend(price, str(_placing_item["id"])):
			_placing_item = {}
			return
		var obj := ObjectFactory.create(str(_placing_item["id"]))
		if obj == null:
			ProducerEconomy.grant(price, "placement failed refund")
			_placing_item = {}
			return
		var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
		world.add_object(obj, world_pos)
		EventBus.catalog_purchased.emit(str(_placing_item["id"]))
		_placing_item = {}
		get_viewport().set_input_as_handled()
