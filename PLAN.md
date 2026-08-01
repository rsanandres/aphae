# Ayle — Confessional Cam Roadmap

**Status:** M1 in progress · **Branch:** `feat/confessional-cam` · **Last updated:** 2026-07-31

Shared working plan. Other agents: read the **Coordination** and **Environment** sections
before touching anything — they record findings that are expensive to rediscover.

---

## Coordination for other agents

- Work happens on `feat/confessional-cam`, **not** `main`.
- Milestones are tracked as tasks M1.1–M6. Claim one before starting so we don't collide.
- **M1 needs no Godot.** M2+ do. If you're waiting on the engine, take M1 work.
- Everything lives under this repo. Don't modify files outside it.
- Confine temp/scratch files to a scratch dir — never commit them.

## Environment status

| Dependency | State | Consequence |
|---|---|---|
| **Godot 4.6** | ✅ installed — portable build, see "Test vehicle" below | M2+ unblocked; parse check + headless run both pass |
| **Ollama** | ⚠️ installed at `%LOCALAPPDATA%\Programs\Ollama`, **service not running** | LLM calls fail until `ollama serve` |
| **Ollama model** | ❓ unverified (service down) | need `ollama pull smollm2:1.7b` |
| **`addons/gdllama`** | ❌ empty dir, not committed | bundled LLM backend won't load |
| **`addons/godotsteam`** | ❌ empty dir, not committed | SteamManager no-ops (by design) |
| **`models/*.gguf`** | ❌ gitignored ("ship with builds") | no bundled model |

**Net effect:** the LLM chain resolves bundled (missing) → Ollama (down) → **heuristic fallback**.
The game runs and confessionals appear, but they're canned personality-flavored lines until
Ollama is up. This is by design — `AgentBrain` degrades the same way.

### Verification without Godot

Static checks that caught real issues so far:
1. Confirm every external symbol exists (`grep` the definition) before trusting a call.
2. Structural pass — balanced delimiters, **tab** indentation (repo convention), no orphaned blocks.
3. Prompt templates: every `{token}` in `resources/prompts/*.txt` must be supplied by the
   caller's `PromptBuilder.build()` dict, or it leaks literally into the prompt.

### Once Godot lands — primary test vehicle

```bash
godot --headless -e --quit-after 5     # parse check
./run_headless.sh 10 3                 # 10 agents at 3x, no rendering
```

`scenes/main/headless_sim.gd` prints `CAM[Day N HH:MM] Speaker: "line"` for every
confessional, so the whole pipeline is verifiable from stdout with no GUI.

---

## Milestones

### ✅ M0 — Confessional Cam v1 (done)

Reality-TV talking heads. When drama strikes, an involved agent cuts away to a confessional
booth and reacts in first person, in their own voice. Complements `Narrator`, which tracks
storylines in dry third person — this is the character-voice layer on top.

| File | Role |
|---|---|
| `autoloads/confessional_director.gd` | Observes dramatic EventBus signals, builds in-character quips |
| `scripts/data/confessional.gd` | Data class (`to_dict`/`from_dict` ready for persistence) |
| `resources/prompts/confessional.txt` | LLM prompt template |
| `scenes/ui/confessional_toast.gd` | Lower-third cutaway with blinking REC dot |
| `scenes/ui/confessional_feed.gd` | Scrollable history panel |

Wired into `event_bus.gd` (`confessional_recorded`), `hud.gd` (**C** key, CAM button, context
menu), `headless_sim.gd` (stdout logging), `project.godot` (autoload).

**Design invariants — preserve these:**
- **Purely additive.** It only *listens* to signals other systems already emit. It must never
  alter their behavior.
- **Degrades offline.** LLM at `Priority.LOW`, heuristic fallback always available.
- **Rate limited.** `COOLDOWN` + single in-flight request + `PENDING_TIMEOUT` so a lost
  callback can't jam the feed.

### 🔨 M1 — Complete the feature (no Godot needed)

- ✅ **M1.1 — Persist confessionals in `SaveManager`** (save v4). The restore sits *outside*
  the `version >= 2` gate on purpose: an absent key loads as empty, so pre-v4 slots stay
  valid. Non-dict entries skipped; trims from the front so newest survive. The latest quip
  also shows in the "While you were away" load summary.
