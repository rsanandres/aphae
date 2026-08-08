class_name SpriteFactory
## Generates pixel art sprites procedurally. Chibi characters (12x16), furniture (various).
## Characters: 2 idle frames + 4 walk frames.

# --- CHARACTERS (12x16, chibi proportions: big head, small body) ---

static func create_character(primary: Color, secondary: Color, hair_color: Color, skin: Color = Palette.WOOD_LIGHT) -> Array[ImageTexture]:
	## Returns [idle_0, idle_1, walk_0, walk_1, walk_2, walk_3].
	## Frames are outlined on a 14x18 canvas so the silhouette separates from
	## any floor color.
	var frames: Array[ImageTexture] = []
	# Idle frames (bob)
	for frame_idx in range(2):
		var img := Image.create(12, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw_character(img, primary, secondary, hair_color, skin, frame_idx)
		frames.append(ImageTexture.create_from_image(_outlined(img)))
	# Walk frames (4-frame cycle)
	for walk_idx in range(4):
		var img := Image.create(12, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw_character_walk(img, primary, secondary, hair_color, skin, walk_idx)
		frames.append(ImageTexture.create_from_image(_outlined(img)))
	return frames


static func _outlined(src: Image, outline: Color = Palette.OUTLINE) -> Image:
	## Copy src onto a canvas grown by 1px per side and draw a 1px outline
	## around every opaque region (4-connected).
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(src, Rect2i(0, 0, w, h), Vector2i(1, 1))
	for y in range(h + 2):
		for x in range(w + 2):
			if out.get_pixel(x, y).a > 0.01:
				continue
			var touches_opaque := false
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + offset.x
				var ny := y + offset.y
				if nx < 0 or ny < 0 or nx >= w + 2 or ny >= h + 2:
					continue
				var p := out.get_pixel(nx, ny)
				if p.a > 0.01 and not p.is_equal_approx(outline):
					touches_opaque = true
					break
			if touches_opaque:
				out.set_pixel(x, y, outline)
	return out


static func _draw_character(img: Image, primary: Color, secondary: Color, hair: Color, skin: Color, frame: int) -> void:
	var o := Palette.OUTLINE
	var eye := Palette.OUTLINE
	var hair_dark: Color = hair.darkened(0.3)

	# Y offset for idle bob (frame 0 = normal, frame 1 = up 1px)
	var bob := 0 if frame == 0 else -1

	# --- HAIR / TOP OF HEAD (rows 0-2) ---
	_px(img, 3, 0 + bob, hair); _px(img, 4, 0 + bob, hair); _px(img, 5, 0 + bob, hair)
	_px(img, 6, 0 + bob, hair); _px(img, 7, 0 + bob, hair); _px(img, 8, 0 + bob, hair)
	_px(img, 2, 1 + bob, hair); _px(img, 3, 1 + bob, hair); _px(img, 4, 1 + bob, hair_dark)
	_px(img, 5, 1 + bob, hair); _px(img, 6, 1 + bob, hair); _px(img, 7, 1 + bob, hair_dark)
	_px(img, 8, 1 + bob, hair); _px(img, 9, 1 + bob, hair)
	_px(img, 2, 2 + bob, hair); _px(img, 3, 2 + bob, skin); _px(img, 4, 2 + bob, skin)
	_px(img, 5, 2 + bob, skin); _px(img, 6, 2 + bob, skin); _px(img, 7, 2 + bob, skin)
	_px(img, 8, 2 + bob, skin); _px(img, 9, 2 + bob, hair)

	# --- FACE (rows 3-5) ---
	_px(img, 2, 3 + bob, hair); _px(img, 3, 3 + bob, skin); _px(img, 4, 3 + bob, eye)
	_px(img, 5, 3 + bob, skin); _px(img, 6, 3 + bob, skin); _px(img, 7, 3 + bob, eye)
	_px(img, 8, 3 + bob, skin); _px(img, 9, 3 + bob, hair)

	_px(img, 2, 4 + bob, o); _px(img, 3, 4 + bob, skin); _px(img, 4, 4 + bob, skin)
	_px(img, 5, 4 + bob, skin); _px(img, 6, 4 + bob, skin); _px(img, 7, 4 + bob, skin)
	_px(img, 8, 4 + bob, skin); _px(img, 9, 4 + bob, o)

	_px(img, 3, 5 + bob, o); _px(img, 4, 5 + bob, skin); _px(img, 5, 5 + bob, skin)
	_px(img, 6, 5 + bob, skin); _px(img, 7, 5 + bob, skin); _px(img, 8, 5 + bob, o)

	# --- BODY / SHIRT (rows 6-10) ---
	_px(img, 5, 6 + bob, skin); _px(img, 6, 6 + bob, skin)

	_px(img, 3, 7 + bob, secondary); _px(img, 4, 7 + bob, primary); _px(img, 5, 7 + bob, primary)
	_px(img, 6, 7 + bob, primary); _px(img, 7, 7 + bob, primary); _px(img, 8, 7 + bob, secondary)

	for y in range(8, 11):
		_px(img, 3, y + bob, secondary); _px(img, 4, y + bob, primary); _px(img, 5, y + bob, primary)
		_px(img, 6, y + bob, primary); _px(img, 7, y + bob, primary); _px(img, 8, y + bob, secondary)

	for y in range(7, 10):
		_px(img, 2, y + bob, primary); _px(img, 9, y + bob, primary)
	_px(img, 2, 10 + bob, skin); _px(img, 9, 10 + bob, skin)

	# --- LEGS (rows 11-14) ---
	var pants := secondary.darkened(0.15)
	for y in range(11, 14):
		_px(img, 4, y + bob, pants); _px(img, 5, y + bob, pants)
		_px(img, 6, y + bob, pants); _px(img, 7, y + bob, pants)

	_px(img, 3, 14 + bob, o); _px(img, 4, 14 + bob, o)
	_px(img, 7, 14 + bob, o); _px(img, 8, 14 + bob, o)

	if frame == 1:
		_px(img, 3, 15, o); _px(img, 4, 15, o)


static func _draw_character_walk(img: Image, primary: Color, secondary: Color, hair: Color, skin: Color, walk_frame: int) -> void:
	## Walk cycle: 4 frames (stand, left-forward, stand, right-forward)
	var o := Palette.OUTLINE
	var eye := Palette.OUTLINE
	var hair_dark: Color = hair.darkened(0.3)
	var pants := secondary.darkened(0.15)

	# Slight bob on frames 1 and 3 (mid-stride)
	var bob := -1 if (walk_frame == 1 or walk_frame == 3) else 0

	# Draw upper body (same as idle frame 0 + bob)
	# --- HAIR ---
	_px(img, 3, 0 + bob, hair); _px(img, 4, 0 + bob, hair); _px(img, 5, 0 + bob, hair)
	_px(img, 6, 0 + bob, hair); _px(img, 7, 0 + bob, hair); _px(img, 8, 0 + bob, hair)
	_px(img, 2, 1 + bob, hair); _px(img, 3, 1 + bob, hair); _px(img, 4, 1 + bob, hair_dark)
	_px(img, 5, 1 + bob, hair); _px(img, 6, 1 + bob, hair); _px(img, 7, 1 + bob, hair_dark)
	_px(img, 8, 1 + bob, hair); _px(img, 9, 1 + bob, hair)
	_px(img, 2, 2 + bob, hair); _px(img, 3, 2 + bob, skin); _px(img, 4, 2 + bob, skin)
	_px(img, 5, 2 + bob, skin); _px(img, 6, 2 + bob, skin); _px(img, 7, 2 + bob, skin)
	_px(img, 8, 2 + bob, skin); _px(img, 9, 2 + bob, hair)

	# --- FACE ---
	_px(img, 2, 3 + bob, hair); _px(img, 3, 3 + bob, skin); _px(img, 4, 3 + bob, eye)
	_px(img, 5, 3 + bob, skin); _px(img, 6, 3 + bob, skin); _px(img, 7, 3 + bob, eye)
	_px(img, 8, 3 + bob, skin); _px(img, 9, 3 + bob, hair)

	_px(img, 2, 4 + bob, o); _px(img, 3, 4 + bob, skin); _px(img, 4, 4 + bob, skin)
	_px(img, 5, 4 + bob, skin); _px(img, 6, 4 + bob, skin); _px(img, 7, 4 + bob, skin)
	_px(img, 8, 4 + bob, skin); _px(img, 9, 4 + bob, o)

	_px(img, 3, 5 + bob, o); _px(img, 4, 5 + bob, skin); _px(img, 5, 5 + bob, skin)
	_px(img, 6, 5 + bob, skin); _px(img, 7, 5 + bob, skin); _px(img, 8, 5 + bob, o)

	# --- BODY ---
	_px(img, 5, 6 + bob, skin); _px(img, 6, 6 + bob, skin)
	_px(img, 3, 7 + bob, secondary); _px(img, 4, 7 + bob, primary); _px(img, 5, 7 + bob, primary)
	_px(img, 6, 7 + bob, primary); _px(img, 7, 7 + bob, primary); _px(img, 8, 7 + bob, secondary)

	for y in range(8, 11):
		_px(img, 3, y + bob, secondary); _px(img, 4, y + bob, primary); _px(img, 5, y + bob, primary)
		_px(img, 6, y + bob, primary); _px(img, 7, y + bob, primary); _px(img, 8, y + bob, secondary)

	# Arms swing slightly
	match walk_frame:
		0, 2:  # Standing frames - arms normal
			for y in range(7, 10):
				_px(img, 2, y + bob, primary); _px(img, 9, y + bob, primary)
			_px(img, 2, 10 + bob, skin); _px(img, 9, 10 + bob, skin)
		1:  # Left arm forward, right arm back
			for y in range(7, 10):
				_px(img, 2, y + bob, primary); _px(img, 9, y + bob, primary)
			_px(img, 2, 10 + bob, skin); _px(img, 9, 10 + bob, skin)
			_px(img, 1, 9 + bob, skin)  # Left arm extended
		3:  # Right arm forward, left arm back
			for y in range(7, 10):
				_px(img, 2, y + bob, primary); _px(img, 9, y + bob, primary)
			_px(img, 2, 10 + bob, skin); _px(img, 9, 10 + bob, skin)
			_px(img, 10, 9 + bob, skin)  # Right arm extended

	# --- LEGS (walk cycle) ---
	match walk_frame:
		0:  # Stand
			for y in range(11, 14):
				_px(img, 4, y + bob, pants); _px(img, 5, y + bob, pants)
				_px(img, 6, y + bob, pants); _px(img, 7, y + bob, pants)
			_px(img, 3, 14 + bob, o); _px(img, 4, 14 + bob, o)
			_px(img, 7, 14 + bob, o); _px(img, 8, 14 + bob, o)
		1:  # Left foot forward
			# Left leg forward
			_px(img, 3, 11 + bob, pants); _px(img, 4, 11 + bob, pants)
			_px(img, 3, 12 + bob, pants); _px(img, 4, 12 + bob, pants)
			_px(img, 2, 13 + bob, pants); _px(img, 3, 13 + bob, pants)
			_px(img, 2, 14 + bob, o); _px(img, 3, 14 + bob, o)
			# Right leg back
			_px(img, 7, 11 + bob, pants); _px(img, 8, 11 + bob, pants)
			_px(img, 7, 12 + bob, pants); _px(img, 8, 12 + bob, pants)
			_px(img, 8, 13 + bob, pants); _px(img, 9, 13 + bob, pants)
			_px(img, 8, 14 + bob, o); _px(img, 9, 14 + bob, o)
		2:  # Stand (passing)
			for y in range(11, 14):
				_px(img, 4, y + bob, pants); _px(img, 5, y + bob, pants)
				_px(img, 6, y + bob, pants); _px(img, 7, y + bob, pants)
			_px(img, 3, 14 + bob, o); _px(img, 4, 14 + bob, o)
			_px(img, 7, 14 + bob, o); _px(img, 8, 14 + bob, o)
		3:  # Right foot forward
			# Left leg back
			_px(img, 3, 11 + bob, pants); _px(img, 4, 11 + bob, pants)
			_px(img, 3, 12 + bob, pants); _px(img, 4, 12 + bob, pants)
			_px(img, 2, 13 + bob, pants); _px(img, 3, 13 + bob, pants)
			_px(img, 2, 14 + bob, o); _px(img, 3, 14 + bob, o)
			# Right leg forward
			_px(img, 7, 11 + bob, pants); _px(img, 8, 11 + bob, pants)
			_px(img, 7, 12 + bob, pants); _px(img, 8, 12 + bob, pants)
			_px(img, 8, 13 + bob, pants); _px(img, 9, 13 + bob, pants)
			_px(img, 8, 14 + bob, o); _px(img, 9, 14 + bob, o)


static func _px(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)


# --- FURNITURE ---

static func create_desk_sprite() -> ImageTexture:
	var img := Image.create(24, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(1, 23):
		_px(img, x, 3, Palette.WOOD_MID); _px(img, x, 4, Palette.WOOD_MID); _px(img, x, 5, Palette.WOOD_DARK)
	for x in range(1, 23):
		_px(img, x, 2, Palette.WOOD_LIGHT)
	for y in range(6, 14):
		_px(img, 2, y, Palette.WOOD_DARK); _px(img, 3, y, Palette.WOOD_DARK)
		_px(img, 20, y, Palette.WOOD_DARK); _px(img, 21, y, Palette.WOOD_DARK)
	for x in [1, 2, 3, 4, 19, 20, 21, 22]:
		_px(img, x, 14, Palette.OUTLINE)
	for x in range(8, 16):
		_px(img, x, 0, Palette.DARK_GRAY)
	for x in range(8, 16):
		for y in range(0, 2):
			_px(img, x, y, Palette.DARK_GRAY)
	for x in range(9, 15):
		_px(img, x, 0, Palette.BLUE); _px(img, x, 1, Palette.BLUE.darkened(0.2))
	_px(img, 11, 2, Palette.MID_GRAY); _px(img, 12, 2, Palette.MID_GRAY)
	return ImageTexture.create_from_image(_outlined(img))


static func create_coffee_machine_sprite() -> ImageTexture:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(3, 11):
		for y in range(1, 11):
			_px(img, x, y, Palette.MID_GRAY)
	for y in range(1, 11):
		_px(img, 2, y, Palette.DARK_GRAY); _px(img, 11, y, Palette.DARK_GRAY)
	for x in range(2, 12):
		_px(img, x, 0, Palette.DARK_GRAY); _px(img, x, 11, Palette.DARK_GRAY)
	for x in range(3, 11):
		_px(img, x, 1, Palette.LIGHT_GRAY)
	for x in range(3, 11):
		_px(img, x, 2, Palette.RED)
	_px(img, 10, 4, Palette.GREEN)
	_px(img, 6, 7, Palette.DARK_GRAY); _px(img, 7, 7, Palette.DARK_GRAY)
	_px(img, 5, 9, Palette.CREAM); _px(img, 6, 8, Palette.CREAM); _px(img, 7, 8, Palette.CREAM)
	_px(img, 8, 9, Palette.CREAM); _px(img, 5, 10, Palette.CREAM)
	_px(img, 6, 10, Palette.WOOD_LIGHT); _px(img, 7, 10, Palette.WOOD_LIGHT); _px(img, 8, 10, Palette.CREAM)
	for x in range(1, 13):
		_px(img, x, 12, Palette.OUTLINE)
	return ImageTexture.create_from_image(_outlined(img))


static func create_couch_sprite() -> ImageTexture:
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cush := Color("#4a6fa5")
	var cush_dark := Color("#3a5580")
	var cush_light := Color("#6088b8")
	var frame_c := Color("#3a4466")
	for x in range(2, 30):
		for y in range(2, 6):
			_px(img, x, y, cush_dark)
	for x in range(3, 29):
		_px(img, x, 2, cush_light)
	for x in range(2, 30):
		for y in range(6, 11):
			_px(img, x, y, cush)
	for y in range(6, 11):
		_px(img, 15, y, cush_dark); _px(img, 16, y, cush_dark)
	for x in range(3, 14):
		_px(img, x, 6, cush_light)
	for x in range(17, 29):
		_px(img, x, 6, cush_light)
	for y in range(3, 11):
		_px(img, 0, y, frame_c); _px(img, 1, y, cush_dark)
		_px(img, 30, y, cush_dark); _px(img, 31, y, frame_c)
	_px(img, 0, 2, cush_light); _px(img, 1, 2, cush_light)
	_px(img, 30, 2, cush_light); _px(img, 31, 2, cush_light)
	for y in range(11, 14):
		_px(img, 3, y, Palette.OUTLINE); _px(img, 4, y, Palette.OUTLINE)
		_px(img, 27, y, Palette.OUTLINE); _px(img, 28, y, Palette.OUTLINE)
	for x in range(3, 29):
		_px(img, x, 11, frame_c)
	return ImageTexture.create_from_image(_outlined(img))


static func create_water_cooler_sprite() -> ImageTexture:
	var img := Image.create(12, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(4, 8):
		for y in range(0, 5):
			_px(img, x, y, Palette.BLUE.lightened(0.3))
	_px(img, 4, 0, Palette.BLUE); _px(img, 7, 0, Palette.BLUE)
	for x in range(3, 9):
		for y in range(5, 12):
			_px(img, x, y, Palette.LIGHT_GRAY)
	for y in range(5, 12):
		_px(img, 3, y, Palette.MID_GRAY); _px(img, 8, y, Palette.MID_GRAY)
	_px(img, 9, 8, Palette.DARK_GRAY); _px(img, 10, 8, Palette.DARK_GRAY)
	_px(img, 9, 7, Palette.RED); _px(img, 9, 9, Palette.BLUE)
	for x in range(2, 10):
		_px(img, x, 12, Palette.DARK_GRAY)
	for y in range(12, 15):
		_px(img, 3, y, Palette.OUTLINE); _px(img, 8, y, Palette.OUTLINE)
	return ImageTexture.create_from_image(_outlined(img))


static func create_whiteboard_sprite() -> ImageTexture:
	var img := Image.create(28, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(2, 26):
		_px(img, x, 1, Palette.MID_GRAY); _px(img, x, 11, Palette.MID_GRAY)
	for y in range(1, 12):
		_px(img, 2, y, Palette.MID_GRAY); _px(img, 25, y, Palette.MID_GRAY)
	for x in range(3, 25):
		for y in range(2, 11):
			_px(img, x, y, Palette.WHITE)
	for x in range(5, 15):
		_px(img, x, 4, Palette.BLUE)
	for x in range(5, 20):
		_px(img, x, 6, Palette.RED)
	for x in range(5, 12):
		_px(img, x, 8, Palette.GREEN)
	for x in range(4, 24):
		_px(img, x, 12, Palette.DARK_GRAY)
	_px(img, 6, 12, Palette.RED); _px(img, 8, 12, Palette.BLUE); _px(img, 10, 12, Palette.GREEN)
	_px(img, 8, 13, Palette.OUTLINE); _px(img, 8, 14, Palette.OUTLINE)
	_px(img, 19, 13, Palette.OUTLINE); _px(img, 19, 14, Palette.OUTLINE)
	for x in range(6, 12):
		_px(img, x, 15, Palette.OUTLINE)
	for x in range(17, 23):
		_px(img, x, 15, Palette.OUTLINE)
	return ImageTexture.create_from_image(_outlined(img))


static func create_bookshelf_sprite() -> ImageTexture:
	var img := Image.create(20, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(0, 16):
		_px(img, 1, y, Palette.WOOD_DARK); _px(img, 18, y, Palette.WOOD_DARK)
	for x in range(1, 19):
		_px(img, x, 0, Palette.WOOD_DARK); _px(img, x, 5, Palette.WOOD_MID)
		_px(img, x, 10, Palette.WOOD_MID); _px(img, x, 15, Palette.WOOD_DARK)
	var book_colors: Array[Color] = [Palette.RED, Palette.BLUE, Palette.GREEN, Palette.PURPLE, Palette.ORANGE, Palette.TEAL]
	var bx := 3
	for i in range(5):
		var c: Color = book_colors[i % book_colors.size()]
		for y in range(1, 5):
			_px(img, bx, y, c); _px(img, bx + 1, y, c.darkened(0.2))
		bx += 3
	bx = 2
	for i in range(6):
		var c: Color = book_colors[(i + 2) % book_colors.size()]
		for y in range(6, 10):
			_px(img, bx, y, c); _px(img, bx + 1, y, c.darkened(0.15))
		bx += 3
	bx = 4
	for i in range(4):
		var c: Color = book_colors[(i + 4) % book_colors.size()]
		for y in range(11, 15):
			_px(img, bx, y, c); _px(img, bx + 1, y, c.darkened(0.2))
		bx += 3
	return ImageTexture.create_from_image(_outlined(img))


static func create_plant_sprite() -> ImageTexture:
	var img := Image.create(10, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(3, 7):
		for y in range(10, 13):
			_px(img, x, y, Palette.ORANGE)
	_px(img, 2, 10, Palette.ORANGE.darkened(0.2)); _px(img, 7, 10, Palette.ORANGE.darkened(0.2))
	for x in range(2, 8):
		_px(img, x, 13, Palette.ORANGE.darkened(0.3))
	for x in range(3, 7):
		_px(img, x, 9, Palette.WOOD_DARK)
	_px(img, 5, 8, Palette.GREEN.darkened(0.3)); _px(img, 5, 7, Palette.GREEN.darkened(0.3))
	_px(img, 5, 6, Palette.GREEN.darkened(0.2))
	_px(img, 3, 5, Palette.GREEN); _px(img, 4, 4, Palette.GREEN); _px(img, 5, 3, Palette.GREEN)
	_px(img, 6, 4, Palette.GREEN); _px(img, 7, 5, Palette.GREEN)
	_px(img, 4, 5, Palette.GREEN.lightened(0.2)); _px(img, 6, 5, Palette.GREEN.lightened(0.2))
	_px(img, 5, 4, Palette.GREEN.lightened(0.3))
	_px(img, 3, 3, Palette.GREEN.lightened(0.1)); _px(img, 7, 3, Palette.GREEN.lightened(0.1))
	_px(img, 2, 4, Palette.GREEN); _px(img, 8, 4, Palette.GREEN)
	return ImageTexture.create_from_image(_outlined(img))


static func create_radio_sprite() -> ImageTexture:
	var img := Image.create(14, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(2, 12):
		for y in range(3, 9):
			_px(img, x, y, Palette.DARK_GRAY)
	for x in range(2, 12):
		_px(img, x, 2, Palette.MID_GRAY)
	for x in range(3, 7):
		for y in range(4, 8):
			_px(img, x, y, Palette.OUTLINE)
	_px(img, 4, 5, Palette.MID_GRAY); _px(img, 5, 6, Palette.MID_GRAY)
	_px(img, 9, 5, Palette.WARM_YELLOW); _px(img, 10, 5, Palette.WARM_YELLOW)
	_px(img, 9, 6, Palette.ORANGE); _px(img, 10, 6, Palette.ORANGE)
	_px(img, 3, 1, Palette.MID_GRAY); _px(img, 3, 0, Palette.MID_GRAY)
	_px(img, 4, 1, Palette.MID_GRAY)
	_px(img, 11, 4, Palette.GREEN)
	for x in range(1, 13):
		_px(img, x, 9, Palette.OUTLINE)
	return ImageTexture.create_from_image(_outlined(img))


static func create_bed_sprite() -> ImageTexture:
	var img := Image.create(28, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var frame_c := Palette.WOOD_DARK
	var mattress := Color("#6088b8")
	var pillow := Palette.WHITE
	for x in range(1, 5):
		for y in range(1, 8):
			_px(img, x, y, frame_c)
	for x in range(5, 25):
		for y in range(3, 9):
			_px(img, x, y, mattress)
	for x in range(5, 25):
		_px(img, x, 3, mattress.lightened(0.2))
	for x in range(5, 10):
		for y in range(4, 7):
			_px(img, x, y, pillow)
	for x in range(12, 25):
		_px(img, x, 5, mattress.darkened(0.15))
	for x in range(0, 27):
		_px(img, x, 9, frame_c)
	_px(img, 2, 10, Palette.OUTLINE); _px(img, 2, 11, Palette.OUTLINE)
	_px(img, 24, 10, Palette.OUTLINE); _px(img, 24, 11, Palette.OUTLINE)
	for x in range(23, 27):
		for y in range(4, 9):
			_px(img, x, y, frame_c)
	return ImageTexture.create_from_image(_outlined(img))


static func create_from_color(primary: Color) -> Array[ImageTexture]:
	## Generate a character sprite from a primary color. Hair and skin derive
	## deterministically from the color so a saved agent keeps their look.
	var secondary: Color = primary.darkened(0.3)
	var hair_idx := int(primary.h * 137.508) % PersonalityGenerator.HAIR_TONES.size()
	var hair_color: Color = PersonalityGenerator.HAIR_TONES[hair_idx]
	var skin_idx := int(primary.r * 255.0 + primary.g * 97.0 + primary.b * 31.0) % Palette.SKIN_TONES.size()
	return create_character(primary, secondary, hair_color, Palette.SKIN_TONES[skin_idx])


# --- Character presets for each personality ---

static func create_alice() -> Array[ImageTexture]:
	return create_character(Palette.ALICE_PRIMARY, Palette.ALICE_SECONDARY, Color("#b86f50"))

static func create_bob() -> Array[ImageTexture]:
	return create_character(Palette.BOB_PRIMARY, Palette.BOB_SECONDARY, Color("#3a4466"))

static func create_clara() -> Array[ImageTexture]:
	return create_character(Palette.CLARA_PRIMARY, Palette.CLARA_SECONDARY, Color("#e43b44").lightened(0.3))

static func create_dave() -> Array[ImageTexture]:
	return create_character(Palette.DAVE_PRIMARY, Palette.DAVE_SECONDARY, Color("#5a6988"))

static func create_emma() -> Array[ImageTexture]:
	return create_character(Palette.EMMA_PRIMARY, Palette.EMMA_SECONDARY, Color("#1a1c2c"))
