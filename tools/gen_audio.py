#!/usr/bin/env python3
"""Synthesize every HarvestInn sound from scratch (CC0) into assets/audio/*.wav.

  python3 tools/gen_audio.py

SFX are short plucks/chirps/noise bursts, one distinct sound per action.
music_day: plucked-guitar pentatonic loop with pad, bass, arpeggio and a soft shaker.
music_night: slow music-box bells over a pad. Both loop seamlessly and crossfade in game.
Ambience loops (wind, birds, water, chatter, crickets) play positionally in the world.
Standard library only (math, wave, struct, random).
"""
import math
import pathlib
import random
import struct
import wave

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio"
SR = 22050


LOOPS = {"music_day", "music_night", "ambience", "birds", "water", "chatter", "crickets"}


def write(name, samples, gain=0.8):
    if name not in LOOPS:   # 15 ms fade-out: one-shots never end on a click
        f = min(len(samples), int(SR * 0.015))
        for i in range(f): samples[len(samples) - f + i] *= 1 - i / f
    peak = max(1e-9, max(abs(s) for s in samples))
    k = gain / peak
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * k)) * 32767)) for s in samples))


def env(t, a, d):
    """Attack/exponential-decay envelope."""
    return min(1.0, t / a) * math.exp(-t / d) if t >= 0 else 0.0


def tone(freq, dur, a=0.005, d=0.15, wave_="sine", glide=0.0, vib=0.0):
    out = []
    ph = 0.0
    for i in range(int(SR * dur)):
        t = i / SR
        f = freq * (1 + glide * t) * (1 + vib * math.sin(2 * math.pi * 6 * t))
        ph += 2 * math.pi * f / SR
        if wave_ == "sine":
            v = math.sin(ph)
        elif wave_ == "tri":
            v = 2 / math.pi * math.asin(math.sin(ph))
        else:  # soft square
            v = math.tanh(3 * math.sin(ph))
        out.append(v * env(t, a, d))
    return out


def noise(dur, d=0.05, lp=0.2, seed=1):
    r = random.Random(seed)
    out, y = [], 0.0
    for i in range(int(SR * dur)):
        y += lp * (r.uniform(-1, 1) - y)
        out.append(y * env(i / SR, 0.002, d))
    return out


def mix(*tracks, offsets=None):
    offsets = offsets or [0] * len(tracks)
    n = max(int(o * SR) + len(t) for t, o in zip(tracks, offsets))
    out = [0.0] * n
    for t, o in zip(tracks, offsets):
        s = int(o * SR)
        for i, v in enumerate(t):
            out[s + i] += v
    return out


def pluck(freq, dur, decay=0.994, bright=0.5, seed=0):
    """Karplus-Strong plucked string: warm, guitar-like."""
    r = random.Random(seed)
    n = max(2, int(SR / freq))
    buf = [r.uniform(-1, 1) for _ in range(n)]
    out = []
    for i in range(int(SR * dur)):
        a = buf[i % n]
        b = buf[(i + 1) % n]
        buf[i % n] = decay * (bright * a + (1 - bright) * b)
        out.append(a)
    return out


def bell(freq, dur, d=1.2):
    """Music-box bell: sine plus inharmonic partials that die faster."""
    out = []
    for i in range(int(SR * dur)):
        t = i / SR
        v = math.sin(2 * math.pi * freq * t) * math.exp(-t / d)
        v += 0.4 * math.sin(2 * math.pi * freq * 2.76 * t) * math.exp(-t / (d * 0.3))
        v += 0.2 * math.sin(2 * math.pi * freq * 5.4 * t) * math.exp(-t / (d * 0.12))
        out.append(v * min(1.0, t / 0.003))
    return out


def formant(samples, f, q=0.9):
    """Two-pole resonator: gives noise/saw a vowel-ish colour (chatter, moo)."""
    w = 2 * math.pi * f / SR
    a1, a2 = -2 * q * math.cos(w), q * q
    y1 = y2 = 0.0
    out = []
    for x in samples:
        y = x - a1 * y1 - a2 * y2
        y2, y1 = y1, y
        out.append(y)
    return out


def note(n):  # MIDI -> Hz
    return 440.0 * 2 ** ((n - 69) / 12)


