"""The Story Mode boss score (#172): three looping cues in D minor, each in
layers the game blends by what is happening (boss/boss_music.gd).

  fight   132 bpm, 16 bars. 1: the pulse (spiccato ostinato, low drums, ticking
          clock, sub). 2: war drums, low brass, braams. 3: Velle's theme in the
          horns and strings, full choir, crashes, tremolo.
  chase   160 bpm, 16 bars. 1: the run (drums on every beat, driving 16ths).
          2: what is behind you (brass stabs, shrieking tremolo, choir), swelled
          by how close the tentacles are.
  finale  "Toll" (art/music/variants.py, the user's pick, 2026-11-15): a 7-bar
          intro played once while the ground cracks (a gong, bells ringing the
          motif, a heartbeat of kicks, a snare roll), then drum and bass at 174
          bpm, 32 bars. 1: the break and the reese bass. 2: dark horns, choir
          and bells on the theme. The first, heroic finale (finale_heroic
          below) was "too saccharine".

Velle's motif is D-Eb-D-A: a half-step up and back, then down to the dark
fifth. It is in all three cues.

Run from the `Dome Keeper` folder (needs numpy, scipy, soundfile):
    python art/music/score.py [cue ...]
Writes mods-unpacked/flantor-StoryMode/music/boss_<cue>_<layer>.ogg and, with
--preview, a full mix and a spectrogram per cue to art/music/preview/.
"""
import os
import sys

import numpy as np
import soundfile as sf

sys.path.insert(0, os.path.dirname(__file__))
import synth as S  # noqa: E402

OUT = "mods-unpacked/flantor-StoryMode/music"
PREVIEW = "art/music/preview"

# Chord roots (octave 2) and qualities.
ROOT = {"D": 38, "Eb": 39, "F": 41, "G": 43, "A": 45, "Bb": 46, "C": 48, "C#": 37, "Ab": 44, "B": 47}
CHORDS = {
    "Dm": ("D", [0, 3, 7]), "Bb": ("Bb", [0, 4, 7]), "A": ("A", [0, 4, 7]), "Gm": ("G", [0, 3, 7]),
    "Eb": ("Eb", [0, 4, 7]), "F": ("F", [0, 4, 7]), "C": ("C", [0, 4, 7]),
    "Fm": ("F", [0, 3, 7]), "Bbm": ("Bb", [0, 3, 7]), "Ab": ("Ab", [0, 4, 7]), "Abm": ("Ab", [0, 3, 7]),
    "Bm": ("B", [0, 3, 7]), "C#dim": ("C#", [0, 3, 6]), "Bdim": ("B", [0, 3, 6]), "A7b9": ("A", [0, 4, 7, 10, 13]),
}


# A chord name, optionally over a bass note: "A/C#" is A major over C#.
def _parts(ch):
    name, _, bass = ch.partition("/")
    return name, (bass or None)


def root(ch, octave=2):
    """The chord's lowest note: its bass if it has one, else its root."""
    name, bass = _parts(ch)
    return ROOT[bass or CHORDS[name][0]] + 12 * (octave - 2)


def voicing(ch, octave=3, spread=True):
    name, bass = _parts(ch)
    r = ROOT[CHORDS[name][0]] + 12 * (octave - 2)
    notes = [r + i for i in CHORDS[name][1]]
    if spread:
        notes = [root(ch, octave) - 12] + notes + [r + 12]
    return notes


def N(name):
    """'D5', 'Eb4', 'C#5' -> midi."""
    names = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
    pitch, octv = name[:-1], int(name[-1])
    return 12 * (octv + 1) + names[pitch]


# 16ths over one bar, semitones over the chord root: root-root-octave-root,
# fifth-root-octave-root, with the minor sixth pulling at the end.
OSTINATO = [0, 0, 12, 0, 7, 0, 12, 0, 0, 0, 12, 0, 7, 8, 7, 12]


