"""Paints the stairwell graffiti as spray-paint textures for wall decals.

Every inscription is written with a hand-drawn single-stroke Cyrillic alphabet (no computer
fonts) and then "sprayed": a simulated nozzle moves along each stroke, slowing at starts and
corners, laying down a soft core of paint plus individual overspray droplets. Heavy spots run
into drips. The paint soaks unevenly into the wall, using the game's own plaster and concrete
textures as the surface, and old pieces fade, flake, get scrubbed or grimed over.

Writes assets/graffiti/*.png and assets/graffiti/graffiti.json (placement for main.gd).

Run:  python tools/make_graffiti.py
"""
import json
import math
import os
import struct
import zlib

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "graffiti")
PPM = 320.0                       # texture pixels per metre of wall
rng = np.random.default_rng(1986)

# Colours: dirty, faded, nothing bright.
BLACK = (0.055, 0.052, 0.055)
GREY = (0.19, 0.19, 0.185)
WHITE = (0.64, 0.62, 0.56)
WINE = (0.29, 0.055, 0.05)


# ------------------------------------------------------------------ PNG in/out

def read_png(path):
    data = open(path, "rb").read()
    pos = 8
    idat = b""
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", chunk[:10])
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + n
    ch = {6: 4, 2: 3, 0: 1, 4: 2}[ctype]
    raw = zlib.decompress(idat)
    stride = w * ch
    img = np.zeros((h, stride), np.int32)
    prev = np.zeros(stride, np.int32)
    for y in range(h):
        f = raw[y * (stride + 1)]
        row = np.frombuffer(raw, np.uint8, stride, y * (stride + 1) + 1).astype(np.int32)
        out = np.zeros(stride, np.int32)
        if f == 0:
            out = row
        elif f == 2:
            out = (row + prev) & 255
        else:
            for i in range(stride):
                a = out[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                if f == 1:
                    p = a
                elif f == 3:
                    p = (a + b) // 2
                else:
                    pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                    p = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                out[i] = (row[i] + p) & 255
        img[y] = out
        prev = out
    return img.reshape(h, w, ch)[:, :, :3].astype(np.float32) / 255.0


def write_png(path, rgba):
    h, w, _ = rgba.shape
    data = (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)
    raw = b"".join(b"\x00" + data[y].tobytes() for y in range(h))

    def chunk(kind, body):
        c = struct.pack(">I", len(body)) + kind + body
        return c + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


# ------------------------------------------------------------------ the wall surface

def _lum(img):
    return img.mean(axis=2)


def _sample(tex, x_m, y_m, tile_m):
    """Bilinear lookup of a tiling texture at wall coordinates in metres."""
    h, w = tex.shape
    u = (x_m / tile_m) * w
    v = (-y_m / tile_m) * h
    x0 = np.floor(u).astype(int)
    y0 = np.floor(v).astype(int)
    fx = u - x0
    fy = v - y0
    x0 %= w
    y0 %= h
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    return ((tex[y0, x0] * (1 - fx) + tex[y0, x1] * fx) * (1 - fy)
            + (tex[y1, x0] * (1 - fx) + tex[y1, x1] * fx) * fy)


PLASTER = _lum(read_png(os.path.join(ROOT, "assets", "psx", "plaster.png")))
CONCRETE = _lum(read_png(os.path.join(ROOT, "assets", "psx", "concrete.png")))


def _norm(a):
    lo, hi = np.percentile(a, 2), np.percentile(a, 98)
    return np.clip((a - lo) / max(hi - lo, 1e-6), 0, 1)


def surface(xm, ym, seed):
    """Relief of the wall under the paint: coarse plaster plus fine concrete grain."""
    ox, oy = seed * 0.37, seed * 0.61
    coarse = _sample(PLASTER, xm + ox, ym + oy, 1.5)
    fine = _sample(CONCRETE, xm * 1.0 + oy, ym + ox, 0.45)
    return _norm(coarse * 0.55 + fine * 0.45), _norm(_sample(PLASTER, xm * 0.5 + 3.1 + ox, ym * 0.5 + oy, 1.5))


# ------------------------------------------------------------------ hand-drawn alphabet
# Units: cap height 1, baseline 0, y up. Each glyph is (width, [strokes]); a stroke is a list
# of points, drawn in that order with one press of the nozzle.

def arc(cx, cy, rx, ry, a0, a1, n=10):
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def _bowl(y_top, y_bot, x0=0.05, xr=0.3):
    """Stem-side bowl from (x0, y_top) round to (x0, y_bot), as in Б, Ь, Ы, Р, В."""
    cy = (y_top + y_bot) / 2
    ry = (y_top - y_bot) / 2
    return [(x0, y_top), (xr, y_top)] + arc(xr, cy, 0.24, ry, 90, -90, 8)[1:-1] + [(xr, y_bot), (x0, y_bot)]


GLYPHS = {
    "А": (0.66, [[(0, 0), (0.33, 1), (0.66, 0)], [(0.13, 0.36), (0.53, 0.38)]]),
    "Б": (0.6, [[(0.56, 1), (0.05, 1), (0.05, 0)], _bowl(0.56, 0)]),
    "В": (0.6, [[(0.05, 0), (0.05, 1)], _bowl(1, 0.53, xr=0.27), _bowl(0.53, 0, xr=0.31)]),
    "Г": (0.55, [[(0.06, 0), (0.05, 1), (0.56, 1)]]),
    "Д": (0.72, [[(0.0, -0.17), (0.0, 0), (0.72, 0), (0.72, -0.17)], [(0.08, 0), (0.24, 1), (0.58, 1), (0.6, 0)]]),
    "Е": (0.55, [[(0.56, 1), (0.05, 1), (0.05, 0), (0.57, 0)], [(0.05, 0.52), (0.45, 0.53)]]),
    "Ё": (0.55, [[(0.56, 1), (0.05, 1), (0.05, 0), (0.57, 0)], [(0.05, 0.52), (0.45, 0.53)],
                 [(0.17, 1.2), (0.19, 1.22)], [(0.4, 1.2), (0.42, 1.22)]]),
    "Ж": (0.84, [[(0.42, 0), (0.42, 1)], [(0.02, 1), (0.42, 0.5), (0.82, 1)], [(0, 0), (0.42, 0.5), (0.84, 0)]]),
    "З": (0.58, [arc(0.29, 0.76, 0.25, 0.24, 150, -90, 8) + arc(0.3, 0.27, 0.28, 0.27, 90, -150, 9)[1:]]),
    "И": (0.64, [[(0.05, 1), (0.05, 0), (0.6, 1), (0.6, 0)]]),
    "Й": (0.64, [[(0.05, 1), (0.05, 0), (0.6, 1), (0.6, 0)], arc(0.33, 1.25, 0.15, 0.1, 200, 340, 6)]),
    "К": (0.6, [[(0.05, 0), (0.05, 1)], [(0.56, 1), (0.07, 0.47), (0.6, 0)]]),
    "Л": (0.64, [[(0, 0.02), (0.12, 0.12), (0.26, 1), (0.6, 1), (0.61, 0)]]),
    "М": (0.78, [[(0.03, 0), (0.07, 1), (0.39, 0.33), (0.71, 1), (0.75, 0)]]),
    "Н": (0.64, [[(0.05, 0), (0.05, 1)], [(0.6, 1), (0.6, 0)], [(0.05, 0.5), (0.6, 0.52)]]),
    "О": (0.68, [arc(0.34, 0.5, 0.31, 0.5, 100, 460, 18)]),
    "П": (0.64, [[(0.05, 0), (0.05, 1), (0.6, 1), (0.61, 0)]]),
    "Р": (0.56, [[(0.05, 0), (0.05, 1)], _bowl(1, 0.47, xr=0.29)]),
    "С": (0.62, [arc(0.36, 0.5, 0.33, 0.5, 45, 320, 14)]),
    "Т": (0.64, [[(0, 1), (0.64, 1.01)], [(0.32, 1), (0.31, 0)]]),
    "У": (0.66, [[(0, 1), (0.34, 0.38)], [(0.66, 1), (0.2, 0)]]),
    "Х": (0.62, [[(0, 1), (0.62, 0)], [(0.62, 1), (0, 0)]]),
    "Ц": (0.7, [[(0.05, 1), (0.05, 0), (0.6, 0), (0.6, 1)], [(0.6, 0), (0.7, -0.17)]]),
    "Ч": (0.6, [[(0.05, 1), (0.06, 0.64), (0.16, 0.48), (0.55, 0.48)], [(0.56, 1), (0.55, 0)]]),
    "Ш": (0.9, [[(0.05, 1), (0.05, 0), (0.85, 0), (0.85, 1)], [(0.45, 1), (0.45, 0)]]),
    "Ы": (0.8, [[(0.05, 1), (0.05, 0)], _bowl(0.54, 0), [(0.75, 1), (0.75, 0)]]),
    "Ь": (0.56, [[(0.05, 1), (0.05, 0)], _bowl(0.54, 0)]),
    "Э": (0.62, [arc(0.27, 0.5, 0.33, 0.5, 135, -135, 14), [(0.24, 0.5), (0.58, 0.51)]]),
    "Я": (0.6, [[(0.56, 0), (0.56, 1), (0.32, 1)] + arc(0.32, 0.74, 0.25, 0.26, 90, 270, 8)[1:] + [(0.56, 0.48)],
                [(0.38, 0.48), (0.02, 0)]]),
    "0": (0.6, [arc(0.3, 0.5, 0.28, 0.5, 100, 460, 18)]),
    "2": (0.62, [arc(0.3, 0.72, 0.27, 0.28, 155, -35, 9) + [(0.03, 0), (0.62, 0.01)]]),
    "!": (0.22, [[(0.11, 1), (0.1, 0.3)], [(0.1, 0.03), (0.11, 0.0)]]),
    ",": (0.18, [[(0.1, 0.06), (0.03, -0.14)]]),
    "—": (0.78, [[(0.06, 0.5), (0.72, 0.52)]]),
    "+": (0.6, [[(0.3, 0.12), (0.31, 0.76)], [(0.02, 0.44), (0.58, 0.45)]]),
    " ": (0.42, []),
}


def layout(text, rnd, hand):
    """Places the glyphs of a (possibly multi-line) string. Returns strokes in cap units,
    centred on (0, 0), plus the bounding box."""
    lines = text.split("\n")
    strokes_all = []
    line_boxes = []
    for li, line in enumerate(lines):
        x = 0.0
        base = -li * 1.45
        drift = 0.0
        line_strokes = []
        for ch in line:
            small = ch != ch.upper()
            glyph = GLYPHS.get(ch.upper(), GLYPHS[" "])
            gw, strokes = glyph
            s = (0.74 if small else 1.0) * rnd.uniform(0.92, 1.08)
            rot = math.radians(rnd.uniform(-4, 4) * hand["jitter"])
            drift += rnd.uniform(-0.035, 0.035) * hand["jitter"]
            drift *= 0.8
            for st in strokes:
                pts = []
                for (px, py) in st:
                    px *= s
                    py *= s
                    px, py = (px * math.cos(rot) - py * math.sin(rot), px * math.sin(rot) + py * math.cos(rot))
                    px += py * hand["slant"]
                    pts.append((x + px, base + drift + py))
                line_strokes.append(pts)
            x += gw * s + hand["spacing"] + rnd.uniform(-0.04, 0.05)
        width = x - hand["spacing"]
        line_boxes.append(width)
        strokes_all.append((line_strokes, width))
    # Centre each line, then the whole block.
    out = []
    widest = max(line_boxes)
    for line_strokes, width in strokes_all:
        dx = -width / 2 + rnd.uniform(-0.08, 0.08) * (widest - width)
        out += [[(px + dx, py) for (px, py) in st] for st in line_strokes]
    ys = [p[1] for st in out for p in st]
    cy = (max(ys) + min(ys)) / 2
    return [[(px, py - cy) for (px, py) in st] for st in out]


# ------------------------------------------------------------------ the spray can

_kernels = {}


def kernel(sigma):
    key = round(sigma * 4) / 4
    if key not in _kernels:
        r = int(math.ceil(key * 3))
        y, x = np.mgrid[-r:r + 1, -r:r + 1]
        _kernels[key] = (np.exp(-(x * x + y * y) / (2 * key * key)).astype(np.float32), r)
    return _kernels[key]


def stamp(canvas, x, y, sigma, amount):
    k, r = kernel(sigma)
    xi, yi = int(round(x)), int(round(y))
    h, w = canvas.shape
    x0, x1 = max(xi - r, 0), min(xi + r + 1, w)
    y0, y1 = max(yi - r, 0), min(yi + r + 1, h)
    if x0 >= x1 or y0 >= y1:
        return
    canvas[y0:y1, x0:x1] += k[y0 - yi + r:y1 - yi + r, x0 - xi + r:x1 - xi + r] * amount


def resample(pts, step):
    out = [np.array(pts[0], np.float64)]
    for a, b in zip(pts[:-1], pts[1:]):
        a = np.array(a, np.float64)
        b = np.array(b, np.float64)
        n = max(1, int(np.linalg.norm(b - a) / step))
        for i in range(1, n + 1):
            out.append(a + (b - a) * i / n)
    return np.array(out)


def spray(paths_px, shape, hand, rnd):
    """Moves the nozzle along each path. Returns paint density, droplets and drip candidates."""
    D = np.zeros(shape, np.float32)
    S = np.zeros(shape, np.float32)
    drips = []
    sigma = hand["width_px"] / 2.4 * hand["distance"]
    amp_unit = 0.5 / (math.sqrt(2 * math.pi) * sigma)
    px_all, py_all, pv_all = [], [], []
    for path in paths_px:
        if len(path) < 2:
            continue
        path = [np.array(q, np.float64) for q in path]
        # Overshoot or stop short, as a quick hand does.
        d0 = path[1] - path[0]
        d1 = path[-1] - path[-2]
        path = [path[0] - d0 / (np.linalg.norm(d0) + 1e-6) * rnd.uniform(-0.3, 1.0) * hand["overshoot"]] + list(path) \
            + [path[-1] + d1 / (np.linalg.norm(d1) + 1e-6) * rnd.uniform(-0.3, 1.0) * hand["overshoot"]]
        p = resample(path, 0.5)
        n = len(p)
        seg = np.diff(p, axis=0)
        length = np.concatenate([[0], np.cumsum(np.linalg.norm(seg, axis=1))])
        total = length[-1]
        # Tremor across the stroke.
        dirs = np.vstack([seg, seg[-1:]])
        dirs /= np.linalg.norm(dirs, axis=1, keepdims=True) + 1e-9
        normal = np.stack([-dirs[:, 1], dirs[:, 0]], axis=1)
        wob = np.zeros(n)
        for lam in (40.0, 17.0, 7.0):
            wob += np.sin(length / lam * 2 * math.pi + rnd.uniform(0, 6.3)) * hand["tremor"] * lam / 40.0
        p = p + normal * wob[:, None]
        # Speed: accelerate off the press, slow into corners and at the end.
        ramp = hand["width_px"] * 1.6
        v = np.minimum(1.0, 0.25 + length / ramp) * np.minimum(1.0, 0.35 + (total - length) / ramp)
        turn = np.zeros(n)
        if n > 10:
            ang = np.arctan2(dirs[:, 1], dirs[:, 0])
            dang = np.abs((np.diff(ang) + np.pi) % (2 * np.pi) - np.pi)
            turn[1:] = dang
            turn = np.convolve(turn, np.ones(9) / 9, mode="same")
        v = v / (1.0 + turn * 18.0)
        v *= rnd.uniform(0.85, 1.15)
        dwell = hand["density"] / np.maximum(v, 0.12)
        # The press before the hand moves leaves a heavier dot.
        stamp(D, p[0][0], p[0][1], sigma * 1.1, amp_unit * hand["density"] * 9.0)
        for i in range(n):
            stamp(D, p[i][0], p[i][1], sigma, amp_unit * dwell[i])
        # Individual droplets of overspray: most close to the line, a few far out.
        lam = hand["mist"] * 0.5 * dwell
        counts = rnd.poisson(lam)
        idx = np.repeat(np.arange(n), counts)
        far = rnd.random(idx.size) < 0.25
        spread = np.where(far, sigma * 4.2, sigma * 2.1)
        px_all.append(p[idx, 0] + rnd.normal(0, 1, idx.size) * spread)
        py_all.append(p[idx, 1] + rnd.normal(0, 1, idx.size) * spread)
        pv_all.append(rnd.uniform(0.12, 0.55, idx.size) * np.where(far, 0.6, 1.0))
        # Where paint pooled it may run.
        for i in [0, n - 1] + list(np.nonzero(dwell > hand["density"] * 2.2)[0][::25]):
            drips.append((p[i][0], p[i][1], float(dwell[i]) / hand["density"]))
    if px_all:
        x = np.concatenate(px_all).round().astype(int)
        y = np.concatenate(py_all).round().astype(int)
        val = np.concatenate(pv_all)
        ok = (x >= 0) & (x < shape[1]) & (y >= 0) & (y < shape[0])
        np.add.at(S, (y[ok], x[ok]), val[ok])
        # A share of droplets are a little bigger.
        big = ok & (rnd.random(ok.size) < 0.12)
        for dx, dy in ((1, 0), (0, 1)):
            xx, yy = np.clip(x[big] + dx, 0, shape[1] - 1), np.clip(y[big] + dy, 0, shape[0] - 1)
            np.add.at(S, (yy, xx), val[big] * 0.6)
    return D, S, drips, sigma


def run_drips(D, drips, sigma, hand, rnd):
    """Paint that pooled runs straight down, thinning, and ends in a small bead."""
    for x, y, heavy in drips:
        if heavy < 1.6 or rnd.random() > hand["drip"] * min(1.0, heavy / 3.5):
            continue
        length = rnd.uniform(0.2, 1.0) ** 2 * hand["drip_len_px"] * min(1.4, heavy / 2.5)
        x += rnd.uniform(-0.4, 0.4) * sigma
        y += sigma * 0.6
        w0 = sigma * rnd.uniform(0.45, 0.7)
        steps = int(length / 0.5)
        for i in range(steps):
            t = i / max(steps, 1)
            w = w0 * (1.0 - 0.45 * t)
            stamp(D, x + math.sin(i * 0.05 + x) * 0.3, y + i * 0.5, max(w, 0.6), 0.5 / (math.sqrt(2 * math.pi) * w) * 2.2)
        stamp(D, x, y + length, w0 * 0.9, 1.4)


# ------------------------------------------------------------------ a whole piece

def paint(name, strokes_m, color, hand, age, seed):
    rnd = np.random.default_rng(seed)
    pts = np.array([p for st in strokes_m for p in st])
    pad = 0.07
    pad_bottom = pad + hand["drip_len_px"] / PPM * 1.7
    x0, x1 = pts[:, 0].min() - pad, pts[:, 0].max() + pad
    y0, y1 = pts[:, 1].min() - pad_bottom, pts[:, 1].max() + pad
    w = int(math.ceil((x1 - x0) * PPM))
    h = int(math.ceil((y1 - y0) * PPM))
    to_px = lambda st: [((px - x0) * PPM, (y1 - py) * PPM) for (px, py) in st]
    paths = [to_px(st) for st in strokes_m]

    D, S, drips, sigma = spray(paths, (h, w), hand, rnd)
    run_drips(D, drips, sigma, hand, rnd)

    # Wall coordinates of every texel, for the surface it sits on.
    gx, gy = np.meshgrid(np.arange(w) / PPM + x0, y1 - np.arange(h) / PPM)
    relief, patches = surface(gx, gy, seed % 97)

    # Raised grain catches paint first, pits stay bare at the edges; deep pores stay open.
    catch = 0.5 + 1.0 * relief
    A = 1.0 - np.exp(-2.8 * D * catch)
    A = np.maximum(A, np.clip(S * (0.4 + 0.9 * relief), 0, 1) * 0.92)
    A *= np.where(relief < 0.1, 0.55, 1.0)

    thick = np.clip(D * 2.8 - 1.0, 0, 1)
    col = np.ones((h, w, 3), np.float32) * np.array(color, np.float32)
    col *= (1.0 - 0.18 * thick)[..., None]                   # puddled paint is deeper
    col *= (0.88 + 0.16 * relief)[..., None]                  # soaked into pores, a little darker

    # Age: fade towards the wall, flake where the plaster is weakest, dirt over the top.
    fade = age.get("fade", 0.0)
    if fade > 0:
        wallish = np.array((0.42, 0.41, 0.38), np.float32)
        col = col * (1 - fade * 0.6) + wallish * fade * 0.6
        A *= 1.0 - fade * 0.55
    flake = age.get("flake", 0.0)
    if flake > 0:
        # Only the weakest patches of plaster have shed their paint, and never all of it.
        A *= 0.3 + 0.7 * np.clip((patches - flake * 0.5) / 0.18, 0, 1)
    grime = age.get("grime", 0.0)
    if grime > 0:
        dirt = np.clip((0.55 - patches) / 0.35, 0, 1) * grime
        dirt += np.clip((y0 + 0.4 - gy) / 0.8, 0, 1) * grime * 0.4      # more near the floor
        col *= (1.0 - 0.45 * np.clip(dirt, 0, 1))[..., None]
        A *= 1.0 - 0.45 * np.clip(dirt, 0, 1)
    scrub = age.get("scrub")
    if scrub:
        # Someone went at it with a wet rag: a band of side-to-side smearing.
        cx, cy, rw, rh = scrub
        cx = (cx - x0) * PPM
        cy = (y1 - cy) * PPM
        yy, xx = np.mgrid[0:h, 0:w]
        m = np.clip(1.2 - (((xx - cx) / (rw * PPM)) ** 2 + ((yy - cy) / (rh * PPM)) ** 2), 0, 1)
        m *= 0.75 + 0.25 * relief
        k = int(0.06 * PPM)
        cs = np.cumsum(np.pad(A, ((0, 0), (k, k)), mode="edge"), axis=1)
        smear = (cs[:, 2 * k:] - cs[:, :-2 * k]) / (2 * k)
        A = A * (1 - m * 0.8) + smear[:, :w] * m * 0.35
        col = col * (1 - m[..., None] * 0.3) + np.array((0.4, 0.39, 0.36)) * m[..., None] * 0.3

    rgba = np.concatenate([col, np.clip(A, 0, 1)[..., None]], axis=2)
    write_png(os.path.join(OUT, name + ".png"), rgba)
    # Decal centre relative to the anchor (the old label position), in metres.
    return {"w": (x1 - x0), "h": (y1 - y0), "cx": (x0 + x1) / 2, "cy": (y0 + y1) / 2}


HANDS = {
    # careful: written slowly, heavy, runs
    "heavy": dict(wfrac=0.13, distance=1.0, density=1.15, mist=1.1, tremor=0.5, jitter=0.6, slant=0.04,
                  spacing=0.24, overshoot=2.0, drip=0.4, drip_len=0.45),
    # normal tag
    "tag": dict(wfrac=0.12, distance=1.1, density=1.0, mist=1.4, tremor=0.8, jitter=1.0, slant=0.1,
                spacing=0.21, overshoot=3.0, drip=0.15, drip_len=0.3),
    # in a hurry: can held further away, thin, uneven, misty
    "hurried": dict(wfrac=0.1, distance=1.3, density=0.8, mist=2.2, tremor=1.2, jitter=1.15, slant=0.16,
                    spacing=0.22, overshoot=4.0, drip=0.12, drip_len=0.28),
    # a thin line, close to the wall
    "thin": dict(wfrac=0.07, distance=0.9, density=0.9, mist=1.0, tremor=0.9, jitter=1.0, slant=0.06,
                 spacing=0.2, overshoot=2.0, drip=0.05, drip_len=0.2),
}


def make_hand(kind, cap_m):
    h = dict(HANDS[kind])
    h["width_px"] = max(2.4, h.pop("wfrac") * cap_m * PPM)
    h["drip_len_px"] = h.pop("drip_len") * cap_m * PPM * 1.6
    h["tremor"] *= cap_m * PPM * 0.012
    h["overshoot"] *= cap_m * PPM * 0.012
    return h


def rotate(strokes, tilt):
    c, s = math.cos(tilt), math.sin(tilt)
    return [[(x * c - y * s, x * s + y * c) for (x, y) in st] for st in strokes]


# ------------------------------------------------------------------ the pieces

def circle(c, r, a0=0.0, a1=360.0, n=16):
    return arc(c[0], c[1], r, r, a0, a1, n)


def heart():
    pts = []
    for i in range(25):
        a = 2 * math.pi * i / 24
        pts.append((16 * math.sin(a) ** 3 / 17, (13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a)
                                                 - math.cos(4 * a)) / 17))
    return [pts]


