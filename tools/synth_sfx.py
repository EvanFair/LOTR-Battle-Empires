"""Synthesize LOTR-flavoured SFX (CC0, original) for LOTR Battle Empires."""
import numpy as np, wave, sys, os
SR = 44100
out = sys.argv[1]
rng = np.random.default_rng(7)

def save(name, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())

def t(d): return np.arange(int(SR * d)) / SR

def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc; y[i] = acc
    return y

def env(n, attack, release_frac=0.3):
    e = np.ones(n); a = int(attack * SR)
    e[:a] = np.linspace(0, 1, a)
    r = int(n * release_frac); e[-r:] *= np.linspace(1, 0, r) ** 1.5
    return e

# Horn: a war horn with a swell — low brassy saw with a little vibrato and a pitch rise
def horn(base=98.0, dur=2.6):
    tt = t(dur)
    f = base * (1 + 0.06 * np.clip(tt / 0.25, 0, 1)) * (1 + 0.004 * np.sin(2 * np.pi * 5 * tt))
    phase = 2 * np.pi * np.cumsum(f) / SR
    x = sum((1 / k) * np.sin(k * phase) for k in range(1, 14))
    x = lowpass(x, 900) + 0.3 * lowpass(x, 2400)
    return x * env(len(tt), 0.35, 0.35)
h = horn()
save("horn", np.concatenate([h, horn(130.8, 1.6) * 0.9]))

# War drums: three deep thumps (Mordor / Isengard)
def thump(f0=55, dur=0.9):
    tt = t(dur)
    f = f0 * (1 + 1.5 * np.exp(-tt * 18))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 5)
    n = lowpass(rng.standard_normal(len(tt)), 400) * np.exp(-tt * 30) * 0.6
    return x + n
d = np.zeros(int(SR * 2.4))
for start, amp in [(0.0, 1.0), (0.55, 0.8), (1.1, 1.0), (1.4, 0.7)]:
    s = thump(); i = int(start * SR); d[i:i + len(s)] += s[: len(d) - i] * amp
save("drums", d)

# Sword clash: inharmonic metallic partials with fast decay
tt = t(0.7)
partials = [(1840, 1.0), (2630, 0.7), (3510, 0.5), (4980, 0.35), (6120, 0.2)]
x = sum(a * np.sin(2 * np.pi * f * tt) * np.exp(-tt * (6 + f / 900)) for f, a in partials)
x += rng.standard_normal(len(tt)) * np.exp(-tt * 60) * 0.8
save("clash", x)

# Boulder impact: low crunch
tt = t(0.8)
x = lowpass(rng.standard_normal(len(tt)), 300) * np.exp(-tt * 7) * 3
x += np.sin(2 * np.pi * 45 * tt) * np.exp(-tt * 9)
save("boulder", x)

# Blast (sapper / Saruman's fire): boom + crackle
tt = t(1.6)
x = lowpass(rng.standard_normal(len(tt)), 180) * np.exp(-tt * 3) * 4
x += np.sin(2 * np.pi * 38 * tt * (1 + np.exp(-tt * 6))) * np.exp(-tt * 4) * 1.2
crackle = (rng.random(len(tt)) > 0.997) * rng.standard_normal(len(tt)) * np.exp(-tt * 2) * 3
x += crackle
save("blast", x)

# Building collapse: long rumble
tt = t(2.2)
x = lowpass(rng.standard_normal(len(tt)), 220) * np.exp(-tt * 1.6) * 3
save("collapse", x)

# Construction complete: three hammer taps
tt = t(0.18)
tap = (np.sin(2 * np.pi * 820 * tt) + 0.5 * np.sin(2 * np.pi * 1290 * tt)) * np.exp(-tt * 40)
x = np.zeros(int(SR * 0.9))
for s in [0.0, 0.25, 0.5]:
    i = int(s * SR); x[i:i + len(tap)] += tap
save("build_done", x)
print("ok")
