class_name UIManager
extends Node
## Owns the overlay policy: which panels exist, which may be open together,
## and what Esc closes. HUD registers panels here and routes shortcuts through
## toggle(); direct panel.close() calls (X buttons) stay valid because closing
## never violates the one-exclusive-overlay invariant.
##
## Kinds:
##  EXCLUSIVE — center overlays (producer, relationships, ...): opening one
##              closes the others and any modal.
##  MODAL     — settings/achievements/save picker: sit above, Esc-first.
##  DOCK      — narrative log, inspector: coexist with everything.

enum Kind { EXCLUSIVE, MODAL, DOCK }

var _panels: Dictionary = {}  # name -> {control, kind}

# Toast stack (top-center, max 3, newest on top)
const MAX_TOASTS := 3
var _toast_box: VBoxContainer = null


func register(panel_name: String, control: Control, kind: Kind) -> void:
	_panels[panel_name] = {"control": control, "kind": kind}


func toggle(panel_name: String) -> void:
	var entry: Dictionary = _panels.get(panel_name, {})
	if entry.is_empty():
		return
	var control: Control = entry["control"]
	if control.visible:
		_hide(control)
	else:
		open(panel_name)


func open(panel_name: String) -> void:
	var entry: Dictionary = _panels.get(panel_name, {})
	if entry.is_empty():
		return
	var kind: Kind = entry["kind"]
	if kind != Kind.DOCK:
		for other_name in _panels:
			if other_name == panel_name:
				continue
			var other: Dictionary = _panels[other_name]
			if other["kind"] != Kind.DOCK and (other["control"] as Control).visible:
				_hide(other["control"])
	_show(entry["control"])


func close(panel_name: String) -> void:
	var entry: Dictionary = _panels.get(panel_name, {})
	if not entry.is_empty():
		_hide(entry["control"])


func close_top() -> bool:
	## Esc: close the topmost thing. Modals first, then the exclusive overlay.
	## Docks are left alone. Returns false if nothing was open.
	for kind in [Kind.MODAL, Kind.EXCLUSIVE]:
		for panel_name in _panels:
			var entry: Dictionary = _panels[panel_name]
			if entry["kind"] == kind and (entry["control"] as Control).visible:
				_hide(entry["control"])
				return true
	return false


func _show(control: Control) -> void:
	if control.has_method("open"):
		control.open()
	elif control.has_method("toggle") and not control.visible:
		control.toggle()
	else:
		control.visible = true


func _hide(control: Control) -> void:
	if control.has_method("close"):
		control.close()
	elif control.has_method("toggle") and control.visible:
		control.toggle()
	else:
		control.visible = false


# --- Toasts ----------------------------------------------------------------

func setup_toasts(layer: CanvasLayer) -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.theme = UITheme.get_theme()
	_toast_box.anchor_left = 0.5
	_toast_box.anchor_right = 0.5
	_toast_box.anchor_top = 0.0
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.offset_left = -140
	_toast_box.offset_right = 140
	_toast_box.offset_top = 24
	_toast_box.add_theme_constant_override("separation", 4)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_toast_box)


func add_toast(toast: Control) -> void:
	## Newest on top; cap the stack so simultaneous events cannot pile up
	## at identical coordinates the way the old free-floating toasts did.
	if _toast_box == null:
		return
	while _toast_box.get_child_count() >= MAX_TOASTS:
		var oldest := _toast_box.get_child(_toast_box.get_child_count() - 1)
		_toast_box.remove_child(oldest)
		oldest.queue_free()
	_toast_box.add_child(toast)
	_toast_box.move_child(toast, 0)
