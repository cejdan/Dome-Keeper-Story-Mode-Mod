"""Finale candidates (#172, round 2), rendered to art/music/preview/ for the
user to choose from. The first finale was too saccharine: a pop-heroic
i-VI-III-VII loop with the theme leaping up and strings an octave over it.
Each candidate has two layers like the finale (1 the battle, 2 the theme) and
keeps Velle's motif, D-Eb-D-A.

  siege     150 bpm. The chase's drive: dissonant chords over a held D, the
            motif low in dark horns, then high trumpets in the second half.
  requiem   108 bpm. Tragic and broad: a choir lament over the falling lament
            bass (D C# C B Bb ...), the motif in low horns, bells.
  unravel   138 bpm. Horror: a chromatic ostinato, the motif climbing by minor
            thirds (D, F, Ab, B), shrieking on the flat ninth at the end.
  toll      The user's idea: bells and a gong toll the motif while the ground
            cracks (a 4-bar intro, played once), then the battle drops into
            drum and bass at 174 bpm: a breakbeat and a reese bass on the
            motif's rhythm, dark horns, choir and bells over it.

    python art/music/score.py siege requiem unravel toll
"""
import os

import numpy as np

import synth as S
from score import N, root, voicing, ostinato, melody, write_ogg, spectrogram

PEDAL = [0, 0, 12, 0, 1, 0, 12, 0, 0, 0, 12, 0, 8, 7, 1, 0]
HEART = [0, None, 0, None, 12, None, 0, None, 0, None, 0, None, 7, None, 0, None]
CHROMATIC = [0, 1, 0, 12, 0, 1, 0, 7, 0, 1, 0, 12, 6, 7, 6, 1]
TRESILLO = [(0, 1.0), (0.75, 0.6), (1.5, 0.8), (2, 0.95), (2.75, 0.6), (3.5, 0.8)]


def _drums(t, layer, bars, pattern, snares=(1, 3), ticks=0.5, fills=(), send=0.33):
    for b in bars:
        for off, v in pattern:
            t.put(layer, b * 4 + off, S.taiko(v, 1.0), send=send)
        for sb in snares:
            t.put(layer, b * 4 + sb, S.snare(0.85), send=0.3)
        if ticks:
            for e in range(int(4 / ticks)):
                t.put(layer, b * 4 + e * ticks, S.tick(0.55 if e % 2 == 0 else 0.35, -0.35 if e % 2 == 0 else 0.35), send=0.08)
        if b in fills:
            for k in range(8):
                t.put(layer, b * 4 + 2 + k * 0.25, S.tom(0.45 + 0.07 * k, 1.35 - 0.06 * k, -0.4 + 0.1 * k), send=0.3)


def _low_pulse(t, chords, vel=0.9):
    """Low string octaves on the 8ths and a sub under each bar."""
    for b, ch in enumerate(chords):
        for e in range(8):
            t.put("1", b * 4 + e * 0.5, S.strings_stacc(root(ch, 2), vel if e % 2 == 0 else vel * 0.78, length=0.12, bright=1800), send=0.15)
        t.put("1", b * 4, S.sub(root(ch, 1) + 12, 4 * t.beat * 0.9, 0.8))


# ---- siege ------------------------------------------------------------------

