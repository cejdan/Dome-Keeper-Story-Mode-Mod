# Mod skeleton: Story Mode appears in the loadout and starts a run

Type: task (AFK)
Status: open
Blocked by: 01, 04

## Question

Create the mod in `mods-unpacked/<Author-StoryMode>/` (`manifest.json`, `mod_main.gd`, `modInit()`), and register a Story Mode game mode that starts a normal-looking run with the Engineer.

## Done when

- Launching the game with the command from ticket 04 shows Story Mode in the loadout screen (screenshot).
- Choosing it starts a run with no errors in the log.
- A vanilla mode still starts normally with the mod loaded.
