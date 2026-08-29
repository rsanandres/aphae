class_name DataObject
extends InteractableObject
## A catalog-defined office object: everything about it — name, size, sprite
## recipe, interaction, need effects, passive aura — comes from one entry in
## resources/objects.json. One class serves a hundred object types; a type
## that needs bespoke behavior gets its own script in scenes/objects/ and
## ObjectFactory prefers that automatically.

const CATALOG_PATH := "res://resources/objects.json"

static var _defs: Dictionary = {}  # id -> Dictionary
static var _loaded: bool = false

const _NEED_LOOKUP := {
	"energy": NeedType.Type.ENERGY,
	"hunger": NeedType.Type.HUNGER,
	"social": NeedType.Type.SOCIAL,
	"productivity": NeedType.Type.PRODUCTIVITY,
	"health": NeedType.Type.HEALTH,
}


static func _load_catalog() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if not file:
		push_warning("DataObject: could not load %s" % CATALOG_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_warning("DataObject: %s is not an array" % CATALOG_PATH)
		return
	for entry in parsed:
		if entry is Dictionary and str(entry.get("id", "")).is_valid_identifier():
			_defs[str(entry["id"])] = entry


static func get_def(id: String) -> Dictionary:
	_load_catalog()
	return _defs.get(id, {})


static func get_ids() -> Array:
	_load_catalog()
	var ids := _defs.keys()
	ids.sort()
	return ids


static func get_ids_by_category() -> Dictionary:
	## category -> sorted Array of ids, for pickers.
	_load_catalog()
	var out: Dictionary = {}
	for id in get_ids():
		var cat := str(_defs[id].get("category", "misc"))
		if not out.has(cat):
			out[cat] = []
		(out[cat] as Array).append(id)
	return out


func configure(id: String) -> bool:
	## Called by ObjectFactory before the node enters the tree.
	var def := get_def(id)
	if def.is_empty():
		return false
	object_type = id
	display_name = str(def.get("name", id.capitalize()))
	interaction_duration = float(def.get("duration", 20.0))
	max_occupants = int(def.get("occupants", 1))
	_need_effects = _parse_effects(def.get("effects", {}))
	passive_effect_radius = float(def.get("passive_radius", 0.0))
	passive_need_effects = _parse_effects(def.get("passive", {}))
	var sprite: Dictionary = def.get("sprite", {})
	var texture := SpriteFactory.create_archetype_sprite(
		str(sprite.get("shape", "box")),
		int(sprite.get("w", 14)), int(sprite.get("h", 12)),
		Color(str(sprite.get("c1", "#8a6142"))),
		Color(str(sprite.get("c2", "#6b4a2f"))),
		Color(str(sprite.get("c3", "#4a3320"))),
		id.hash() % 1000)
	var sprite_node: Sprite2D = get_node_or_null("Sprite2D")
	if sprite_node:
		sprite_node.texture = texture
	return true


func is_available() -> bool:
	# Pure decor (occupants 0) is felt, never used — same contract as the
	# bespoke aquarium.
	if max_occupants <= 0:
		return false
	return super.is_available()


static func _parse_effects(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in raw:
		if _NEED_LOOKUP.has(str(key)):
			out[_NEED_LOOKUP[str(key)]] = float(raw[key])
	return out