def siege():
    chords = ["Dm", "Eb/D", "Dm", "C#dim/D", "Dm", "Eb/D", "Bbm/D", "A/D", "Gm", "Ab/G", "Gm", "A", "Dm", "Eb", "C#dim", "A"]
    t = S.Track(150, 16, ["1", "2"])
    ostinato(t, "1", chords[:8], vel=0.85, length=0.09, pattern=PEDAL, pedal="D3")
    ostinato(t, "1", chords[8:], vel=0.85, length=0.09, start_bar=8)
    _drums(t, "1", range(16), TRESILLO, ticks=0.25, fills=(7, 15))
    _low_pulse(t, chords)
    t.put("1", 0, S.boom(1.0), send=0.3)
    t.put("1", 15 * 4, S.riser(4 * t.beat, 0.9), send=0.2)
    low = [("D4", 2), ("Eb4", 2), ("D4", 2), ("A3", 2), ("R", 2), ("F4", 1), ("E4", 1), ("E4", 2), ("C#4", 2),
           ("D4", 2), ("Eb4", 2), ("G4", 2), ("Bb3", 2), ("F4", 2), ("Db4", 2), ("E4", 2), ("C#4", 2)]
    high = [("G4", 2), ("Ab4", 2), ("G4", 2), ("D4", 2), ("Bb4", 2), ("A4", 1), ("G4", 1), ("A4", 2), ("C#5", 2),
            ("D5", 2), ("Eb5", 2), ("D5", 2), ("A4", 2), ("E5", 2), ("G5", 2), ("A5", 4)]
    melody(t, "2", low, 0, vel=1.0, inst="horns")
    melody(t, "2", high, 8, vel=1.0, inst="brass")
    for b in range(4, 8):
        t.put("2", b * 4, S.choir(voicing(chords[b], 3, spread=False), 4 * t.beat * 0.97, 0.7, vowel="oh", attack=0.3), send=0.45)
    for b in range(12, 16):
        t.put("2", b * 4, S.choir(voicing(chords[b], 4, spread=False), 4 * t.beat * 0.97, 0.9, attack=0.15), send=0.45)
        t.put("2", b * 4, S.tremolo([n + 12 for n in voicing(chords[b], 4, spread=False)], 4 * t.beat, 0.3 + 0.08 * (b - 12), rate=18), send=0.35)
    for b in (0, 8, 12):
        t.put("2", b * 4, S.braam(root(chords[b], 2), 2.0, 1.0), send=0.45)
    for b in (0, 8):
        t.put("2", b * 4, S.crash(0.9), send=0.4)
    return t, None


# ---- requiem ----------------------------------------------------------------

def requiem():
    chords = ["Dm", "A/C#", "Dm/C", "Bdim", "Bb", "Gm", "A", "A", "Dm", "Bb", "Eb", "C#dim", "Dm", "Gm", "A7b9", "A"]
    t = S.Track(108, 16, ["1", "2"])
    ostinato(t, "1", chords, octave=2, vel=1.0, length=0.2, pattern=HEART, accent=1.2)
    _drums(t, "1", range(16), [(0, 1.0), (2, 0.85), (3.5, 0.45)], snares=(), ticks=0)
    for b, ch in enumerate(chords):
        t.put("1", b * 4, S.brass(voicing(ch, 2, spread=False) + [root(ch, 2)], 4 * t.beat * 0.96, 0.7, attack=0.25, dark=500, bright=1300), send=0.4)
        t.put("1", b * 4, S.sub(root(ch, 1) + 12, 4 * t.beat * 0.9, 0.8))
        if b % 4 == 3:
            for k in range(16):
                t.put("1", b * 4 + k * 0.25, S.snare(0.2 + 0.045 * k), send=0.3)
        if b % 4 == 0:
            t.put("1", b * 4, S.bell(N("D3"), 0.7, ring=5.0), send=0.5)
    t.put("1", 0, S.boom(1.0), send=0.3)
    lament = [("A4", 2), ("D5", 2), ("C#5", 4), ("C5", 3), ("D5", 1), ("B4", 4), ("Bb4", 2), ("D5", 2), ("D5", 2), ("Bb4", 2),
              ("A4", 4), ("A4", 2), ("C#5", 2), ("D5", 2), ("Eb5", 1), ("D5", 1), ("A4", 2), ("Bb4", 2), ("G5", 2), ("Eb5", 2),
              ("E5", 4), ("F5", 2), ("E5", 1), ("D5", 1), ("D5", 2), ("Bb4", 2), ("A4", 2), ("Bb4", 2), ("A4", 4)]
    melody(t, "2", lament, 0, vel=1.0, inst="choir", send=0.5)
    melody(t, "2", [("R", 48), ("D4", 4), ("Eb4", 2), ("D4", 2), ("A3", 8)], 0, vel=1.0, inst="horns")
    for b in (10, 11, 14, 15):
        t.put("2", b * 4, S.tremolo([n + 12 for n in voicing(chords[b], 4, spread=False)], 4 * t.beat, 0.4, rate=12), send=0.4)
    for b, r in ((0, "D2"), (8, "D2"), (10, "Eb2")):
        t.put("2", b * 4, S.braam(N(r), 2.6, 1.0), send=0.5)
    for b in (0, 8):
        t.put("2", b * 4, S.crash(0.8), send=0.45)
    return t, None


# ---- unravel ----------------------------------------------------------------

