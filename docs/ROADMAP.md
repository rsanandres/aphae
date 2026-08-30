<!-- Produced 2026-08-30 by an 8-analyst / 3-skeptic / 1-synthesis agent panel.
     41 proposals raised, 35 survived adversarial review. Working engineering
     detail stays in PLAN.md; this is the strategy. -->

# Aphae — The Plan

## North Star

Aphae is **the reality show you produce, starring an AI cast that's actually alive** — a tiny broadcast that runs in the corner of your screen where every frame reads as television (LIVE bug, hard cuts, talking-head confessionals), every producer verb visibly moves the ratings, and the story engine renews itself instead of rerunning. "Next level" is measurable: a first-time browser player completes a full drama → grade → Influence → purchase loop inside 30 minutes, sees all three headline systems (confessionals, secrets, the mole) in hour one, never hears a verbatim repeat in hour two, and — on the exact web page every curious visitor lands on — can flip one switch and watch the cast think for real. The pitch stops being a claim and becomes the demo.

---

## Now — ~2 weeks: make the first hour prove the game

Everything here is felt in a first session. Sequence matters: 1–2 fix what the player does, 3–4 fix what they see, 5–6 fix what they're told.

1. **The Premiere package** *(week)* — merge of "1-day Pilot" + "Premiere Night" + "authored first 20 minutes." Base: `EPISODE_DAYS=1` for S1E1 with a pointed Catalog prompt at wrap. On top: the premiere curve — intro confessionals in the first ~5 minutes, one guaranteed seeded secret with an early booth admission, one event before noon of day 1, the host teasing the Mole with `open_case()` guaranteed by day 3–4. Acceptance test: full core loop completes inside 30 real minutes at 1x. *Everything else on this roadmap is invisible if the tab closes at minute ten.*
2. **Produced beats** *(days)* — read ImpactLog's existing attribution window in ProducerEconomy; ripples above importance 5.0 attributed to an intervention count double and fire a "Viewers loved that" toast. Fixes the verified absurdity that nudges (3.5) can't clear the 5.0 beat threshold. The producer fantasy made mechanically true, in one read-only hook.
3. **Broadcast chrome + hard cuts** *(days)* — LIVE/REC corner bug, DAY/time stamp, channel bug, vignette; `reset_smoothing()` + flash + zoom punch in `_do_cut`; the already-wired pixel font swap. Every screenshot becomes self-captioning. Prerequisite for every clip and trailer downstream.
4. **Zones shape drama** *(days)* — `social` block in synergies.json multiplying RumorMill / confide / romance rolls at the conversation midpoint. **Condition from the panel: print the modifier on the zone label** ("secrets flow here +60%") — a hidden 1.6x on a rare roll is invisible; a stated promise is a plan the player builds toward. This turns the placement verb from Sims residue into set design.
5. **Gate god mode** *(days)* — Tab becomes a labeled Creative toggle that flags the save; show mode routes all placement through Influence with progressive unlocks. Reorder the tutorial so the economy hint precedes the cheat hint. Without this, items 1–4 build an economy the Tab key voids.
6. **Honest words + honest prompts** *(days)* — soften "nothing here is scripted" to something the heuristic path can defend (an hour); verbalize Big Five traits in system.txt, add few-shot voice lines, anti-repeat context, per-task temperature; change the default model rec from the never-validated smollm2:1.7b to a 4B-class model. Zero-cost multiplier on every current and future backend.

---

## Next — ~2 months: renewable drama, a face, and a funnel

**Track A — the show gets a face** (do first; Track C depends on it)
- **Confessional booth cutaway** *(week)* — picture-in-picture talking head: scaled sprite, curtain + spotlight, mouth flap, typewriter quote, REC dot inside the frame. The marquee promise stops being a text toast; this is the game's shareable clip format.
- **Emotive faces + facing** *(week)* and **voice blips + leitmotif** *(days)* — mood-stamped eyes/mouths across existing frames, flip toward conversation partner, per-agent pitch hashed from the same seed as their looks, one five-note motif on wrap/achievement/cutaway. Drama becomes camera-legible; clips get an audio brand. Cap the audio-tuning time.

