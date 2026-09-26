"""Draws the app icon: a grug-style doodle (hand-drawn wobbly strokes, one colour on a
flat field, lowercase handwriting ending in a period), after the Apple Design Award
winner grug by Ocho studio: https://developer.apple.com/news/?id=ux44ymcr

    python3 ios/tools/icon/make_icon.py   # writes AppIcon.appiconset/AppIcon.png
"""
import math, random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

S = 4096                      # supersampled; downsized to 1024 at the end
BG = (3, 74, 58)              # grug's deep green
INK = (240, 234, 204)         # cream line
W = int(S * 0.0075)           # stroke width
random.seed(7)

img = Image.new("RGB", (S, S), BG)
d = ImageDraw.Draw(img)

def wobble(n_terms=3, amp=1.0):
    terms = [(random.uniform(1, 4), random.uniform(0, 2 * math.pi), random.uniform(0.3, 1)) for _ in range(n_terms)]
    return lambda t: amp * sum(a * math.sin(f * t + p) for f, p, a in terms) / n_terms

def stroke(pts, width=W):
    d.line(pts, fill=INK, width=width, joint="curve")
    r = width / 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - r, y - r, x + r, y + r), fill=INK)

def loop(cx, cy, rx, ry, jitter, start=0.0, sweep=2 * math.pi + 0.35, n=400):
    """A hand-drawn ellipse: radius wobbles, and the pen overshoots its start like a real loop."""
    w = wobble(amp=jitter)
    pts = []
    for i in range(n + 1):
        t = start + sweep * i / n
        k = 1 + w(t) + 0.012 * (i / n)          # drift so the overshoot doesn't land on the start
        pts.append((cx + rx * k * math.cos(t), cy + ry * k * math.sin(t)))
    stroke(pts)

def squiggle(p0, p1, amp, waves, n=120):
    (x0, y0), (x1, y1) = p0, p1
    w = wobble(amp=0.25)
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy); nx, ny = -dy / L, dx / L
    pts = []
    for i in range(n + 1):
        u = i / n
        o = amp * (math.sin(u * waves * math.pi) + w(u * 6))
        pts.append((x0 + dx * u + nx * o, y0 + dy * u + ny * o))
    stroke(pts)

# Head CT slice, as grug would draw it: skull, brain, midline, a couple of gyri.
cx, cy = S * 0.5, S * 0.40
loop(cx, cy, S * 0.235, S * 0.265, 0.035, start=-1.9)                 # skull
loop(cx, cy + S * 0.005, S * 0.19, S * 0.22, 0.04, start=0.7)         # brain
squiggle((cx, cy - S * 0.2), (cx + S * 0.01, cy + S * 0.2), S * 0.012, 5)   # midline
squiggle((cx - S * 0.15, cy - S * 0.07), (cx - S * 0.05, cy - S * 0.1), S * 0.02, 3)
squiggle((cx + S * 0.05, cy - S * 0.1), (cx + S * 0.15, cy - S * 0.06), S * 0.02, 3)
squiggle((cx - S * 0.14, cy + S * 0.08), (cx - S * 0.05, cy + S * 0.11), S * 0.018, 3)
squiggle((cx + S * 0.05, cy + S * 0.11), (cx + S * 0.14, cy + S * 0.07), S * 0.018, 3)

# Handwritten wordmark, lowercase with grug's full stop.
font = ImageFont.truetype("/System/Library/Fonts/Supplemental/ChalkboardSE.ttc", int(S * 0.112), index=0)
text = "generalizable."
x0, y0, x1, y1 = d.textbbox((0, 0), text, font=font)
tw = x1 - x0
d.text(((S - tw) / 2 - x0, S * 0.77 - y0), text, font=font, fill=INK)

out = Path(__file__).resolve().parents[2] / "Generalizable/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
img.resize((1024, 1024), Image.LANCZOS).save(out)
print(out)