def sfx():
    write("click", tone(880, 0.06, d=0.02, wave_="tri"), 0.5)
    write("plant", mix(noise(0.12, 0.04, 0.08, 2), tone(520, 0.15, d=0.06, glide=1.5)), 0.6)
    write("harvest", mix(tone(660, 0.12, d=0.05), tone(990, 0.18, d=0.08), offsets=[0, 0.06]), 0.7)
    write("coins", mix(*[tone(f, 0.25, d=0.08, wave_="tri") for f in (1318, 1760, 2093)], offsets=[0, 0.05, 0.1]), 0.6)
    write("collect", mix(tone(784, 0.2, d=0.07), tone(1047, 0.25, d=0.1), offsets=[0, 0.07]), 0.7)
    write("craft", mix(noise(0.08, 0.03, 0.4, 3), noise(0.08, 0.03, 0.4, 4), tone(330, 0.2, d=0.08, wave_="tri"), offsets=[0, 0.12, 0.05]), 0.6)
    write("build", mix(*[noise(0.1, 0.04, 0.15, s) for s in (5, 6, 7)], tone(196, 0.3, d=0.1, wave_="tri"), offsets=[0, 0.15, 0.3, 0.3]), 0.7)
    write("level_up", mix(*[tone(note(n), 0.5, d=0.25, wave_="tri") for n in (72, 76, 79, 84)], offsets=[0, 0.1, 0.2, 0.3]), 0.7)
    write("error", tone(220, 0.25, d=0.12, wave_="square", glide=-0.6), 0.4)
    write("door", mix(noise(0.25, 0.1, 0.05, 8), tone(150, 0.3, d=0.12)), 0.6)
    write("pet", mix(tone(700, 0.18, d=0.08, vib=0.03), tone(900, 0.2, d=0.1, vib=0.03), offsets=[0, 0.09]), 0.5)
    write("pickup", tone(440, 0.15, d=0.08, glide=2.0, wave_="tri"), 0.5)
    write("sell", mix(noise(0.05, 0.02, 0.6, 11), *[tone(f, 0.35, d=0.12, wave_="tri") for f in (1568, 2093, 2637)], offsets=[0, 0.04, 0.09, 0.14]), 0.6)
    write("feed", mix(*[noise(0.05, 0.015, 0.5, 20 + k) for k in range(5)], offsets=[k * 0.055 for k in range(5)]), 0.5)
    write("serve", mix(tone(2400, 0.2, d=0.05), tone(3100, 0.25, d=0.07), noise(0.03, 0.01, 0.7, 30), offsets=[0, 0.03, 0]), 0.5)
    write("pop", tone(600, 0.09, d=0.03, glide=4.0), 0.5)
    write("achieve", mix(*[pluck(note(n), 0.8, 0.996, seed=n) for n in (67, 72, 76, 79, 84)], offsets=[0, 0.08, 0.16, 0.24, 0.4]), 0.7)
    write("cluck", mix(*[tone(f, 0.07, d=0.025, wave_="square", glide=-1.5) for f in (900, 760, 980)], offsets=[0, 0.1, 0.17]), 0.4)
    moo = [v * env(i / SR, 0.08, 0.5) for i, v in enumerate(tone(140, 0.9, a=0.1, d=2.0, wave_="square", glide=-0.25, vib=0.01))]
    write("moo", formant(moo, 600, 0.97), 0.5)
    baa = tone(420, 0.6, a=0.03, d=0.4, wave_="square", vib=0.06)
    write("baa", formant(baa, 1100, 0.95), 0.4)
    bleat = tone(560, 0.45, a=0.02, d=0.25, wave_="square", vib=0.12)
    write("bleat", formant(bleat, 1400, 0.95), 0.4)


def _track(bars, bpm, total_fn):
    beat = 60 / bpm
    total = int(SR * beat * 4 * bars)
    out = [0.0] * total
    def add(samples, at, vol):
        st = int(at * SR)
        for i, v in enumerate(samples):
            out[(st + i) % total] += v * vol      # wrap the tail: seamless loop
    total_fn(add, beat)
    return out


def music_day():
    """16 bars at 84 BPM, C major pentatonic: plucked guitar melody, arpeggio, pad, bass, shaker."""
    r = random.Random(42)
    scale = [60, 62, 64, 67, 69, 72, 74, 76]
    chords = [(48, 55, 64), (45, 52, 60), (41, 48, 57), (43, 50, 59)]   # C Am F G
    def body(add, beat):
        for bar in range(16):
            root = chords[bar % 4]
            t0 = bar * 4 * beat
            for n in root:
                add(tone(note(n), beat * 4.2, a=0.4, d=2.5, vib=0.004), t0, 0.07)
            add(pluck(note(root[0] - 12), beat * 2, 0.996, 0.3, bar), t0, 0.30)
            add(pluck(note(root[0] - 5), beat * 2, 0.996, 0.3, bar + 50), t0 + 2 * beat, 0.22)
            if bar >= 4:   # arpeggio enters after the intro
                for k in range(8):
                    add(pluck(note(root[k % 3] + 12), beat, 0.993, 0.5, bar * 8 + k), t0 + k * beat / 2, 0.07)
            pos = 0.0
            while pos < 4:
                if r.random() < 0.6:
                    n = r.choice(scale) + (12 if r.random() < 0.15 else 0)
                    add(pluck(note(n), 0.9, 0.995, 0.5, r.randint(0, 999)), t0 + pos * beat, 0.22)
                pos += r.choice([0.5, 0.5, 1.0])
            for k in range(8):   # soft shaker on the off-beats, kick on 1 and 3
                if k % 2: add(noise(0.05, 0.015, 0.9, bar * 8 + k), t0 + k * beat / 2, 0.05)
            for k in (0, 2):
                add(tone(70, 0.25, a=0.002, d=0.08, glide=-0.6), t0 + k * beat, 0.25)
    write("music_day", _track(16, 84, body), 0.55)


