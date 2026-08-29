# Aphae — Working Plan

**The single source of truth for this project.** If you are an agent joining this repo, read
this file before touching anything. It records decisions, environment setup, and findings that
are expensive to rediscover — several entries here exist because someone already lost an hour
to them.

**Status:** M0–M5, M7, M8, V, E, P, A, and G shipped — every phase of the build order is done · **Branch:** `main` (CI on every push; releases by `v*` tag) · **Open:** backlog items and M6 (mobile) only
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
| **M4 — demo GIF** | ✅ **done** (2026-08-28, `docs/demo.gif`, top of the README) | — |

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

### ✅ Phase 2 — Make agents *want* things

| Item | Effort | Needs |
|---|---|---|
| **Goals that resolve** | medium | Phase 0 |

✅ **Done.** See **G — Goals that resolve** below. Goals now carry progress, deadlines, and
resolution; `narrative_event` fires when one lands or dies.

**Why it was here:** agents drifted. Goals give them intent, which every later feature reads
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

### ✅ Phase 5 — A game on top of the simulation (done, 2026-08-28)

| Item | Effort | Needs |
|---|---|---|
| **M5 — Social deduction ("The Mole")** | large | Phase 4 ✅ |

Shipped as `WhodunitDirector` + `CaseState`. One cast member quietly sabotages
the office (the existing sabotage script, actor forced, memories threaded per
case). Evidence accrues only the ways evidence already can: a witness-glimpse
memory that the RumorMill can carry, M7 confides, and booth admissions the
player alone sees — knowing is not proving. The win condition is a **house
meeting** (producer panel, costs Influence): every agent votes from evidence
they personally hold; plurality is accused. Catch the mole → payout, they are
voted off. Accuse an innocent → the office gets meaner, the mole gets bolder
(1-day incident interval). Five incidents uncaught → the mole wins and walks.
The player's levers are the producer tools that already existed — interviews,
planted rumours (negative hearsay naming a suspect sways votes), nudges.

**Harness:** `scenes/main/whodunit_test.tscn` — **43 passed**. It caught a
real design bug before any player saw it: sabotage memories name the VICTIM,
so the first vote model counted victimhood as guilt and the house reliably
voted out whoever had been sabotaged. Votes now count only sightings —
case-thread memories with the suspicion/curiosity emotions (the glimpse and
its rumour-mill copies). Being a target is not being a suspect.

It then caught a second one, via CI: a freed-node race (comparing
`mole2.agent_name` after the winner departed and was freed) that every
assertion SURVIVED — only the suite runner's "SCRIPT ERROR fails a passing
run" rule flagged it, on the first run where harness discovery actually
executed this harness. The fixed sleeps that raced `depart()` were also
masking a cast-size bug (two departures put the roster under MIN_CAST).
Departures are now awaited by polling the roster, never by guessing a
duration — copy `_wait_cast_size` for any test that departs an agent.

Three achievements (39 total: Gotcha, Kangaroo Court, The Perfect Crime).
Save v8. Seam: `WhodunitDirector.auto_enabled`, off in every harness.

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
| **Export templates 4.6** | ✅ installed (`%APPDATA%\Godot\export_templates.6.stable`) | `--export-release` works; first Windows+Linux builds produced 2026-08-28, exe smoke-tested clean |
| **`addons/godotsteam`** | ❌ empty dir, not committed | SteamManager no-ops (by design) |
| **`models/*.gguf`** | ❌ gitignored ("ship with builds") | no bundled model |

**Net effect:** with Ollama up the chain resolves bundled (missing) → **Ollama**. Without it,
→ heuristic fallback. Both paths are verified. To use Ollama, write
`user://settings.cfg` (`%APPDATA%\Godot\app_userdata\Aphae\settings.cfg`):

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

> **Superseded by V (2026-08-08):** the GUI check ran, found six defects, and then the whole
> layout space changed — the viewport is now **640×360** (window 1280×720) and every offset
> in this section's tables refers to the dead 320×214 space. `gui_check.gd` sweeps 1280×720
> and 480×320 and now also asserts overlay mutual exclusion and speech bubbles.

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

### ✅ M7 — Secrets & lies (done, 2026-08-28)

Shipped. The design below was the agreed direction; what was built:

