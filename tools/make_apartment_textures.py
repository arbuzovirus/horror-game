"""Paints the PS1-style textures for flat 17 (the two-room khrushchevka) into apartment/textures.

Small (32-256 px), drawn from patterns: wallpapers, Soviet carpets, parquet, linoleum, tiles,
enamel, veneer, fabrics, plus wear: fading, grime, chips, rust, damp.

Run:  python tools/make_apartment_textures.py
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_graffiti import write_png  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "apartment", "textures")
rng = np.random.default_rng(1964)


def grid(n, m=None):
    m = m or n
    y, x = np.mgrid[0:m, 0:n].astype(np.float32)
    return (x + 0.5) / n, (y + 0.5) / m


def col(c):
    return np.array(c, np.float32)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def tnoise(n, cells, seed, m=None):
    """Tileable value noise: smooth, used only for wear and colour drift, never as a pattern."""
    m = m or n
    r = np.random.default_rng(seed)
    g = r.random((cells, cells)).astype(np.float32)
    u, v = grid(n, m)
    x = u * cells
    y = v * cells
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = smooth(0, 1, x - x0)
    fy = smooth(0, 1, y - y0)
    x1 = (x0 + 1) % cells
    y1 = (y0 + 1) % cells
    x0 %= cells
    y0 %= cells
    a = g[y0, x0] * (1 - fx) + g[y0, x1] * fx
    b = g[y1, x0] * (1 - fx) + g[y1, x1] * fx
    return a * (1 - fy) + b * fy


def fbm(n, seed, m=None, base=4):
    return (tnoise(n, base, seed, m) * 0.5 + tnoise(n, base * 2, seed + 1, m) * 0.3
            + tnoise(n, base * 4, seed + 2, m) * 0.2)


def save(name, rgb, alpha=None):
    os.makedirs(OUT, exist_ok=True)
    rgb = np.clip(rgb, 0, 1)
    a = np.ones(rgb.shape[:2] + (1,), np.float32) if alpha is None else np.clip(alpha, 0, 1)[..., None]
    write_png(os.path.join(OUT, name + ".png"), np.concatenate([rgb, a], axis=2))
    print(name, rgb.shape[1], "x", rgb.shape[0])


def mix(a, b, t):
    t = np.asarray(t, np.float32)
    if t.ndim == 2:
        t = t[..., None]
    return a * (1 - t) + b * t


def age(rgb, n, seed, amount=0.25, yellow=0.15):
    """Fades towards a dirty yellowed grey and adds uneven grime."""
    g = fbm(n, seed, rgb.shape[0], base=2)
    dirty = col((0.45, 0.42, 0.34))
    out = mix(rgb, dirty * (rgb.mean(axis=2, keepdims=True) * 1.4 + 0.2), yellow)
    return out * (1 - amount * (g - 0.3))[..., None]


# ------------------------------------------------------------------ walls

def wallpaper(name, bg, ink, ink2, kind, seed, repeats=2):
    n = 128
    u, v = grid(n)
    u = (u * repeats) % 1.0
    v = (v * repeats) % 1.0
    a = np.zeros((n, n), np.float32)
    b = np.zeros((n, n), np.float32)
    for oy in (0.0, 0.5):
        for ox in ((0.0,) if oy == 0 else (0.5,)):
            cu = (u - ox) % 1.0 - 0.5
            cv = (v - oy) % 1.0 - 0.5
            r = np.sqrt(cu * cu + cv * cv)
            th = np.arctan2(cv, cu)
            if kind == "damask":
                # A vase-like medallion: petals around a centre, a teardrop on top and below.
                petal = r < 0.17 * (0.6 + 0.4 * np.abs(np.cos(3 * th)))
                drop = ((cu / 0.07) ** 2 + ((np.abs(cv) - 0.3) / 0.13) ** 2) < 1
                ring = np.abs(r - 0.23) < 0.012
                a = np.maximum(a, (petal | drop).astype(np.float32))
                b = np.maximum(b, ring.astype(np.float32))
            else:
                # Small flower sprigs on a trellis of thin lines.
                flower = r < 0.08 * (0.55 + 0.45 * np.cos(5 * th))
                leaf = ((cu - 0.1) / 0.06) ** 2 + ((cv + 0.08) / 0.025) ** 2 < 1
                a = np.maximum(a, (flower | leaf).astype(np.float32))
    if kind != "damask":
        d1 = np.abs(((u + v) * 2.0) % 1.0 - 0.5) < 0.012
        d2 = np.abs(((u - v) * 2.0) % 1.0 - 0.5) < 0.012
        b = np.maximum(b, (d1 | d2).astype(np.float32))
    rgb = np.ones((n, n, 3), np.float32) * col(bg)
    rgb = mix(rgb, col(ink), a * 0.8)
    rgb = mix(rgb, col(ink2), b * 0.7)
    rgb *= (0.92 + 0.08 * np.sin(v * math.pi * 16))[..., None] ** 0.3      # paper print banding
    # Seam where two strips of paper meet, slightly lifted and dark.
    seam = np.abs(grid(n)[0] - 0.02) < 0.008
    rgb[seam] *= 0.7
    rgb = age(rgb, n, seed, 0.1, 0.25)
    save(name, rgb)


def stripes_wallpaper():
    n = 128
    u, v = grid(n)
    base = np.ones((n, n, 3), np.float32) * col((0.42, 0.3, 0.2))
    s = (u * 8) % 1.0
    base = mix(base, col((0.5, 0.38, 0.26)), (s > 0.55).astype(np.float32) * 0.8)
    base = mix(base, col((0.26, 0.17, 0.11)), (np.abs(s - 0.5) < 0.04).astype(np.float32))
    # Little rhombs in the light stripes.
    rh = (np.abs(((s - 0.77) * 6)) + np.abs(((v * 16) % 1.0 - 0.5) * 2)) < 0.55
    base = mix(base, col((0.6, 0.48, 0.32)), (rh & (s > 0.55)).astype(np.float32) * 0.6)
    base = age(base, n, 21, 0.4, 0.2)
    save("wallpaper_hall", base)


def oil_paint(name, lower, upper, split, seed):
    n = 128
    u, v = grid(n)
    rgb = np.where((v > split)[..., None], col(lower), col(upper))
    brush = tnoise(n, 32, seed) * 0.1 + (np.sin(u * 90 + tnoise(n, 8, seed + 1) * 6) * 0.03)
    rgb = rgb * (0.95 + brush)[..., None]
    line = np.abs(v - split) < 0.01
    rgb[line] *= 0.6
    rgb = age(rgb, n, seed, 0.12, 0.15)
    save(name, rgb)


def tiles(name, size_px, tile_col, grout, seed, n=128, cracked=0.06):
    u, v = grid(n)
    x = u * n
    y = v * n
    tx = (x // size_px).astype(int)
    ty = (y // size_px).astype(int)
    r = np.random.default_rng(seed)
    tone = r.uniform(0.86, 1.08, (n // size_px + 1, n // size_px + 1)).astype(np.float32)
    rgb = np.ones((n, n, 3), np.float32) * col(tile_col) * tone[ty, tx][..., None]
    # Glaze highlight in each tile corner.
    lx = (x % size_px) / size_px
    ly = (y % size_px) / size_px
    rgb *= (1.0 + 0.08 * (1 - smooth(0.0, 0.5, lx + ly)))[..., None]
    gl = (x % size_px < 1.2) | (y % size_px < 1.2)
    rgb[gl] = col(grout)
    # A few cracked tiles and one missing.
    for i in range(int((n // size_px) ** 2 * cracked) + 1):
        cx, cy = r.integers(0, n // size_px, 2)
        x0, y0 = cx * size_px, cy * size_px
        p = np.array([x0 + r.uniform(1, size_px - 1), y0 + 1.0])
        for k in range(size_px * 2):
            p += (r.uniform(-0.8, 0.8), 0.5)
            px, py = int(p[0]) % n, int(p[1]) % n
            if py >= y0 + size_px:
                break
            rgb[py, px] *= 0.45
    cx, cy = r.integers(0, n // size_px, 2)
    hole = (tx == cx) & (ty == cy)
    rgb[hole] = col((0.36, 0.34, 0.3)) * (0.8 + 0.2 * tnoise(n, 16, seed))[hole][..., None]
    rgb = age(rgb, n, seed, 0.3, 0.2)
    rust = fbm(n, seed + 3)
    rgb = mix(rgb, col((0.36, 0.22, 0.12)), smooth(0.7, 0.85, rust) * 0.5 * (v > 0.3))
    save(name, rgb)


def whitewash(name, seed, tint=(0.78, 0.76, 0.7)):
    n = 128
    rgb = np.ones((n, n, 3), np.float32) * col(tint)
    rgb *= (0.9 + 0.1 * tnoise(n, 32, seed))[..., None]
    stain = fbm(n, seed + 1, base=3)
    ring = smooth(0.62, 0.64, stain) * (1 - smooth(0.64, 0.7, stain))
    rgb = mix(rgb, rgb * col((0.85, 0.72, 0.5)), smooth(0.58, 0.7, stain) * 0.2)
    rgb *= (1 - 0.08 * ring)[..., None]
    rgb = age(rgb, n, seed, 0.08, 0.1)
    save(name, rgb)


# ------------------------------------------------------------------ floors

def parquet():
    n = 128
    u, v = grid(n)
    x, y = u * n, v * n
    plank_w, plank_l = 8, 32
    row = (y // plank_w).astype(int)
    off = (row % 2) * (plank_l // 2)
    idx = ((x + off) // plank_l).astype(int)
    r = np.random.default_rng(5)
    tone = r.uniform(0.75, 1.1, (40, 40)).astype(np.float32)
    base = col((0.33, 0.2, 0.11)) * tone[row % 40, idx % 40][..., None]
    grain = np.sin((y % plank_w) * 1.9 + np.sin((x + off) * 0.21 + row) * 1.5)
    rgb = np.ones((n, n, 3), np.float32) * base * (0.92 + 0.08 * grain)[..., None]
    joint = ((y % plank_w) < 0.9) | (((x + off) % plank_l) < 0.9)
    rgb[joint] *= 0.5
    # Varnish worn off along the walking lines, grey and dull.
    wear = fbm(n, 6)
    rgb = mix(rgb, col((0.36, 0.3, 0.24)), smooth(0.5, 0.75, wear) * 0.5)
    save("parquet", rgb)


def linoleum():
    n = 128
    u, v = grid(n)
    x, y = u * 8, v * 8
    cell = ((np.floor(x) + np.floor(y)) % 2)
    rgb = np.ones((n, n, 3), np.float32) * col((0.36, 0.27, 0.18))
    rgb = mix(rgb, col((0.44, 0.34, 0.22)), cell * 0.7)
    fleck = tnoise(n, 64, 8)
    rgb *= (0.88 + 0.2 * fleck)[..., None]
    diam = (np.abs((x % 1) - 0.5) + np.abs((y % 1) - 0.5)) < 0.18
    rgb = mix(rgb, col((0.27, 0.19, 0.13)), diam.astype(np.float32) * 0.6)
    wear = fbm(n, 9)
    rgb = mix(rgb, col((0.3, 0.27, 0.22)), smooth(0.45, 0.75, wear) * 0.6)
    save("linoleum", rgb)


def carpet(name, field, border, ink, light, seed, n=256):
    u, v = grid(n)
    x, y = u * 2 - 1, v * 2 - 1
    ax, ay = np.abs(x), np.abs(y)
    m = np.maximum(ax, ay)
    rgb = np.ones((n, n, 3), np.float32) * col(field)
    # Borders: outer dark band with a running zigzag, inner thin light line.
    outer = m > 0.84
    rgb[outer] = col(border)
    zig = np.abs(((np.where(ax > ay, y, x) * 12) % 2) - 1)
    edge = np.abs(m - 0.92 - (zig - 0.5) * 0.05) < 0.02
    rgb[edge & outer] = col(light)
    rgb[np.abs(m - 0.8) < 0.012] = col(light)
    rgb[np.abs(m - 0.77) < 0.008] = col(ink)
    # Field: small repeated diamond "guls".
    gx, gy = (x * 5) % 1 - 0.5, (y * 7) % 1 - 0.5
    gul = (np.abs(gx) * 1.4 + np.abs(gy)) < 0.25
    gul_in = (np.abs(gx) * 1.4 + np.abs(gy)) < 0.12
    inner = m < 0.76
    rgb[gul & inner] = col(ink)
    rgb[gul_in & inner] = col(light)
    # Central stepped medallion.
    d = ax * 1.3 + ay
    med = d < 0.55
    rgb[med] = col(border)
    step = np.abs(d - 0.45 - 0.03 * np.sign(np.sin(ax * 40))) < 0.03
    rgb[step] = col(light)
    rgb[(d < 0.3)] = col(field)
    rgb[np.abs(d - 0.2) < 0.03] = col(ink)
    rgb[(d < 0.08)] = col(light)
    # Corner pieces.
    cc = ((ax - 0.62) ** 2 + (ay - 0.62) ** 2) < 0.012
    rgb[cc] = col(light)
    # Pile: tiny knot pattern, and wear (the pile flattened and grey in the middle).
    knot = ((np.mgrid[0:n, 0:n][0] + np.mgrid[0:n, 0:n][1]) % 2) * 0.05
    rgb *= (0.95 + knot)[..., None]
    rgb = age(rgb, n, seed, 0.35, 0.2)
    worn = np.exp(-(x * x * 2 + y * y * 1.2)) * fbm(n, seed + 4)
    rgb = mix(rgb, col((0.33, 0.27, 0.22)), np.clip(worn * 0.9, 0, 0.55))
    save(name, rgb)


# ------------------------------------------------------------------ materials

def wood(name, base, n=128, seed=11, rings=40.0, gloss=True):
    u, v = grid(n)
    warp = tnoise(n, 4, seed) * 3 + tnoise(n, 16, seed + 1) * 0.6
    g = np.sin((u * rings + warp) * math.pi)
    rgb = np.ones((n, n, 3), np.float32) * col(base) * (0.85 + 0.15 * g)[..., None]
    if gloss:
        rgb *= (1.0 + 0.06 * np.sin(v * 3 + u))[..., None]
    rgb = age(rgb, n, seed, 0.2, 0.08)
    # Scratches through the lacquer.
    r = np.random.default_rng(seed)
    for i in range(10):
        x0, y0 = r.integers(0, n, 2)
        ln = r.integers(6, 30)
        dx, dy = r.uniform(-1, 1), r.uniform(-0.3, 0.3)
        for t in range(ln):
            px, py = int(x0 + dx * t) % n, int(y0 + dy * t) % n
            rgb[py, px] = rgb[py, px] * 0.7 + 0.12
    save(name, rgb)


def fabric(name, a, b, n=64, kind="weave", seed=3):
    u, v = grid(n)
    x, y = u * n, v * n
    w = ((x.astype(int) + y.astype(int)) % 2) * 0.08
    rgb = np.ones((n, n, 3), np.float32) * col(a) * (0.92 + w)[..., None]
    if kind == "tufted":
        d = (np.abs((u * 4) % 1 - 0.5) + np.abs((v * 4) % 1 - 0.5))
        rgb *= (0.8 + 0.25 * smooth(0.0, 0.5, d))[..., None]
        btn = (((u * 4) % 1 - 0.5) ** 2 + ((v * 4) % 1 - 0.5) ** 2) < 0.006
        rgb[btn] = col(b)
    elif kind == "check":
        c = (((u * 8).astype(int) + (v * 8).astype(int)) % 2)
        rgb = mix(rgb, col(b), c * 0.6)
    elif kind == "floral":
        cu, cv = (u * 3) % 1 - 0.5, (v * 3 + 0.5 * (np.floor(u * 3) % 2)) % 1 - 0.5
        r = np.sqrt(cu * cu + cv * cv)
        th = np.arctan2(cv, cu)
        fl = r < 0.22 * (0.55 + 0.45 * np.cos(5 * th))
        rgb[fl] = col(b) * (0.8 + 0.4 * (r[fl] < 0.06))[..., None]
        leaf = (((cu + 0.25) / 0.12) ** 2 + ((cv - 0.2) / 0.05) ** 2) < 1
        rgb[leaf] = col((0.22, 0.28, 0.16))
    elif kind == "folds":
        rgb *= (0.7 + 0.3 * (0.5 + 0.5 * np.sin(u * math.pi * 6)))[..., None]
    rgb = age(rgb, n, seed, 0.3, 0.15)
    save(name, rgb)


def enamel(name, base, n=64, seed=13, chips=12, rust=0.4):
    u, v = grid(n)
    rgb = np.ones((n, n, 3), np.float32) * col(base)
    rgb *= (0.94 + 0.06 * tnoise(n, 8, seed))[..., None]
    r = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:n, 0:n]
    for i in range(chips):
        cx, cy = r.integers(0, n, 2)
        rad = r.uniform(0.6, 2.2)
        m = (xx - cx) ** 2 + (yy - cy) ** 2 < rad * rad
        rgb[m] = col((0.08, 0.07, 0.07))
        halo = ((xx - cx) ** 2 + (yy - cy + 2) ** 2 < (rad + 1.5) ** 2) & ~m
        rgb[halo] = rgb[halo] * 0.6 + col((0.3, 0.16, 0.08)) * 0.4
    run = fbm(n, seed + 1)
    rgb = mix(rgb, col((0.42, 0.26, 0.12)), smooth(0.74, 0.86, run) * rust * (v > 0.4))
    rgb = age(rgb, n, seed, 0.12, 0.2)
    save(name, rgb)


def flat(name, c, n=32, seed=17, var=0.12, amount=0.2):
    rgb = np.ones((n, n, 3), np.float32) * col(c)
    rgb *= (1 - var / 2 + var * tnoise(n, 8, seed))[..., None]
    rgb = age(rgb, n, seed, amount, 0.1)
    save(name, rgb)


def iron_paint():
    n = 64
    u, v = grid(n)
    rgb = np.ones((n, n, 3), np.float32) * col((0.62, 0.58, 0.5))
    layers = fbm(n, 31)
    rgb = mix(rgb, col((0.5, 0.52, 0.46)), smooth(0.55, 0.57, layers) * 0.35)    # an older green coat
    rgb = mix(rgb, col((0.33, 0.18, 0.09)), smooth(0.74, 0.78, layers))         # rust under it all
    rgb *= (0.9 + 0.1 * np.sin(v * 50))[..., None]                             # drips of paint
    save("iron_paint", rgb)


def books():
    n = 64
    u, v = grid(n)
    x = u * n
    r = np.random.default_rng(41)
    rgb = np.zeros((n, n, 3), np.float32)
    pos = 0
    palette = [(0.3, 0.08, 0.06), (0.1, 0.15, 0.25), (0.18, 0.22, 0.12), (0.35, 0.28, 0.15),
               (0.2, 0.18, 0.17), (0.4, 0.33, 0.25), (0.12, 0.1, 0.09)]
    while pos < n:
        w = int(r.integers(3, 8))
        c = col(palette[int(r.integers(0, len(palette)))]) * r.uniform(0.8, 1.15)
        sl = slice(pos, min(pos + w, n))
        rgb[:, sl] = c
        rgb[:, sl] *= (0.85 + 0.25 * np.sin(np.linspace(0, math.pi, sl.stop - sl.start)))[None, :, None]
        for band_y in (int(n * r.uniform(0.15, 0.25)), int(n * r.uniform(0.7, 0.85))):
            rgb[band_y:band_y + 2, sl] = col((0.55, 0.47, 0.25))
        for k in range(3):
            yy = int(n * r.uniform(0.35, 0.6)) + k * 2
            rgb[yy, pos + 1:min(pos + w - 1, n)] = col((0.6, 0.55, 0.45)) * 0.8
        pos += w
    rgb = age(rgb, n, 42, 0.2, 0.15)
    save("books", rgb)


def crt():
    n = 64
    u, v = grid(n)
    x, y = u * 2 - 1, v * 2 - 1
    rgb = np.ones((n, n, 3), np.float32) * col((0.07, 0.08, 0.075))
    glare = np.exp(-((x + 0.4) ** 2 * 6 + (y + 0.5) ** 2 * 10))
    rgb += glare[..., None] * 0.12
    rgb *= (1 - 0.5 * np.clip(x * x + y * y - 0.5, 0, 1))[..., None]
    save("crt_off", rgb)
    # Several frames of snow, stacked vertically; the material scrolls through them.
    frames = 4
    r = np.random.default_rng(7)
    snow = np.zeros((n * frames, n, 3), np.float32)
    for f in range(frames):
        s = r.random((n // 2, n // 2)).astype(np.float32)
        s = np.repeat(np.repeat(s, 2, 0), 2, 1)
        lines = (0.85 + 0.15 * np.sin(np.arange(n) * 1.3 + f))[:, None]
        frame = (0.25 + 0.65 * s) * lines
        roll = (np.abs(((np.arange(n) / n + f * 0.27) % 1) - 0.5) < 0.06)[:, None] * 0.2
        snow[f * n:(f + 1) * n] = (frame + roll)[..., None] * col((0.75, 0.85, 0.85))
    snow *= (1 - 0.5 * np.clip(np.tile(x * x + y * y, (frames, 1)) - 0.5, 0, 1))[..., None]
    save("crt_snow", snow)


def mirror():
    n = 64
    u, v = grid(n)
    rgb = np.ones((n, n, 3), np.float32) * col((0.2, 0.22, 0.24))
    rgb += (np.exp(-((u - 0.3) ** 2 * 8 + (v - 0.25) ** 2 * 6)) * 0.15)[..., None]
    rgb *= (0.8 + 0.2 * (1 - v))[..., None]
    spots = fbm(n, 51)
    rgb = mix(rgb, col((0.05, 0.05, 0.05)), smooth(0.74, 0.8, spots))           # silvering gone
    edge = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))
    rgb = mix(rgb, col((0.08, 0.07, 0.06)), smooth(0.12, 0.0, edge) * fbm(n, 52))
    save("mirror", rgb)


def door_paint():
    n = 64
    u, v = grid(n)
    rgb = np.ones((n, n, 3), np.float32) * col((0.72, 0.7, 0.62))
    panel = (np.abs(u - 0.5) < 0.38) & (((v > 0.08) & (v < 0.46)) | ((v > 0.54) & (v < 0.92)))
    edge = (np.abs(np.abs(u - 0.5) - 0.38) < 0.02) & (v > 0.08) & (v < 0.92)
    rgb[panel] *= 0.94
    rgb[edge] *= 0.7
    hand = np.exp(-(((u - 0.85) / 0.12) ** 2 + ((v - 0.52) / 0.15) ** 2))
    rgb *= (1 - 0.35 * hand)[..., None]                                          # years of hands
    rgb = age(rgb, n, 61, 0.15, 0.3)
    chip = fbm(n, 62)
    rgb = mix(rgb, col((0.42, 0.33, 0.24)), smooth(0.72, 0.76, chip))           # wood under the paint
    save("door_paint", rgb)


def tulle():
    n = 64
    u, v = grid(n)
    x, y = u * n, v * n
    net = ((x % 4) < 1) | ((y % 4) < 1)
    cu, cv = (u * 2) % 1 - 0.5, (v * 2) % 1 - 0.5
    r = np.sqrt(cu * cu + cv * cv)
    th = np.arctan2(cv, cu)
    motif = (r < 0.3 * (0.6 + 0.4 * np.cos(6 * th))) & (r > 0.12)
    hem = v > 0.93
    a = np.where(net | motif | hem, 0.85, 0.0).astype(np.float32)
    rgb = np.ones((n, n, 3), np.float32) * col((0.66, 0.64, 0.56))
    rgb = age(rgb, n, 71, 0.3, 0.35)
    save("tulle", rgb, a)


def newspaper():
    n = 64
    u, v = grid(n)
    rgb = np.ones((n, n, 3), np.float32) * col((0.62, 0.58, 0.47))
    x, y = (u * n).astype(int), (v * n).astype(int)
    col_m = (x % 16) < 14
    text = col_m & ((y % 3) == 0) & (y > 10) & ((x * 7 + y * 3) % 11 > 2)
    rgb[text] *= 0.55
    rgb[(y > 2) & (y < 8) & (x > 3) & (x < 60)] *= 0.4                     # the masthead
    rgb = age(rgb, n, 81, 0.35, 0.3)
    save("newspaper", rgb)


def photo():
    n = 32
    u, v = grid(n)
    rgb = np.ones((n, n, 3), np.float32) * col((0.5, 0.42, 0.3))
    head = ((u - 0.5) / 0.16) ** 2 + ((v - 0.38) / 0.2) ** 2 < 1
    body = ((u - 0.5) / 0.32) ** 2 + ((v - 0.95) / 0.35) ** 2 < 1
    rgb[head | body] = col((0.22, 0.17, 0.12))
    rgb = age(rgb, n, 91, 0.4, 0.3)
    save("photo", rgb)


def decals():
    n = 128
    u, v = grid(n)
    # Damp stain: soft brown blot with dark tide-lines.
    d = np.sqrt((u - 0.5) ** 2 + (v - 0.5) ** 2) * 2
    shape = fbm(n, 101) * 0.6 + (1 - d) * 0.9
    a = smooth(0.55, 0.75, shape)
    tide = np.clip(1 - np.abs(shape - 0.58) / 0.025, 0, 1)
    rgb = np.ones((n, n, 3), np.float32) * col((0.33, 0.26, 0.16))
    rgb = mix(rgb, col((0.18, 0.13, 0.08)), tide)
    save("decal_damp", rgb, np.maximum(a * 0.55, tide * 0.8))
    # Mould spreading out of a corner (decal placed in the corner).
    shape = fbm(n, 111, base=8) * 0.7 + (1 - np.sqrt(u * u + (1 - v) ** 2)) * 0.8
    a = smooth(0.6, 0.9, shape)
    rgb = np.ones((n, n, 3), np.float32) * col((0.09, 0.1, 0.07))
    save("decal_mould", rgb, a * 0.9)
    # Torn wallpaper showing old newspaper and grey plaster beneath.
    shape = fbm(n, 121) * 0.7 + (1 - d) * 0.8
    hole = smooth(0.6, 0.62, shape)
    ring = np.clip(1 - np.abs(shape - 0.6) / 0.02, 0, 1)
    rgb = np.ones((n, n, 3), np.float32) * col((0.5, 0.48, 0.44))
    paper = (((u * n).astype(int) % 6) < 5) & (((v * n).astype(int) % 3) == 0)
    rgb[paper & (fbm(n, 122) > 0.5)] *= 0.6
    rgb = mix(rgb, col((0.7, 0.66, 0.55)), ring)
    save("decal_torn", rgb, np.maximum(hole, ring))
    # A crack in the plaster, with a few branches.
    a = np.zeros((n, n), np.float32)
    r = np.random.default_rng(131)
    for branch in range(4):
        p = np.array([n * 0.5, 2.0]) if branch == 0 else np.array([r.uniform(30, 98), r.uniform(20, 100)])
        for k in range(160):
            p += (r.uniform(-1.2, 1.2), 0.8)
            if not (0 <= p[0] < n and 0 <= p[1] < n):
                break
            a[int(p[1]), int(p[0])] = 1.0
            if int(p[0]) + 1 < n:
                a[int(p[1]), int(p[0]) + 1] = 0.5
    rgb = np.ones((n, n, 3), np.float32) * col((0.12, 0.1, 0.09))
    save("decal_crack", rgb, a)
    # Dirt where hands and shoulders rubbed the wall, and dust in a corner.
    shape = np.exp(-((u - 0.5) ** 2 * 8 + (v - 0.5) ** 2 * 3)) * (0.6 + 0.4 * fbm(n, 141))
    rgb = np.ones((n, n, 3), np.float32) * col((0.12, 0.1, 0.08))
    save("decal_grime", rgb, shape * 0.6)


def main():
    wallpaper("wallpaper_living", (0.5, 0.48, 0.36), (0.3, 0.33, 0.22), (0.6, 0.55, 0.4), "damask", 1, 3)
    wallpaper("wallpaper_bed", (0.58, 0.5, 0.43), (0.45, 0.25, 0.23), (0.48, 0.42, 0.36), "sprig", 2, 4)
    stripes_wallpaper()
    oil_paint("paint_kitchen", (0.46, 0.55, 0.5), (0.7, 0.69, 0.62), 0.55, 4)
    oil_paint("paint_bath", (0.46, 0.5, 0.55), (0.68, 0.68, 0.64), 0.5, 5)
    tiles("tile_kitchen", 16, (0.72, 0.71, 0.66), (0.3, 0.28, 0.24), 6)
    tiles("tile_bath", 10, (0.42, 0.52, 0.56), (0.18, 0.18, 0.17), 7, n=120, cracked=0.05)
    tiles("tile_floor", 8, (0.45, 0.34, 0.27), (0.17, 0.15, 0.13), 8, n=64, cracked=0.02)
    whitewash("ceiling", 9)
    whitewash("plaster_grey", 10, (0.55, 0.53, 0.5))
    parquet()
    linoleum()
    carpet("carpet_floor", (0.38, 0.07, 0.06), (0.1, 0.1, 0.18), (0.08, 0.06, 0.06), (0.62, 0.55, 0.4), 15)
    carpet("carpet_wall", (0.3, 0.1, 0.07), (0.25, 0.06, 0.05), (0.08, 0.1, 0.16), (0.58, 0.48, 0.32), 16)
    wood("wood_dark", (0.27, 0.15, 0.08))
    wood("wood_mid", (0.42, 0.27, 0.14), seed=12, rings=30)
    wood("wood_light", (0.55, 0.42, 0.28), n=64, seed=14, rings=20, gloss=False)
    fabric("fabric_sofa", (0.3, 0.29, 0.18), (0.14, 0.13, 0.08), kind="tufted", seed=21)
    fabric("fabric_chair", (0.42, 0.24, 0.14), (0.2, 0.1, 0.06), seed=22)
    fabric("bedspread", (0.42, 0.12, 0.1), (0.62, 0.5, 0.36), n=128, kind="floral", seed=23)
    fabric("pillow", (0.66, 0.63, 0.56), (0.5, 0.45, 0.4), seed=24)
    fabric("drape", (0.36, 0.26, 0.17), (0.2, 0.14, 0.1), kind="folds", seed=25)
    fabric("oilcloth", (0.62, 0.58, 0.5), (0.48, 0.14, 0.11), kind="check", seed=26)
    fabric("coat", (0.2, 0.19, 0.18), (0.1, 0.1, 0.1), n=32, seed=27)
    fabric("coat_brown", (0.28, 0.2, 0.13), (0.1, 0.1, 0.1), n=32, seed=28)
    fabric("towel", (0.5, 0.46, 0.38), (0.3, 0.3, 0.3), n=32, kind="check", seed=29)
    enamel("enamel", (0.74, 0.72, 0.65))
    enamel("enamel_bath", (0.7, 0.69, 0.64), seed=14, chips=18, rust=0.7)
    flat("chrome", (0.5, 0.5, 0.48), var=0.3)
    flat("aluminium", (0.55, 0.54, 0.5), var=0.25)
    flat("leather", (0.12, 0.09, 0.07))
    flat("plastic_cream", (0.66, 0.62, 0.5))
    flat("pipe_paint", (0.5, 0.5, 0.44), amount=0.4)
    flat("gas_pipe", (0.6, 0.48, 0.12), amount=0.4)
    flat("rubber", (0.06, 0.06, 0.06))
    flat("lampshade", (0.62, 0.48, 0.3), amount=0.3)
    flat("soil", (0.12, 0.09, 0.07))
    flat("leaf", (0.15, 0.2, 0.1), var=0.4)
    flat("glass_dark", (0.12, 0.15, 0.16), var=0.1)
    flat("bulb_on", (1.0, 0.86, 0.6), var=0.0, amount=0.0)
    iron_paint()
    books()
    crt()
    mirror()
    door_paint()
    tulle()
    newspaper()
    photo()
    decals()


if __name__ == "__main__":
    main()
