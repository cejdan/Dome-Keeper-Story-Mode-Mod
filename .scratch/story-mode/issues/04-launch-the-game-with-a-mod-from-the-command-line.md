# How do we launch the game with an unpacked mod from the command line?

Type: research (AFK)
Status: open
Blocked by: none

## Question

What exact command runs the decompiled project with the custom engine (`../custom_godot_for_windows/godot.windows.editor.x86_64.exe`) so that ModLoader loads a mod from `mods-unpacked/`, with no clicks in the editor?

Find out:

- Engine flags for running the project without the editor UI (`--path`, scene override, window size, `--quit-after`).
- Which ModLoader settings resource applies (`game/mod_loader_settings/`: `dome_editor.tres`, `dome_default.tres`) and how dev mode is switched on.
- Whether the game needs Steam running (`steam_api64.dll`, `systems/platform`) and how to run without it.
- Where game and ModLoader logs are written, and how to read errors after a run.
- How an existing game mode is registered and started (`Data.registerGameMode`, `content/gamemode/`, the wiki's Further Examples page).

Sources: wiki pages Getting Started, Testing your Mod, Troubleshooting, Known Issues; `addons/mod_loader/`.