def unravel():
    chords = ["Dm"] * 4 + ["Fm"] * 4 + ["Abm"] * 4 + ["Bm", "Bm", "A", "A"]
    t = S.Track(138, 16, ["1", "2"])
    ostinato(t, "1", chords, vel=0.85, length=0.1, pattern=CHROMATIC)
    _drums(t, "1", range(14), TRESILLO, ticks=0.25, fills=(3, 7, 11))
    _drums(t, "1", (14, 15), [(e * 0.5, 0.9 if e % 2 == 0 else 0.7) for e in range(8)], ticks=0.25, fills=(15,))
    _low_pulse(t, chords, 0.85)
    t.put("1", 0, S.boom(1.0), send=0.3)
    t.put("1", 15 * 4, S.riser(4 * t.beat, 1.0), send=0.2)
    climb = [("D4", 2), ("Eb4", 2), ("D4", 2), ("A3", 2), ("R", 4), ("A4", 1), ("Bb4", 1), ("A4", 2),
             ("F4", 2), ("Gb4", 2), ("F4", 2), ("C4", 2), ("R", 4), ("C5", 1), ("Db5", 1), ("C5", 2),
             ("Ab4", 2), ("A4", 2), ("Ab4", 2), ("Eb4", 2), ("R", 4), ("Eb5", 1), ("E5", 1), ("Eb5", 2),
             ("B4", 2), ("C5", 2), ("B4", 2), ("F#4", 2), ("A4", 4), ("Bb4", 4)]
    melody(t, "2", climb, 0, vel=1.0, inst="horns")
    melody(t, "2", [("R", 56), ("A4", 4), ("Bb4", 4)], 0, octave_shift=1, vel=0.7, inst="strings")
    for b in (0, 4, 8, 12):
        ch = chords[b]
        cluster = voicing(ch, 3, spread=False) + [root(ch, 4) + 1]
        held = (16 if b < 12 else 8) * t.beat * 0.97
        t.put("2", b * 4, S.choir(cluster, held, 0.75, vowel="oh", attack=0.6), send=0.5)
        t.put("2", b * 4, S.braam(root(ch, 2), 2.0, 1.0), send=0.45)
    t.put("2", 14 * 4, S.choir([N("A4"), N("C#5"), N("E5"), N("Bb5")], 8 * t.beat * 0.97, 1.0, attack=0.2), send=0.45)
    for b in range(12, 16):
        hi = [n + 24 for n in voicing(chords[b], 3, spread=False)] + ([root(chords[b], 5) + 1] if b >= 14 else [])
        t.put("2", b * 4, S.tremolo(hi, 4 * t.beat, 0.3 + 0.07 * (b - 12), rate=20), send=0.35)
    for b in (0, 12):
        t.put("2", b * 4, S.crash(0.9), send=0.4)
    return t, None


# ---- toll: bells, then drum and bass ------------------------------------------
# Round 3 (the user, 2026-11-15): loved the ominous theme and the church bells
# ringing it; wanted a long, dramatic bell pause (about 10 s) before the drop,
# a softer snare, and more drum and bass.

INTRO_BARS = 7   # 9.7 s at 174 bpm: the first cracking lasts this long in the game


def _toll_intro(bpm):
    """Played once while the ground cracks: a gong and a low bell, then the
    bells ring the motif slowly into the silence, a second gong, a heartbeat
    of kicks speeding up, and a soft snare roll and riser into the drop."""
    t = S.Track(bpm, INTRO_BARS, ["intro"])
    end = INTRO_BARS * 4
    t.put("intro", 0, S.gong(1.0, ring=9.0), send=0.5)
    t.put("intro", 0, S.bell(N("D3"), 1.0, ring=8.0), send=0.55)
    t.put("intro", 0, S.boom(0.9), send=0.3)
    for beat, name in ((4, "D4"), (8, "Eb4"), (12, "D4"), (16, "A3")):
        t.put("intro", beat, S.bell(N(name), 0.95, ring=7.0), send=0.55)
    t.put("intro", 20, S.bell(N("D3"), 0.9, ring=8.0), send=0.55)
    t.put("intro", 20, S.gong(0.7, ring=8.0), send=0.5)
    t.put("intro", 2, S.choir([N("D3"), N("A3"), N("D4"), N("Eb4")], 22 * t.beat, 0.75, vowel="oh", attack=4.0, release=0.4), send=0.55)
    for beat, v in ((20, 0.5), (22, 0.55), (24, 0.6), (25, 0.65), (26, 0.7), (26.5, 0.75), (27, 0.8), (27.5, 0.9)):
        t.put("intro", beat, S.kick(v), send=0.15)
    for k in range(8):
        t.put("intro", end - 2 + k * 0.25, S.dnb_snare(0.25 + 0.08 * k), send=0.25)
    t.put("intro", end - 6, S.riser(6 * t.beat, 1.0), send=0.2)
    return t


