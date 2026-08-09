---
name: run-aphae
description: Run, test, or screenshot the Aphae Godot game. Use for any request to launch the game, run its test harnesses, capture screenshots, verify a UI change, or soak-test the simulation. Covers the headless-vs-windowed split, the isolated sandbox runner, all five harnesses with their expected pass counts, and the traps that cost real time.
---

# Running and testing Aphae

Godot 4.6 project. `godot` is on PATH (`/opt/homebrew/bin/godot` via Homebrew).
Always run from the repo root.

## The one rule that is not a preference

**Always pass `--audio-driver Dummy`.** The game synthesizes all its audio
procedurally, so any run — headless included — makes noise on the owner's
machine. This is a standing request from the repo owner. Do not omit it.

## Two run modes, and why the split matters

| Need | Mode | Why |
|---|---|---|
| Logic, simulation, save/load, event consequences | `--headless` | Fast, no window |
| Anything visual: screenshots, panel layout, sprites | **windowed** | `--headless` swaps in the dummy display driver — every capture comes out **blank** |

Visual harnesses that are run headless will "pass" while producing empty
PNGs. If a capture looks blank, that is the first thing to check.

## Invisible, isolated runs — prefer this for visual work

```bash
tools/sandbox_run.sh res://scenes/main/panel_check.tscn
tools/sandbox_run.sh -s /abs/path/to/probe.gd
SANDBOX_KEEP=1 tools/sandbox_run.sh ...   # keep the copy to inspect
```

Mirrors the repo to `/tmp/aphae-sandbox`, rewrites `config/name` to
`AphaeSandbox`, and parks the window at `--position -5000,-5000`.

- **Invisible**: macOS still renders an off-screen window (verified: 99
  distinct pixel colors off-screen vs. nothing under true headless), so
  captures are real while the owner's screen stays free.
- **Isolated**: Godot derives `user://` from `config/name`, so the sandbox
  gets its own saves, settings, achievements, and `producer.json`. A test
  run cannot clobber the owner's game or inflate their lifetime progression.

Sandbox output lands in
`~/Library/Application Support/Godot/app_userdata/AphaeSandbox/`.

## Harnesses and their expected results

Pass the scene path directly. **Never use `run_headless.sh`** — it `sed`s
`run/main_scene` in `project.godot` and restores it via an EXIT trap, which
corrupts the file if the run is killed.

```bash
G="godot --headless --path . --audio-driver Dummy"
$G -e --quit-after 5                                  # parse check, exit 0
$G res://scenes/main/producer_test.tscn               # 14 passed
$G res://scenes/main/confessional_test.tscn           # 15 passed
$G res://scenes/main/events_test.tscn                 # 56 passed
$G res://scenes/main/economy_test.tscn                # 32 passed
$G res://scenes/main/headless_sim.tscn -- --agents=12 --speed=3   # soak; runs forever, kill it
```

Windowed only (use the sandbox runner):

```bash
tools/sandbox_run.sh res://scenes/main/panel_check.tscn   # 55 passed, 15 shots
tools/sandbox_run.sh res://scenes/main/gui_check.tscn     # layout sweep, 2 window sizes
tools/sandbox_run.sh res://scenes/main/screenshots.tscn   # README images
```

`panel_check` answers "can the player close what they opened"; `gui_check`
answers "does it fit on screen". They are not redundant.

## Launching the game for a human to play

```bash
godot --path . --audio-driver Dummy     # boots to the main menu
```

Run it in the background so it does not block the session, then tail the log
for `SCRIPT ERROR` while the owner plays — a runtime error caught with its
stack beats asking them to reproduce it.

## Watching a live playtest

Launch in the background, then tail the log for errors. **Capture the
GDScript backtrace, not just the ERROR line** — Godot prints the trace on
the following lines, and a grep matching only `SCRIPT ERROR|ERROR:` throws
away the one piece of information that identifies the culprit:

```bash
grep -E -A6 "SCRIPT ERROR|ERROR:" playtest.log      # -A6 keeps the backtrace
```

Chasing a "previously freed object" error without its trace cost real time
in this repo; the trace named the exact function on the first line.

## Traps that have cost real time

- **Test harnesses must neutralize global state.** Set
  `ProducerEconomy.meta_persistence_enabled = false` (otherwise CI runs
  inflate the owner's real lifetime progression — this happened), freeze the
  clock with `TimeManager.is_paused = true`, zero event probabilities
  (`trigger_event()` bypasses them), and set
  `SaveManager._last_auto_save_day = 999999`.
- **`-s` probe scripts cannot reference project `class_name`s.** Autoloads
  and script classes are not registered when a SceneTree script compiles.
  Use `load("res://...")` and `root.get_node_or_null("/root/Autoload")`.
- **A runtime error inside an `await`ed coroutine hangs the harness
  silently** — no report, no quit. If a run times out with no output,
  suspect an error mid-coroutine.
- **Untyped iteration breaks at scene load, not parse.** `for x in [1,2,3]`
  yields Variant; a following `var y := x` is a parse error that only
  surfaces when the scene loads. Type the loop variable.
- **Ollama**: works on the default port 11434 on this Mac with
  `smollm2:1.7b`. (PLAN.md documents a port-11500 workaround — that is
  specific to the owner's Windows box, not this machine.)
- **Anchors before offsets.** Assigning `anchors_preset` silently discards
  offsets already set.
- **Never collect freed objects into a typed array.** `Array[T].push_back`
  validates and rejects them, so cleanup code written as "gather the dead
  ones, then erase them" errors on the gather. Remove by index instead
  (iterate backwards). This was a live bug in `conversation_manager`.
- **`custom_minimum_size` larger than the assigned rect silently wins** and
  pushes panels off-screen. This one bug family accounted for most of the
  historical layout defects.
