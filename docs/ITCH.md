# itch.io mirror — owner setup checklist

The CI scaffolding is already in place: every push to `main` that deploys
the Pages demo also tries to mirror the same web build to itch.io via
[butler](https://itch.io/docs/butler/). Until the secret below exists, that
step skips itself and prints why — nothing fails.

Why bother when Pages already hosts the demo: itch is where browser-game
players actually browse, and its analytics are the baseline the roadmap's
distribution decisions (Show HN timing, WebLLM go/no-go) want.

## One-time setup (~15 minutes, all on itch.io)

1. **Create the project.** itch.io → Upload new project.
   - Kind of project: **HTML**.
   - Pricing: free (or "no payments") to start.
   - You don't need to upload a file by hand — butler will create the
     `web` channel on its first push. If itch insists on a file to save the
     draft, upload any zip and delete it after the first CI push.
2. **Viewport**: 1280×720, and tick **"This file will be played in the
   browser"** on the channel after the first push (butler cannot set it).
3. **AI disclosure, honestly.** In the project's metadata, itch asks about
   generative-AI usage. The truthful answer for Aphae: the game *optionally*
   uses a local LLM the player runs themselves (and ships a hand-written
   heuristic path); repository art and text are authored. Tag it as the form
   requires — do not untick it to chase visibility; the roadmap's whole
   pitch is the honest audit trail.
4. **API key.** itch.io → Settings → API keys → generate.
5. **GitHub secret.** Repo → Settings → Secrets and variables → Actions →
   New repository secret: name `BUTLER_API_KEY`, value the key from step 4.
6. **(Only if the itch project isn't `rsanandres/aphae`)** add a repository
   *variable* `ITCH_TARGET` with the real `user/game` slug. The workflow
   defaults to `rsanandres/aphae`.

Next push to `main` does the rest. Check the run's "Mirror to itch.io" step
the first time; after that, butler pushes only changed files.

## What CI pushes

`build/web` (the no-threads web export, same artifact as the Pages demo) to
channel `web`, versioned by commit hash. Desktop builds stay on GitHub
Releases for now — mirroring those to itch channels is a one-line addition
to `release.yml` when wanted.