**Track B — episodes become television and stories renew**
- **Finale night + resolution scoring** *(days)* — last episode day raises admission/incident pressure; `_finish_episode` pays bonuses for goals, exposures, romances, and cases resolved inside the window. Interventions that *conclude* stories are what score. Do this before the wrap card work below.
- **"Next time on Aphae" — teasers + producer bets** *(week)* — at wrap, 2–3 teaser cards from live autoload state; stake Influence on one outcome. **Absorbs Network notes**: one predicate-verification engine and one card UI serve both framings; ship bets first, add contract-style objectives later only if the wrap moment still needs them. This is the one-more-day engine and the economy's missing sink.
- **The voice pipeline** *(week + ongoing)* — externalize all string pools (conversation, confessional, secrets, goals/quirks) to `resources/dialogue/*.json` with a coverage lint, **then** through the same pipe: per-session no-repeat draws, 5–10x offline-batch-generated pools (bake gemma3 quality into JSON), relational secrets with per-secret voice, event-keyed chatter lines. One migration, four proposals' payoff — the panel was unanimous that these must not be built separately.
- **Renewable drama wiring** *(days each)* — failed goals become secrets via `assign_custom`; exposure aftermath payloads through ConsequenceEngine (+ the probe-resentment trust rule); arcs.json 3→12 with a cooldown field; archetype cards + shuffle cast. All data-shaped, all ideal AI-agent content work, all defending week two against going quiet.

**Track C — distribution, in strict order**
- **Days 1–10:** itch.io mirror via butler in existing CI + honest AI-disclosure tags. The analytics baseline everything else needs.
- **Days 7–14:** gate the Pages deploy on CI passing, **then** Show HN with the audit-trail story. One-time card; don't play it before the gate and the Now-horizon polish land.
- **Days 14–45:** confessional clip cadence, two shorts/week — reality-show framing in player channels, AI-dev framing only in dev channels. Requires the cutaway. This is the only recurring marketing commitment; don't add more.
- **In parallel:** OpenAI-compatible backend (~200 lines: auth header, `/v1/chat/completions`, LM Studio/Groq autodetect) **with Step 3's LIVE tag and side-by-side sample riding along** as its conversion surface.

---

## Later — the big swing and the storefront

- **WebLLM opt-in brain for the browser demo** *(week claimed; budget 2–3x)* — the headline move: the differentiator, demonstrated on the exact page every visitor lands on, weights streamed from HF's CDN at zero hosting cost. Gated on itch analytics proving web traffic justifies a permanent support surface; the prompt pass and OpenAI backend de-risk it first.
- **The footage bin** *(weeks)* — the player picks 3 clips to headline the episode; auto-score becomes the floor, the edit becomes the skill. The last unbuilt README promise ("decide what airs") and the correct v2 once finale scoring has made wraps matter at all.
- **Steam page, day ~45–60** *(weeks)* — trailer cut from proven clips, capsule, screenshots from the existing harness, fix the stale achievement count, GodotSteam init-path test. Wishlists compound toward **February 2027 Next Fest — do not spend the one-shot slot on an October rush.**
- **Pre-Steam hardening** *(days each)* — scale-proof the tier round-robin (divide interval by tier size) + measure at 12/25/50 agents; save-version fixture corpus + forward-compat guard. Both mandatory before Auto-Cloud and "50 agents" become storefront claims; both invisible before then.
- **Small identity fixes when touched:** bloc voting/gossip terms from GroupManager data; aging-to-death behind a toggle (vote-outs and poachings are the genre-correct exits).

---

## Deliberately NOT doing

- **Bundled gguf / in-game model downloader** — never-run backend, empty addon dir, ~1GB depot, "slow/hot" vs. ambient positioning. The repo already documents every reason. Revisit only after WebLLM proves which small model is good enough.
- **Three separate onboarding systems** — Pilot, Premiere Night, and the authored first-20-minutes are one merged package, not three pacing systems tuned against each other.
- **A third episode overlay** — bets + finale resolution scoring cover stakes and missions; a standalone contract/quest board pushes the HUD toward generic management-sim clutter. Merged, not multiplied.
- **Event volume chasing (37→80 as a goal in itself)** — chains and chatter defend the illusion; raw incident count is RimWorld's game, not ours. Growth stays subordinate to the voice pipeline.
- **WebLLM this month** — highest-variance integration in the set; it waits for the analytics and the prompt/backend groundwork.
- **More marketing surface than one clip cadence** — an evenings-and-weekends solo dev cannot also run weekly devlogs and community seeding. One channel, measured.
- **Mobile (M6)** — still the only unshipped phase, still last.

---

## Tomorrow morning

**Ship the Pilot parameter.** Set episode 1 of a fresh save to wrap after one game-day with its grade card, payout, and a pointed Catalog prompt — then play it in the browser build at 1x and time the loop. It's the days-sized base every other Now item stacks onto, and its acceptance test ("full loop in 30 minutes") is the metric the whole Now horizon answers to. While the build runs: make the one-hour README caption fix.
