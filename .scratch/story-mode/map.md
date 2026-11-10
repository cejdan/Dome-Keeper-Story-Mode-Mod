# Story Mode mod

Label: wayfinder:map

## Destination

A playable, single-player Story Mode for Dome Keeper with all four core mechanics working and playtested: story text boxes that freeze the wave timer, a dollar economy and shop, a depth-based mineral ladder, and metal gates only the Suit Blaster breaks. Built on a playtest harness that lets an agent verify its own changes in the running game.

## Notes

- **Domain:** a GDScript mod for the decompiled game, loaded by ModLoader. Vanilla files are reference only; mod code lives in `mods-unpacked/`. Design goals: https://claude.ai/artifact/2uRKfLccTeaYAzEsKDNzrA. Working rules: `CLAUDE.md`.
- **This map carries execution.** Unlike a planning-only map, `task` tickets here are build work, each sized to one session. Every build ticket ends with its "Done when" checks run in the game: through the playtest harness once [Playtest harness v1](issues/07-playtest-harness-v1.md) is resolved, by launching the game and capturing screenshots before then.
- **Who decides what.** Game-design calls (values, feel, story, scope) are HITL `grilling` or `prototype` tickets and wait for the user; the agent never answers the user's side. Technical how-to calls are the agent's: resolved by spike inside the task ticket, with the reasoning recorded on it.
- **Skills:** `grilling` and `domain-modeling` for grilling tickets, `prototype` for prototype tickets, `research` for research tickets.
- **Pace:** one ticket per session, except research tickets. Takeable tickets are the open, unblocked, unclaimed ones; lowest number first.

## Decisions so far

- [Story Mode is its own game mode](issues/01-story-mode-is-its-own-game-mode.md): a separate mode in the loadout screen; vanilla modes stay untouched.
- [Story Mode is single-player only](issues/02-story-mode-is-single-player.md): one keeper, one team; co-op is not part of this effort.
- [Which pixel art tool will the agent use, and can it drive it?](issues/31-pixel-art-tool-the-agent-can-drive.md): LibreSprite, scripted headless, with a palette-encoding step; three test sprites verified in the engine.
- [How do we get sprites for the new minerals and the metal gate tiles?](issues/13-sprites-for-minerals-and-metal.md): agent-made sprites with locked colors in mod-owned palette cells; squares for metals, stars for gems, iron turns grey.

## Not yet specified

- **Full-run balance.** Once money, minerals, the shop and waves all exist: does a 30-minute run feel paced right, and where does it stall? Needs whole-run playtests and the user's feel calls.
- **Deposit count with depth.** "Slightly more common deeper" needs a number, after the per-layer mix is working.
- **Depth atmosphere.** Music, rumble, lighting or screen effects that rise with depth alongside the text boxes.
- **HUD polish.** A depth meter, money pop-ups on delivery, how the balance is shown.
- **Vanilla systems in Story Mode.** Which caves, relics, gadget chambers, power cores, drones and prestige features stay, change or go.
- **Translations and string keys** for new upgrades, minerals and story lines (wiki: Translations).
- **Art polish.** Whether agent-made sprites ship as final or get a human pass; the shape for mythril and unobtainium.
- **Release.** Packaging, versioning and distribution (wiki: Distributing your Mod).

## Out of scope

- Final boss, keeper health and mine hazards: a later effort with its own map, once this destination is reached.
- Co-op support: ruled out by [Story Mode is single-player only](issues/02-story-mode-is-single-player.md).
- Changes to vanilla game modes: ruled out by [Story Mode is its own game mode](issues/01-story-mode-is-its-own-game-mode.md).