| Piece | What it does |
|---|---|
| **SecretState / SecretManager** | ~35% of agents arrive holding a solo truth from a pool (`secret_manager.gd::POOL`). The substance is a protected memory with thread `secret_<id>` — so `get_secrets()`, the RumorMill trust gate, and the producer's leak dilemma all keep working unchanged. |
| **Propagation is earned** | A holder's own memory names no third party, so **the mill can never lift a secret straight out of their head**. It moves only when the holder CONFIDES (trust > 60, per-conversation roll) — the confidant's memory IS about a third party, and from there the existing gossip chain carries it, distortion and all. Three ears = EXPOSED (narrative ≥ 7.5, social hit). |
| **The floor lies** | Conversation prompt gains `{secret_line}` (deny, deflect) and `{gossip_line}` (you heard a rumor); heuristic pool gains deflections for holders and probes for knowers. A probe costs the pair trust both ways. Mechanics run at conversation wrap-up next to RumorMill, LLM or not — lines are flavor. |
| **The booth tells the truth** | Daily roll: one unadmitted holder files a `secret`-kind confessional that names the truth (heuristic lines carry it verbatim — without an LLM this is the player's only organic way to learn it). Confessionals feed only the speaker's memory, so **the cast stays in the dark: dramatic irony, delivered**. |
| **Surfaced** | Inspector teases ("…is hiding something.") and reveals only what the player has legitimately learned (booth admission or exposure). Save v7, outside the version gate. Three achievements (36 total). Soak logs CONFIDED / BOOTH ADMISSION / EXPOSED. |

**Harness:** `scenes/main/secrets_test.tscn` — **41 passed**. Test seams:
`SecretManager.auto_assign_enabled` / `auto_admit_enabled`, same convention as
`ArcManager.auto_start_enabled`.

Original direction, kept for the record:

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

### ✅ V — Visual & audio overhaul (done, 2026-08-08)

The owner's verdict on the old presentation: "cluttered, human eye can't read what's
happening, audio clutter." Shipped in five stages, each gated on parse + producer 14/14 +
confessional 15/15 + a windowed `gui_check`/`screenshots` run. Commits `34237ca` → `d57b5c9`.

| Stage | What changed |
|---|---|
| **V1 resolution/camera** | Viewport 320×214 → **640×360** (window 1280×720), world drawn at camera zoom 2 (crisp 2×2 world pixels, UI at full res). The two-camera situation (tscn `GameCamera` + a runtime one in `main.gd`) collapsed into `game_camera.gd` alone: smoothing, bounds, pet-mode fit-to-view. The status bar had been off-screen at y=295 since the 480×320 era — restored. Office shrunk to 300×160 so it fits one screen at default zoom. |
| **V2 theme/UIManager** | `UIPalette` + `UITheme` (code-built Theme; pixel font is a one-line swap), `BasePanel` chrome, `UIManager` with EXCLUSIVE/MODAL/DOCK kinds — one center overlay at a time, Esc closes topmost, toasts stack top-center capped at 3. Every panel rect re-authored for 640×360; the agent-inspector min-size overflow (170×250 in a 142×176 rect) fixed. |
| **V3 dialogue** | Both LLM backends returned `success=true, {"raw"}` on parse failure — now a real failure (callers already have heuristics), after trying to salvage the first balanced `{...}` object. `LLMSanitizer.clean_line()` guards every model-output→screen path; the `know?"} [{"` class of leak is dead. Bubbles are screen-space (`SpeechBubbleLayer`, CanvasLayer 5): 150px, 2 lines + ellipsis, speaker-colored border + tail, cap 4, zoom-independent. Full transcript in the narrative log's new **Talk** tab; conversation lines no longer flood Events. |
| **V4 world** | 1px outline pass on all character/object sprites (canvas grown 1px/side), curated 12-color clothing ramp + 5 skin tones (derived from the persisted color — saved agents keep their look), warm checkered floor + wall band, day/night via `CanvasModulate` (world canvas only, actually visible at night), y-sort + feet shadows, selection ring at the feet in front, occupancy dot above objects, ♪ contentment badge removed, names at 60% alpha until hover/select, sprite-derived collision for runtime objects. |
| **V5 audio** | Footsteps deleted (0.35s/agent unthrottled — the noise floor). `SFX_RULES` per-sound cooldown + concurrency in `play_sfx`. Achievement double-sting and pause+speed-change chord fixed at source. `conversation_end` cut; `conversation_murmur` finally plays — looped on the (previously dead) Ambient bus while conversations run. Three real ~20s music loops (calm/busy/menu) switch on `DramaDirector.drama_level` with 10s hysteresis and duck −6dB under confessional cutaways. All generated buffers peak-normalized. In-game UI clicks at −14dB. Volume logic single-owned by `SettingsManager.apply_audio()`. |
| **V6 HUD** | Icon bar: readable labels (`Log Talk Cam Rel Prod Recap · God Awards Set`), toggle buttons lit while their panel is open, speed/pause reflect live state. LLM status is a colored ● with the full backend string in its tooltip. God toolbar moved below the status bar (they overlapped at y2) and themed. Main menu on the shared theme. README screenshots regenerated. |

**Gotchas from this work:**
- **A `custom_minimum_size` larger than the assigned rect silently wins** — this one family
  of bug accounted for the inspector, settings, recap, god toolbar, and (pre-908d298) the
  narrative log, producer, and story feed. When authoring any panel: min ≤ rect, always.
- **Zoomed-out camera limits pin top-left.** If Camera2D limits are smaller than the visible
  area Godot stops centering; `game_camera.gd::_apply_zoom` floors zoom at fit-to-limits.
- **`for x in [1, 2, 3]` yields Variant** — `var captured := x` inside the loop is a parse
  error at *reload* (gui_check caught it; the editor parse check did not). Type the loop var.
- The sanitizer's schema-echo extraction must run **before** its JSON-artifact cut, or an
  echoed `{"line": ...}` object gets truncated to nothing at its own opening brace.

### ✅ E — Events that change people (done, 2026-08-09)

The owner's ask: "more things and events that will happen that can change and alter" the
agents. Shipped in six stages (`a57c548` → this), each gated on parse + producer 14/14 +
confessional 15/15 + the new events harness.

| Stage | What shipped |
|---|---|
| **E1 ConsequenceEngine** | Events are data now. Declarative payloads (relationship deltas/tags/status, modifiers, conditions, memories with **witness radius** instead of broadcast-to-all, capped permanent **trait shifts**, trait-conditioned bystander reactions, weighted outcomes, named scripts) + prerequisites + second-actor selection + a real `specific` target mode. heated_argument/promotion migrated to JSON; `motivated` finally does something (halves productivity decay). **SAVE_VERSION 5**: modifiers, cooldowns, in-flight events, drama state, and `personality_data` for every agent (file agents' trait shifts used to silently revert — `save_manager.gd` gated on `__procedural__`). Life-stage signal no longer emits an empty name. |
| **E2 Romance + arcs** | `romantic_interest` was **never incremented anywhere** — organic romance was provably impossible (confession gate is >40). Now positive conversations grow it (compatibility-weighted, blocked when committed elsewhere), CRUSHING gets set, `romantic_reflect.txt` is wired. ArcManager autoload: multi-day staged storylines in `arcs.json` (burnout spiral, secret hobby, promotion chase, goal-pursuit template — goals finally resolve, Phase 2 delivered). |
| **E3 Cast churn** | `agent.depart()` — a non-death exit (no grief cascade, no `agent_died`). Departures are archived (personality + relationships + memories) so **returning_ex** brings people back with grudges intact. new_hire seeds compatibility-based first impressions + mid-season intro confessional. |
| **E4 Secrets & sabotage** | A secret is a memory (`decay_protected`, thread `secret_*`) per the M7 agreement. Sabotage events pick a hidden actor (rivals/low-agreeableness/repeat offenders weighted); victim's memory names no one; RumorMill passes third-party memories at conversation wrap-up, trust-gated and distorting — the leak mechanism (Phase 3 down payment). |
| **E5 Producer dilemmas** | Events can pause the show for a producer decision (DilemmaPanel modal, real-time countdown, default on timeout/dismiss/headless; prior pause state restored). Poached is now a dilemma (counter-offer vs let them walk); The Leak and The Footage gate on `has_secret`/`has_secret_thread`. |
| **E6 Content + pacing** | 37 events total (~15 new: imposter syndrome, health scare w/ new `stress` condition, viral post, mentor moment, prank outcomes, late-night romance feeder, reconciliation via new `grudge` second-actor + `requires_tag_prefix`, headhunter w/ `secret_jobhunt` thread, secret admirer, team win, coffee crisis). **Three intra-day roll windows** (start/12:00/17:00) replace the midnight burst, capped 6/day. Measured 2.0 events/day at neutral drama over 20 simulated days (quiet-escalation lifts slow days). |

**Gotchas from this work:**
- **Test worlds must freeze the clock AND zero event probabilities** — the harness's manual
  `day_changed` emissions roll real organic events; a `returning_ex` once consumed the
  departure archive between two assertions. `trigger_event()` bypasses probability, so
  zeroing is safe for force-fire tests.
- **The event walker must re-pick a live target every iteration** — churn events depart
  agents mid-walk, and a runtime error inside an awaited coroutine hangs the harness
  silently (no report, no quit).
- **Measure pacing at controlled drama.** Firing 37 events back-to-back drives
  `drama_level` past the climax threshold and the director suppresses everything after it
  to 0.1–0.3×; the band assertion resets pacing state per simulated day.
- `for x in [1, 2, 3]`-style untyped iteration strikes again: `var y := array[0]` on an
  untyped Array is a parse error only at scene load. Type the variable.

### ✅ P — Producer meta-game: seasons, Influence, the Catalog (done, 2026-08-09)

The missing session structure plus the owner's "unlockable items that influence people,"
built as one system: drama earns Influence, Influence buys influence tools, episodes give it
rhythm and a score. Backlog items 6/8-adjacent delivered. Commits `63b606e` → this.

| Piece | What shipped |
|---|---|
| **Episodes** | Every 3 game-days wraps an episode: drama sampled every 30 game-min into avg/peak/beats aggregates, score = avg·8 + peak·3 + beats (graded S–D), payout 20 + score. Five episodes per season. `S1E2 · d2/3` and `◆ 42` live in the status bar; the EpisodeCard auto-opens with grade, breakdown, top storyline, payout, and a recap-export button. |
| **Influence** | Per-save currency. Payouts + capped trickle on big beats. Producer actions now cost: nudge ◆1, interview ◆2, rumour ◆5 — charged in ProducerPanel, **never in PlayerDirector** (the API stays free so producer_test's direct calls hold 14/14). |
| **Catalog** (`B`) | Three tabs from `resources/catalog.json`. Unlock gates are cross-save meta (`user://producer.json`, achievements.json pattern): lifetime episodes, best score, or named achievements, OR-combined; locked rows show their condition. Consumables: anonymous gift (suspected-sender romance nudge), leaked memo, documentary crew day (2× event rolls until midnight — via ONE multiplier seam in `_roll_events`). Studio: better_cameras halves confessional cooldown via `cooldown_scale`. |
| **Objects** | karaoke_machine (duet → conversation + narrative beat), arcade_cabinet (auto-chat), meditation_pod (clears stress, 30% dissolves a grudge on exit), aquarium (passive calm). Wired into the heuristic brain (anxious → pod, slacker → arcade, extravert → karaoke). Pay-on-placement; Esc cancels free. |
| **ObjectFactory** | The identical object-construction body that lived in god_toolbar, save_manager, and headless_sim is one static factory with four callers. |

**Gotchas from this work:**
- **God-mode placement had passed raw SCREEN coords to `world.add_object` since forever** —
  invisible at the old zoom-1 default, wrong-by-half at the V-overhaul's zoom 2. Both
  placement paths now convert via `get_canvas_transform().affine_inverse()`.
- **Meta pollution:** all five dev harnesses must set
  `ProducerEconomy.meta_persistence_enabled = false` — confessional_test's deaths and
  confessions banked 13◆ of "lifetime earnings" into the real producer.json before the guard
  covered every harness. If a new harness appears, guard it.
- **Wire panel buttons after the panel exists** — the icon-bar Shop button connected to a
  null `_catalog_panel` because the catalog was created later in `_ready` (caught by a
  windowed probe, invisible to headless tests).
- `-s` SceneTree probe scripts cannot reference project `class_name`s at compile time
  (autoloads/classes aren't registered yet) — use `load("res://...")` dynamically.
- Harness: `scenes/main/economy_test.tscn`, 24 checks.

### ✅ A — Ambient identity (done, 2026-08-09)

**Product decision, not just a feature:** this is an ambient game you leave running, not a
foreground sim you stare at. The pacing already demanded it (a game-day is 24 real minutes at
1x; an episode over an hour), the catch-up machinery was already the best-built part of the
project (log tabs, confessional feed, recaps, wrap cards), and the positioning is far stronger
— "a reality show that lives on your desktop" competes with nothing, while "another AI office
sim" competes with RimWorld and loses.

The code had been arguing with itself: `auto_pause_on_focus_loss` **defaulted to true**, so the
game stopped dead the instant you clicked away, while shipping a desktop-pet mode that begs to
run in a corner. Resolved in favor of ambient.

- **`AmbientMode` autoload**: on focus loss (when auto-pause is off) the office enters low
  power — every agent forced to the heuristic brain via the existing `force_heuristic` lever,
  think cadence ×3, audio muted (optional) — and notable events are collected. On return, a
  digest fires *only* if the player was gone ≥60s AND ≥2 notable things happened, so a quick
  alt-tab is never punished with a popup. **Nothing blocks on attention; attention is rewarded.**
- `AgentManager.low_power` + `think_interval_for(tier)` centralize the cadence (the three
  hardcoded interval checks collapsed into one loop).
- Defaults flipped: auto-pause **off**, low-power **on**, mute-when-unfocused **on**; all three
  exposed in Settings under "Ambient Play".
- `AwayDigestPanel` (BasePanel modal) renders the catch-up, color-coded by kind.

**Open follow-up:** two catch-up modals now exist — this one and the pre-theme hand-rolled
"Welcome Back" save-load summary in `main.gd:_show_load_summary`. They can stack, and the older
one predates the design system. Unify them.

**The remaining ambient blocker is the LLM.** Low-power mode stops agents *queueing* LLM work
while unfocused, which is the right first move, but a bundled model still idles in memory. A
true background build wants the model unloaded (not just unused) when backgrounded.

### ✅ G — Goals that resolve (done, 2026-08-28)

Phase 2. `PersonalityProfile.goals` was prose read in three places and pursued in none.
Now every goal becomes a `GoalState` (`scripts/data/goal_state.gd`) owned by the `GoalManager`
autoload, with a kind, live progress, and a deadline.

| Piece | What it does |
|---|---|
| **Kind inference** | The goal's own text picks its kind once, at assignment — ROMANCE / BALANCE / CREATIVE / SOCIAL, else WORK. Keyword table lives in `GoalState._KIND_KEYWORDS`, most specific first. **Adding a goal string needs no code change.** |
| **Progress** | Only real events move a goal: finishing at a matching object (WORK/CREATIVE), a new conversation partner (SOCIAL/CREATIVE), an accepted confession or a started romance (ROMANCE), ending the day with every need above 55 (BALANCE). A goal cannot advance on narration. |
| **Resolution** | Landing or losing one runs a `ConsequenceEngine` payload — protected memory, trait shift, `narrative_event` at 7.5 (achieved) or 6.5 (failed). Both clear the confessional's importance-6 bar, so a resolved goal earns a booth cutaway for free. Achieving also pays 6 Influence. |
| **Deadline** | 10 days, then failure — unless progress ≥ 75, which buys exactly one 3-day extension. The near-miss beat is the point. |
| **Pursuit** | `HeuristicBrain._goal_decision` runs *before* personality drift when needs are calm: goals outrank idling. It yields ~45% of the time (`GOAL_PURSUIT_CHANCE`) so agents read as people, not quest markers. SOCIAL goals prefer a partner they have not met yet. |
| **Surfaced** | Agent inspector grows a Goals section with an ASCII meter (a real ProgressBar per goal does not read at 9px in a 170px panel). The LLM decision prompt gets standing, not bare text: `"…(40% there, 6 days left)"`. |
| **Persisted** | Save v6. The restore sits outside the version gate, like confessionals — a pre-v6 save has no goal block and agents re-derive from personality on spawn. |
| **Achievements** | Four new: Goal Getter, Driven, Unfinished Business, Self-Actualized. 29 → 33. |

**Harness:** `scenes/main/goals_test.tscn` — **75 passed**.

**Gotcha this cost:** `ConsequenceEngine._apply_memories` keys memory specs by *role* —
`affected`, `second`, `witness`. There is no `target` role, and a payload using one is
**dropped silently**: no error, no warning, just no memory. Caught only because the harness
asserted the memory existed.

**Death is deliberately quiet.** An agent who dies mid-goal has it marked FAILED with no
narrative and no confessional — death is drama enough — but the `GoalState` is *kept*, so a
recap can still say what they were three days short of.

### ✅ Backlog items #6 and #10 — the star, and "Because of you" (done, 2026-08-28)

**#6 Pick the episode's star** — `PlayerDirector.set_star`: the producer panel
pins one agent for ◆3. The camera follows them and `_reclassify_tiers` never
lets them leave ACTIVE — attention literally buys them the LLM brain. Toggling
the current star clears the spotlight. Persisted (save v9).

**#10 "Because of you"** — `ImpactLog` autoload + a **You** tab in the
narrative log. Every intervention (nudge, rumour, meeting, purchase, dilemma,
star) opens a 180-game-minute attribution window; notable things that happen
to the people you touched attach as ripples (cap 3, newest plausible cause
wins). Deliberately a heuristic and honest about it — the sim does not track
true causality, and neither does a TV producer. Writes nothing back into the
simulation, so it cannot collide with a harness; carries the standard seam
anyway. Covered in `producer_test` (14 → 30 assertions).

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

## Steam readiness (assessed 2026-08-28)

What exists already: `SteamManager` (GodotSteam wrapper, safe no-op without
Steam), achievements routed through it on unlock, `include_filter="*.gguf"`
in every export preset, and — as of today — filled `export_path`s, a
`release-builds` workflow producing Windows+Linux artifacts with a boot
smoke-test, and `build/` + `steam_appid.txt` gitignored.

### Code side, in order

1. ✅ **A build exists.** Export presets wired, release workflow exports
   Windows + Linux on tag or manual dispatch, smoke-tests the Linux binary
   for script errors before uploading.
2. **GodotSteam addon** — `addons/godotsteam/` is an empty dir. Decision to
   make: the GDExtension (drop-in, ships .dll/.so in the addon) vs the
   precompiled module editor+templates (heavier pipeline). GDExtension is
   the sane default. When it lands, TEST the init path: `SteamManager`
   checks `Engine.has_singleton("Steam")`, which is the MODULE-flavored
   check — the GDExtension may need `ClassDB.class_exists("Steam")` and the
   `steamInit()` signature has changed across GodotSteam majors
   (`steamInitEx(app_id)` on current ones). The wrapper no-ops either way,
   so nothing breaks before then.
3. **Achievement API names** — `SteamManager.set_achievement()` sends the
   internal ids (`goal_getter`, `cover_blown`, ...). Define the Steamworks
   achievement API names to be EXACTLY these ids and nothing needs mapping.
   36 achievements → 36 Steamworks entries + icons (achievement icons are a
   store-side asset job, 64x64 gray+color pairs).
4. **The gguf decision** — presets already include `*.gguf`, but `models/`
   is gitignored and empty, and `addons/gdllama` is empty too. Either ship
   heuristic-only for launch (the game fully works; PLAN documents the
   fallback chain as verified) and patch bundled-LLM in later, or commit to
   gdllama + a ~1GB depot. Heuristic-first is the smaller risk: an LLM that
   writes dialogue on a player's machine is also a content-rating and
   support question.
5. **Steam Cloud** — saves/settings live in `user://`; enable Steam Auto-Cloud
   on that path in Steamworks, no code needed. But note `user://producer.json`
   (lifetime meta) syncing across machines is a FEATURE here, not a risk.
6. **Steam Deck (later)** — 640x360 viewport scales cleanly to 1280x800, but
   the interaction model is mouse-first. Playable-with-touch is realistic;
   Verified needs controller work. Park with M6.

### Steamworks side (owner's checklist, no code)

- Steamworks partner account + $100 app credit → App ID.
- Store page: capsule art set, 5+ screenshots (the `screenshots.tscn`
  harness already produces clean 1280x720 shots), short trailer — this is
  M4's demo GIF grown up, still the single most valuable missing asset.
- Depots: upload `build/windows` + `build/linux` artifacts via SteamPipe;
  wire launch options (Windows exe / Linux binary).
- Achievements defined with API names = internal ids (see 3).
- Auto-Cloud config (see 5). Controller config stub for Deck.
- Content survey: procedural/LLM text means checking the "user-generated /
  AI content" disclosure box honestly — with the heuristic-only build this
  is canned-lines-only and simpler to answer.

## Playtest program (2026-08-28)

Nine single-feature playtesters (subagents) each spent a session on one
system and reported ranked findings with math. What was implemented, by
tester:

| Tester | Top finding | Fix shipped |
|---|---|---|
| Mole vote | **plant_rumor wrote sentiment 0.0 against a `< 0.0` hearsay gate — the player's one counterplay scored zero points, and the harness had hidden it by patching sentiment manually** | plant_rumor smears at -0.4 when aimed at someone; harness patch deleted |
| Mole vote | all-zero suspicion resolved by dict insertion order: every blind meeting deterministically lynched whoever spawned first | voters abstain under 5.0 suspicion; a no-plurality meeting is INCONCLUSIVE — half refund, no scars, case continues |
| Impact log | 4 of 6 intervention types burned ripple slot 1 restating themselves same-frame; "X and Y talked" filled the rest; meetings listed the whole cast as subjects | same-minute ripple guard; talk ripples capped at one slot; meeting subjects = accused only |
| Floor dialogue | the memory-splice template produced literal gibberish bubbles (truncated, lowercased transcripts) | unspeakable memories (colons, >70 chars, CONVERSATION type) fall through to normal pools; first-person rewrite; in-conversation repeat reroll |
| Secrets | first organic confide ≈ 2-3 game-weeks; booth outraced the floor 10x; hearsay could never re-leak so 3-ear exposure was ~probability zero | confide gate 60→40, probe cost 6→3, secondhand re-pass at 0.5x, secret-thread memories never age out of the gossip window |
| Goals | agents whose goals resolved went wantless forever; every goal shared one deadline → synchronized day-10 mass-fail; SOCIAL trivial at 8 agents, WORK unfinishable | resolution refills from the pool; ±2-day deadline jitter; roster-aware social step (100/living-1 clamped 2..6); WORK_STEP 12→15 |
| Economy | active daily spend (10◆) exactly equaled the trickle cap (10◆): engagement taxed to break-even; aquarium cost more than the starting bank | trickle cap 15; aquarium 35→25 |
| Confessional voice | 3-line pools drawn with replacement repeated back-to-back; mid-range personalities got zero flavor; templates discarded the event (romance never named the partner) | per-kind last-line reroll; "even" deadpan bucket; detail-threaded lines for romance/tragedy/rivalry; drama pool grown, worst line replaced |
| First 5 minutes | not one hint mentioned any post-README feature; the reward loop had no hint at all | event hint on first confessional (C + P), Influence/Catalog hint at 120s, log hint teaches L, menu subtitle sells the fantasy |
| Recap | the mole case and goals were invisible — PLAN.md's own promise ("what they were three days short of") was never implemented | The Mole / Dreams Kept and Broken / Secrets Out sections; episode+grade byline; storylines marked ongoing/concluded |
| Dialogue reach | the romance pool (the file's best writing) needed ~27 positive conversations to unlock | ROMANCE_GROWTH_BASE 1.5→3.0 |

**Deferred, recorded honestly:** brains tick on wall-time while deadlines are
game-days (3x speed = 1/3 the decisions per game-day — a deep scheduler
change); witness testimony spreading to adjacent voters pre-vote; a cast-fate
cache so departed agents keep their story in the recap; icon-bar renames
(320px-era viewport math makes labels risky to widen).

## Security review (2026-08-28)

Threat model for a local Godot game: the untrusted inputs are **save files**
(hand-edited, corrupted, or shared between players), **LLM output**, and
**whatever answers on the Ollama port** — not network listeners. Findings:

| Hole | Fix |
|---|---|
| `ObjectFactory.create` built `res://scenes/objects/%s.gd` from a save-file string — `"../../autoloads/x"` reached `load()` | rejects non-identifier names |
| `personality_file` from a save built a `res://` path the same way | same identifier check in `agent._load_personality` |
| `Color(c[0], c[1], c[2])` on a save-provided array — short or non-array value aborted the whole agent load, in both `PersonalityProfile` loaders | falls back to grey |
| Non-Dictionary entries in a save's `agents`/`objects` arrays errored mid-load, leaving a half-restored world | skipped per entry |
| Ollama handler typed `json.data` as Dictionary and passed `content_json.data` to typed-Dictionary callbacks — a 200 carrying a top-level array or scalar (models emit `[{...}]`; the port squatter on 11434 answers with who-knows-what) script-errored in the callback | every parse now requires `is Dictionary` before a success callback; anything else routes to the heuristic fallback |
| `sandbox_run.sh` does `rm -rf "$SANDBOX"` with `SANDBOX_DIR` env-controlled — empty, `/`, or `$HOME` would be catastrophic | denylist guard at the top |

Checked and already defended (do not re-fix): `_to_bbcode` escapes `[` → `[lb]`
so LLM text cannot inject BBCode into the recap RichTextLabels;
`_try_load_file` rejects non-Dictionary save roots; `load_modifiers_data`
guards per entry; no `OS.execute`/`Expression` anywhere; recap export
filenames derive from the timestamp only. Regression assertions live in
`economy_test` (factory traversal/empty, malformed color).

Known and accepted: prompt injection via agent memories is inherent to the
design (memories are meant to reach prompts); `ollama_url` is the user's own
config and may point anywhere they like.

## Gotchas discovered

- **`add_memory()` returns the entry it created — use that, never `memories[-1]`.**
  `add_memory` can *synchronously* append a reflection on top of yours: the
  heuristic path in `_trigger_reflection` calls `add_reflection` inline when no
  LLM is configured, which is the normal state for every test run. So the last
  element is not reliably the memory you just added, and `narrative_thread` /
  `emotion` / `decay_protected` land on a reflection instead. This was live in
  **grief, departure, mental-break, homecoming, confessional-recall, rumour,
  and the whole `ConsequenceEngine` memory path** — 30 call sites. A previous
  agent hit it in `confessional_test` and worked around it locally
  (*"add_memory can trigger a reflection that appends after ours"*) without
  fixing the root. Now fixed at the source; the return value is the contract.
- **`:=` cannot infer a type through an untyped receiver.**
  `var m := other.memory.add_memory(...)` is a parse error when `other` is a
  bare `Node2D`, because `.memory` is Variant. Write
  `var m: MemoryEntry = ...`. Same family as the untyped-loop trap below, and
  it cost a broken build here.
- **The parse check's exit code is not a gate.** `godot -e --quit-after 5`
  returned **`exit=0` while three scripts failed to compile.** Grep its output
  for `Parse Error|Compile Error` instead of trusting `$?`.
- **A broken build makes every harness print `0 passed, 0 failed`** — which a
  grep for "0 failed" reads as success. Every `_report()` now prints
  `NO ASSERTIONS RAN — treat this as a FAILURE` when nothing was asserted.
  Do not remove that guard; it is the only thing standing between a compile
  error and a green-looking suite.
- **`events_test` was flaky at ~25%; two separate causes, both now fixed.**
  Measured: 2 of 8 runs failed originally. Affected assertions:
  `leak is marked secondhand`, `leak is weaker than the original`, and
  `arc ran to completion`.
  **Cause 1 (the leak pair):** the `memories[-1]` defect above — the
  `secret_test` thread was landing on a reflection instead of the planted
  secret. Fixed by `add_memory()` returning its entry.
  **Cause 2 (`arc ran to completion`):** `ArcManager._on_day_changed` runs
  `_tick_active` and then `_maybe_start`. The instant the forced arc finished,
  the agent became eligible again for the same tick's 0.3 spontaneous roll, so
  over 12 day-ticks it sometimes picked up a *fresh* arc and `has_arc()` was
  true at the assertion. The arc HAD completed; a second one had begun. Fixed
  with `ArcManager.auto_start_enabled`, a seam mirroring
  `EventManager.auto_resolve_dilemmas`; `events_test` disables it around that
  block.
  **Evidence:** 0 failures in 30 consecutive runs afterwards. Good evidence,
  not proof — at the old rate, 30 clean runs would happen by luck a few
  percent of the time. If it resurfaces, capture the `FAIL` line first; all
  three assertions are bounded loops over probabilistic systems and the cause
  is never guessable from the summary count alone.
- **Harnesses must neutralize EVERY background roll, not just the ones they
  assert on.** The trap list below names `EventManager` probabilities, the
  clock, and autosave; `ArcManager.auto_start_enabled` was forced by a flaky
  arc assertion, and then `confessional_test` — a harness that never mentions
  goals or secrets — started failing at ~20% the day both landed. The
  mechanism: the harness emits `romance_started`, a procedural agent holding
  a "find love" goal resolves it, the resolution narrates at 7.5, the
  ConfessionalDirector records THAT quip, and its 8s cooldown then silently
  swallows the quip the harness was testing for (`_record` drops emits during
  cooldown). Disabling the Secret seams alone did NOT cure it; the GoalManager
  seam did. The pattern: any autoload that acts on `agent_spawned`,
  `day_changed`, or the social signals will eventually collide with a harness
  — through the confessional cooldown if nothing else.
  New autoload with a background roll ⇒ ship it with an `auto_*_enabled`
  seam and turn it off in ALL harnesses on the same commit.
- **`Config.MAX_AGENTS_DESKTOP := 3` is not about desktop-vs-mobile.** It's the *desktop pet*
  overlay (480×320). There is no mobile awareness in the codebase.
- **`set_v_scroll` is correct on Godot 4** — `ScrollContainer.scroll_vertical` binds to
  `set_v_scroll`/`get_v_scroll`. Matches `narrative_log.gd`. Don't "fix" it to `set_scroll_vertical`.
- **GDLlama is referenced dynamically** in `llm_backend_bundled.gd` (`var _gdllama: Node`, guarded
  by `has_method`/`has_signal`) specifically to avoid a hard dependency. Keep it that way — the
  missing addon degrades instead of crashing.
- **The `/Users/raph/...` path in `CLAUDE.md` is a macOS doc example only.** The project is
  cross-platform; `export_presets.cfg` ships Windows, Linux, and macOS presets.
- Repo and product are both **Aphae** now (renamed from Ayle 2026-08-28; `config/name` changed, so `SettingsManager._migrate_from_ayle` copies the old `app_userdata/Ayle` tree into `Aphae` once, never overwriting).
- **`Time.get_datetime_string_from_system()` contains colons**, which are illegal in Windows
  filenames. Sanitize before using it in a path — `EpisodeRecap._file_stamp()` does.
- **The Ollama port gotcha below is machine-specific (Windows box).** On the owner's Mac
  (2026-08-08) plain `11434` works — Ollama.app serves it with `smollm2:1.7b` installed, and
  Godot is on PATH via Homebrew (`/opt/homebrew/bin/godot`). Confessional test is 15/15 now,
  not 13/13.
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
