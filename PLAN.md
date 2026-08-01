# Ayle — Working Plan

**The single source of truth for this project.** If you are an agent joining this repo, read
this file before touching anything. It records decisions, environment setup, and findings that
are expensive to rediscover — several entries here exist because someone already lost an hour
to them.

**Status:** M0–M4 and M8 shipped · **Branch:** `main` · **Open:** M2 (GUI only), M7
**Maintainer:** this file is owned and kept current. Amend it when you learn something; do not
let it drift. Two claims in it have already been proven false and corrected — a stale doc is
worse than no doc, because it is trusted.

**Scope note:** this began as the Confessional Cam roadmap and has outgrown that. It now covers
the whole feature programme, including producer controls and the player-agency backlog.

---

## Priority order — build in this sequence

Not a wish list. Each phase makes the next one possible or better, so **do them in order**.
Items inside a phase are independent and can run in parallel.

### 🟠 Phase 0 — Validate what already exists

| Item | Status | Needs |
|---|---|---|
| **M2 — GUI check** | ✅ **done** (`e8c5e9b`) | — |
| **M4 — demo GIF** | ❌ open | windowed Godot |

**The GUI check was worth doing — it found six real defects in one pass**, none of which any
headless run could have seen. The viewport is **320×214** and every offset is authored in that
space:

| Defect | Was | Now |
|---|---|---|
| Icon bar clipped both ends | 13 buttons ≈358px in a 320px viewport — pause and half of SET unreachable | buttons 20px, gaps 1px |
| Producer panel off-screen | `250→490` (+170px) | `78→308` |
| Story feed off-screen | `250→470` (+150px) | `90→310` |
| Relationship web off-screen | `100→380` (+60px) | `20→300` |
| Agent inspector below screen | `bottom 280` in a 214-tall viewport | `24→200` |
| **Narrative log offsets silently ignored** | `anchors_preset` assigned *after* offsets, which resets them — the log started above the screen top and sprayed text over the world | anchors first, then offsets |

That last one is the trap worth remembering: **set anchors before offsets, always.** Assigning
`anchors_preset` discards any offsets already set, and it fails silently.

Confirmed fine: the confessional toast sits cleanly above the icon bar — the collision we
expected is not real.

**Harness:** `scenes/main/gui_check.tscn` boots the real game in a window, drives it with real
key events, and saves PNGs of every overlay at both window sizes to `user://gui_check/`. It
**must not** be run headless (no rendering → blank captures). Re-run it after any UI change.

### ✅ Phase 1 — Done and pushed

`M1.3` and `M1.4` are complete (`d050858`, `b5e8a7f`). Those files are no longer claimed.

### 🟢 Phase 2 — Make agents *want* things

| Item | Effort | Needs |
|---|---|---|
| **Goals that resolve** | medium | Phase 0 |

`PersonalityProfile.goals` is decoration today: interpolated into prompts
(`agent_brain.gd:88`, `conversation_instance.gd:269`) and never pursued, achieved, or failed.
Give goals real progress and resolution, emitting a `narrative_event` when one lands.

**Why here:** agents currently drift. Goals give them intent, which every later feature reads
from — and **a secret is just a goal an agent is hiding**, so this is the structural precursor
to Phase 4. Cheapest change on this list with the largest downstream effect.

### 🔵 Phase 3 — Let information move between agents

| Item | Effort | Needs |
|---|---|---|
| **Rumour propagation** | medium | M8 ✅, M3 ✅ |

Planting a rumour works (M8); it does not *spread*. Let memories pass agent-to-agent through
conversation, distorting as they go.

**Why here:** it creates information asymmetry — different agents believing different things.
Without it a secret cannot leak, and a secret that cannot leak carries no tension.

### 🟣 Phase 4 — The payoff

| Item | Effort | Needs |
|---|---|---|
| **M7 — Secrets & lies** | large | Phase 2 + Phase 3 |

Agents hold a private truth, deny it in conversation, and admit it to the confessional camera.
The player knows more than the cast: dramatic irony, not just drama.

**Not purely additive** — the lying lives inside `ConversationInstance`, so it changes what
agents say. Validate at runtime, not by static review.

### ⚫ Phase 5 — A game on top of the simulation