def house():
    return [[(-1, -1), (1, -1), (1, 0.4), (-1, 0.4), (-1, -1)], [(-1.2, 0.4), (0, 1.5), (1.2, 0.4)],
            [(-0.3, -1), (-0.3, -0.2), (0.3, -0.2), (0.3, -1)]]


def sun():
    out = [circle((0, 0), 0.5)]
    for i in range(8):
        a = 2 * math.pi * i / 8
        out.append([(math.cos(a) * 0.7, math.sin(a) * 0.7), (math.cos(a) * 1.1, math.sin(a) * 1.1)])
    return out


def tally():
    out = []
    for g in range(3):
        for i in range(4):
            tx = g * 1.5 + i * 0.25
            out.append([(tx, 0), (tx + 0.03, 1)])
        out.append([(g * 1.5 - 0.15, 0.2), (g * 1.5 + 0.9, 0.8)])
    return out


def eye():
    return [arc(0, -0.75, 1.25, 1.25, 48, 132, 10), arc(0, 0.75, 1.25, 1.25, 228, 312, 10),
            circle((0, 0), 0.38), circle((0, 0), 0.12, 0, 360, 8)]


def figure():
    return [circle((0, 1.3), 0.35), [(0, 0.95), (0, -0.3)], [(-0.6, 0.2), (0, 0.7), (0.6, 0.2)],
            [(-0.45, -1.3), (0, -0.3), (0.45, -1.3)]]


