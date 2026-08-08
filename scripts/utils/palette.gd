class_name Palette
## Curated 12-color cozy office palette from Sweetie-16 + Endesga-32.

# Core
const OUTLINE := Color("#1a1c2c")       # Near-black, selective outlines
const DARK_GRAY := Color("#3a4466")      # Dark accents, shadows
const MID_GRAY := Color("#5a6988")       # Metallic, cool mid-tone
const LIGHT_GRAY := Color("#8b9bb4")     # Light surfaces, cool highlight
const CREAM := Color("#ead4aa")          # Warm cream, backgrounds
const WHITE := Color("#f4f4f4")          # Highlights, eyes

# Wood / furniture
const WOOD_DARK := Color("#733e39")      # Dark wood, legs
const WOOD_MID := Color("#b86f50")       # Medium wood, surfaces
const WOOD_LIGHT := Color("#e4a672")     # Light wood, highlights, skin

# Accents
const WARM_YELLOW := Color("#ffcd75")    # Lamp light, warm glow
const GREEN := Color("#38b764")          # Plants, positive indicators
const BLUE := Color("#41a6f6")           # Screens, tech, cool accent
const RED := Color("#e43b44")            # Alert, negative, coffee machine accent
const ORANGE := Color("#ef7d57")         # Warm mid accent
const PURPLE := Color("#5d275d")         # Deep accent
const TEAL := Color("#257179")           # Cool secondary

# Skin tones for procedural agents (WOOD_LIGHT kept first for save compat
# with sprites that always used it).
const SKIN_TONES: Array[Color] = [
	Color("#e4a672"),
	Color("#f0c8a0"),
	Color("#c68d5e"),
	Color("#9c6a44"),
	Color("#6f4a2f"),
]

# Curated clothing ramp for procedural agents: palette-adjacent, saturated,
# and mutually distinct — replaces uniform HSV pastels that made everyone
# look like the same person in a different wash.
const CLOTHING_COLORS: Array[Color] = [
	Color("#3b5dc9"),  # royal blue
	Color("#38b764"),  # green
	Color("#b55088"),  # magenta
	Color("#ef7d57"),  # orange
	Color("#41a6f6"),  # sky
	Color("#e43b44"),  # red
	Color("#257179"),  # teal
	Color("#d9a740"),  # mustard
	Color("#8e6fc9"),  # lavender
	Color("#265c42"),  # forest
	Color("#a3535e"),  # wine
	Color("#5a6988"),  # slate
]

# Agent-specific hair/clothing palettes
const ALICE_PRIMARY := Color("#3b5dc9")  # Blue uniform
const ALICE_SECONDARY := Color("#29366f")
const BOB_PRIMARY := Color("#38b764")    # Green hoodie
const BOB_SECONDARY := Color("#265c42")
const CLARA_PRIMARY := Color("#b55088")  # Pink/magenta
const CLARA_SECONDARY := Color("#68386c")
const DAVE_PRIMARY := Color("#ef7d57")   # Orange
const DAVE_SECONDARY := Color("#b86f50")
const EMMA_PRIMARY := Color("#41a6f6")   # Light blue/cyan
const EMMA_SECONDARY := Color("#257179")
