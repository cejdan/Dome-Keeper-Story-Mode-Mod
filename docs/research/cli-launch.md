# Launching the game with an unpacked mod from the command line

Research for issue #5. Researched 2026-11-10 against the decompiled project (Godot 4.3.1 custom build `8573e4829`), `addons/mod_loader/`, and the DomeKeeperMods wiki (cloned from `https://github.com/DomeKeeperMods/Docs.wiki.git`). Every claim cites the file and line that owns it. Claims marked **verified** were also checked by launching the game (runs 1 to 5, 2026-11-10).

## The answer

Run this from **PowerShell** (or cmd), with the project's `override.cfg` in place:

```powershell
& "C:\Users\ncejd\Documents\dome_keeper_modding_v5.x\custom_godot_for_windows\godot.windows.editor.x86_64.exe" `
  --path "C:\Users\ncejd\Documents\dome_keeper_modding_v5.x\Dome Keeper" `
  --windowed --resolution 960x540 --position 40,40 `
  --quit-after 1500 `
  --log-file "C:\<somewhere private>\run.log" `
  -- --my-mod-arg
```

- No editor UI opens. Every folder in `res://mods-unpacked/` loads with no other setup. **Verified.**
- The game boots in dev mode, skips the title, and goes straight to `stages/landing/landing`, then the level. **Verified.**
- Steam does not need to run, and is not used. The run uses `PlatformFacadeDummy`. **Verified.**
- `--quit-after 1500` exits cleanly with code 0 after about 22 to 29 seconds. That is enough to reach the level. **Verified.**

**Don't launch from the Git Bash tool through MSYS `timeout`** (or any other MSYS wrapper). The child then gets no `APPDATA`, so `user://` falls back to `<project>/StoryModeDev/` (see Gotchas). Launching the exe directly from Bash works. Launching from PowerShell works.

## 1. Engine flags

From `godot.windows.editor.x86_64.exe --help` on this build:

| Flag | Effect |
|---|---|
| `--path <dir>` | Runs the project in `<dir>` (must hold `project.godot`). No `-e`, so the game runs and the editor stays closed. |
| `[scene path]` (positional) | Overrides the main scene. **Don't use it here.** `res://game/Game.tscn` (`project.godot` `run/main_scene`) does all the boot work in `Game._ready()`: `Platform.init`, `GameWorld.init` (which calls each mod's `modInit()`), `Options.init`. Any other scene skips all of it (`game/Game.gd:21-95`). |
| `--quit-after <n>` | Quits after `n` main-loop iterations (frames), not seconds. 1500 frames was about 25 s here. `--quit` quits after one frame. |
| `--resolution WxH`, `--position X,Y`, `--windowed`, `--screen N`, `--always-on-top` | Window placement. 960x540 is half of the game's 1920x1080. |
| `--log-file <abs path>` | Sends the engine log (stdout and errors) to this file instead of `user://logs/godot.log`. Use it to keep a run's log private from concurrent runs. It does **not** move `modloader.log`. **Verified.** |
| `--headless` | No window and a dummy audio driver. Not tried for a full game run. The renderer-heavy game may not be happy with it. |
| `--fixed-fps`, `--time-scale`, `--disable-vsync`, `--max-fps` | Deterministic or faster runs. |
| `--write-movie <file.png\|.avi>` | Records frames. It pairs with `--quit-after`. |
| `-- <args>` | Everything after `--` is for game code only. Read it with `OS.get_cmdline_user_args()`. This is the clean way to pass our own switches to the mod. |

Engine-unknown flags placed *before* `--` (such as the ModLoader flags below) are passed through. ModLoader and the game read them with `OS.get_cmdline_args()`.

### ModLoader CLI flags (`addons/mod_loader/mod_loader_store.gd:191-223`)

| Flag | Effect |
|---|---|
| `--disable-mods` | Sets `enable_mods = false`. **Verified**: `modloader.log` says `Mods are currently disabled`. Handy for a vanilla baseline run. |
| `--mods-path <dir>` | Overrides where **zipped** mods are found (`override_path_to_mods`). Unpacked mods always come from `res://mods-unpacked` (`internal/path.gd:194-200`). |
| `--configs-path <dir>` | Overrides the mod config folder. |
| `-v`/`--log-warning`, `-vv`/`--log-info`, `-vvv`/`--log-debug` | ModLoader log verbosity. |
| `--log-ignore=<mod,mod>` | Hides those mods' log lines. |
| `--enable-mods` | Only matters if `REQUIRE_CMD_LINE` is true. It is `false` here (`mod_loader_store.gd:24`, `mod_loader.gd:36`). |

