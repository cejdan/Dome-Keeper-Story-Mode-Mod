"""Instruments and mixing for the Story Mode boss score (#172).

Everything here is plain numpy/scipy synthesis: band-limited wavetable saws
for strings and brass, formant-filtered saws for the choir, pitch-dropping
sines and filtered noise for the drums, and a convolution reverb with a
synthetic impulse response. score.py writes the music with these.
"""
import numpy as np
from scipy import signal

SR = 44100
TABLE = 4096
_rng = np.random.default_rng(172)


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


# ---- oscillators -----------------------------------------------------------

_saw_tables = {}


def _saw_table(top_hz):
    """One cycle of a saw with harmonics up to 15 kHz at `top_hz`."""
    n = max(1, int(15000 / top_hz))
    key = n
    if key not in _saw_tables:
        t = np.arange(TABLE) / TABLE
        w = np.zeros(TABLE)
        for k in range(1, n + 1):
            w += np.sin(2 * np.pi * k * t) / k
        _saw_tables[key] = (w * (2 / np.pi)).astype(np.float64)
    return _saw_tables[key]


def osc_saw(freq, n, phase0=None, vib_hz=0.0, vib_cents=0.0, drift_cents=0.0):
    """Saw at `freq` (Hz, scalar) for n samples, with optional vibrato."""
    t = np.arange(n) / SR
    cents = np.zeros(n)
    if vib_cents:
        cents += vib_cents * np.sin(2 * np.pi * vib_hz * t + _rng.uniform(0, 6.28)) * np.clip(t / 0.35, 0, 1)
    if drift_cents:
        cents += drift_cents * np.sin(2 * np.pi * 0.3 * t + _rng.uniform(0, 6.28))
    f = freq * 2.0 ** (cents / 1200.0)
    ph = (phase0 if phase0 is not None else _rng.uniform()) + np.cumsum(f) / SR
    table = _saw_table(freq * 1.03)
    x = (ph % 1.0) * TABLE
    i = x.astype(np.int64)
    fr = x - i
    return table[i % TABLE] * (1 - fr) + table[(i + 1) % TABLE] * fr


def osc_sine(freq, n, phase0=0.0):
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * freq * t + phase0)


# ---- envelopes and filters ---------------------------------------------------

def env(n, a, d, s, r, hold=None):
    """ADSR over n samples; the release starts at `hold` seconds (default n - r)."""
    t = np.arange(n) / SR
    total = n / SR
    hold = total - r if hold is None else hold
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = t > hold
    if rel.any():
        level = e[np.argmax(rel)] if rel.any() else s
        e = np.where(rel, level * np.exp(-(t - hold) / max(r / 4.0, 1e-4)), e)
    return e


