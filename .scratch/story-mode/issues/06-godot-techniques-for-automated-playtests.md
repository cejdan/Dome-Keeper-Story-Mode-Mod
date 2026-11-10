# Which Godot 4.3 techniques can drive and observe the game for automated playtests?

Type: research (AFK)
Status: open
Blocked by: none

## Question

What is the most reliable way for an agent to drive Dome Keeper and see the result?

Find out:

- Input injection: `Input.parse_input_event`, `Input.action_press` and `action_release`, and how `KeeperInputProcessor` reads input (so injected input moves the keeper).
- Screenshot capture from the viewport, and whether it works in `--headless` (likely not; then windowed).
- Movie Maker mode (`--write-movie`, `--fixed-fps`) for repeatable frame sequences.
- Passing a scenario to the game (`OS.get_cmdline_user_args`, `-- --scenario=...`).
- Calling the game's existing cheat functions (`stages/level/Cheats.gd`: add resources, skip or disable waves, reveal tiles, game speed, save and load slots) from a script.
- Fixing the map seed and time scale for repeatable runs.
- Where computer use (real mouse and keyboard on the game window) is the better tool.