def ostinato(t, layer, chords, octave=3, vel=0.8, accent=1.35, length=0.11, pattern=None, start_bar=0, pedal=None):
    """16ths over each bar (None in `pattern` is a rest), on each chord's
    lowest note, or on `pedal` (a note name) for every bar."""
    for b, ch in enumerate(chords, start_bar):
        r = N(pedal) if pedal else root(ch, octave)
        for i, iv in enumerate(pattern or OSTINATO):
            if iv is None:
                continue
            v = vel * (accent if i % 4 == 0 else 1.0) * (0.92 + 0.16 * S._rng.random())
            t.put(layer, b * 4 + i * 0.25, S.strings_stacc(r + iv, v, length=length), send=0.18)


def melody(t, layer, notes, start_bar=0, octave_shift=0, vel=0.9, inst="brass", send=0.35):
    """notes: [(name, beats), ...] played legato from start_bar."""
    beat = start_bar * 4.0
    for name, dur in notes:
        if name == "R":
            beat += dur
            continue
        m = N(name) + 12 * octave_shift
        secs = dur * t.beat
        if inst == "horns":
            # Darker: the filter barely opens, the octave below is stronger.
            t.put(layer, beat, S.brass([m, m - 12, m - 12], secs * 0.97, vel, attack=0.07, dark=600, bright=1500), send=send)
        elif inst == "choir":
            t.put(layer, beat, S.choir([m, m - 12], secs * 0.98, vel, attack=0.12, release=0.4), send=send)
        elif inst == "brass":
            t.put(layer, beat, S.brass([m, m - 12], secs * 0.97, vel, attack=0.05), send=send)
        elif inst == "strings":
            t.put(layer, beat, S.strings_long([m, m + 12], secs * 0.98, vel, bright=5200, attack=0.07, release=0.35), send=send)
        beat += dur


# Velle's theme: the motif, then its answer.
THEME = [("D5", 2), ("Eb5", 1), ("D5", 1), ("A4", 4), ("G4", 1.5), ("Bb4", 0.5), ("D5", 2), ("C#5", 3), ("E5", 1),
         ("F5", 2), ("E5", 1), ("D5", 1), ("Eb5", 3), ("D5", 1), ("D5", 2), ("Bb4", 2), ("A4", 4)]


# ---- fight ------------------------------------------------------------------

def fight():
    chords = ["Dm", "Dm", "Bb", "A", "Dm", "Eb", "Gm", "A", "Dm", "Dm", "Bb", "A", "Dm", "Eb", "Bb", "A"]
    t = S.Track(132, 16, ["1", "2", "3"])
    # 1: the pulse.
    ostinato(t, "1", chords, octave=3, vel=0.75)
    for b, ch in enumerate(chords):
        t.put("1", b * 4, S.sub(root(ch, 1) + 12, 1.6 * t.beat, 0.9))
        t.put("1", b * 4 + 2.5, S.sub(root(ch, 1) + 12, 1.2 * t.beat, 0.7))
        t.put("1", b * 4, S.taiko(0.75, 0.9), send=0.35)
        t.put("1", b * 4 + 2.5, S.taiko(0.5, 1.0), send=0.35)
        for e in range(8):
            t.put("1", b * 4 + e * 0.5, S.tick(0.5 if e % 2 else 0.8, 0.35 if e % 2 else -0.35), send=0.1)
        t.put("1", b * 4, S.strings_long(voicing(ch, 3, spread=False), 4 * t.beat, 0.35, bright=1800, attack=0.6), send=0.4)
    for b in (0, 8):
        t.put("1", b * 4, S.choir([N("D3"), N("A3"), N("D4")], 8 * t.beat * 0.95, 0.5, vowel="oh"), send=0.5)
    t.put("1", 7 * 4 + 2, S.riser(2 * t.beat, 0.7), send=0.2)
    t.put("1", 15 * 4, S.riser(4 * t.beat, 0.9), send=0.2)

    # 2: war.
    pattern = [(0, 1.0), (0.75, 0.55), (1.5, 0.7), (2, 0.95), (2.75, 0.5), (3, 0.8), (3.5, 0.7)]
    for b, ch in enumerate(chords):
        for off, v in pattern:
            t.put("2", b * 4 + off, S.taiko(v, 1.0 + 0.1 * (off % 1 > 0)), send=0.35)
        t.put("2", b * 4 + 1, S.snare(0.8), send=0.3)
        t.put("2", b * 4 + 3, S.snare(0.95), send=0.3)
        t.put("2", b * 4, S.brass(voicing(ch, 3, spread=False)[:2] + [root(ch, 2)], 4 * t.beat * 0.96, 0.75, attack=0.12), send=0.35)
        if b % 4 == 3:
            for k in range(4):
                t.put("2", b * 4 + 3 + k * 0.25, S.tom(0.6 + 0.12 * k, 1.25 - 0.1 * k, -0.4 + 0.27 * k), send=0.3)
    for b in (0, 8):
        t.put("2", b * 4, S.braam(N("D2"), 2.4, 1.0), send=0.45)
        t.put("2", b * 4, S.boom(1.0), send=0.3)
    t.put("2", 5 * 4, S.braam(N("Eb2"), 1.6, 0.8), send=0.45)
    t.put("2", 13 * 4, S.braam(N("Eb2"), 1.6, 0.8), send=0.45)

    # 3: Velle's theme over everything.
    melody(t, "3", THEME, 0, vel=0.95, inst="brass")
    melody(t, "3", THEME, 8, vel=0.75, inst="strings")
    melody(t, "3", THEME, 8, vel=0.9, inst="brass")
    for b, ch in enumerate(chords):
        t.put("3", b * 4, S.choir(voicing(ch, 4, spread=False), 4 * t.beat * 0.97, 0.8, attack=0.25, release=0.5), send=0.45)
        if ch == "A":
            t.put("3", b * 4, S.tremolo([N("A5"), N("C#6"), N("E6")], 4 * t.beat, 0.55), send=0.35)
        if b % 2 == 1:
            t.put("3", b * 4 + 2, S.anvil(0.9), send=0.4)
        if b % 4 == 3:
            for k in range(8):
                t.put("3", b * 4 + 2 + k * 0.25, S.tom(0.5 + 0.06 * k, 1.4 - 0.06 * k, 0.4 - 0.1 * k), send=0.3)
    for b in (0, 4, 8, 12):
        t.put("3", b * 4, S.crash(1.0), send=0.4)
    return t