- ✅ **M1.2 — Episode recap.** `scripts/utils/episode_recap.gd` assembles shareable Markdown
  from storylines + confessionals. **Pure synchronous** — storylines already carry LLM
  summaries, so no LLM call and no async. Viewer at **E** (`scenes/ui/recap_panel.gd`),
  exports to `user://recaps/`, and renders on the game-over overlay with a Save Recap button.
- **M1.3 — Achievements.** None of the existing 20 cover confessionals.
- **M1.4 — Cleanup.** Remove 4 commented-out dead signals in `event_bus.gd`
  (`romance_ended`, `narrator_insight`, `game_paused`, `game_resumed`). Fix
  `Narrator._generate_title()`, which truncates raw event text into titles like
  `"Maya's relationship with Devon chan..."`.

### 🧪 M2 — Validate & tune (blocked on Godot)

Parse check → headless smoke test → start Ollama and compare LLM vs heuristic quality →
GUI check (toast vs icon bar collision; layout at 320×214 and 960×640) → tune `COOLDOWN`
(currently 8.0s, a conservative guess) based on how much good material gets dropped.

### 🔁 M3 — Confessionals feed agent memory

Turn confessionals into `MemoryEntry` records so an agent who trash-talked someone on camera
*remembers* it, and it colors later behavior. Converts a cosmetic layer into a real simulation
loop. **Medium risk — changes simulation behavior. Validate at runtime after M2.**

### 🚀 M4 — Ship

Merge/PR, push, capture a demo GIF of cutaways firing during a live run.

### 🎭 M5 — Social deduction mode (stretch)

Hidden-role game: the Drama Director assigns one agent a secret subversive goal; others gossip,
accuse, and vote using the existing conversation/relationship systems. Much stronger now that
Confessional Cam exists — agents lie to camera about their secret role.

### 📱 M6 — Mobile port (stretch)

Feasible, but a real project — the interaction model, not the port, is the cost.

**In favor:** pure GDScript (78 files, ~12.7k LOC), no native deps beyond optional addons;
`stretch/mode="canvas_items"` with `aspect="expand"` already scales; 320×214 pixel art suits
small screens; Godot exports to Android/iOS natively.

**Blockers:**

| Blocker | Detail |
|---|---|
| No touch input | Zero `InputEventScreenTouch`/`ScreenDrag`. All interaction is keyboard + right-click menu |
| No platform checks | Zero `OS.get_name()` / `OS.has_feature()` anywhere |
| Renderer | `rendering_method` unset → `forward_plus`. Mobile wants `mobile` / `gl_compatibility` |
| UI scale | Font sizes 9–10px; panels sized in absolute px |
| Export presets | Only Windows / Linux / macOS configured |
| Desktop-only features | Per-pixel transparency and desktop-pet mode are meaningless on mobile |
| LLM | Ollama impossible on-device; GDLlama 1.7B is slow/hot → heuristic-only |

---

## Gotchas discovered

- **`Config.MAX_AGENTS_DESKTOP := 3` is not about desktop-vs-mobile.** It's the *desktop pet*
  overlay (480×320). There is no mobile awareness in the codebase.
- **`set_v_scroll` is correct on Godot 4** — `ScrollContainer.scroll_vertical` binds to
  `set_v_scroll`/`get_v_scroll`. Matches `narrative_log.gd`. Don't "fix" it to `set_scroll_vertical`.
- **GDLlama is referenced dynamically** in `llm_backend_bundled.gd` (`var _gdllama: Node`, guarded
  by `has_method`/`has_signal`) specifically to avoid a hard dependency. Keep it that way — the
  missing addon degrades instead of crashing.
- **The `/Users/raph/...` path in `CLAUDE.md` is a macOS doc example only.** The project is
  cross-platform; `export_presets.cfg` ships Windows, Linux, and macOS presets.
- Repo is `aphae`; the project/product name is **Ayle**.
- **`Time.get_datetime_string_from_system()` contains colons**, which are illegal in Windows
  filenames. Sanitize before using it in a path — `EpisodeRecap._file_stamp()` does.
- **Storylines and confessionals outlive their agents.** After a total party death
  `AgentManager.agents` is empty, so anything summarizing a run must derive its cast from
  storylines/confessionals rather than the live agent list.