def _bells_motif(t, layer, bar, octave_names, v=0.85):
    for k, name in enumerate(octave_names):
        t.put(layer, bar * 4 + k * 2, S.bell(N(name), v, ring=5.0), send=0.5)


def toll():
    bpm = 174
    chords = ["Dm", "Dm", "Dm", "Dm", "Bb", "Bb", "A", "A", "Dm", "Dm", "Eb", "Eb", "Gm", "Gm", "A", "A",
              "Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A", "Dm", "Dm", "Eb", "Eb", "Bb", "Bb", "A", "A"]
    t = S.Track(bpm, 32, ["1", "2"])
    # 1: break and bass. Bars 0-15 a two-step roller, 16-31 the harder half.
    for b, ch in enumerate(chords):
        hard = b >= 16
        fill = b % 8 == 7
        kicks = (0, 0.75, 2.5, 3.25) if hard and b % 2 else (0, 0.75, 2.5) if (hard or b % 2) else (0, 2.5)
        for off in kicks:
            t.put("1", b * 4 + off, S.kick(1.0), send=0.05)
        t.put("1", b * 4 + 1, S.dnb_snare(1.0), send=0.2)
        if not fill:
            t.put("1", b * 4 + 3, S.dnb_snare(1.0), send=0.2)
            ghosts = (1.75, 2.25, 3.75) if hard else ((1.75,) if b % 2 else (3.25,))
            for g in ghosts:
                t.put("1", b * 4 + g, S.dnb_snare(0.3), send=0.15)
        else:
            for k in range(8):
                t.put("1", b * 4 + 2 + k * 0.25, S.dnb_snare(0.35 + 0.08 * k), send=0.2)
        for e in range(16):
            if fill and e >= 8:
                break
            if e % 2 == 0:
                t.put("1", b * 4 + e * 0.25, S.hat(0.9 if e % 4 == 2 else 0.6, p=0.3), send=0.05)
            elif hard:
                t.put("1", b * 4 + e * 0.25, S.hat(0.4, p=-0.3), send=0.05)
        if hard:
            for e in (0.5, 1.5, 2.5, 3.5):
                t.put("1", b * 4 + e, S.hat(0.5, open_=True, p=-0.2), send=0.08)
        # The reese on the motif. First half: D-Eb-D, then the drop to the
        # fifth, with rests. Second half: the same notes as driving 8ths.
        r = root(ch, 2)
        if r > 42:
            r -= 12
        if not hard:
            riff = [(r, 1.5), (None, 0.5), (r, 0.5), (r + 1, 1.0), (r, 0.5)] if b % 2 == 0 else \
                [(r - 5, 2.0), (None, 0.5), (r - 5, 0.5), (r - 2, 1.0)]
            beat = b * 4
            for m, d in riff:
                if m is not None:
                    t.put("1", beat, S.reese(m, d * t.beat * 0.95, 1.0), send=0.02)
                beat += d
        else:
            notes = [r, r, r + 1, r, r - 5, r - 5, r - 2, r]
            for k, m in enumerate(notes):
                length = 0.45 if k % 2 == 0 else 0.3
                t.put("1", b * 4 + k * 0.5, S.reese(m, length * t.beat, 0.95 if k % 2 == 0 else 0.75, cutoff=800), send=0.02)
    t.put("1", 0, S.boom(1.0), send=0.3)
    t.put("1", 16 * 4, S.boom(0.8), send=0.3)
    t.put("1", 15 * 4, S.riser(4 * t.beat, 0.7), send=0.2)
    t.put("1", 31 * 4, S.riser(4 * t.beat, 0.8), send=0.2)
    # 2: the bells, the horns and the choir over it.
    theme = [("D4", 2), ("Eb4", 2), ("D4", 2), ("A3", 2), ("R", 4), ("A3", 1), ("Bb3", 1), ("A3", 2),
             ("F4", 2), ("D4", 2), ("Bb3", 4), ("C#4", 2), ("E4", 2), ("A4", 4),
             ("D5", 2), ("Eb5", 2), ("D5", 2), ("A4", 2), ("G4", 2), ("Bb4", 2), ("Eb5", 4),
             ("D5", 2), ("Bb4", 2), ("G4", 4), ("A4", 3), ("Bb4", 1), ("A4", 4)]
    melody(t, "2", theme[:14], 0, vel=1.0, inst="horns")
    melody(t, "2", theme[14:], 8, vel=1.0, inst="brass")
    # Second half: the motif in long, half-time horn notes, then the brass.
    melody(t, "2", [("D4", 4), ("Eb4", 4), ("D4", 4), ("A3", 4), ("Bb3", 4), ("A3", 4), ("G3", 4), ("A3", 4)], 16, vel=1.0, inst="horns")
    melody(t, "2", theme[14:], 24, vel=1.0, inst="brass")
    for b in range(0, 32, 2):
        vowel = "oh" if b % 16 < 8 else "ah"
        t.put("2", b * 4, S.choir(voicing(chords[b], 3 if vowel == "oh" else 4, spread=False), 8 * t.beat * 0.97, 0.7, vowel=vowel, attack=0.4), send=0.5)
    # The bells ring the motif at the top of each half.
    _bells_motif(t, "2", 0, ["D4", "Eb4", "D4", "A3"], 0.8)
    _bells_motif(t, "2", 16, ["D5", "Eb5", "D5", "A4"], 0.7)
    for b, name in ((8, "A3"), (24, "D3")):
        t.put("2", b * 4, S.bell(N(name), 0.8, ring=6.0), send=0.5)
    for b in (14, 15, 30, 31):
        t.put("2", b * 4, S.tremolo([N("A5"), N("C#6"), N("E6"), N("Bb6")], 4 * t.beat, 0.35, rate=21), send=0.35)
    for b in (0, 8, 16, 24):
        t.put("2", b * 4, S.braam(N("D2") if chords[b] == "Dm" else root(chords[b], 2), 1.8, 1.0), send=0.45)
    for b in (0, 16):
        t.put("2", b * 4, S.crash(0.8), send=0.4)
    return t, _toll_intro(bpm)


