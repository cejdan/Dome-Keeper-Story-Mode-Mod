# Dome Keeper: Story Mode mod

This folder is the decompiled Dome Keeper project (Godot 4.3.1, custom build). We are building a Story Mode mod: a Motherload-style descent with a money economy, a depth-based mineral ladder, story text boxes from a monster in the depths, and metal gates that only the Suit Blaster can break.

- Design goals: https://claude.ai/artifact/2uRKfLccTeaYAzEsKDNzrA
- Build plan and issue board: `.scratch/story-mode/map.md` (wayfinder map, tickets in `.scratch/story-mode/issues/`)
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

- Git repo root is this folder. `.gitignore` ignores everything by default and allowlists only our files (`mods-unpacked/`, `.scratch/`, `docs/`, `art/`, `CLAUDE.md`, `GLOSSARY.md`). Never commit vanilla game files; to track a new top-level file of ours, add a `!/<name>` line to `.gitignore`.
- One commit per ticket, made when the ticket resolves, covering its code, assets and the ticket/map updates. Message: `<ticket NN>: <ticket title>`, then a line or two on what changed and how it was verified.
- Before committing, run `git status` and check that only our files are staged.
- To roll back a ticket's change, `git revert` its commit. Don't rewrite history or force anything.

## Agent skills

### Issue tracker

Local markdown under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at this folder's root, created when first needed. See `docs/agents/domain.md`.
