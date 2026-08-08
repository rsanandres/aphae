extends Node2D
## The office world. Clean white room with subtle details.

@onready var objects_container: Node2D = $Objects
@onready var agents_container: Node2D = $Agents

var _all_objects: Array[InteractableObject] = []
var _w: float = Config.DESKTOP_OFFICE_WIDTH
var _h: float = Config.DESKTOP_OFFICE_HEIGHT
var _m: float = 10.0  # margin


func _ready() -> void:
	add_to_group("world")
	_collect_objects()
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


var _redraw_timer: float = 0.0


func _process(delta: float) -> void:
	_redraw_timer += delta
	if _redraw_timer >= 5.0:
		_redraw_timer = 0.0
		queue_redraw()


func _draw() -> void:
	var floor_rect := Rect2(_m, _m, _w, _h)

	# Day/night tint based on game time
	var hour := fmod(TimeManager.game_minutes / 60.0, 24.0)
	var tint := _get_day_night_tint(hour)
	var floor_color := Color(0.96, 0.96, 0.97, 0.95).lerp(tint, 0.15)

	draw_rect(floor_rect, floor_color)

	# Subtle tile grid
	var grid_color := Color(0.88, 0.88, 0.9, 0.4)
	for x in range(int(_m), int(_m + _w) + 1, 16):
		draw_line(Vector2(x, _m), Vector2(x, _m + _h), grid_color, 1.0)
	for y in range(int(_m), int(_m + _h) + 1, 16):
		draw_line(Vector2(_m, y), Vector2(_m + _w, y), grid_color, 1.0)

	# Thin border
	draw_rect(floor_rect, Color(0.75, 0.75, 0.78, 0.8), false, 1.0)

	# Soft shadow along bottom and right edges (depth)
	draw_line(Vector2(_m, _m + _h), Vector2(_m + _w, _m + _h), Color(0.7, 0.7, 0.72, 0.5), 2.0)
	draw_line(Vector2(_m + _w, _m), Vector2(_m + _w, _m + _h), Color(0.7, 0.7, 0.72, 0.5), 2.0)


func _get_day_night_tint(hour: float) -> Color:
	if hour < 5.0 or hour >= 22.0:
		return Color(0.7, 0.75, 0.95)  # Night blue
	elif hour < 7.0:
		var t := (hour - 5.0) / 2.0
		return Color(0.7, 0.75, 0.95).lerp(Color(1.0, 0.95, 0.85), t)
	elif hour < 17.0:
		return Color(0.98, 0.97, 0.95)  # Daytime warm white
	elif hour < 20.0:
		var t := (hour - 17.0) / 3.0
		return Color(0.98, 0.97, 0.95).lerp(Color(0.95, 0.85, 0.7), t)
	else:
		var t := (hour - 20.0) / 2.0
		return Color(0.95, 0.85, 0.7).lerp(Color(0.7, 0.75, 0.95), t)