def arrow():
    return [[(0, -1), (0.03, 1)], [(-0.35, 0.5), (0.03, 1), (0.4, 0.55)]]


# zone: ["l", k] apartment landing of floor k; ["a", k] flight up from floor k + half-landing;
# ["b", k] flight from that half-landing up. wall: B back, F beside stair opening, R/L shaft
# walls, K block in the entry hall, W window wall. size: the old label's font size.
PIECES = [
    # Entry hall and first floor: years of ordinary scribbling.
    ("vasya", ["a", -1], "K", 0.6, -0.55, "Здесь был Вася", WHITE, 44, -0.05, "tag",
     {"fade": 0.3, "grime": 0.45, "scrub": (0.2, -0.57, 0.22, 0.06)}),
    ("kino", ["b", -1], "L", 1.3, 1.0, "КИНО", BLACK, 84, 0.04, "heavy", {"fade": 0.25, "grime": 0.4}),
    ("tsoi", ["a", -1], "R", 3.0, 0.55, "ЦОЙ ЖИВ", BLACK, 80, 0.0, "heavy", {"fade": 0.12, "flake": 0.15, "grime": 0.2}),
    ("grob", ["l", 0], "F", 1.97, 2.05, "ГрОб", BLACK, 84, -0.05, "hurried", {"fade": 0.3, "grime": 0.3}),
    ("sasha", ["l", 0], "F", -1.97, 2.15, "Саша\n+ Маша", GREY, 44, 0.07, "thin", {"fade": 0.35, "flake": 0.2}),
    ("heart", ["l", 0], "F", -1.97, 1.72, heart(), WINE, 0.12, 0.1, "thin", {"fade": 0.55, "flake": 0.35}),
    ("lyokha", ["l", 0], "B", 0.0, 2.3, "Лёха лох", GREY, 40, 0.08, "hurried", {"fade": 0.2}),
    ("punks", ["a", 0], "R", 1.3, 2.75, "ПАНКИ ХОЙ!", BLACK, 72, 0.06, "tag", {"fade": 0.3, "flake": 0.3, "grime": 0.25}),
    ("house", ["a", 0], "W", -0.95, 3.3, house(), WHITE, 0.15, 0.0, "thin", {"fade": 0.7, "grime": 0.5}),
    ("sun", ["a", 0], "W", -1.0, 3.85, sun(), WHITE, 0.1, 0.0, "thin", {"fade": 0.75, "grime": 0.5}),
    # Second and third floors.
    ("spartak", ["b", 0], "L", 1.3, 4.25, "Спартак — чемпион", WINE, 50, -0.03, "tag", {"fade": 0.35, "flake": 0.3}),
    ("mama", ["l", 1], "F", 1.97, 5.0, "мама,\nя дома", GREY, 44, -0.05, "thin", {"fade": 0.55, "grime": 0.45}),
    ("vika", ["a", 1], "R", 1.3, 5.75, "Вика дура", GREY, 52, 0.05, "hurried", {"fade": 0.3, "grime": 0.2}),
    ("tally", ["a", 1], "W", -0.7, 6.2, tally(), BLACK, 0.11, 0.0, "thin", {"fade": 0.4}),
    ("dont_go_up", ["l", 2], "F", -1.97, 8.0, "НЕ ХОДИ\nНАВЕРХ", WINE, 56, 0.04, "hurried", {"fade": 0.05}),
    ("fifth_floor", ["a", 2], "R", 1.3, 8.7, "оно на пятом этаже", WINE, 44, 0.05, "hurried", {"fade": 0.15, "grime": 0.3}),
    ("come_back", ["b", 2], "L", 1.3, 10.3, "вернись", WINE, 60, -0.06, "tag",
     {"fade": 0.1, "scrub": (1.35, 10.3, 0.4, 0.12)}),
    # Fourth floor (dark) and up: recent, hurried, wrong.
    ("dont_open", ["l", 3], "B", 0.0, 11.3, "НЕ ОТКРЫВАЙ", WINE, 72, -0.03, "heavy", {}),
    ("eye", ["l", 3], "F", 1.97, 11.0, eye(), BLACK, 0.24, 0.0, "tag", {"fade": 0.1}),
    ("i_see_you", ["l", 3], "F", 1.97, 10.5, "я вижу тебя", BLACK, 40, -0.04, "thin", {"fade": 0.45, "grime": 0.4}),
    ("stick_man", ["a", 3], "W", -0.95, 12.2, figure(), BLACK, 0.17, 0.0, "thin", {"fade": 0.2}),
    ("dont_look_up", ["b", 3], "L", 1.3, 13.1, "НЕ СМОТРИ\nНАВЕРХ", WINE, 60, 0.04, "hurried", {}),
    ("arrow", ["b", 3], "L", 0.45, 13.1, arrow(), WINE, 0.22, 0.0, "hurried", {}),
    ("no_exit", ["l", 4], "B", 0.0, 14.3, "ВЫХОДА НЕТ", WINE, 92, 0.0, "heavy", {}),
    ("been_here", ["l", 4], "F", -1.97, 13.9, "ты уже\nбыл здесь", WHITE, 46, -0.05, "thin",
     {"fade": 0.75, "grime": 0.55}),
    ("twenty", ["l", 4], "F", 1.97, 13.7, "20", WINE, 120, 0.1, "heavy", {"fade": 0.05}),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = []
    for i, (name, zone, wall, along, y, content, color, size, tilt, hand_kind, age) in enumerate(PIECES):
        rnd = np.random.default_rng(1000 + i)
        if isinstance(content, str):
            cap = size * 0.0026
            hand = make_hand(hand_kind, cap)
            hand_units = dict(HANDS[hand_kind])
            strokes = layout(content, rnd, hand_units)
            strokes = [[(x * cap, yy * cap) for (x, yy) in st] for st in strokes]
        else:
            # A drawing: `size` is metres per drawing unit, as before.
            hand = make_hand(hand_kind, size * 1.6)
            hand["width_px"] = max(2.4, HANDS[hand_kind]["wfrac"] * 0.12 * PPM * (1.4 if hand_kind == "tag" else 1.0))
            strokes = [[(x * size, yy * size) for (x, yy) in st] for st in content]
        strokes = rotate(strokes, tilt)
        info = paint(name, strokes, color, hand, age, 1000 + i)
        manifest.append(dict(name=name, zone=zone, wall=wall, along=along, y=y,
                             w=round(info["w"], 4), h=round(info["h"], 4),
                             cx=round(info["cx"], 4), cy=round(info["cy"], 4)))
        print(name, round(info["w"], 2), "x", round(info["h"], 2), "m")
    json.dump(manifest, open(os.path.join(OUT, "graffiti.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
