class_name UITheme
## The one Theme for all in-game UI, built in code (procedural, diffable).
## Assign via UITheme.get_theme() on a panel root; it propagates to children.
## Font: Godot's default at readable sizes for the 640x360 viewport. Swapping
## in a pixel font later is a one-line change in _build().

const FONT_BODY := 10
const FONT_HEADER := 13
const FONT_SMALL := 9

static var _theme: Theme = null


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_BODY

	# Panels
	t.set_stylebox("panel", "PanelContainer", make_panel_style())

	# Labels
	t.set_font_size("font_size", "Label", FONT_BODY)
	t.set_color("font_color", "Label", UIPalette.TEXT)
	t.add_type("HeaderLabel")
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font_size("font_size", "HeaderLabel", FONT_HEADER)
	t.set_color("font_color", "HeaderLabel", UIPalette.ACCENT_WARM)
	t.add_type("DimLabel")
	t.set_type_variation("DimLabel", "Label")
	t.set_font_size("font_size", "DimLabel", FONT_SMALL)
	t.set_color("font_color", "DimLabel", UIPalette.TEXT_DIM)

	# Buttons
	t.set_font_size("font_size", "Button", FONT_BODY)
	t.set_color("font_color", "Button", UIPalette.TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_stylebox("normal", "Button", _button_style(UIPalette.BG_BUTTON))
	t.set_stylebox("hover", "Button", _button_style(UIPalette.BG_BUTTON_HOVER))
	t.set_stylebox("pressed", "Button", _button_style(UIPalette.BG_BUTTON_PRESSED))
	t.set_stylebox("focus", "Button", _button_style(UIPalette.BG_BUTTON))

	# OptionButton / CheckBox inherit Button styleboxes automatically only if
	# unset per-type; set explicitly for consistency.
	t.set_font_size("font_size", "OptionButton", FONT_BODY)
	t.set_stylebox("normal", "OptionButton", _button_style(UIPalette.BG_BUTTON))
	t.set_stylebox("hover", "OptionButton", _button_style(UIPalette.BG_BUTTON_HOVER))
	t.set_stylebox("pressed", "OptionButton", _button_style(UIPalette.BG_BUTTON_PRESSED))
	t.set_font_size("font_size", "CheckBox", FONT_BODY)

	# LineEdit
	t.set_font_size("font_size", "LineEdit", FONT_BODY)
	t.set_color("font_color", "LineEdit", UIPalette.TEXT)
	var input := StyleBoxFlat.new()
	input.bg_color = UIPalette.BG_INPUT
	input.border_color = UIPalette.BORDER_DIM
	input.set_border_width_all(1)
	input.set_corner_radius_all(2)
	input.set_content_margin_all(3)
	t.set_stylebox("normal", "LineEdit", input)

	# RichTextLabel
	t.set_font_size("normal_font_size", "RichTextLabel", FONT_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", FONT_BODY)
	t.set_color("default_color", "RichTextLabel", UIPalette.TEXT)

	# Tooltips
	var tip := StyleBoxFlat.new()
	tip.bg_color = UIPalette.BG_HEADER
	tip.border_color = UIPalette.BORDER
	tip.set_border_width_all(1)
	tip.set_corner_radius_all(2)
	tip.set_content_margin_all(4)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_font_size("font_size", "TooltipLabel", FONT_SMALL)

	# Separators: subtle line
	var sep := StyleBoxLine.new()
	sep.color = UIPalette.BORDER_DIM
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = UIPalette.BORDER_DIM
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)

	return t


static func make_panel_style(border: Color = UIPalette.BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UIPalette.BG_PANEL
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	return style


static func _button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(2)
	style.set_content_margin(SIDE_LEFT, 6)
	style.set_content_margin(SIDE_RIGHT, 6)
	style.set_content_margin(SIDE_TOP, 2)
	style.set_content_margin(SIDE_BOTTOM, 2)
	return style