The game itself reads `--server` and `--client` (`game/Game.gd:79-80`), for a dev networked start. Nothing else.

## 2. Which ModLoader settings apply, and dev mode

`res://addons/mod_loader/options/options.tres` picks the profile:

- `current_options = game/mod_loader_settings/dome_default.tres`: `enable_mods = true`, `log_level = 1`, `load_from_unpacked = true`, `load_from_local = true`, no workshop.
- `feature_override_options`: `"editor"` → `dome_editor.tres`, and `"console"` / `"disable_mods"` → `dome_disable_mods.tres`.
- `ModLoaderStore._update_ml_options_from_options_resource()` applies an override for each feature tag that `OS.has_feature()` reports (`mod_loader_store.gd:159-178`). The editor binary always has the `editor` tag, even when running the game without the editor. So **`dome_editor.tres` applies**: mods on, unpacked loading on, `log_level = 3` (debug). **Verified**: godot.log shows `Applying options override with feature tag "editor"`, and the other two tags are skipped.
- The files in `addons/mod_loader/options/profiles/` (including `current.tres`) are **not** referenced by `options.tres`. They are ModLoader's stock samples, not the active settings. The issue's earlier note that `current.tres` "already has" the right values is true but irrelevant.
- With the `editor` tag, unpacked mods load regardless of `load_from_unpacked` (`internal/path.gd:198`). The hook pack is skipped (`mod_loader.gd:42`).

Dev mode (`game/Game.gd:26-29`, `91-95`):

- `Game.devMode` defaults to `true` (`@export var devMode := true`, not overridden in `Game.tscn`).
- `if not OS.has_feature("editor"): devMode = false`, so an editor-binary run is always dev mode, unless...
- `user://dev-mode` existing forces dev mode on. That is how a shipped build gets it.
- Run mode: if `res://addons/dome_editor_ext/dome_editor_conf.tres` has `custom_play_pressed = true`, its `play_mode`, `game_mode` and players settings win. Otherwise dev mode means `ENTER_PLAY_MODE.Level`, and non-dev means Title. `dome_editor_conf.tres` has `custom_play_pressed = false`, so we get the hard-coded dev Level start.
- That dev Level start (`game/Game.gd:120-235`) builds a **Versus** loadout. `loadout.modeId = CONST.MODE_VERSUS` is fixed unless the editor conf says Relic. The loadout has dome1 (droneyard) and dome2 (shield) and one keeper. This explains the vanilla noise `unknown win condition ''` in `content/gamemode/versus/Versus.gd:30`: the dev loadout sets no versus win condition.
- There is **no CLI switch to land on the title screen or in a different mode**. The wiki's recipe (Testing your Mod → Switching to Dev Mode) is to toggle `Dev Mode` on `Game.tscn` or edit `Game.gd`. Its code sample is older than the current `Game.gd`. Both edit vanilla files, which our rules forbid. See Follow-ups.
- In dev mode, F1 opens the cheat menu (wiki, Testing your Mod).

## 3. Steam

- `Platform.create_facade()` (`systems/platform/Platform.gd:28-37`) uses Steam only if (`useSteamInEditor` and `editor` feature and the `Steam` singleton) or (`steam` feature and the `Steam` singleton). `Game.tscn` leaves `useSteamPlatformInEditor = false`, and the editor binary has no `steam` feature tag. So a CLI run always gets **`PlatformFacadeDummy`**. **Verified**: godot.log says `Initializing Platform: PlatformFacadeDummy_gd`.
- `steam_api64.dll` sits next to the engine exe, but nothing in a dummy-platform run needs Steam running. Earlier runs worked with Steam closed (issue comment). Today's runs happened with Steam open, and Steam was still not used.
- Testing a **zipped** mod: put it in `res://mods/` (wiki, Testing your Mod → Testing Your Mod Zip Locally). `load_from_local = true` reads that folder. godot.log notes `The directory for mods at path "res://mods" does not exist` when there is none.
- Testing in the real Steam game: drop the zip into `...\Steam\steamapps\workshop\content\1637320\<new folder>\` (wiki, Testing your Mod → Testing Your Mod in Steam). That run uses the real save folder, so it's off limits for agents.

## 4. Logs and reading errors

With `override.cfg` (`config/use_custom_user_dir=true`, `config/custom_user_dir_name="StoryModeDev"`), `user://` is `%APPDATA%\StoryModeDev\`:

