# Boss score (#172)

The boss sequence's music is written in code: `score.py` (the notes, the cues and their layers) and `variants.py` (the finale and the other finale candidates) play instruments from `synth.py` (saw-wavetable strings and brass, a formant choir, taiko and toms, braams, church bells, a tam-tam, a drum and bass kit with a reese bass, a convolution reverb) and write seamless loops to `mods-unpacked/cejdan-StoryMode/music/boss_<cue>_<layer>.ogg`. `boss/boss_music.gd` reads those OGGs from their bytes (no import step) and blends the layers with the fight.

| Cue | Tempo, length | Layers |
|---|---|---|
| fight | 132 bpm, 16 bars | 1 the pulse (phase 1), 2 war drums and brass (phase 2), 3 Velle's theme, choir, crashes (phase 3) |
| chase | 160 bpm, 16 bars | 1 the run, 2 what is behind you (louder as the tentacles close in) |
| finale ("Toll") | intro 7 bars once, then 174 bpm, 32 bars | intro: a gong and church bells ring the motif while the ground cracks, a heartbeat of kicks, a snare roll. 1 the break and reese bass, 2 dark horns, choir and bells on the theme |

Everything is in D minor. Velle's motif is D-Eb-D-A, in all three cues.

The finale opens with a breath of silence (#196): the intro starts when the keeper takes Battle at the console, or after 4 s walking about (the console's menu and the shop hold it off), and it pauses whenever the game does. The intro (`boss_finale_intro.ogg`) plays once; the loop starts exactly where its 7 bars end, and `boss/finale.gd` cracks the ground on each bell toll by the music's clock, so the tentacles break out on the drop. The beat map the visuals use is in `data/boss.gd` (`FINALE_TOLLS` and friends): change it together with `_toll_intro` in `variants.py`.

History, from the user's listens on 2026-11-15: the chase is loved as it is; the first finale (`finale_heroic` in `score.py`) was "too saccharine"; of four darker candidates (siege, requiem, unravel, toll) the user picked toll, then asked for a 10 s bell pause, a softer snare (the first one hurt: centred at 5 kHz), and the drums back up after that.

## Regenerate

Needs Python with `numpy`, `scipy`, `soundfile` (and `matplotlib` for `--preview`). From the `Dome Keeper` folder:

```
python art/music/score.py                            # all cues into the mod
python art/music/score.py finale                     # one cue
python art/music/score.py --preview                  # also a two-loop full mix and a spectrogram per cue in art/music/preview/
python art/music/score.py siege requiem unravel toll # finale candidates, to art/music/preview/ only
```

Each cue is seeded by its name, so rendering one cue never changes another, and the same command gives the same file. (The committed fight and chase files were rendered before per-cue seeds: rendering them again gives the same music with slightly different humanising dice.)

The master step gives all layers of a cue one shared gain (so their balance holds), aiming at the game's own battle music loudness (about 0.2 RMS for the full mix); band balance was matched to the vanilla final-wave music. In the game, `boss_music.gd` plays all of it `GAIN_DB` (3 dB) above that, because the boss fights are busier with sound than a wave (the user found the music a touch quiet against them, 2026-11-15); change the in-game level there, not in the files, which already peak near full scale. Levels, balance and seams are checked by measurement and spectrogram; the user listens and decides.