def music_night():
    """12 bars at 66 BPM: music-box bells over a slow pad in A minor pentatonic. No drums."""
    r = random.Random(7)
    scale = [69, 72, 74, 76, 79, 81, 84]
    chords = [(45, 52, 60), (41, 48, 57), (43, 50, 59), (40, 47, 55)]   # Am F G Em
    def body(add, beat):
        for bar in range(12):
            root = chords[bar % 4]
            t0 = bar * 4 * beat
            for n in root:
                add(tone(note(n), beat * 4.4, a=1.2, d=3.0, vib=0.003), t0, 0.08)
            add(tone(note(root[0] - 12), beat * 3.5, a=0.3, d=1.5), t0, 0.12)
            pos = 0.0
            while pos < 4:
                if r.random() < 0.45:
                    add(bell(note(r.choice(scale)), 2.0), t0 + pos * beat, 0.16)
                pos += r.choice([1.0, 1.0, 1.5, 0.5])
    write("music_night", _track(12, 66, body), 0.5)


def _loop(dur, fill):
    n = int(SR * dur)
    out = [0.0] * n
    fill(out, n)
    return out


def ambience():
    """Seamless loops: wind (global bed) + birds, water, chatter, crickets (positional)."""
    r = random.Random(9)
    def wind(out, n):
        y = y2 = 0.0
        for i in range(n):
            y += 0.002 * (r.uniform(-1, 1) - y)
            y2 += 0.02 * (y - y2)
            out[i] = y2 * 60 * (0.6 + 0.4 * math.sin(2 * math.pi * i / n))   # exact period: seamless
    write("ambience", _loop(20.0, wind), 0.3)
    def birds(out, n):
        t = 0.5
        while t < n / SR - 1.0:
            f0 = r.uniform(2600, 4200)
            for k in range(r.randint(2, 6)):
                chirp = tone(f0 * r.uniform(0.9, 1.15), 0.09, a=0.005, d=0.035, glide=r.uniform(-3, 3))
                s0 = int((t + k * 0.12) * SR)
                for j, v in enumerate(chirp): out[(s0 + j) % n] += v
            t += r.uniform(1.0, 3.0)
    write("birds", _loop(16.0, birds), 0.5)
    def water(out, n):
        y = 0.0
        for i in range(n):   # brook: bright noise, gently bubbling amplitude
            y += 0.25 * (r.uniform(-1, 1) - y)
            bub = 0.55 + 0.25 * math.sin(2 * math.pi * 7 * i / n) + 0.2 * math.sin(2 * math.pi * 23 * i / n)
            out[i] = y * bub
        for k in range(40):   # droplets
            d = tone(r.uniform(700, 1500), 0.06, a=0.002, d=0.02, glide=r.uniform(2, 5))
            s0 = r.randrange(n)
            for j, v in enumerate(d): out[(s0 + j) % n] += v * 0.3
    write("water", _loop(10.0, water), 0.4)
    def chatter(out, n):
        src = [r.uniform(-1, 1) for _ in range(n)]
        voiced = formant(formant(src, 500, 0.985), 1500, 0.9)
        for i in range(n):   # murmur: syllable-rate bursts from several overlapping talkers
            t = i / SR
            amp = sum(max(0.0, math.sin(2 * math.pi * (3.1 + k * 0.7) * t + k * 1.7)) ** 2 for k in range(4)) / 4
            out[i] = voiced[i] * amp * (0.7 + 0.3 * math.sin(2 * math.pi * i / n))
        for k in range(10):   # cups and cutlery
            c = tone(r.uniform(2200, 3400), 0.12, a=0.001, d=0.03)
            s0 = r.randrange(n)
            for j, v in enumerate(c): out[(s0 + j) % n] += v * 0.004
    write("chatter", _loop(12.0, chatter), 0.4)
    def crickets(out, n):
        for c in range(3):   # three crickets, each a 4.5 kHz pulse train at its own rate
            f, rate, ph = r.uniform(4200, 4900), r.uniform(1.6, 2.4), r.random()
            for i in range(n):
                t = i / SR
                cyc = (t * rate + ph) % 1.0
                if cyc < 0.25:
                    gate = math.sin(math.pi * cyc / 0.25) * (0.5 + 0.5 * math.sin(2 * math.pi * 30 * t))
                    out[i] += math.sin(2 * math.pi * f * t) * gate * 0.3
    write("crickets", _loop(8.0, crickets), 0.35)


if __name__ == "__main__":
    sfx()
    music_day()
    music_night()
    ambience()
    print("audio written:", sorted(p.name for p in OUT.glob("*.wav")))