| Log | Path | Notes |
|---|---|---|
| Engine log | `%APPDATA%\StoryModeDev\logs\godot.log` (rotated to `godot<timestamp>.log`) | Everything printed, including ModLoader lines with `[color=…]` BBCode prefixes. `--log-file` moves it. |
| ModLoader log | `%APPDATA%\StoryModeDev\logs\modloader.log` (`api/log.gd:9`) | Rotated on every start to `modloader_<date>_<time>.log` (`api/log.gd:571-590`). The number of backups follows `debug/file_logging/max_log_files`. The path is fixed, and `--log-file` doesn't move it. |

How to read a run:

1. Mod loaded: `modloader.log` shows `<mod>: Init` and `DONE: Completely finished loading mods`, and later `<mod>: Done`. **Verified.**
2. Mod script errors: grep godot.log for `SCRIPT ERROR`, `Parse Error`, and `Failed to load script`. A mod whose `mod_main.gd` fails to parse shows `Parse Error … (mod_main.gd:<line>)`, then ModLoader's `Nonexistent function 'new' in base 'GDScript'` at `mod_loader.gd:250`. The run carries on without that mod. **Verified**: another agent's WIP `cejdan-PlaytestSpike` did exactly this in my runs. Note the `inference_on_variant` warning ("type is being inferred from a Variant value") is an *error* in this project.
3. Ignore the vanilla noise: 34+34 `localization_*.translation` "Cannot open file" / "Resource file not found" lines, `unknown win condition ''`, and `Texture with GL ID … leaked` at exit. `Can't create shader cache folder … user://` means `user://` resolved badly (see Gotchas).
4. The ModLoader `feature tag` lines happen before `modloader.log` is rotated, so they appear only in godot.log.

## 5. How a game mode is registered and started

