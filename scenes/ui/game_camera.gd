extends Camera2D
## The game's only camera. Owns zoom, pan, follow, and world bounds limits;
## main.gd routes raw input here. Default zoom 2 = one world pixel drawn 2x2.

var _zoom_level: float = Config.CAMERA_ZOOM_DEFAULT
var _follow_agent: Node2D = null
var _fit_mode: bool = false  # desktop pet: whole office locked in view


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0
	limit_smoothed = true
	_apply_zoom(Config.CAMERA_ZOOM_DEFAULT)
	EventBus.agent_selected.connect(_on_agent_selected)
	center_on_office()
	reset_smoothing()


func _process(_delta: float) -> void:
	_update_limits()
	if _fit_mode:
		_fit_office()
	elif _follow_agent and is_instance_valid(_follow_agent):
		position = _follow_agent.global_position


func zoom_in() -> void:
	_apply_zoom(_zoom_level + Config.CAMERA_ZOOM_STEP)


func zoom_out() -> void:
	_apply_zoom(_zoom_level - Config.CAMERA_ZOOM_STEP)


func zoom_by_factor(factor: float) -> void:
	_apply_zoom(_zoom_level * factor)


func pan_screen(screen_delta: Vector2) -> void:
	## Move the camera by a screen-space delta (drag/gesture). Cancels follow.
	if _fit_mode:
		return
	position -= screen_delta / _zoom_level
	_follow_agent = null


func clear_follow() -> void:
	_follow_agent = null


func follow(agent: Node2D) -> void:
	## External follow request (BroadcastDirector cuts, etc.).
	if not _fit_mode:
		_follow_agent = agent


func focus_position(pos: Vector2) -> void:
	if not _fit_mode:
		_follow_agent = null
		position = pos


func center_on_office() -> void:
	_fit_mode = false
	var bounds := _office_bounds()
	if bounds.size != Vector2.ZERO:
		position = bounds.get_center()
	_apply_zoom(Config.CAMERA_ZOOM_DEFAULT)


func fit_office() -> void:
	## Desktop pet mode: keep the entire office in view.
	_fit_mode = true
	_follow_agent = null
	_fit_office()
	reset_smoothing()


func _fit_office() -> void:
	var bounds := _office_bounds()
	if bounds.size == Vector2.ZERO:
		return
	var view := get_viewport_rect().size
	var fit := minf(view.x / (bounds.size.x + 20.0), view.y / (bounds.size.y + 20.0))
	# Snap down to a half step so pixels stay crisp.
	fit = maxf(floorf(fit * 2.0) / 2.0, Config.CAMERA_ZOOM_MIN)
	_zoom_level = fit
	zoom = Vector2(fit, fit)
	position = bounds.get_center()


func _apply_zoom(level: float) -> void:
	# Never zoom out past "whole limits region in view": with limits smaller
	# than the visible area, Godot pins the camera top-left instead of centering.
	var floor_zoom := Config.CAMERA_ZOOM_MIN
	var bounds := _office_bounds()
	if bounds.size != Vector2.ZERO:
		var view := get_viewport_rect().size
		floor_zoom = maxf(floor_zoom, maxf(
			view.x / (bounds.size.x + 32.0),
			view.y / (bounds.size.y + 32.0)
		))
	_zoom_level = clampf(level, floor_zoom, Config.CAMERA_ZOOM_MAX)
	zoom = Vector2(_zoom_level, _zoom_level)


func punch() -> void:
	## Hard-cut accent: land a hair tight and settle out. Purely cosmetic —
	## _zoom_level is untouched, so the next zoom action overrides cleanly.
	if _fit_mode:
		return
	var target := _zoom_level
	zoom = Vector2(target * 1.08, target * 1.08)
	var tween := create_tween()
	tween.tween_property(self, "zoom", Vector2(target, target), 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_agent_selected(agent: Node2D) -> void:
	if not _fit_mode:
		_follow_agent = agent


func _office_bounds() -> Rect2:
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_method("get_bounds"):
		return world.get_bounds()
	return Rect2()


func _update_limits() -> void:
	var bounds := _office_bounds()
	if bounds.size == Vector2.ZERO:
		return
	var pad := 16.0
	limit_left = int(bounds.position.x - pad)
	limit_top = int(bounds.position.y - pad)
	limit_right = int(bounds.end.x + pad)
	limit_bottom = int(bounds.end.y + pad)
