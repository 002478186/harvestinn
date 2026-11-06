#!/usr/bin/env python3
"""Synthesize every HarvestInn sound from scratch (CC0) into assets/audio/*.wav.

  python3 tools/gen_audio.py

SFX are short plucks/chirps/noise bursts; music_farm is a relaxing pentatonic
loop (soft plucked melody + warm pad + bass) that seamlessly repeats.
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


def write(name, samples, gain=0.8):
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


def music():
    """A 16-bar loop at 84 BPM in C major pentatonic, gentle and repetitive on purpose."""
    bpm, bars = 84, 16
    beat = 60 / bpm
    total = int(SR * beat * 4 * bars)
    out = [0.0] * total
    r = random.Random(42)
    scale = [60, 62, 64, 67, 69, 72, 74, 76]
    chords = [(48, 55, 64), (45, 52, 60), (41, 48, 57), (43, 50, 59)]   # C Am F G
    def add(samples, at, vol):
        s = int(at * SR)
        for i, v in enumerate(samples):
            if s + i < total:
                out[s + i] += v * vol
            else:  # wrap the tail so the loop is seamless
                out[(s + i) % total] += v * vol
    for bar in range(bars):
        root = chords[bar % 4]
        t0 = bar * 4 * beat
        for n in root:  # pad
            add(tone(note(n), beat * 4.2, a=0.4, d=2.5, wave_="sine", vib=0.004), t0, 0.10)
        add(tone(note(root[0] - 12), beat * 1.8, a=0.02, d=0.6, wave_="tri"), t0, 0.22)        # bass
        add(tone(note(root[0] - 5), beat * 1.8, a=0.02, d=0.6, wave_="tri"), t0 + 2 * beat, 0.16)
        pos = 0.0
        while pos < 4:   # melody: plucks on eighths, with rests
            if r.random() < 0.62:
                n = r.choice(scale) + (12 if r.random() < 0.15 else 0)
                add(tone(note(n), 0.6, a=0.004, d=0.22, wave_="tri"), t0 + pos * beat, 0.16)
            pos += r.choice([0.5, 0.5, 1.0])
    write("music_farm", out, 0.55)


def ambience():
    """A 20 s seamless loop: soft wind (filtered noise) with occasional bird chirps."""
    dur = 20.0
    n = int(SR * dur)
    r = random.Random(9)
    out, y, y2 = [0.0] * n, 0.0, 0.0
    for i in range(n):
        y += 0.002 * (r.uniform(-1, 1) - y)
        y2 += 0.02 * (y - y2)
        swell = 0.6 + 0.4 * math.sin(2 * math.pi * i / n)          # exact period -> seamless
        out[i] = y2 * 60 * swell
    t = 0.7
    while t < dur - 1.0:
        f0 = r.uniform(2600, 4200)
        for k in range(r.randint(2, 5)):                            # a little phrase of chirps
            chirp = tone(f0 * r.uniform(0.9, 1.15), 0.09, a=0.005, d=0.035, glide=r.uniform(-3, 3))
            s0 = int((t + k * 0.12) * SR)
            for j, v in enumerate(chirp):
                if s0 + j < n: out[s0 + j] += v * 0.35
        t += r.uniform(1.5, 4.0)
    write("ambience", out, 0.35)


if __name__ == "__main__":
    sfx()
    music()
    ambience()
    print("audio written:", sorted(p.name for p in OUT.glob("*.wav")))
