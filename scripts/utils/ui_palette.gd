class_name UIPalette
## Single source of truth for UI chrome colors. World/sprite colors live in
## Palette; this file covers panels, text, and accents so every overlay stops
## inventing its own near-identical dark background.

const BG_PANEL := Color(0.08, 0.08, 0.11, 0.97)
const BG_HEADER := Color(0.11, 0.11, 0.15, 1.0)
const BG_BUTTON := Color(0.15, 0.15, 0.2, 0.9)
const BG_BUTTON_HOVER := Color(0.24, 0.24, 0.33, 1.0)
const BG_BUTTON_PRESSED := Color(0.3, 0.3, 0.42, 1.0)
const BG_INPUT := Color(0.12, 0.12, 0.16, 1.0)

const BORDER := Color(0.32, 0.34, 0.42, 0.9)
const BORDER_DIM := Color(0.22, 0.23, 0.28, 0.8)

const TEXT := Color(0.88, 0.88, 0.92)
const TEXT_DIM := Color(0.62, 0.62, 0.7)
const TEXT_FAINT := Color(0.45, 0.45, 0.52)

const ACCENT_WARM := Color(0.95, 0.85, 0.55)   # titles, highlights
const ACCENT_COOL := Color(0.55, 0.85, 1.0)    # producer / informational
const ACCENT_POS := Color(0.5, 0.9, 0.6)       # success, agreement
const ACCENT_NEG := Color(1.0, 0.55, 0.45)     # errors, refusals, rivalry
const ACCENT_ROMANCE := Color(1.0, 0.55, 0.7)
const ACCENT_REC := Color(1.0, 0.45, 0.45)     # confessional REC red


static func drama_color(score: float) -> Color:
	if score >= 8.0:
		return Color(1.0, 0.4, 0.3)
	elif score >= 5.0:
		return Color(1.0, 0.75, 0.3)
	elif score >= 3.0:
		return Color(0.8, 0.8, 0.5)
	return Color(0.6, 0.6, 0.7)