From the source (the wiki's Further Examples page has no game-mode example. It only links the Multiplayer-Examples repo for a monster and a keeper):

1. **Register for the loadout menu**: `Data.registerGameMode("<id>")` (`systems/data/Data.gd:1137-1139`) appends to `Data.loadoutGameModes`. The vanilla list is `[relichunt, assignments, prestige, versus]` (`Data.gd:19`). Call it from `modInit()`. `mod_main.gd` must `add_to_group("mod_init")`. `GameWorld.init()` calls `modInit()` on that group (`game/GameWorld.gd:187-188`) (wiki: Common Mod Hooks, Data class).
2. **Loadout validation**: a loadout whose `modeId` isn't in `loadoutGameModes` is silently reset to the first mode (`Data.gd:1246-1247`).
3. **Loadout UI** (`stages/loadout/MultiplayerloadoutStage.gd:720-734`): each mode gets icon `res://content/icons/loadout_<id>.png` and text `upgrades.<id>.title` / `upgrades.<id>.desc`. It's disabled unless `GameWorld.unlocks.is_unlocked(<id>)`, so the mod must unlock it (e.g. `GameWorld.unlockElement(<id>)`). `versus` is hidden in single-player.
4. **Level prep**: `GameWorld.prepareLevelStart` matches `modeId` for vanilla modes. An unknown id falls to `_:` and logs `unknown game mode` (`GameWorld.gd:232-337`), so nothing sets `levelStartData.mapArchetype` for us. Then **every node in group `gamemodes-prepare` gets `prepareGameMode(modeId, levelStartData)`** (`GameWorld.gd:340-341`, wiki: Common Mod Hooks → Using prepareGameMode()). That is the mod's hook to set the map archetype, upgrade limits and so on. `prepareRegularLevelStart()` (`GameWorld.gd:382-394`) shows what vanilla modes set.
5. **Mode node**: `LevelStage` instantiates `res://content/gamemode/<id>/<id.capitalize()>.tscn` and sets `Level.mode` to it (`stages/level/LevelStage.gd:188-191`). `String.capitalize()` turns `story_mode` or `storyMode` into `"Story Mode"`, with a space. So use a single lowercase word, e.g. `storymode` → `res://content/gamemode/storymode/Storymode.tscn`. The mod has to supply a resource at that path, e.g. `preload("res://mods-unpacked/cejdan-StoryMode/…/Storymode.tscn").take_over_path("res://content/gamemode/storymode/Storymode.tscn")` (wiki: Overwriting Resources). Vanilla mode scripts are plain `Node`s (`content/gamemode/relichunt/Relichunt.gd:1`).
6. **Starting it**: through the title → loadout flow, or by building a `LevelStartData` with `loadout.modeId = "<id>"` and calling `StageManager.startStage("stages/landing/landing", [startData])`, as `Game.gd`'s dev start does (`Game.gd:226-235`).

## Gotchas found while verifying

- **MSYS `timeout` drops `APPDATA`.** Launching the exe through `timeout` from the Git Bash tool, the game saw `OS.has_environment("APPDATA") == false`. So `OS.get_data_dir()` returned `.`, and `user://` became `<project>/StoryModeDev/`. (Run-only probe script: `get_user_data_dir()` printed `./StoryModeDev`.) The `APPDATA=… timeout …` prefix didn't help either. Launching the exe directly from Bash, or from PowerShell, gave `C:/Users/ncejd/AppData/Roaming/StoryModeDev`. Real saves stay safe either way (the path is never `Godot\app_userdata\Dome Keeper`). But logs land in the wrong place, `--quit-after` should be used instead of `timeout`, and a stray `Dome Keeper/StoryModeDev/` folder appears in the project (git-ignored by the allowlist). Another agent's live game was writing there during this research, so it was left in place.
- **ModLoader thinks our `override.cfg` is its own setup.** It logs `override.cfg setup detected, ModLoader will be the last autoload loaded` (`internal/godot.gd:21-26`), just because the file exists. Harmless today, because `ModLoaderStore` and `ModLoader` are already autoloads 1 and 2 in `project.godot`.
- **Every `mods-unpacked/` folder in the main checkout loads**, including other agents' unfinished mods (e.g. `cejdan-PlaytestSpike`). There's no CLI flag to load just one unpacked mod. Worktrees hold only our allowlisted files, not `project.godot`, so a worktree can't be run on its own.
- **Sentry starts in dev runs.** `project.godot [sentry]` holds Bippinbits' DSN. godot.log shows the SDK starting and `sending request … ingest.de.sentry.io … /envelope/`, even with `allowCrashReports: false` in the dev `options.txt` (`addons/sentry/sentry_configuration.gd` sets `options.enabled` from that flag).

## Sources

- Engine: `godot.windows.editor.x86_64.exe --help` (v4.3.1.rc.custom_build.8573e4829)
- `project.godot` (`[application]`, `[autoload]`, `[sentry]`), `override.cfg`
- `addons/mod_loader/mod_loader_store.gd`, `mod_loader.gd`, `internal/cli.gd`, `internal/path.gd`, `internal/godot.gd`, `api/log.gd`, `options/options.tres`, `options/profiles/*.tres`
- `game/mod_loader_settings/dome_default.tres`, `dome_editor.tres`, `dome_disable_mods.tres`
- `game/Game.gd`, `game/Game.tscn`, `game/GameWorld.gd`, `systems/data/Data.gd`, `systems/Const.gd`, `systems/platform/Platform.gd`, `stages/level/LevelStage.gd`, `stages/loadout/MultiplayerloadoutStage.gd`, `content/gamemode/versus/Versus.gd`, `addons/dome_editor_ext/dome_editor_conf.tres`, `addons/sentry/sentry_configuration.gd`
- Wiki (DomeKeeperMods/Docs): Getting Started, Testing your Mod, Troubleshooting, Known Issues, Further Examples, Common Mod Hooks, Data class, Overwriting Resources
- Verification runs, 2026-11-10: PowerShell `Start-Process … --quit-after 1500 --log-file …` (mods on), and `--disable-mods --quit-after 600` (mods off)

## Follow-ups

- **Boot straight into Story Mode, or onto the title, from the CLI without editing vanilla files.** Dev mode hard-codes a Versus Level start. Candidates: the mod reads `OS.get_cmdline_user_args()` (e.g. `-- --story-start`) and either script-extends `res://game/Game.gd` (`startGameInMode`), or replaces the stage after boot. It needs a spike to confirm `Game.gd` isn't loaded before the mod's extension installs.
- **Isolating one mod per run.** Other agents' WIP mods in the shared `mods-unpacked/` load into every run. Options: a per-run ModLoader user profile, a CLI arg our harness respects, or agreeing that WIP spikes live elsewhere.
- **Do dev runs send data to Bippinbits' Sentry?** The log shows envelopes sent despite `allowCrashReports: false`. Check, and turn it off for dev runs if so (e.g. an `override.cfg` key under `[sentry]`).