| Item | Effort | Needs |
|---|---|---|
| **M5 — Social deduction** | large | Phase 4 |

Hidden roles, accusations, voting. This is Phase 4 plus a win condition — attempting it before
secrets exist means building the same machinery twice.

### Unscheduled

**M6 — mobile port.** A real project in its own right; the interaction model, not the port, is
the cost. See its section for the blocker list.

**Before claiming anything:** run `git status`. A modified file is someone's in-flight work.

---

## Coordination for other agents

- **Work happens on `main`.** `feat/confessional-cam` was merged and is finished — do not
  branch from it. (This line previously said the opposite; it went stale at the merge.)
- Milestones run M0–M8 plus the player-agency backlog. Claim one before starting.
- **Stage explicit paths. Never `git add -A` or `git commit -a`.** This has already gone
  wrong once: an `add -A` swept another agent's uncommitted work into an unrelated commit,
  so three separate features now live inside one titled "Feed confessionals back into agent
  memory". Nothing was lost, but the history is misleading.
- **Before editing, run `git status`.** A modified file is someone's in-flight work — leave
  it alone and pick something else. Running their tests is fine; editing their files is not.
- Everything lives under this repo. Don't modify files outside it.
- Confine temp/scratch files to a scratch dir — never commit them.
- **Correct this file when you prove it wrong.** Two claims here have already been falsified
  (the branch line above; "LLM fallbacks are the degradation path working, not a defect").
  A stale doc costs the next agent a full investigation.

## Environment status

| Dependency | State | Consequence |
|---|---|---|
| **Godot 4.6** | ✅ installed — portable, `C:\Users\quort\Godot\Godot_v4.6-stable_win64.exe` (not on PATH) | M2+ unblocked; parse check + headless run + integration test all pass |
| **Ollama** | ✅ works, but **only on port 11500** — 11434 is unusable on this machine (see gotchas) | start with `OLLAMA_HOST=127.0.0.1:11500 ollama serve` |
| **Ollama model** | ✅ `gemma3:latest` (4.3B Q4_K_M). `smollm2:1.7b` — the project default — is **not** installed | point `ollama_model` at `gemma3:latest`, or pull smollm2 |
| **`addons/gdllama`** | ❌ empty dir, not committed | bundled LLM backend won't load |
| **`addons/godotsteam`** | ❌ empty dir, not committed | SteamManager no-ops (by design) |
| **`models/*.gguf`** | ❌ gitignored ("ship with builds") | no bundled model |

**Net effect:** with Ollama up the chain resolves bundled (missing) → **Ollama**. Without it,
→ heuristic fallback. Both paths are verified. To use Ollama, write
`user://settings.cfg` (`%APPDATA%\Godot\app_userdata\Ayle\settings.cfg`):

```ini
[llm]

backend="ollama"
ollama_url="http://127.0.0.1:11500"
ollama_model="gemma3:latest"
```

Quality difference is stark. Heuristic: *"I keep expecting them to walk back in."* Same event
via gemma3: *"Dios mio, it's* triste*. Just… *triste*."* — and a second agent in the same run
produced *"Her rejection is a cruel, obsidian bloom upon my otherwise perfect day."*
Distinct voices per personality, which the canned lines cannot do.

~~Individual LLM requests still fail sometimes and fall back mid-run — observed once in a
13-check pass. That is the degradation path working, not a defect.~~ **This was wrong — it was
a defect.** gemma3 routinely closes a JSON string with a typographic quote instead of `"`:

```
{ "answer": "Oh, it's lovely! ... ”}
```

The payload will not parse, so the answer was generated and then thrown away. Measured **5 of
8** responses malformed this way. Not truncation — it fails identically at `num_predict` 150
and 300. `llm_backend_ollama.gd` now normalises typographic quotes and trailing padding and
retries; that recovered **8 of 8**. The repair runs only after a parse has already failed, so
it cannot alter a well-formed response.

**Residual fallbacks are a timeout, not a parse failure.** `TIMEOUT_SEC := 30.0` in
`llm_backend_ollama.gd` can be exceeded by a *cold* gemma3 load plus generation, so the first
request after the model unloads still degrades. Left as-is deliberately: raising it means a
stuck request occupies the queue longer. Warm the model if you need the first call to land.

### Verification without Godot

