<!-- Second edition, 2026-11-21. Supersedes the 2026-08-30 panel synthesis
     (kept in git history). Working engineering detail stays in PLAN.md;
     this file is the strategy and the open feature list. -->

# Aphae: The Plan

## Direction

Aphae is **the reality show you produce, starring an AI cast that is actually alive**. That has not changed. What changes in this edition is what "next" is for: Aphae is first an open playground for AI-agent simulation, and the storefront is parked (see [Storefront](#storefront-parked-not-cut)). So the plan now weights four things, in this order of dependency:

1. **Real brains**: the LLM path has to be something a visitor can switch on, not something the README describes.
2. **Deeper drama**: stories the simulation can recognise, renew, and conclude on its own.
3. **More producer game**: verbs with fallout, and an edit that is a skill.
4. **Look and sound**: faces, voices and clips, so the drama reads without a text log.

Three measures replace the old first-hour checklist. Each is a number a headless run can print, so an agent session can assert on it:

- **Repeat rate**: share of spoken lines that are verbatim repeats in a two-hour soak. Target zero on both brain paths.
- **Conclusion rate**: storylines that reach an ending (goal landed, secret out, case closed, pact broken) per episode.
- **Stance spread**: share of conversation turns that are not agreement. LLM agents drift prosocial ([arXiv 2504.02234](https://arxiv.org/pdf/2504.02234)); a cast that only agrees is not a show.

---

## Where the last edition landed

| 2026-08-30 item | State |
|---|---|
| Now 1-6: Premiere package, produced beats, broadcast chrome, zones shape drama, the economy gate, honest prompts | Shipped |
| Confessional booth cutaway; facing | Shipped |
| Finale night + resolution scoring; "Next time on Aphae" teasers and bets | Shipped |
| Episode snapshots and rewind | Shipped (was not on the plan) |
| Voice pipeline | Step 1 only: the confessional pool is data, with a lint and a local generator. Conversation, secret, goal and quirk pools are still in code; no per-session no-repeat draw |
| Emotive faces; voice blips + leitmotif | Open, carried below as L1 and L2 |
| Renewable drama wiring (failed goals become secrets, exposure aftermath, more arcs, archetype cards) | Open, carried as D1 and D4. `arcs.json` holds 4 arcs, none with a cooldown |
| OpenAI-compatible backend; in-browser brain | Open, carried as B1 and B3 |
| The footage bin | Open, carried as P1 |
| Scale-proofing the think round-robin; save fixture corpus | Open, carried as F3 |
| itch.io mirror | Scaffolded in CI behind a deploy secret; the step skips until one is added |
| Gate the Pages deploy on CI | Open, carried as F4. `web-demo.yml` still deploys on every push to `main` |

---

## What the research says

Collected 2026-11-21. Links are in [Sources](#sources). Anything marked unverified there is not relied on here.

**On the genre**

- The closest comparable, *The Crush House* (reality-show producer sim), was praised for named audience segments with concrete demands and trait-matched "sagas", and criticised because each day became the same task loop and buying props mattered more than the drama. Aphae should borrow the first two and treat the last two as warnings about the Catalog.
- LLM-NPC games that shipped did well where the AI was the whole loop and badly where it was bolted on. The recurring complaints are repetition, memory that resets, multi-second latency, and "tech demo" feel. Memory is called the weakest link.
- *Tomodachi Life: Living the Dream* was criticised for having no conflict, conversations that always go the same way, moods fixed by a snack, and no record of departed characters. It was praised for characters reusing words the player taught them.
- RimWorld's storytellers work because tension rises and falls with breathing room, and the simulation stays simple enough to observe.

**On making emergent drama legible**

- Story sifting can run incrementally and show *partial* pattern matches before they complete (Winnow). Ranking by statistical surprise finds moments hand-written patterns miss.
- LLMs sift poorly on their own: asked to find the story in a log, they paraphrase it. Select in code, narrate with the model.
- Project Sid's agents stayed coherent because one bottlenecked decision conditions both action and speech, and because a social-awareness module tracks how others feel about the agent. Without it, relationships flatten.
- Personas grounded in an interview transcript hold their voice better than trait adjectives.

**On the tech**

- No Godot LLM addon exports to the web. The browser brain has to live on the JavaScript side and be reached through `JavaScriptBridge`. No published write-up of that pairing was found, so it starts as a spike.
- WebGPU has 86.83% global support by caniuse, with Firefox and desktop Safari partial. WebLLM 0.2.89 ships prebuilt small models (by its own figures LFM2.5-350M needs 532 MB of VRAM, Qwen3.5-0.8B 1,629 MB). wllama 3.13.0 runs GGUF, offers an OpenAI-style API, and needs COOP/COEP headers only for multithreading. Aphae's web export is single-threaded on purpose, which keeps plain Pages hosting working.
- NobodyWho is the one maintained in-engine option that targets Godot 4.6, with JSON-schema constrained sampling, tool calling and embeddings. The GDLlama slot Aphae reserves is empty and its Asset Library entry dates from 2024.
- Small models with permissive licences now exist at every size: Qwen3.5 0.8B / 2B / 4B (Apache-2.0; 533 MB, 1.28 GB, 2.74 GB at Q4_K_M), SmolLM3-3B (Apache-2.0, 1.92 GB), Phi-4-mini (MIT, 2.49 GB), Gemma 4 E2B (Apache-2.0, 3.11 GB). The README's current recommendation, `gemma3:4b`, sits under the Gemma Terms and has never been measured here.
- Embedding models small enough to ignore exist: all-MiniLM-L6-v2 (Apache-2.0, 21 MB) and bge-small-en-v1.5 (MIT, 25 to 37 MB).
- Bundled speech has a licence problem: Kokoro and Piper both pull in GPL-3 espeak-ng. Procedural voice blips have none.

---

## The feature list

Sizes describe scope, not duration. **S** touches one system and its harness. **M** touches two or three systems or adds an autoload. **L** adds a subsystem with UI and a save bump. Every item names the check that proves it, because most of this will be built by agent sessions working against the headless harnesses.

### F. Foundations: make the rest measurable

| # | Item | Size | What and why | Proof |
|---|---|---|---|---|
| F1 | **Seeded runs** | S | A `--seed` user argument that seeds the global RNG for `headless_sim` and every harness. There is no seeding today, so a flake cannot be replayed. Applies to the heuristic path only; LLM output is not deterministic. | Two runs with the same seed print identical narrative logs |
| F2 | **The soak report** | S | `headless_sim` writes a metrics JSON at exit: repeat rate, conclusion rate, stance spread, time to first drama, conversations per game-day, think-tick time. The three measures above become CI numbers. | CI publishes the report; a threshold on repeat rate fails the run |
| F3 | **Scale and save hardening** | M | Divide the tier round-robin interval by tier size and record think-tick time at 12, 25 and 50 agents. Add a fixture corpus of one save per version (v4 to current) with a forward-compat guard. | New harness loads every fixture; the soak report carries the three scale rows |
| F4 | **Deploy only what passed** | S | Run the web deploy after the test workflow succeeds, not beside it. | A red test run publishes nothing |
| F5 | **Content packs** | M | Load and merge `user://packs/*/` JSON for personalities, objects, events, arcs, dialogue and synergies. Everything is already data; this lets content arrive without a code change and makes content pull requests reviewable. Extend the dialogue lint to every pack file type. | A fixture pack adds one object, one arc and one line, and each appears in a seeded run; a malformed pack is skipped with a warning, never a crash |

### B. Real brains

| # | Item | Size | What and why | Proof |
|---|---|---|---|---|
| B1 | **OpenAI-compatible backend** | M | `llm_backend_openai.gd` beside the Ollama backend: `/v1/chat/completions`, optional bearer key kept in `settings.cfg` and never in a save, JSON-schema response format where the server supports it. Opens LM Studio, llama.cpp server and hosted endpoints with one module. | Harness starts a local stub server and asserts request shape, auth header, and fallback to heuristic on timeout and on malformed JSON |
| B2 | **The model bake-off** | M | A script that replays fixed prompt fixtures (decision, conversation, confessional, interview) against any backend and scores JSON validity, measured latency, n-gram repetition, voice distinctness between two personalities, and stance adherence. Results go to `docs/MODELS.md`. Replaces a recommendation nobody measured. | The table exists for at least Qwen3.5 0.8B / 2B / 4B, SmolLM3-3B, Phi-4-mini and Gemma 4 E2B; the README recommendation cites it |
| B3 | **The browser brain** | L | An opt-in switch on the web demo that loads a small model in the page and routes `LLMManager` requests to it through `JavaScriptBridge`. Start with a spike that settles wllama (CPU and WebGPU, OpenAI-style API, so it can reuse B1's request mapping) against WebLLM (WebGPU only). Feature-detect, show download size and progress, fall back to heuristic silently. | A Playwright run loads the export, flips the switch against the smallest model on the wasm path, and sees one model-written line. WebGPU in headless Chromium is unverified, so the wasm path is the CI path |
| B4 | **Stances: the code decides, the model writes** | M | Before each conversation turn, pick a stance from relationship and need state (agree, deflect, needle, refuse, confide, lie) and pass it to the prompt as a constraint. The heuristic path draws from stance-keyed pools. Counters prosocial drift and keeps talk consistent with what the agent then does. | Stance spread in the soak report rises on a rival-pair fixture; a harness asserts a `refuse` stance never yields an acceptance |
| B5 | **Memory receipts** | S | When a retrieved memory shaped a decision or a line, record which one and show it in the inspector ("because: Bob took the credit, day 3"). Makes the most-criticised part of LLM games visible instead of asserted. | Harness plants a memory, triggers the dependent decision, and reads the receipt |
| B6 | **Embedding recall** | M | Optional rerank of `AgentMemory.retrieve` by embedding similarity when the active backend offers embeddings, with the keyword scorer as the fallback and the default. | A fixture of paraphrased queries where keyword scoring misses and the rerank hits |
| B7 | **Interview-grounded personas** | M | Give each cast member a short first-person interview transcript at spawn (authored for the five named cast, generated offline for the rest) and ground prompts in it. | B2's voice-distinctness score improves against the trait-adjective baseline |
| B8 | **In-engine model via NobodyWho** | L | Replace the empty GDLlama slot. The player points at a GGUF file; nothing is bundled in the repo or the release. Gives schema-constrained output with no server running. Do after B2 has named a model worth pointing at. | A smoke harness on Linux CI loads the smallest model from cache and gets one schema-valid decision |

### D. Deeper drama

| # | Item | Size | What and why | Proof |
|---|---|---|---|---|
| D1 | **Finish the voice pipeline** | M | Move the conversation, secret, goal and quirk pools to `resources/dialogue/*.json`, add the per-session no-repeat draw, then grow pools offline with `tools/generate_dialogue.py`. Carried from the last edition, where all four payoffs were to go through one migration. | Lint covers every domain; repeat rate in a two-hour heuristic soak is zero |
| D2 | **Brewing storylines** | L | A pattern file (`resources/story_patterns.json`): each pattern is an ordered list of beat predicates over the event stream (love triangle, betrayal, rise and fall, unlikely friendship, the keeper's dilemma). A matcher keeps partial matches alive and the HUD shows them ("2 of 3 beats"). Teasers and bets read from partial matches, which the existing predicate engine can settle. The model only writes the title and summary. | Harness feeds a scripted event stream and asserts partial then complete matches; a bet placed on a partial match settles |
| D3 | **Surprise ranking** | S | Score every narrative event by importance times rarity (inverse frequency of its kind this season). The recap and episode card lead with the top-ranked moments. Prerequisite for P1. | Harness: one rare event outranks five common ones of equal importance |
| D4 | **Arcs v2: sagas for two and three** | M | Extend `arcs.json` with roles and trait predicates so an arc can cast several agents (a triangle fires when three fits exist), add a cooldown field, and grow 4 arcs to 12. Wire failed goals into secrets through `SecretManager.assign_custom`, and exposure aftermath through `ConsequenceEngine`. | Each new arc runs start to finish in `events_test`; a failed goal produces a secret; no arc restarts inside its cooldown |
| D5 | **Perceived relationships** | M | Each agent tracks what they *believe* another thinks of them, updated from conversations and hearsay, separate from the truth. The gap is drama: the friend who is not one, the crush that was never noticed. Feeds B4 stances and D2 patterns. | Harness plants a false belief, then asserts the stance chosen and the correction memory when the truth lands |
| D6 | **Pacts and blocs** | M | Alliances become explicit state: formed in conversation under trust, visible in the relationship web, and broken with a betrayal memory. `GroupManager` groups vote as blocs in house meetings. | `whodunit_test` gains bloc cases; a broken pact writes a protected memory on both sides |
| D7 | **The Cut** | L | An elimination season format: at each wrap the house votes one cast member off from relationships, blocs and hearsay, and a new hire arrives next episode. Reuses the house-meeting vote and `depart_agent`. Needs D6 first, or the vote is a popularity average. | New harness; roster never drops under `MIN_CAST`; the departed appear on the alumni wall |
| D8 | **Storytellers** | S | Move `DramaDirector`'s constants into `resources/storytellers.json` with three presets (steady climb, long quiet then storm, chaos), chosen at new game. Draw the episode's tension curve on the wrap card. | Three seeded soaks show three distinct event-spacing profiles in the soak report |
| D9 | **Alumni wall** | S | A record of everyone who left: how, when, their arc in two lines, their best quote. Returnees already exist; the record of them does not. | Save round-trip keeps the wall; recap links to it |
| D10 | **The cast picks up your words** | S | Phrases from planted rumours and interview questions enter a small lexicon the cast can reuse later. | Harness plants a coined phrase and finds it in a later line on the heuristic path |

### P. More producer game

| # | Item | Size | What and why | Proof |
|---|---|---|---|---|
| P1 | **The footage bin** | L | At the wrap, pick three clips to headline the episode from the surprise-ranked moments. The auto-score is the floor; the edit moves the grade and which audience segment it lands with. The README's "decide what airs", built. | `economy_test`: the same episode grades differently under two edits; skipping the edit yields the auto-score |
| P2 | **Audience segments** | M | Three or four named audiences with conflicting appetites (romance, chaos, comfort, mystery). Two are tuned in each episode and the mix changes, so the same play does not score twice. Ratings read from which beats aired. Prices in the Catalog stay tied to drama outcomes, not prop counts. | Harness: one event stream scores differently under two segment mixes; the card names who loved it and who left |
| P3 | **The booth, with receipts** | M | Call a cast member to the booth and confront them with something specific: a memory you saw, a rumour you traced. Evidence raises the admission chance; a bluff with nothing behind it costs trust. | `secrets_test`: admission chance with evidence exceeds without; a failed bluff lowers trust and logs to the impact log |
| P4 | **Three verbs with fallout** | M | Seat chart (assign desks beside a rival or a crush), promote or fire (resentment, grief, new rivalries), and mediate a conflict (can backfire on personality). All three are on the standing backlog and none exists. | Each verb has a refusal or backfire branch asserted in `producer_test` and an impact-log entry |
| P5 | **Casting call** | M | At season start, choose the cast from archetype cards that show trait chemistry hints, or shuffle. Makes the first decision of a season a producer decision. | Premiere harness: chosen cards spawn the matching personalities; shuffle is seed-stable |
| P6 | **Renewal night** | M | A season ends with a verdict. Ratings across the season against a bar decide renewed or cancelled, with a recap either way and carry-over on renewal. There is no season-level stake today. | `economy_test` covers both verdicts and the carry-over |
| P7 | **The audience votes** | M | Optional read-only Twitch chat: chat votes on producer dilemmas and house meetings, and viewer names fill new-hire slots. Read-only chat avoids hosting an extension. Off by default and absent from the web build. | Harness feeds a fake chat stream into the vote tally; no network call is made when the setting is off |

### L. Look and sound

| # | Item | Size | What and why | Proof |
|---|---|---|---|---|
| L1 | **Emotive faces** | M | Mood-stamped eyes and mouths across the existing six frames in `SpriteFactory`, so a feud reads at a glance. | Screenshot harness emits a mood sheet per cast member; needs a human look once |
| L2 | **Voice blips and a leitmotif** | M | Per-agent blip pitch hashed from the same seed as their looks, played per syllable in bubbles and the booth; one five-note motif on wrap, achievement and cutaway. Procedural, so no assets and no licence question. | Audio generator harness asserts distinct pitch per agent and silence when SFX is muted |
| L3 | **Share cards and clips** | M | One key writes a composed PNG of the booth frame with its quote; a second keeps a ring buffer of frames and writes the last few seconds as an animation. The web build downloads it. The encoder for the animation needs a spike. | Harness writes a share card and checks dimensions and non-blank pixels |
| L4 | **Previously on Aphae** | S | Loading a save opens with a short montage card of last episode's top-ranked moments, from D3. | Loading a fixture save shows the card with that save's moments |
| L5 | **The strip** | M | A bottom-of-screen layout for desktop-pet mode with a transparent background and mouse passthrough outside the office. Godot supports passthrough on Windows, macOS and X11, not Wayland, so it degrades to the current corner window there. | Windowed check on each platform; cannot be proven headless |
| L6 | **Comfort settings** | S | UI scale, a reduced-flash switch for hard cuts and zoom punches, and mood indicators that do not rely on colour alone. The viewport is 320x214, so small text is the default failure. | `gui_check` runs at each UI scale with no clipped overlay |
| L7 | **Sets** | M | Office themes as data: palette, floor plan and starting furniture (newsroom, loft, night shift). | A seeded run boots on each set with navigation intact |

---

## Order

Each step unblocks the next. Items inside a step are independent.

1. **F1, F2, F4.** Seeds and the soak report first, because every later item claims a number.
2. **D1, B1.** The voice pipeline closes the repeat-rate gap on the heuristic path; the OpenAI-compatible backend is the base the next two brain items stand on.
3. **B2, B4, D3, D8.** Measure the models, fix the agreeable cast, rank the moments, make the pacing a choice.
4. **D2, L1, L2, B5.** The simulation starts recognising its own stories, and the cast gets faces, voices and visible memory.
5. **B3.** The browser brain, once B1's mapping and B2's model choice exist.
6. **P1, P2, D4, D5.** The edit and the audience on top of ranking; sagas and perceived relationships under them.
7. **D6, then D7 and P6.** Blocs before eliminations, and eliminations beside a season verdict.
8. **The rest as wanted:** P3, P4, P5, L3 to L7, D9, D10, F3, F5, B6, B7, B8, P7.

---

## Storefront: parked, not cut

The last edition aimed at Steam Next Fest in February 2027. That target is retired, for reasons that are checkable:

- The February 2027 fest runs February 22 to March 1. Registration closes January 10, 2027 and requires a store page that is already published. There is no store page.
- A game may take part in one Next Fest, ever. The slot is not worth spending early: in the February 2026 fest the median surveyed game gained 806 wishlists, and in October 2026 only 7.6% of demos reached 10 concurrent players among 7,240 entries.
- If the storefront is picked up again, the next edition is June 14 to 21, 2027, with registration closing April 25.

What a restart would need, so nobody rediscovers it: a written guardrails description for live-generated dialogue (Valve asks for one), a plain statement of what the AI does and does not do (a 2026 survey of engaged Steam users found 31% negative toward AI disclosure and only 17% who think developers disclose fully), the GodotSteam init-path test, the achievement count fix, and controller support plus a 9 px minimum font at 1280x800 for Deck. Simplified Chinese is the second-largest Steam language and was 26% of sales for the nearest desktop-idle comparable.

---

## Deliberately not doing

- **Bundling model weights** in the repo or the release. B8 points at a file the player supplies. The reasons in PLAN.md stand.
- **Bundled speech synthesis.** The practical small engines bring GPL-3 espeak-ng or custom model licences. Blips first (L2); revisit only with a clean stack.
- **A cloud brain by default.** Hosted endpoints are something a player can point B1 at with their own key. The project does not run one or pay for one.
- **Letting the model sift.** Selection, scoring and state changes stay in code; the model narrates. This is a research finding and a rule for every item above.
- **A contract or quest board.** Bets, segments and the edit cover stakes without a third episode overlay.
- **Event count as a goal.** Sagas, patterns and voice defend against repetition; raw incident volume does not.
- **A Twitch extension.** Read-only chat (P7) or nothing.
- **Mobile.** Cut 2026-08-31.

---

## Sources

Research gathered 2026-11-21.

- Next Fest dates and rules: [February 2027](https://partner.steamgames.com/doc/marketing/upcoming_events/nextfest/feb_2027), [June 2027](https://partner.steamgames.com/doc/marketing/upcoming_events/nextfest/june_2027), [eligibility](https://partner.steamgames.com/doc/marketing/upcoming_events/nextfest)
- Next Fest outcomes: [February 2026](https://howtomarketagame.com/2026/04/13/making-sense-of-the-february-2026-steam-next-fest/), [October 2026](https://howtomarketagame.com/2026/10/21/how-sloppy-is-the-october-2026-steam-next-fest/)
- Steam AI disclosure: [content survey](https://partner.steamgames.com/doc/gettingstarted/contentsurvey), [player sentiment survey](https://newsletter.gamediscover.co/p/what-do-steam-fans-really-think-about)
- Steam Deck compatibility: [requirements](https://partner.steamgames.com/doc/steamdeck/compat)
- The Crush House: [design interview](https://www.engadget.com/gaming/pc/how-the-crush-house-turns-procedural-generation-into-social-manipulation-160020111.html), [Game8 review](https://game8.co/articles/reviews/the-crush-house-review), [Shacknews review](https://www.shacknews.com/article/140900/the-crush-house-review-score)
- Shipped LLM-NPC games: [what shipped and what worked](https://www.eposyne.com/insights/ai-npcs-what-shipped-what-worked) (single secondary source), [Whispers from the Star review themes](https://vaporlens.app/app/3730100/whispers_from_the_star)
- Tomodachi Life: Living the Dream: [Kotaku review](https://kotaku.com/tomodachi-life-living-the-dream-review-nintendo-switch-miis-island-user-generated-content-2000693325)
- RimWorld storytellers: [wiki](https://rimworldwiki.com/wiki/AI_storyteller)
- Story sifting: [Winnow](https://ojs.aaai.org/index.php/AIIDE/article/view/18903), [Select the Unexpected](https://mkremins.github.io/publications/StU_ICIDS2022.pdf), [LLMs as sifters](https://computationalcreativity.net/iccc23/papers/ICCC-2023_paper_124.pdf), [LLM storylets](https://arxiv.org/abs/2501.09099)
- Agent architecture: [Project Sid](https://arxiv.org/html/2411.00114v1), [prosocial bias](https://arxiv.org/pdf/2504.02234), [interview-grounded personas](https://arxiv.org/abs/2411.10109)
- In-engine LLM: [NobodyWho](https://docs.nobodywho.ooo/godot/), [its sampling docs](https://docs.nobodywho.ooo/godot/sampling), [its web export issue](https://github.com/nobodywho-ooo/nobodywho/issues/111), [godot-llm](https://github.com/Adriankhl/godot-llm)
- Browser inference: [WebGPU support](https://caniuse.com/webgpu), [WebLLM](https://www.npmjs.com/package/@mlc-ai/web-llm), [wllama](https://github.com/ngxson/wllama), [Godot JavaScriptBridge](https://docs.godotengine.org/en/stable/tutorials/platform/web/javascript_bridge.html), [Godot web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- Models: [Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B), [SmolLM3-3B](https://huggingface.co/ggml-org/SmolLM3-3B-GGUF), [Phi-4-mini](https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF), [Gemma 4 E2B](https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF)
- Embeddings: [all-MiniLM-L6-v2](https://huggingface.co/second-state/All-MiniLM-L6-v2-Embedding-GGUF), [bge-small-en-v1.5](https://huggingface.co/CompendiumLabs/bge-small-en-v1.5-gguf)
- Speech: [Kokoro](https://huggingface.co/onnx-community/Kokoro-82M-ONNX), [Piper](https://github.com/OHF-Voice/piper1-gpl)
- Twitch chat for Godot: [Twitcher](https://www.godotengine.org/asset-library/asset/2629)
- Desktop-idle comparables and window flags: [Rusty's Retirement](https://newsletter.gamediscover.co/p/how-rustys-retirement-idle-farmed), [Godot DisplayServer](https://docs.godotengine.org/en/stable/classes/class_displayserver.html)
- Steam language share: [Hardware and Software Survey](https://store.steampowered.com/hwsurvey/Steam-Hardware-Software-Survey-Welcome-to-Steam)
