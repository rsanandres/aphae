extends Node
## Global configuration.

# Needs
const NEED_MAX := 100.0
const NEED_CRITICAL_THRESHOLD := 20.0
var NEED_DECAY_BASE := {
	NeedType.Type.ENERGY: 0.15,
	NeedType.Type.HUNGER: 0.1,
	NeedType.Type.SOCIAL: 0.08,
	NeedType.Type.PRODUCTIVITY: 0.12,
	NeedType.Type.HEALTH: 0.02,
}

# Agent
const AGENT_MOVE_SPEED := 40.0  # pixels per second (slower for desktop feel)
const AGENT_THINK_INTERVAL := 5.0  # real seconds between think ticks (slower = less LLM load)
const MAX_AGENTS_DESKTOP := 3  # fewer agents in desktop mode

# Health & Aging
const AGENT_LIFESPAN_MIN := 80  # game-days
const AGENT_LIFESPAN_MAX := 120
const HEALTH_DECAY_BASE := 0.02  # per game-minute when senior

# Tiles
const TILE_SIZE := 16

# Camera. Default zoom 2 renders each world pixel as 2x2 viewport pixels,
# so the 640x360 viewport shows a 320x180 slice of the world.
const CAMERA_ZOOM_MIN := 1.0
const CAMERA_ZOOM_MAX := 6.0
const CAMERA_ZOOM_STEP := 0.5
const CAMERA_ZOOM_DEFAULT := 2.0

# Desktop mode
const DESKTOP_WINDOW_WIDTH := 480
const DESKTOP_WINDOW_HEIGHT := 320
# Default office must fit the camera's 320x180 view at default zoom,
# including the 10px world margin on every side.
const DESKTOP_OFFICE_WIDTH := 300
const DESKTOP_OFFICE_HEIGHT := 160

# Conversation
const CONVERSATION_TURNS := 4  # exchanges per conversation
const CONVERSATION_LINE_DURATION := 3.0  # seconds to show each speech bubble

# Romance (tunable: these gate how fast organic crushes form)
const ROMANCE_GROWTH_BASE := 1.5  # romantic_interest per positive conversation
const ROMANCE_CRUSH_THRESHOLD := 40.0  # crossing this sets CRUSHING status

# Expanded mode / scaling
const OFFICE_AREA_PER_AGENT := 3000  # px^2 per agent for dynamic sizing
const OFFICE_MAX_WIDTH := 960
const OFFICE_MAX_HEIGHT := 640
var MAX_AGENTS_EXPANDED: int = 50

# Tiered think scheduling (Phase 2)
const THINK_TIER_ACTIVE_INTERVAL := 3.0   # near camera/selected
const THINK_TIER_NORMAL_INTERVAL := 8.0   # in viewport
const THINK_TIER_BACKGROUND_INTERVAL := 20.0  # off-screen, heuristic-only
const LLM_QUEUE_MAX := 16

# Spatial grid
const SPATIAL_GRID_CELL_SIZE := 64

# Social groups
const GROUP_MIN_SIZE := 3
const GROUP_AFFINITY_THRESHOLD := 25.0

# Bundled LLM
const BUNDLED_MODEL_FILENAME := "smollm2-1.7b-instruct-q4_k_m.gguf"
const LLM_CONTEXT_SIZE := 2048
const LLM_MAX_PREDICT := 200