# ---- chase ------------------------------------------------------------------

def chase():
    chords = ["Dm", "Dm", "Eb", "Eb", "Dm", "Dm", "C", "Bb", "Gm", "Gm", "Eb", "Eb", "Bb", "Bb", "A", "A"]
    t = S.Track(160, 16, ["1", "2"])
    # 1: run.
    ostinato(t, "1", chords, octave=3, vel=0.85, length=0.09)
    for b, ch in enumerate(chords):
        for k in range(4):
            t.put("1", b * 4 + k, S.taiko(0.9 if k % 2 == 0 else 0.7, 1.05), send=0.3)
            t.put("1", b * 4 + k + 0.5, S.tom(0.55, 1.1, 0.3 if k % 2 else -0.3), send=0.25)
        t.put("1", b * 4 + 1, S.snare(0.85), send=0.25)
        t.put("1", b * 4 + 3, S.snare(0.9), send=0.25)
        for e in range(16):
            t.put("1", b * 4 + e * 0.25, S.tick(0.35 if e % 2 else 0.6, 0.4 if e % 2 else -0.4), send=0.05)
        # Low string octaves on the 8ths: the engine of the run.
        for e in range(8):
            t.put("1", b * 4 + e * 0.5, S.strings_stacc(root(ch, 2), 0.9 if e % 2 == 0 else 0.7, length=0.12, bright=1800), send=0.15)
        t.put("1", b * 4, S.sub(root(ch, 1) + 12, 4 * t.beat * 0.9, 0.8))
    # A snare roll into the loop's top.
    for k in range(16):
        t.put("1", 15 * 4 + k * 0.25, S.snare(0.35 + 0.04 * k), send=0.25)
    t.put("1", 15 * 4, S.riser(4 * t.beat, 1.0), send=0.2)

    # 2: what is behind you.
    stabs = [0, 0.75, 1.5, 2.5, 3.0]
    for b, ch in enumerate(chords):
        for off in stabs:
            t.put("2", b * 4 + off, S.brass(voicing(ch, 3, spread=False) + [root(ch, 2)], 0.28 * t.beat * 2, 0.95, attack=0.015, release=0.12), send=0.3)
        # High tremolo in the second half of each 4-bar phrase only (no
        # sustained bed: the user found a constant drone distracting, #188),
        # with a minor second on top, a shriek, in the last two bars.
        if b % 4 >= 2:
            hi = [n + 24 for n in voicing(ch, 3, spread=False)] + ([root(ch, 4) + 13] if b >= 14 else [])
            t.put("2", b * 4, S.tremolo(hi, 4 * t.beat, 0.45, rate=18), send=0.35)
        t.put("2", b * 4 + 1, S.anvil(0.7), send=0.35)
        if ch == "Eb" and b % 2 == 0:
            t.put("2", b * 4, S.choir(voicing("Eb", 4, spread=False) + [N("D5")], 8 * t.beat * 0.95, 0.95, attack=0.2), send=0.45)
    for b in (0, 4, 8, 12):
        t.put("2", b * 4, S.braam(root(chords[b], 2), 1.8, 0.95), send=0.4)
        t.put("2", b * 4, S.crash(0.8), send=0.3)
    # The motif, screamed by the horns once per loop.
    melody(t, "2", [("D5", 1), ("Eb5", 1), ("D5", 1), ("A4", 5)], 4, vel=1.0)
    melody(t, "2", [("G5", 1), ("Ab5", 1), ("G5", 1), ("D5", 5)], 8, vel=1.0)
    return t


