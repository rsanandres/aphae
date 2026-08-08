extends Node2D
## The office world: warm floor, perimeter walls, day/night via CanvasModulate.

@onready var objects_container: Node2D = $Objects
@onready var agents_container: Node2D = $Agents

var _all_objects: Array[InteractableObject] = []
var _w: float = Config.DESKTOP_OFFICE_WIDTH
var _h: float = Config.DESKTOP_OFFICE_HEIGHT
var _m: float = 10.0  # margin
var _day_night: CanvasModulate = null
var _last_tint_hour: int = -1

# Floor family: warm tan with a barely-there checker.
const FLOOR_BASE := Color(0.847, 0.769, 0.604)
const FLOOR_ALT := Color(0.818, 0.737, 0.572)
const WALL_FACE := Color("#3a4466")
const WALL_TOP := Color("#5a6988")
const BASEBOARD := Color("#6b5b4a")


func _ready() -> void:
	add_to_group("world")
	_collect_objects()
	# Day/night lives on a CanvasModulate: it tints the whole world canvas
	# (agents and objects included) while the UI CanvasLayers stay untouched.
	_day_night = CanvasModulate.new()
	add_child(_day_night)
	_update_day_night()
	queue_redraw()


func get_all_objects() -> Array[InteractableObject]:
	return _all_objects


func add_object(object: InteractableObject, pos: Vector2) -> void:
	object.position = _snap_to_grid(pos)
	objects_container.add_child(object)
	_all_objects.append(object)
	EventBus.object_placed.emit(object, object.position)
	EventBus.narrative_event.emit(
		"A new %s appeared in the office." % object.display_name,
		[], 3.0
	)
	queue_redraw()


func remove_object(object: InteractableObject) -> void:
	if object in _all_objects:
		_all_objects.erase(object)
		EventBus.object_removed.emit(object)
		EventBus.narrative_event.emit(
			"The %s was removed from the office." % object.display_name,
			[], 3.0
		)
		object.queue_free()
		queue_redraw()


func resize_for_agents(count: int) -> void:
	if count <= Config.MAX_AGENTS_DESKTOP:
		_w = Config.DESKTOP_OFFICE_WIDTH
		_h = Config.DESKTOP_OFFICE_HEIGHT
	else:
		var total_area: float = count * Config.OFFICE_AREA_PER_AGENT
		# 1.5:1 aspect ratio
		_w = clampf(sqrt(total_area * 1.5), Config.DESKTOP_OFFICE_WIDTH, Config.OFFICE_MAX_WIDTH)
		_h = clampf(_w / 1.5, Config.DESKTOP_OFFICE_HEIGHT, Config.OFFICE_MAX_HEIGHT)
	_rebuild_navigation()
	queue_redraw()


func get_bounds() -> Rect2:
	return Rect2(_m, _m, _w, _h)


func _rebuild_navigation() -> void:
	# Rebuild NavigationRegion2D polygon to match new office bounds
	var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
	if nav_region:
		var poly := NavigationPolygon.new()
		var outline := PackedVector2Array([
			Vector2(_m, _m),
			Vector2(_m + _w, _m),
			Vector2(_m + _w, _m + _h),
			Vector2(_m, _m + _h),
		])
		poly.add_outline(outline)
		poly.make_polygons_from_outlines()
		nav_region.navigation_polygon = poly


func _snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(
		snappedi(int(pos.x), Config.TILE_SIZE),
		snappedi(int(pos.y), Config.TILE_SIZE),
	)


func _collect_objects() -> void:
	_all_objects.clear()
	for child in objects_container.get_children():
		if child is InteractableObject:
			_all_objects.append(child)


var _tint_timer: float = 0.0


func _process(delta: float) -> void:
	_tint_timer += delta
	if _tint_timer >= 2.0:
		_tint_timer = 0.0
		_update_day_night()


func _update_day_night() -> void:
	if _day_night == null:
		return
	var hour := fmod(TimeManager.game_minutes / 60.0, 24.0)
	_day_night.color = _get_day_night_tint(hour)
	# The floor itself is static; only redraw when the hour ticks over so the
	# _draw cost isn't paid every couple of seconds.
	if int(hour) != _last_tint_hour:
		_last_tint_hour = int(hour)
		queue_redraw()


func _draw() -> void:
	var floor_rect := Rect2(_m, _m, _w, _h)

	# Warm floor with a 32px checker at ~3-4% value difference: enough for the
	# eye to anchor scale and motion, quiet enough to stay background.
	draw_rect(floor_rect, FLOOR_BASE)
	var checker := 32
	for ty in range(int(_h / checker) + 1):
		for tx in range(int(_w / checker) + 1):
			if (tx + ty) % 2 == 1:
				var cell := Rect2(
					_m + tx * checker, _m + ty * checker,
					minf(checker, _w - tx * checker), minf(checker, _h - ty * checker)
				)
				if cell.size.x > 0 and cell.size.y > 0:
					draw_rect(cell, FLOOR_ALT)

	# Perimeter walls: a 10px face along the top (rooms have backs), thin
	# baseboards on the other three sides.
	draw_rect(Rect2(_m - 4, _m - 10, _w + 8, 10), WALL_FACE)
	draw_rect(Rect2(_m - 4, _m - 10, _w + 8, 2), WALL_TOP)
	draw_rect(Rect2(_m - 4, _m, _w + 8, 2), Palette.OUTLINE * Color(1, 1, 1, 0.35))
	draw_rect(Rect2(_m - 4, _m + _h, _w + 8, 3), BASEBOARD)
	draw_rect(Rect2(_m - 4, _m, 4, _h), BASEBOARD)
	draw_rect(Rect2(_m + _w, _m, 4, _h), BASEBOARD)

	# Outline the whole room so it reads as one object against the void.
	draw_rect(Rect2(_m - 4, _m - 10, _w + 8, _h + 13), Palette.OUTLINE, false, 1.0)


func _get_day_night_tint(hour: float) -> Color:
	## Whole-canvas modulate. Perceptibly dark at night, warm at the edges of
	## the day, neutral at noon.
	if hour < 5.0 or hour >= 22.0:
		return Color(0.58, 0.62, 0.82)  # Night
	elif hour < 7.0:
		var t := (hour - 5.0) / 2.0
		return Color(0.58, 0.62, 0.82).lerp(Color(1.02, 0.98, 0.92), t)
	elif hour < 17.0:
		return Color(1.0, 1.0, 1.0)  # Day
	elif hour < 20.0:
		var t := (hour - 17.0) / 3.0
		return Color(1.0, 1.0, 1.0).lerp(Color(0.95, 0.82, 0.68), t)
	else:
		var t := (hour - 20.0) / 2.0
		return Color(0.95, 0.82, 0.68).lerp(Color(0.58, 0.62, 0.82), t)
