# Version control for the mod workspace

Type: task (HITL)
Status: claimed
Blocked by: none

## Question

What should git track so every session can roll back mod changes, without committing the whole decompiled game?

The `Dome Keeper` folder is the full decompiled game (large, and not ours to redistribute). A `.gitignore` that ignores everything except our own files is the likely answer: `mods-unpacked/`, `.scratch/`, `docs/`, `CLAUDE.md`, `GLOSSARY.md`, and any test harness files.

## Done when

- The user has said yes to creating the repo and to its first commit (commits need the user's go-ahead).
- `git status` lists only our files, never vanilla game files.
- CLAUDE.md says how sessions should commit (one commit per ticket).

## Comments

- 2026-11-10 (agent): Prepared, waiting for the user's go-ahead. `.gitignore` written at the project root as an allowlist (`/*` ignored, then `!/` lines for `.gitignore`, `CLAUDE.md`, `GLOSSARY.md`, `.scratch/`, `docs/`, `art/`, `mods-unpacked/`; `.godot/` ignored everywhere, including `art/tools/engine_render`). Dry run against a throwaway git dir outside the project: 96 files would be tracked (`.scratch` 32, `art` 60, `docs` 2, `CLAUDE.md`, `.gitignore`), and no vanilla files; `project.godot`, `upgrades.yaml`, `content/`, `game/`, `addons/` and `.godot/` all check as ignored. CLAUDE.md now has a Version control section (one commit per ticket, message `<NN>: <title>`, revert to roll back). `../tools/libresprite` and the engine stay outside the repo. No repo created yet.
