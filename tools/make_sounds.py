"""Synthesises the game's sound effects into assets/audio (no downloads needed).

Run:  python tools/make_sounds.py
"""
import os
import sys
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = np.random.default_rng(1986)


def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    data = (x * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(name, round(len(x) / SR, 2), "s")


def noise(n, shape):
    """Noise with a spectrum given by shape(freqs). Periodic over n samples."""
    f = np.fft.rfftfreq(n, 1.0 / SR)
    spec = (rng.normal(size=f.size) + 1j * rng.normal(size=f.size)) * shape(f)
    x = np.fft.irfft(spec, n)
    return x / (np.max(np.abs(x)) + 1e-9)


def band(lo, hi, soft=0.3):
    def s(f):
        a = 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** (2 / soft))
        b = 1.0 / (1.0 + (f / hi) ** (2 / soft))
        return a * b
    return s


def t(n):
    return np.arange(n) / SR


def footstep(seed):
    """A shoe on gritty concrete: heel strike, then the sole coming down, with loose grit."""
    n = int(SR * 0.45)
    tt = t(n)
    x = np.zeros(n)
    # Heel: a short dull knock, mostly low frequencies, no ringing tone.
    attack = np.minimum(tt / 0.002, 1.0)
    heel = noise(n, band(70, 380 + 40 * seed)) * attack * np.exp(-tt / rng.uniform(0.014, 0.022))
    f = 75 + 45 * np.exp(-tt / 0.012)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.022) * 0.45
    x += heel + body
    # Sole / toe lands a moment later: softer, wider, a little brighter.
    i = int(rng.uniform(0.065, 0.1) * SR)
    m = n - i
    sole = noise(m, band(350, 2400)) * np.minimum(t(m) / 0.004, 1.0) * np.exp(-t(m) / rng.uniform(0.022, 0.035))
    x[i:] += sole * rng.uniform(0.3, 0.45)
    # Grit crushed under the shoe: a handful of tiny clicks.
    for _ in range(rng.integers(6, 15)):
        j = int(rng.uniform(0.0, 0.2) * SR)
        m = min(int(SR * 0.02), n - j)
        x[j:j + m] += noise(m, band(1800, 6500)) * np.exp(-t(m) / 0.0025) * rng.uniform(0.03, 0.14)
    # A faint scuff as the foot leaves.
    scuff = noise(n, band(900, 3200)) * np.sin(np.pi * np.clip((tt - 0.1) / 0.16, 0, 1)) ** 2
    x += scuff * rng.uniform(0.03, 0.07)
    # Take the digital edge off.
    spec = np.fft.rfft(x)
    spec *= band(55, 4800, 0.5)(np.fft.rfftfreq(n, 1.0 / SR))
    return np.fft.irfft(spec, n)


def drone():
    n = SR * 24
    tt = t(n)
    rumble = noise(n, lambda f: band(18, 110)(f) / np.maximum(f, 20.0))
    wind = noise(n, band(350, 800, 0.15))
    # Slow swells; whole cycles over the loop so it repeats seamlessly.
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * 2 * tt / 24 + 1.0) * np.sin(2 * np.pi * 5 * tt / 24)
    air = noise(n, band(2000, 6000)) * 0.03
    tone = np.sin(2 * np.pi * 55 * tt) * 0.08 * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * tt / 24))
    return rumble * 1.0 + wind * swell * 0.16 + air + tone


def hum():
    n = SR * 2
    tt = t(n)
    x = np.zeros(n)
    for k, a in ((1, 0.3), (2, 1.0), (3, 0.25), (4, 0.4), (6, 0.2), (8, 0.1)):
        x += a * np.sin(2 * np.pi * 50 * k * tt + k)
    buzz = noise(n, band(3000, 8000)) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 100 * tt))) * 0.12
    return x + buzz


def thud():
    n = int(SR * 2.2)
    tt = t(n)
    body = np.sin(2 * np.pi * 58 * tt * (1 + 0.3 * np.exp(-tt / 0.03))) * np.exp(-tt / 0.22)
    slam = noise(n, band(60, 420)) * np.exp(-tt / 0.12)
    tail = noise(n, band(80, 300)) * np.exp(-tt / 0.7) * 0.25
    return body + slam * 0.8 + tail


def ping(n, f0, decay):
    tt = t(n)
    x = np.zeros(n)
    for ratio, a in ((1.0, 1.0), (2.63, 0.6), (4.25, 0.35), (6.1, 0.2)):
        x += a * np.sin(2 * np.pi * f0 * ratio * tt) * np.exp(-tt / (decay / ratio ** 0.5))
    return x


def knock():
    n = int(SR * 2.6)
    x = np.zeros(n)
    for start, amp in ((0.0, 1.0), (0.42, 0.7), (0.71, 0.85), (1.5, 0.4)):
        i = int(start * SR)
        p = ping(n - i, 520, 0.16) * amp
        x[i:] += p
    return x


def creak():
    n = int(SR * 1.6)
    tt = t(n)
    f = 170 + 110 * np.sin(np.pi * tt / 1.6) ** 2 + 25 * np.sin(2 * np.pi * 3.1 * tt)
    phase = 2 * np.pi * np.cumsum(f) / SR
    saw = (phase / (2 * np.pi)) % 1.0 * 2 - 1
    stick = (np.sin(2 * np.pi * np.cumsum(22 + 14 * np.sin(2 * np.pi * 0.9 * tt)) / SR) > 0.2) * 1.0
    env = np.sin(np.pi * tt / 1.6) ** 0.6
    x = saw * stick * env
    spec = np.fft.rfft(x)
    spec *= band(500, 3200)(np.fft.rfftfreq(n, 1.0 / SR))
    return np.fft.irfft(spec, n)


def steps_above():
    n = int(SR * 4.5)
    x = np.zeros(n)
    for i, start in enumerate((0.0, 0.62, 1.21, 1.86, 2.44, 3.3)):
        s = int(start * SR)
        m = int(SR * 0.5)
        tt = t(m)
        th = np.sin(2 * np.pi * (48 + 5 * (i % 2)) * tt) * np.exp(-tt / 0.09)
        th += noise(m, band(40, 220)) * np.exp(-tt / 0.05) * 0.5
        x[s:s + m] += th * (0.7 + 0.3 * rng.random())
    return x


def click():
    n = int(SR * 0.12)
    x = np.zeros(n)
    for start, amp in ((0.0, 1.0), (0.045, 0.6)):
        i = int(start * SR)
        m = n - i
        x[i:] += noise(m, band(1800, 7000)) * np.exp(-t(m) / 0.004) * amp
    return x


def rattle():
    n = int(SR * 0.9)
    x = np.zeros(n)
    for start in (0.0, 0.09, 0.2, 0.27, 0.41, 0.5):
        i = int(start * SR)
        m = n - i
        hit = noise(m, band(900, 5000)) * np.exp(-t(m) / 0.012)
        hit += ping(m, 780, 0.05) * 0.5
        x[i:] += hit * (0.6 + 0.4 * rng.random())
    x += np.pad(np.sin(2 * np.pi * 70 * t(n)) * np.exp(-t(n) / 0.08), 0) * 0.5
    return x


def main():
    for i in range(6):
        save("step_%d" % i, footstep(i), rng.uniform(0.6, 0.8))
    if "steps" in sys.argv:
        return
    save("drone", drone(), 0.85)
    save("hum", hum(), 0.6)
    # Door, latch, creak and other handling sounds are real recordings in assets/audio/foley and
    # assets/audio/*.mp3, not generated here.


if __name__ == "__main__":
    sys.exit(main())