# ---- finale -----------------------------------------------------------------

FINALE_THEME = [("D4", 1), ("A4", 1), ("D5", 2), ("F5", 2), ("D5", 1), ("Bb4", 1), ("C5", 3), ("A4", 1), ("G4", 2), ("E5", 2),
                ("D5", 1), ("F5", 1), ("A5", 2), ("Bb5", 2), ("A5", 1), ("F5", 1), ("G5", 2), ("D5", 2), ("E5", 2), ("C#5", 2)]
FINALE_ANSWER = [("D5", 2), ("Eb5", 1), ("D5", 1), ("A4", 2), ("D5", 2), ("C5", 3), ("A4", 1), ("G4", 2), ("C5", 2),
                 ("G5", 2), ("Bb5", 2), ("Bb5", 3), ("G5", 1), ("A5", 4), ("C#5", 2), ("E5", 2)]


def finale_heroic():
    chords = ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A", "Dm", "Bb", "F", "C", "Gm", "Eb", "A", "A"]
    t = S.Track(140, 16, ["1", "2"])
    # 1: battle.
    ostinato(t, "1", chords, octave=3, vel=0.8)
    pattern = [(0, 1.0), (1, 0.6), (1.5, 0.7), (2, 0.95), (3, 0.6), (3.5, 0.8)]
    for b, ch in enumerate(chords):
        for off, v in pattern:
            t.put("1", b * 4 + off, S.taiko(v, 1.0), send=0.33)
        t.put("1", b * 4 + 1, S.snare(0.8), send=0.3)
        t.put("1", b * 4 + 3, S.snare(0.9), send=0.3)
        t.put("1", b * 4, S.sub(root(ch, 1) + 12, 2 * t.beat * 0.9, 0.85))
        t.put("1", b * 4 + 2, S.sub(root(ch, 1) + 12, 2 * t.beat * 0.9, 0.75))
        t.put("1", b * 4, S.brass([root(ch, 2), root(ch, 3)], 4 * t.beat * 0.95, 0.6, attack=0.1), send=0.35)
        if b % 4 == 3:
            for k in range(8):
                t.put("1", b * 4 + 2 + k * 0.25, S.tom(0.45 + 0.07 * k, 1.35 - 0.06 * k, -0.4 + 0.1 * k), send=0.3)
    t.put("1", 0, S.boom(1.0), send=0.3)
    t.put("1", 8 * 4, S.boom(0.9), send=0.3)
    t.put("1", 15 * 4, S.riser(4 * t.beat, 0.9), send=0.2)

    # 2: the theme, heroic.
    melody(t, "2", FINALE_THEME, 0, vel=1.0)
    melody(t, "2", FINALE_THEME, 0, octave_shift=1, vel=0.5, inst="strings")
    melody(t, "2", FINALE_ANSWER, 8, vel=1.0)
    melody(t, "2", FINALE_ANSWER, 8, octave_shift=1, vel=0.55, inst="strings")
    for b, ch in enumerate(chords):
        t.put("2", b * 4, S.choir(voicing(ch, 4, spread=False), 4 * t.beat * 0.97, 0.85, attack=0.2, release=0.5), send=0.45)
        if b % 2 == 1:
            t.put("2", b * 4 + 2, S.anvil(0.8), send=0.4)
    for b in (0, 4, 8, 12):
        t.put("2", b * 4, S.crash(1.0), send=0.4)
    t.put("2", 0, S.braam(N("D2"), 2.2, 1.0), send=0.45)
    t.put("2", 8 * 4, S.braam(N("D2"), 2.2, 1.0), send=0.45)
    t.put("2", 13 * 4, S.braam(N("Eb2"), 1.8, 0.9), send=0.45)
    t.put("2", 14 * 4, S.tremolo([N("A5"), N("C#6"), N("E6"), N("A6")], 8 * t.beat, 0.6), send=0.35)
    return t


