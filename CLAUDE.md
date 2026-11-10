# Dome Keeper: Story Mode mod

This folder is the decompiled Dome Keeper project (Godot 4.3.1, custom build). We are building a Story Mode mod: a Motherload-style descent with a money economy, a depth-based mineral ladder, story text boxes from a monster in the depths, and metal gates that only the Suit Blaster can break.

- Design goals: https://claude.ai/artifact/2uRKfLccTeaYAzEsKDNzrA
- Build plan and issue board: GitHub Issues on https://github.com/cejdan/Dome-Keeper-Story-Mode-Mod. The wayfinder map is issue #1 ("Story Mode mod"); its tickets are sub-issues.
- The mod: `mods-unpacked/cejdan-StoryMode/` (`manifest.json`, `mod_main.gd`)
- Modding wiki: https://github.com/DomeKeeperMods/Docs/wiki
- Engine: `../custom_godot_for_windows/godot.windows.editor.x86_64.exe`
- Art: LibreSprite in `../tools/libresprite`, driven by scripts; pipeline and the game's palette encoding in `art/README.md`
- Vanilla game code is reference only. Mod code goes in `mods-unpacked/<Author-ModName>/`, never edits to vanilla files.

## Working rules

- The user is mostly away. Verify every change by playtesting it in the running game (playtest harness, screenshots, frame bursts, state logs) before calling it done. Report what was seen, not what was expected.
- Game-design calls (values, feel, story, scope) are the user's: leave them as HITL tickets. Technical how-to calls are yours: resolve them by spike and record the reasoning on the ticket.
- One ticket per session, except research tickets.
- Story Mode is single-player only and its own game mode; vanilla modes must keep working.

## Version control

- This folder is a clone of https://github.com/cejdan/Dome-Keeper-Story-Mode-Mod (branch `main`). `.gitignore` ignores everything by default and allowlists only our files (`mods-unpacked/`, `.scratch/`, `docs/`, `art/`, `CLAUDE.md`, `GLOSSARY.md`, `README.md`, `override.cfg`). Never commit vanilla game files; to track a new top-level file of ours, add a `!/<name>` line to `.gitignore`.
- Never work on `main`. Each ticket gets its own branch off an up-to-date `main`, named `ticket/<issue>-<short-slug>` (e.g. `ticket/6-mod-skeleton`). Push the branch and open a PR into `main` that links the issue. Merge only when the user says so.
- One commit per ticket, made when the ticket resolves, covering its code and assets. Message: `#<issue>: <ticket title>`, then a line or two on what changed and how it was verified.
- Before committing, run `git status` and check that only our files are staged.
- To roll back a ticket's change, `git revert` its commit. Don't rewrite history or force anything.

## Running the game

- Launch: `../custom_godot_for_windows/godot.windows.editor.x86_64.exe --path "<abs path>/Dome Keeper"`. The project is in dev mode and skips the title screen.
- **Real saves are off limits.** `override.cfg` gives dev runs their own user folder, `%APPDATA%\StoryModeDev`, with logs in `logs/godot.log` and `logs/modloader.log`. Without it, runs write into the real Steam save folder (`%APPDATA%\Godot\app_userdata\Dome Keeper`) and rotate the player's saves out. Never remove `override.cfg`, and never write to the real folder.
- Mod loaded? `modloader.log` should show `cejdan-StoryMode: Init` and `Done`. The title-screen Modding button is hidden in this game version.

## Agent skills

### Issue tracker

GitHub Issues via the `gh` CLI (`C:\Program Files\GitHub CLI\gh.exe`). See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at this folder's root, created when first needed. See `docs/agents/domain.md`.