Still useful for a fast inner loop before spending a Godot run. These caught real issues:
1. Confirm every external symbol exists (`grep` the definition) before trusting a call.
2. Structural pass — balanced delimiters, **tab** indentation (repo convention), no orphaned blocks.
3. Prompt templates: every `{token}` in `resources/prompts/*.txt` must be supplied by the
   caller's `PromptBuilder.build()` dict, or it leaks literally into the prompt.

### Test vehicle — Godot has landed

Portable build, no system install, at a **persistent** path that survives a new session:

```
C:\Users\quort\Godot\Godot_v4.6-stable_win64_console.exe
```

Use the `_console.exe` variant — the plain `.exe` detaches and gives no stdout. If it is ever
missing, re-download `Godot_v4.6-stable_win64.exe.zip` (79,418,197 bytes) from
`https://github.com/godotengine/godot/releases/download/4.6-stable/` and extract there.

**Match 4.6 exactly** — `project.godot` declares `config/features=PackedStringArray("4.6", ...)`.
Opening it in 4.7 can rewrite that file, which shows up as an unwanted repo change.

**Always pass `--audio-driver Dummy`.** Every run below includes it. The game generates audio
procedurally, so a test run makes noise on the owner's machine — headless runs included. This
is a standing request from the repo owner, not a preference. Do not omit it.

```bash
G="C:/Users/quort/Godot/Godot_v4.6-stable_win64_console.exe"
"$G" --headless --path . --audio-driver Dummy -e --quit-after 5                          # parse check — exit 0
"$G" --headless --path . --audio-driver Dummy res://scenes/main/confessional_test.tscn   # 13/13 pass
"$G" --headless --path . --audio-driver Dummy res://scenes/main/headless_sim.tscn -- --agents=12 --speed=3
```

Pass a scene path directly rather than using `run_headless.sh` — the script `sed`s
`run/main_scene` in `project.godot` and restores it via an `EXIT` trap, which corrupts the
file if the run is killed. Passing the scene leaves `project.godot` untouched.

**Organic drama is slow.** Measured: a 10-minute soak at 3× with 12 agents reached Day 1
10:43 and produced exactly **one** confessional. (Wall-clock lags the nominal 3× badly in
headless — 600 real seconds bought ~163 game-minutes, not 1800.) Use
`confessional_test.tscn` to exercise the pipeline; reserve `headless_sim` for soaks.

That soak did confirm the organic path end to end, and the quip came from the
`neuroticism > 0.6` branch, so personality conditioning works on live agents.

**`COOLDOWN = 8.0` needs no tuning.** At roughly one confessional per ten minutes it never
binds. It exists to absorb bursts — a mass-casualty event or a rivalry cascade firing several
signals in one frame — not to throttle steady state. Lowering it would change nothing;
raising it would risk dropping the only quip in a long stretch.

`ObjectDB instances leaked at exit` on shutdown is a benign artifact of quitting mid-frame,
not a defect in this feature.

`scenes/main/headless_sim.gd` prints `CAM[Day N HH:MM] Speaker: "line"` for every
confessional, so the whole pipeline is verifiable from stdout with no GUI.

**Verified end-to-end** (heuristic path; Ollama still down): all six trigger paths fire with
correct speaker/kind/line — confession, romance, high-importance narrative event, rivalry,
death (a survivor reacts), host day recap — plus both negative cases (cooldown suppresses
back-to-back quips; importance < 6 fires nothing). Harness: `scenes/main/confessional_test.tscn`.

**Two findings worth not rediscovering:**
1. **`headless_sim.gd` is broken on `main`** (pre-existing, not ours): `_build_world` assigns
   `office.gd` to the world node *before* adding its `Objects`/`Agents` children, so every
   `@onready` resolves to null and **no objects are ever placed**. Agents can't eat, sleep, or
   use desks — needs decay unopposed. Fix by adding the children before `set_script`.
2. Signals deliver **synchronously**, so a test must sample its "before" count *prior* to
   `emit()`. LLM-backed quips, by contrast, arrive later via callback — assert on both.

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
- ✅ **M1.3 — Achievements.** Four added, bringing the set to **24**: Caught on Camera (first
  confessional), Ensemble Cast (every living agent has faced the camera), Press Tour (25
  recorded), Sweeps Week (host recap at peak drama). Ensemble Cast tracks speakers **per
  session** — the roster changes as agents are born and die, so persisting names would unlock
  it against agents who never spoke — and requires three living agents.