def lp(x, cutoff, order=2):
    sos = signal.butter(order, min(cutoff, SR * 0.45), "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def hp(x, cutoff, order=2):
    sos = signal.butter(order, cutoff, "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def pan2(x, p):
    """Mono to stereo, p in -1 (left) .. 1 (right), equal power."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


# ---- instruments (each returns stereo, n x 2) --------------------------------

def strings_long(midis, dur, vel=1.0, bright=3200, attack=0.35, release=0.6):
    """A string section holding a chord: 3 detuned saws per note, slow bow."""
    n = int((dur + release) * SR)
    out = np.zeros((n, 2))
    for m in midis:
        for v in range(3):
            det = (v - 1) * 7.0
            x = osc_saw(hz(m) * 2 ** (det / 1200), n, vib_hz=5.2 + v * 0.3, vib_cents=9, drift_cents=4)
            x = lp(x, bright)
            out += pan2(x, -0.6 + 0.6 * v + _rng.uniform(-0.1, 0.1))
    e = env(n, attack, 1.0, 0.85, release, hold=dur)
    return out * e[:, None] * vel * 0.20 / max(1, len(midis)) ** 0.5


def strings_stacc(midi, vel=1.0, length=0.13, bright=4200):
    """One short, dug-in string note (spiccato), 2 octaves wide section."""
    n = int((length + 0.12) * SR)
    x = np.zeros(n)
    for det in (-9, 0, 8):
        x += osc_saw(hz(midi) * 2 ** (det / 1200), n)
    x += 0.5 * osc_saw(hz(midi + 12), n)
    # Bow bite: a brighter first few ms.
    bite = hp(x, 1500) * np.exp(-np.arange(n) / (0.012 * SR))
    x = lp(x, bright) + 0.35 * bite
    e = env(n, 0.004, length * 0.6, 0.0, 0.08)
    return pan2(x * e * vel * 0.24, _rng.uniform(-0.25, 0.25))


def tremolo(midis, dur, vel=1.0, rate=14.0):
    """High string tremolo: fast bow strokes on a held chord. Tense."""
    n = int((dur + 0.3) * SR)
    t = np.arange(n) / SR
    out = strings_long(midis, dur, vel=1.0, bright=6000, attack=0.08, release=0.3)
    am = 0.55 + 0.45 * np.abs(np.sin(np.pi * rate * t + _rng.uniform(0, 3)))
    return out[:n] * am[:, None] * vel


def brass(midis, dur, vel=1.0, attack=0.06, release=0.35, dark=900, bright=2600):
    """Horns/trombones: saws with a filter that opens on the attack."""
    n = int((dur + release) * SR)
    out = np.zeros((n, 2))
    for m in midis:
        x = osc_saw(hz(m), n, vib_hz=4.8, vib_cents=6, drift_cents=3) + osc_saw(hz(m) * 2 ** (6 / 1200), n, drift_cents=3)
        d = lp(x, dark)
        b = lp(x, bright)
        t = np.arange(n) / SR
        open_ = np.exp(-t / 0.35) * 0.7 + 0.3 * vel
        y = d * (1 - open_) + b * open_
        y = np.tanh(y * 1.6) / 1.6
        out += pan2(y, _rng.uniform(-0.35, 0.35))
    e = env(n, attack, 0.5, 0.8, release, hold=dur)
    return out * e[:, None] * vel * 0.34 / max(1, len(midis)) ** 0.5


def choir(midis, dur, vel=1.0, attack=0.5, release=0.9, vowel="ah"):
    """A choir on 'ah' or 'oh': detuned saws through three formant bands."""
    formants = {"ah": [(700, 1.0), (1150, 0.6), (2700, 0.25)], "oh": [(450, 1.0), (800, 0.55), (2600, 0.15)]}[vowel]
    n = int((dur + release) * SR)
    out = np.zeros((n, 2))
    for m in midis:
        for v in range(4):
            det = (v - 1.5) * 9.0
            x = osc_saw(hz(m) * 2 ** (det / 1200), n, vib_hz=4.6 + v * 0.4, vib_cents=14, drift_cents=6)
            y = np.zeros(n)
            for f, g in formants:
                y += g * bp(x, f * 0.8, f * 1.25)
            out += pan2(y, -0.75 + 0.5 * v)
    # Breath.
    breath = hp(_rng.standard_normal(n), 3000) * 0.015
    out += pan2(breath, 0.0)
    e = env(n, attack, 1.0, 0.9, release, hold=dur)
    return out * e[:, None] * vel * 0.45 / max(1, len(midis)) ** 0.5


def braam(root, dur=2.6, vel=1.0):
    """The trailer horn blast: a low brass cluster whose filter tears open."""
    n = int((dur + 0.8) * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for m, g in ((root - 12, 0.35), (root, 0.9), (root + 7, 0.7), (root + 12, 0.6)):
        for det in (-12, 0, 11):
            x += g * osc_saw(hz(m) * 2 ** (det / 1200), n, drift_cents=5)
    dark = lp(x, 300)
    bright = lp(x, 2400)
    open_ = np.clip(t / 0.18, 0, 1) * np.exp(-np.maximum(t - 0.18, 0) / 1.1)
    y = dark * (1 - open_) + bright * open_
    y = np.tanh(y * 0.9)
    e = env(n, 0.03, 1.4, 0.35, 0.7, hold=dur)
    out = np.stack([y, np.roll(y, 37)], axis=1)
    return out * e[:, None] * vel * 0.30


def taiko(vel=1.0, pitch=1.0, size=1.0):
    """A big drum: a pitch-dropping body, a skin slap and a little grit."""
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    f = (48 + 70 * np.exp(-t / 0.045)) * pitch
    body = 0.45 * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / (0.3 * size))
    over = np.sin(2 * np.pi * np.cumsum(f * 2.3) / SR) * np.exp(-t / 0.09) * 0.25
    slap = bp(_rng.standard_normal(n), 150, 2500) * np.exp(-t / 0.03) * 1.1
    x = np.tanh((body + over + slap) * 1.5)
    return pan2(x * vel * 0.55, _rng.uniform(-0.15, 0.15))


def tom(vel=1.0, pitch=1.0, p=0.0):
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    f = (110 + 120 * np.exp(-t / 0.03)) * pitch
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.2)
    slap = bp(_rng.standard_normal(n), 300, 4000) * np.exp(-t / 0.02) * 0.6
    return pan2(np.tanh((body + slap) * 1.3) * vel * 0.33, p)


def snare(vel=1.0):
    """An orchestral battle snare: body + bright rattle."""
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05)
    rattle = bp(_rng.standard_normal(n), 1800, 9000) * np.exp(-t / 0.13)
    crack = hp(_rng.standard_normal(n), 900) * np.exp(-t / 0.012)
    x = 0.6 * body + 0.8 * rattle + 0.5 * crack
    return pan2(x * vel * 0.30, 0.1)


def tick(vel=1.0, p=0.3):
    """Hi-hat-like tick of metal: a clock running out."""
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    x = hp(_rng.standard_normal(n), 7000) * np.exp(-t / 0.018)
    return pan2(x * vel * 0.12, p)


def anvil(vel=1.0):
    """A struck metal plate: inharmonic partials, long ring."""
    n = int(2.5 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f, d, g in ((523, 1.2, 1.0), (1311, 0.7, 0.6), (2087, 0.5, 0.45), (2950, 0.35, 0.3), (3720, 0.25, 0.2)):
        x += g * np.sin(2 * np.pi * f * t + _rng.uniform(0, 6)) * np.exp(-t / d)
    x += hp(_rng.standard_normal(n), 2000) * np.exp(-t / 0.01) * 0.6
    return pan2(x * vel * 0.12, -0.2)


def crash(vel=1.0):
    n = int(3.5 * SR)
    t = np.arange(n) / SR
    x = hp(_rng.standard_normal(n), 3500) * (np.exp(-t / 0.9) * 0.8 + np.exp(-t / 0.08) * 0.6)
    x = lp(x, 12000)
    y = np.stack([x, np.roll(x, 211)], axis=1)
    return y * vel * 0.10


def riser(dur, vel=1.0):
    """A reversed-cymbal swell that lands on the next downbeat."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = hp(_rng.standard_normal(n), 2500)
    e = (t / dur) ** 3
    y = np.stack([x, np.roll(x, 113)], axis=1)
    return y * e[:, None] * vel * 0.16


def sub(midi, dur, vel=1.0):
    """A clean sub bass note, short attack, no buzz."""
    n = int((dur + 0.15) * SR)
    x = osc_sine(hz(midi), n) + 0.25 * osc_sine(hz(midi) * 2, n)
    e = env(n, 0.01, 0.4, 0.7, 0.12, hold=dur)
    return pan2(x * e * vel * 0.09, 0.0)


def boom(vel=1.0):
    """The low impact under a section change: a sine drop and a thud."""
    n = int(3.0 * SR)
    t = np.arange(n) / SR
    f = 30 + 60 * np.exp(-t / 0.12)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 1.1)
    x += lp(_rng.standard_normal(n), 400) * np.exp(-t / 0.08) * 0.8
    return pan2(np.tanh(x * 1.4) * vel * 0.22, 0.0)


# ---- bells, gong and a drum and bass kit (finale variants) -------------------

def bell(midi, vel=1.0, ring=6.0):
    """A big church bell: hum, prime, minor-third tierce, quint, nominal and
    the upper partials, each ringing for its own time, and a hard strike."""
    f = hz(midi)
    n = int(ring * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for ratio, g, d in ((0.5, 0.6, 1.0), (1.0, 0.8, 0.55), (1.2, 0.5, 0.4), (1.5, 0.3, 0.3), (2.0, 0.6, 0.3),
                        (2.5, 0.25, 0.15), (3.0, 0.2, 0.12), (4.2, 0.12, 0.07), (5.4, 0.07, 0.05)):
        beat = 1.0 + 0.5 * np.sin(2 * np.pi * _rng.uniform(0.3, 1.2) * t)  # the slow wobble of a real bell
        x += g * np.sin(2 * np.pi * f * ratio * (1 + _rng.uniform(-0.002, 0.002)) * t) * np.exp(-t / (d * ring)) * (0.85 + 0.15 * beat)
    strike = bp(_rng.standard_normal(n), 800, 6000) * np.exp(-t / 0.01)
    x += strike * 0.4
    y = np.stack([x, np.roll(x, 53)], axis=1)
    return y * vel * 0.16


def gong(vel=1.0, ring=7.0):
    """A tam-tam: a dull hit that blooms into a shimmering roar."""
    n = int(ring * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f in np.geomspace(90, 3200, 40) * _rng.uniform(0.95, 1.05, 40):
        x += np.sin(2 * np.pi * f * t + _rng.uniform(0, 6.28)) * _rng.uniform(0.3, 1.0) / np.sqrt(f / 90)
    bloom = (1 - np.exp(-t / 0.35)) * np.exp(-t / (ring * 0.35))
    body = np.sin(2 * np.pi * 62 * t) * np.exp(-t / 1.4) * 2.0
    hit = lp(_rng.standard_normal(n), 900) * np.exp(-t / 0.05) * 2.0
    y = x * bloom * 0.25 + body + hit
    out = np.stack([y, np.roll(y, 97)], axis=1)
    return out * vel * 0.08


def kick(vel=1.0):
    """A punchy electronic kick: a fast pitch drop and a click."""
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 48 + 140 * np.exp(-t / 0.025)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.18)
    x += hp(_rng.standard_normal(n), 3000) * np.exp(-t / 0.004) * 0.5
    return pan2(np.tanh(x * 2.0) * vel * 0.50, 0.0)


def dnb_snare(vel=1.0):
    """A thick, dark break snare: two shell tones and noise kept under 5 kHz.
    The first version cracked at 5 kHz and hurt (the user, 2026-11-15)."""
    n = int(0.4 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(185 + 45 * np.exp(-t / 0.012)) / SR) * np.exp(-t / 0.10)
    body += 0.45 * np.sin(2 * np.pi * 330 * t) * np.exp(-t / 0.05)
    noise = lp(bp(_rng.standard_normal(n), 250, 4500), 5000) * np.exp(-t / 0.11)
    snap = bp(_rng.standard_normal(n), 1800, 5000) * np.exp(-t / 0.008) * 0.5
    x = np.tanh((0.7 * body + 1.2 * noise + snap) * 1.2)
    return pan2(x * vel * 0.31, 0.05)


def hat(vel=1.0, open_=False, p=0.25):
    """A soft hat: noise between 6 and 11 kHz, no fizz on top."""
    n = int((0.25 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    x = lp(hp(_rng.standard_normal(n), 6000), 11000) * np.exp(-t / (0.07 if open_ else 0.012))
    return pan2(x * vel * 0.11, p)


def reese(midi, dur, vel=1.0, cutoff=520):
    """Drum and bass reese: two detuned saws and a sub, low-passed, with a
    slow filter wobble so a held note moves instead of droning."""
    n = int((dur + 0.08) * SR)
    t = np.arange(n) / SR
    x = osc_saw(hz(midi) * 2 ** (-11 / 1200), n) + osc_saw(hz(midi) * 2 ** (11 / 1200), n)
    lo = lp(x, cutoff * 0.6)
    hi = lp(x, cutoff * 1.6)
    wob = 0.5 + 0.5 * np.sin(2 * np.pi * 1.5 * t - np.pi / 2)
    y = lo * (1 - wob) + hi * wob
    y = np.tanh(y * 1.5) * 0.6 + osc_sine(hz(midi - 12), n) * 0.7
    e = env(n, 0.006, 0.3, 0.85, 0.06, hold=dur)
    return pan2(y * e * vel * 0.30, 0.0)


# ---- reverb and mixing -----------------------------------------------------

_ir_cache = {}


def _ir(seconds, damp):
    key = (seconds, damp)
    if key not in _ir_cache:
        n = int(seconds * SR)
        t = np.arange(n) / SR
        decay = np.exp(-6.9 * t / seconds)
        chans = []
        for c in range(2):
            noise = _rng.standard_normal(n)
            # Darker as it decays: mix a lowpassed copy in over time.
            dark = lp(noise, damp)
            mix = noise * np.exp(-t / 0.25) + dark * (1 - np.exp(-t / 0.25))
            ir = mix * decay
            pre = int(0.022 * SR)
            ir = np.concatenate([np.zeros(pre + c * 37), ir])[:n]
            chans.append(ir / np.sqrt((ir ** 2).sum()))
        _ir_cache[key] = np.stack(chans, axis=1)
    return _ir_cache[key]


def reverb(x, seconds=2.6, damp=3500):
    ir = _ir(seconds, damp)
    out = np.zeros((x.shape[0] + ir.shape[0] - 1, 2))
    for c in range(2):
        out[:, c] = signal.fftconvolve(x[:, c], ir[:, c])
    return out[: x.shape[0]]


class Track:
    """A loop of `bars` bars at `bpm` in 4/4, rendered into named layers.

    Events are placed by beat; sounds that ring past the loop's end wrap round
    to its start, so the loop is seamless.
    """

    TAIL = 6.0

    def __init__(self, bpm, bars, layers):
        self.bpm = bpm
        self.bars = bars
        self.beat = 60.0 / bpm
        self.length = int(round(bars * 4 * self.beat * SR))
        n = self.length + int(self.TAIL * SR)
        self.dry = {l: np.zeros((n, 2)) for l in layers}
        self.wet = {l: np.zeros((n, 2)) for l in layers}

    def at(self, beat):
        return int(round(beat * self.beat * SR))

    def put(self, layer, beat, sound, send=0.3):
        i = self.at(beat)
        n = min(sound.shape[0], self.dry[layer].shape[0] - i)
        if n <= 0:
            return
        self.dry[layer][i:i + n] += sound[:n]
        self.wet[layer][i:i + n] += sound[:n] * send

    def render(self, room=2.6):
        out = {}
        for l in self.dry:
            mix = self.dry[l] + reverb(self.wet[l], room) * 1.0
            loop = mix[: self.length].copy()
            tail = mix[self.length:]
            loop[: tail.shape[0]] += tail[: self.length]
            out[l] = loop
        return out


def master(layers, target_rms=0.2, ceiling=0.93):
    """Glues the layers: one gain for all (so their balance holds), a gentle
    high-pass, and a soft clip so the full mix never passes the ceiling."""
    for k in layers:
        layers[k] = hp(layers[k].T, 28).T
    full = sum(layers.values())
    rms = np.sqrt((full ** 2).mean())
    g = target_rms / max(rms, 1e-9)
    out = {}
    for k in layers:
        y = layers[k] * g
        out[k] = np.tanh(y / ceiling) * ceiling
    return out, g