VARIANTS = {"siege": siege, "requiem": requiem, "unravel": unravel, "toll": toll}


def once(track):
    """A track rendered without wrapping its tail round: a one-shot."""
    out = {}
    for l in track.dry:
        out[l] = track.dry[l] + S.reverb(track.wet[l]) * 1.0
    return out


def render(name, preview_dir):
    track, intro = VARIANTS[name]()
    layers, gain = S.master(track.render())
    full = sum(layers.values())
    print(name, "%.1fs" % (track.length / S.SR), "gain %.2f" % gain,
          {k: "rms %.3f peak %.3f" % (np.sqrt((v ** 2).mean()), np.abs(v).max()) for k, v in layers.items()})
    os.makedirs(preview_dir, exist_ok=True)
    for k, v in layers.items():
        write_ogg(os.path.join(preview_dir, "finale_%s_%s.ogg" % (name, k)), v)
    song = np.concatenate([full, full])
    if intro is not None:
        # The intro rings on into the loop: its bars, then its tail laid over
        # the loop's start. Same gain as the loop.
        ring = once(intro)["intro"]
        ring = np.tanh(S.hp(ring.T, 28).T * gain / 0.93) * 0.93
        write_ogg(os.path.join(preview_dir, "finale_%s_intro.ogg" % name), ring)
        song = np.concatenate([np.zeros((intro.length, 2)), song])
        song[: ring.shape[0]] += ring
        print("  intro %.2fs (+%.1fs tail) rms %.3f" % (intro.length / S.SR, (ring.shape[0] - intro.length) / S.SR, np.sqrt((ring ** 2).mean())))
    # Both layers together can pass full scale; the preview gets a soft limit.
    song = np.tanh(song / 0.95) * 0.95
    write_ogg(os.path.join(preview_dir, "finale_%s_full.ogg" % name), song)
    spectrogram(song, os.path.join(preview_dir, "finale_%s.png" % name), "finale %s: %stwo loops" % (name, "intro, " if intro is not None else ""))