def finale():
    import variants
    return variants.toll()


CUES = {"fight": fight, "chase": chase, "finale": finale}


def write_ogg(path, x):
    """OGG Vorbis in small blocks: one big write overflows libsndfile's stack on Windows."""
    x = np.ascontiguousarray(x, dtype=np.float32)
    with sf.SoundFile(path, "w", S.SR, x.shape[1], format="OGG", subtype="VORBIS") as f:
        for i in range(0, x.shape[0], 2048):
            f.write(x[i:i + 2048])


def spectrogram(x, path, title):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(2, 1, figsize=(14, 7), gridspec_kw={"height_ratios": [1, 3]})
    m = x.mean(axis=1)
    tt = np.arange(len(m)) / S.SR
    ax[0].plot(tt[::50], m[::50], lw=0.3)
    ax[0].set_xlim(0, tt[-1])
    ax[0].set_title(title)
    ax[1].specgram(m, NFFT=4096, Fs=S.SR, noverlap=2048, cmap="magma", vmin=-120)
    ax[1].set_ylim(0, 8000)
    fig.tight_layout()
    fig.savefig(path, dpi=80)
    plt.close(fig)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    preview = "--preview" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    import variants
    for name in args or list(CUES):
        # Each cue draws its own dice, so rendering one never changes another.
        S._rng = np.random.default_rng(sum(ord(c) * (i + 1) for i, c in enumerate(name)))
        if name in variants.VARIANTS:
            variants.render(name, preview_dir=PREVIEW)
            continue
        track = CUES[name]()
        intro = None
        if isinstance(track, tuple):
            track, intro = track
        layers = track.render()
        layers, gain = S.master(layers)
        if intro is not None:
            # Played once before the loop: same gain, its tail left ringing.
            layers_intro = variants.once(intro)["intro"]
            write_ogg(os.path.join(OUT, "boss_%s_intro.ogg" % name), np.tanh(S.hp(layers_intro.T, 28).T * gain / 0.93) * 0.93)
            print("  intro %.3fs (+tail), the loop starts at its end" % (intro.length / S.SR))
        full = sum(layers.values())
        info = {k: "rms %.3f peak %.3f" % (np.sqrt((v ** 2).mean()), np.abs(v).max()) for k, v in layers.items()}
        print(name, "%.1fs" % (track.length / S.SR), "gain %.2f" % gain, info, "full rms %.3f peak %.3f" % (np.sqrt((full ** 2).mean()), np.abs(full).max()))
        for k, v in layers.items():
            write_ogg(os.path.join(OUT, "boss_%s_%s.ogg" % (name, k)), v)
        if preview:
            os.makedirs(PREVIEW, exist_ok=True)
            # Two loops back to back, to hear the seam.
            both = np.concatenate([full, full])
            write_ogg(os.path.join(PREVIEW, "boss_%s_full.ogg" % name), both)
            spectrogram(both, os.path.join(PREVIEW, "boss_%s.png" % name), "%s: full mix, two loops" % name)


if __name__ == "__main__":
    main()
