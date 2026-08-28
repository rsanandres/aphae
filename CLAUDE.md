# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Ayle — AI Agent Office Simulation. A top-down 2D pixel art game where AI agents with distinct personalities live together in an office. The player observes and rearranges the environment as emergent social behavior unfolds. Built with Godot 4.6 (GDScript) with bundled LLM (GDLlama) + Ollama fallback.

## Build & Development

- **Engine**: Godot 4.6 (GDScript)
- **LLM Backend**: Bundled (GDLlama GDExtension) → Ollama → heuristic fallback
- Open project in Godot editor: `godot --editor project.godot`
- Run from CLI: `godot --path /Users/raph/Documents/ayle`
- Parse check: `godot --headless -e --quit-after 5`

## Architecture

### Autoloads (24 singletons, load order matters)
- `EventBus` — Global signal bus (~40 signals)
- `TimeManager` — Game clock (1 real sec = 1 game minute at 1x), pause/1x/2x/3x
- `Config` — Constants (need decay rates, speeds, thresholds)
- `SettingsManager` — Persists user settings to `user://settings.cfg` (MUST load before LLMManager/AudioManager)
- `AgentManager` — Agent registry, round-robin think ticks, spawn/remove
- `LLMManager` — Backend abstraction: bundled (GDLlama) → Ollama → heuristic
- `GameManager` — Top-level game state, selected agent tracking
- `ConversationManager` — Active conversations, prevents double-booking
- `DramaDirector` — RimWorld-style storyteller pacing events for narrative satisfaction
- `EventManager` — Random/triggered life events with probabilities and cooldowns
- `ArcManager` — Multi-day personal storylines; a small state machine per agent from `resources/events/arcs.json`
- `GoalManager` — Turns `PersonalityProfile.goals` into pursued `GoalState`s with progress, deadlines, and resolution
- `SecretManager` — M7 secrets & lies: private truths denied on the floor, confided under trust, spread by the RumorMill, admitted to the camera
- `SaveManager` — Multi-slot (5) save system with `.bak` backup and corruption recovery
- `GroupManager` — Social group formation and rivalry tracking
- `Narrator` — Storyline tracking and narrative arc management
- `ConfessionalDirector` — Reality-TV confessional cam: first-person "talking head" quips reacting to drama (LLM + heuristic fallback), plus host day recaps
- `PlayerDirector` — Producer controls: nudge (refusable), interview, plant rumour
- `AudioManager` — 3 audio buses (Music/SFX/Ambient), crossfade, procedural fallback sounds
- `AchievementManager` — 36 achievements, persists to `user://achievements.json`, Steam sync
- `TutorialManager` — Contextual hints for new players
- `SteamManager` — GodotSteam wrapper (graceful no-op without Steam)
- `ProducerEconomy` — Seasons, episodes, the Influence balance, and the Catalog
- `AmbientMode` — Keeps the office living while the window is unfocused; builds the away digest

### Key Directories
- `autoloads/` — Singleton scripts + LLM backend modules
- `scenes/agents/` — Agent scene, needs, brain, memory, relationships
- `scenes/objects/` — InteractableObject base + 9 object types
- `scenes/conversations/` — ConversationInstance (multi-turn LLM dialogues)
- `scenes/events/` — EventManager, EventDefinition
- `scenes/world/` — Office layout with navigation, day/night tinting
- `scenes/ui/` — HUD, main menu, settings, save picker, achievements, hints, toasts
- `scenes/main/` — Root game scene
- `scripts/enums/` — AgentState, NeedType, ActionType, LifeStage
- `scripts/data/` — MemoryEntry, PersonalityProfile, RelationshipEntry, HealthState
- `scripts/utils/` — SpriteFactory, Palette, PromptBuilder, AudioGenerator, EpisodeRecap
- `resources/` — Personalities (JSON), prompts (TXT), events (JSON), achievements (JSON)

### Agent Systems
- **Needs**: energy, hunger, social, productivity, health — decay over game time
- **Brain**: LLM-powered with heuristic fallback (200+ diverse dialogue lines)
- **Memory**: Scored retrieval, emotional metadata, narrative threads, life summaries (max 300). Agents also remember their own confessionals as REFLECTIONs (`agent.gd::_on_confessional_recorded`), so what they said on camera feeds back into later decisions
- **Relationships**: Per-pair affinity/trust/familiarity/romantic_interest, personality compatibility
- **Secrets** (M7): ~35% of agents hold a private truth (`SecretManager`), backed by a protected `secret_<id>`-thread memory. They deny it in conversation (prompt `{secret_line}`), confide it only under trust, and the RumorMill spreads it from the confidant onward — three ears and it is exposed. The booth is the truth channel: admissions are player-only dramatic irony
- **Goals**: `personality.goals` prose becomes `GoalState`s (`GoalManager`). Kind is inferred from the text once; progress accrues only from real events (objects used, new conversation partners, confessions, days ended whole). Landing or losing one runs a `ConsequenceEngine` payload and clears the confessional's importance-6 bar
- **Health**: Aging through life stages (young→adult→senior→dying→dead), conditions, grief
- **Mood**: Visible emoji indicators (happy, tired, hungry, angry, sick, romantic)
- **State machine**: IDLE → DECIDING → WALKING → INTERACTING / TALKING → IDLE
- **Sprites**: 6-frame procedural pixel art (2 idle + 4 walk cycle)

### Objects (9 types)
desk, couch, coffee_machine, water_cooler (2 occupants), whiteboard (3 occupants), bookshelf, plant (passive), radio (toggleable), bed

### Keyboard Shortcuts
Space=pause, 1/2/3=speed, Tab=god mode, F5=save, F9=load, F12=screenshot, L=narrative log, R=relationships, C=confessional cam, E=episode recap, Esc=close overlays

### Save/Load
5 save slots at `user://saves/slot_N.json` with `.bak` backup. Auto-save every 5 game-days. Legacy migration from single-file save. Save v4 adds confessionals, v6 goals, v7 secrets; these restores sit outside the version gate, so older saves still load — a pre-v6 save simply has no goal block and agents re-derive theirs from personality on spawn.

### Episode Recap
`EpisodeRecap` (`scripts/utils/`) assembles a shareable Markdown recap from Narrator storylines + ConfessionalDirector quips. Pure synchronous read — storylines already carry LLM summaries, so it needs no LLM call. Viewable with **E**, exports to `user://recaps/`, and shown on the game-over overlay.

### Audio
Procedural fallback (AudioGenerator) when WAV/OGG files missing. File-based audio takes priority when present. Music crossfade between tracks.