- ✅ **M1.4 — Cleanup.** Four dead commented-out signals removed from `event_bus.gd` (verified
  zero references first). `Narrator._generate_title()` now names the cast — "Maya & Devon",
  "Maya, Devon & 2 more" — instead of cutting raw event text at 37 chars into
  `"Maya's relationship with Devon change..."`. These titles are player-visible in the story
  feed until the LLM writes a real one. The no-agent fallback cuts on a word boundary.

### 🧪 M2 — Validate & tune (**GUI check only** — no longer blocked)

Godot is installed, so this is mostly done:

- ✅ Parse check — exit 0
- ✅ Headless smoke test — `headless_sim` runs, agents spawn, converse, use objects
- ✅ LLM vs heuristic compared — see Environment. The gap is large and in the LLM's favour
- ✅ `COOLDOWN` resolved at 8.0s — measured, never binds, needs no tuning
- ❌ **GUI check — never done.** Toast vs icon-bar collision, and layout at 320×214 (desktop
  pet) and 960×640. The icon bar has since gained CAM, EP and DIR buttons and its width was
  widened twice, all unverified in a window.

**This is the largest remaining risk in the project.** Every feature shipped so far was
validated headless, which cannot see a layout defect.

### ✅ M3 — Confessionals feed agent memory

A confessional is no longer a dead end. `agent.gd` subscribes to `confessional_recorded` and,
when it is the speaker, stores the quip as a `REFLECTION` — landing it in the retrieval pool
`AgentBrain` already queries, so an agent who trash-talked someone on camera carries that into
later decisions instead of contradicting themselves an hour later.

**The mutation lives in `agent.gd`, not `ConfessionalDirector`** — deliberately. Writing to
agent memory from the director would have broken its "purely additive, only listens" invariant.
Putting the subscription on the agent keeps the director observational and matches how
`agent.gd` already handles `day_changed` / `agent_selected`. Preserve this split.

Weighting by kind: tragedy 7.0 (`grief`, `decay_protected` — what you said about a death is a
landmark), romance 6.0 (`vulnerable`), rivalry 5.0 (`defiance`), everything else 4.0 (`candid`).
Deliberately below `add_reflection`'s default 8.0, which at ~one quip per ten minutes would
push `_importance_accumulator` toward the reflection threshold too aggressively.

Host recaps are skipped — "Narrator" is not an agent, and a test asserts no agent memory
carries `confessional_host`.

### 🚀 M4 — Ship (mostly done)

- ✅ `feat/confessional-cam` merged into `main`
- ✅ Pushed to `origin/main`
- ❌ **Demo GIF** of cutaways firing during a live run — needs a windowed session, so it is
  gated behind the M2 GUI check. Do both in one sitting.

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

### 🤫 M7 — Secrets & lies (agreed direction, **low priority**)

The chosen next direction, but deliberately parked — **do not start it ahead of M1–M4**.

Confessional Cam created something the sim otherwise lacks: a **truth channel**. Give an agent
a private secret (broke the coffee machine, job-hunting, resents Opal). In *conversation* they
deny or deflect; in the *confessional* they admit it. The player then knows more than the cast,
which is the actual engine of reality TV — dramatic irony, not just drama.

Reuses conversations, relationships, memory, and the existing director. Mostly additive, but
the lying happens inside `ConversationInstance`, so unlike Confessional Cam it is **not** purely
observational — it changes what agents say. Treat it as behaviour-changing and validate at
runtime.

**Sequencing:** wait for M3 to land. Secrets want to live alongside memories, and building a
parallel store while `MemoryEntry` is being reworked would guarantee a conflict.

**Groundwork that helps and is independently useful:** `PersonalityProfile.goals` is currently
decoration — interpolated into prompts (`agent_brain.gd:88`, `conversation_instance.gd:269`)
and never pursued, achieved, or failed. Giving goals real resolution is the natural precursor:
a secret is just a goal an agent is hiding.

### ✅ M8 — Producer controls (nudge / interview / rumour) — done

