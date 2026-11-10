# Playtest harness v1: run a scenario, capture screenshots and a state log

Type: task (AFK)
Status: open
Blocked by: 05, 06

## Question

Build a dev-only harness inside the mod that runs a scenario and records what happened. It must not ship in release builds.

A scenario names: game mode, seed, setup steps (cheat functions or `Data.apply`), a list of timed actions (hold or press input actions, wait), and capture points (screenshot, frame burst of N frames, state snapshot).

## Done when

- One command runs a scenario and exits on its own.
- The output folder holds numbered screenshots, a frame burst, and a JSON log of chosen `Data` values (inventory, depth, `monsters.wavecooldown`), plus any errors.
- Demo scenario: start Story Mode, drill straight down 5 tiles, screenshot each step. The screenshots show the keeper going down.
- CLAUDE.md documents how to write and run a scenario.