Backlog items 1–3 below, built. `PlayerDirector` (autoload) + `ProducerPanel` (**P**, DIR
button, context menu). Harness: `scenes/main/producer_test.tscn`, **14/14**.

| Action | Behaviour |
|---|---|
| **Nudge** | Suggest rest / coffee / work / mingle. Compliance is computed from agreeableness, a trait relevant to the suggestion, and whether the matching need is actually low — then rolled. Measured 9 agreed / 15 refused over 24 nudges. |
| **Interview** | Question answered in character from `memory.retrieve(question)`. LLM at `Priority.HIGH` (a person is waiting), heuristic fallback echoes a real memory. |
| **Plant rumour** | Injects a `MemoryEntry` (importance 6.5, `related_agents` set) so it surfaces in retrieval and colours later prompts. True or false — that is the point. |

**Design invariants:**
- **No agent code was changed.** Everything goes through existing public API —
  `_execute_decision` (which `AgentManager` already drives) and `AgentMemory`.
- **Refusal is the feature.** A nudge is a suggestion weighed against personality and needs,
  never a command. Both outcomes must stay reachable; the harness asserts it.
- **Hard refusal while `TALKING`** — interrupting would strand the other agent in that state.

Not yet done: rumours do not *spread*. Planting colours one agent's behaviour; propagation
between agents is the natural follow-up and belongs with M7.

### 🎛️ Backlog — player agency

**The gap:** the player can reshape the *world* (god toolbar places objects, spawns/removes
agents, triggers events) but can never touch an *agent*. `agent_inspector.gd` is entirely
read-only — every method is `_update_*`, there is not one button. You are a landlord, not a
participant.

**The frame:** Confessional Cam made this a reality-TV sim, so player control should feel like
**producing an episode**, not piloting a character.

| # | Idea | Notes |
|---|---|---|
| 1 | **Nudge an agent** | Suggest an action; they may **refuse** on personality/need. Refusal is the point — influence, not puppetry. Reuses `ActionType` + decision pipeline. Best value-to-effort. |
| 2 | **Interview an agent** | Ask a question, answered in character from real memories. Biggest "these are people" moment; reuses memory + LLM + the confessional voice. |
| 3 | **Plant a rumor** | Inject a memory, true or not. They act on it and it spreads. Wait for M3. |
| 4 | **Call someone to the confessional** | Force a booth cutaway on a chosen topic. Nearly free on `ConfessionalDirector`; makes the marquee feature interactive. |
| 5 | **Assign desks** | Seat an agent beside a rival or crush. Proximity already drives interaction. |
| 6 | **Pick the episode's star** | Pin an agent: camera follows and think-tier stays `ACTIVE`, so attention literally buys them the LLM brain. `ThinkTier` already supports it. |
| 7 | **Promote / fire** | Power with fallout — resentment, grief, new rivalries. |
| 8 | **One purchase per week** | Forced tradeoffs make the player own the room's problems. |
| 9 | **Mediate a conflict** | Outcome depends on personalities; can backfire. |
| 10 | **"Because of you" log** | Ties interventions to consequences. Control you cannot see the effect of does not feel like control. |
| 11 | **Predict the day** | Commit a guess, scored by the Narrator. Turns watching into playing. |

Start with **1**; it is the smallest change that turns a spectator into a participant.

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
- **Port 11434 is unusable on this machine.** A `svchost` PID holds it LISTENING, accepts
  connections, then drops them without responding — so `ollama serve` fails to bind and the
  client reports `wsarecv: An existing connection was forcibly closed`. It is *not* a Windows
  reserved range (`netsh interface ipv4 show excludedportrange protocol=tcp` does not list it).
  Do **not** kill the svchost. Use `OLLAMA_HOST=127.0.0.1:11500` and set `ollama_url` to match.
- **A fixed wait in a test is invalid once an LLM backend is configured.** The harness used a
  1.5s sleep tuned for the synchronous heuristic path; with gemma3 the callback lands later and
  three checks reported false failures. `_check()` and `_cool()` now poll for arrival and for
  `ConfessionalDirector._pending` to clear. Keep it that way.
- **Storylines and confessionals outlive their agents.** After a total party death
  `AgentManager.agents` is empty, so anything summarizing a run must derive its cast from
  storylines/confessionals rather than the live agent list.
