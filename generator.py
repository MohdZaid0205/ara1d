#!/usr/bin/env python3
"""
plot_results.py - turn a per-kernel results.csv into the SVG figures used by
the per-kernel README.

Usage:
    python3 plot_results.py -i apps/ipred_smooth/res/results.csv
    python3 plot_results.py -i apps/ipred_smooth/res -o some/dir -k ipred_smooth
    python3 plot_results.py -i path/to/results.csv -p 0
    python3 plot_results.py -i path/to/results.csv -W 900 -H 500
    python3 plot_results.py -i path/to/results.csv --theme dark

CSV header (as produced by hand from the harness output):
    w,h,pattern,c_cycles,rvv_cycles,status
The `pattern` column is optional (missing = a single pattern 0).

Output (written to <csv dir> if that dir is named "res", else <csv dir>/res,
unless -o is given), where <k> is the kernel name:
    <k>_results.svg   speedup (C/RVV) per square block size
    <k>_cpc.svg       cycles per call, square blocks (log y)
    <k>_cpp.svg       cycles per pixel, square blocks
    <k>_heatmap.svg   speedup over W x H (all sizes)
    <k>_cpr.svg       cost per row from cycles = fixed + per_row * H fits

Size:
    -W / --width and -H / --height set the pixel size of EVERY figure (default
    760 x 440 for the charts; the heatmap sizes itself from the number of
    rows/columns unless you give a size). The layout stretches to fit. Very
    small sizes (below about 480 x 320) will make labels crowd.

Look:
    The background is transparent (nothing is painted behind the chart).
    Text, grid, axes and the C/RVV colours follow the viewer's light/dark
    setting through an embedded prefers-color-scheme style block (works when the
    SVG is shown through <img> / markdown image links, e.g. on GitHub).
    --theme light|dark forces one palette instead. The font is the viewer's
    system UI font (font-family: system-ui ...); override with --font.
    The heatmap cells keep fixed red/white/blue colours with fixed label ink so
    the numbers stay readable on any background.

Only the Python standard library is used (no matplotlib).
Rows whose status is not PASS are left out of the figures (a warning is printed).
Figures use the rows of ONE pattern (default: the highest pattern number, which
matches the "pattern-1 rows" convention used for the cost-per-row fit in the
ipred_smooth README). Change it with -p.
"""
import argparse
import csv
import math
import sys
from pathlib import Path
from xml.sax.saxutils import escape

# --------------------------------------------------------------------------
# theme: colours are CSS variables, defined once in an embedded <style>
# --------------------------------------------------------------------------
C_COL = "var(--c)"        # scalar C (bars/lines)
C_INK = "var(--c-ink)"    # scalar C (text)
R_COL = "var(--r)"        # RVV
R_INK = "var(--r-ink)"    # RVV (text)
BAD = "var(--bad)"        # speedup < 1 (C faster)
GRID = "var(--grid)"
AXIS = "var(--axis)"
INK = "var(--ink)"
MUTED = "var(--muted)"

LIGHT = {"ink": "#0f172a", "muted": "#64748b", "grid": "#e2e8f0", "axis": "#94a3b8",
         "c": "#94a3b8", "c-ink": "#64748b", "r": "#2563eb", "r-ink": "#1d4ed8",
         "bad": "#ef4444"}
DARK = {"ink": "#e6edf3", "muted": "#9198a1", "grid": "#3d444d", "axis": "#6e7681",
        "c": "#8b949e", "c-ink": "#adb5bd", "r": "#58a6ff", "r-ink": "#79c0ff",
        "bad": "#f85149"}

DEFAULT_FONT = "system-ui,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"

# heatmap cells are drawn in fixed colours, so their label ink is fixed too
CELL_DARK = "#0f172a"
CELL_LIGHT = "#ffffff"


def style_block(theme, font):
    def decl(p):
        return "".join(f"--{k}:{v};" for k, v in p.items())
    if theme == "light":
        css = f":root{{{decl(LIGHT)}}}"
    elif theme == "dark":
        css = f":root{{{decl(DARK)}}}"
    else:  # auto: follow the viewer
        css = (f":root{{{decl(LIGHT)}}}"
               f"@media (prefers-color-scheme: dark){{:root{{{decl(DARK)}}}}}")
    return f"<style>{css}text{{font-family:{font}}}</style>"


# --------------------------------------------------------------------------
# tiny SVG writer (transparent: no background or border is painted)
# --------------------------------------------------------------------------
class Svg:
    def __init__(self, w, h, theme="auto", font=DEFAULT_FONT):
        self.w, self.h, self.p = w, h, []
        self.theme, self.font = theme, font

    def add(self, s):
        self.p.append(s)

    def rect(self, x, y, w, h, fill, stroke=None, rx=0, sw=1):
        st = f";stroke:{stroke};stroke-width:{sw}" if stroke else ""
        self.add(f'<rect x="{x:.1f}" y="{y:.1f}" width="{max(w,0):.1f}" '
                 f'height="{max(h,0):.1f}" rx="{rx}" style="fill:{fill}{st}"/>')

    def line(self, x1, y1, x2, y2, col=AXIS, width=1, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.add(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
                 f'style="stroke:{col};stroke-width:{width}"{d}/>')

    def text(self, x, y, t, size=12, anchor="start", fill=INK,
             weight="normal", rot=None):
        tr = f' transform="rotate({rot} {x:.1f} {y:.1f})"' if rot else ""
        self.add(f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" '
                 f'text-anchor="{anchor}" font-weight="{weight}" '
                 f'style="fill:{fill}"{tr}>{escape(str(t))}</text>')

    def circle(self, x, y, r, fill):
        self.add(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" style="fill:{fill}"/>')

    def polyline(self, pts, col, width=2.5):
        s = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        self.add(f'<polyline points="{s}" style="fill:none;stroke:{col};'
                 f'stroke-width:{width}" stroke-linejoin="round" stroke-linecap="round"/>')

    def save(self, path):
        head = (f'<?xml version="1.0" encoding="UTF-8"?>\n'
                f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" '
                f'height="{self.h}" viewBox="0 0 {self.w} {self.h}">\n'
                f'{style_block(self.theme, self.font)}\n')
        Path(path).write_text(head + "\n".join(self.p) + "\n</svg>\n",
                              encoding="utf-8")


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def nice_ticks(hi, n=5):
    """0 .. >=hi with 'nice' step. Returns (ticks, top)."""
    hi = max(hi, 1e-9)
    raw = hi / n
    e = math.floor(math.log10(raw))
    f = raw / 10 ** e
    nf = 1 if f <= 1 else 2 if f <= 2 else 5 if f <= 5 else 10
    step = nf * 10 ** e
    top = math.ceil(hi / step) * step
    k = int(round(top / step))
    return [i * step for i in range(k + 1)], top


def tick_label(v):
    return f"{v:,.0f}" if v >= 1 or v == 0 else f"{v:g}"


def fmt_int(v):
    return f"{v:,.0f}"


def fmt_2(v):
    return f"{v:.2f}"


def fmt_x(v):
    return f"{v:.2f}\u00d7"


def legend(svg, items, right, y):
    """Right-aligned swatch legend on the title row."""
    widths = [22 + 7 * len(n) + 18 for n, _ in items]
    x = right - sum(widths)
    for (name, col), w in zip(items, widths):
        svg.rect(x, y - 10, 12, 12, col, rx=3)
        svg.text(x + 18, y, name, 12, fill=MUTED)
        x += w


def chart_frame(svg, W, H, title, ylabel, xlabel, subtitle=None, rm=28):
    pl, pr, pt, pb = 84, W - rm, 86, H - 62
    svg.text(28, 34, title, 17, weight="bold")
    if subtitle:
        svg.text(28, 54, subtitle, 12, fill=MUTED)
    svg.text(24, (pt + pb) / 2, ylabel, 12, "middle", fill=MUTED, rot=-90)
    svg.text((pl + pr) / 2, H - 16, xlabel, 12, "middle", fill=MUTED)
    return pl, pr, pt, pb


def y_grid(svg, pl, pr, pt, pb, lo, hi, ticks, log):
    if log:
        def ymap(v):
            return pb - (math.log10(v) - math.log10(lo)) / (math.log10(hi) - math.log10(lo)) * (pb - pt)
    else:
        def ymap(v):
            return pb - (v - lo) / (hi - lo) * (pb - pt)
    for t in ticks:
        y = ymap(t)
        svg.line(pl, y, pr, y, GRID, 1)
        svg.text(pl - 10, y + 4, tick_label(t), 11, "end", fill=MUTED)
    return ymap


def x_axis(svg, pl, pr, pb):
    svg.line(pl, pb, pr, pb, AXIS, 1.5)


# --------------------------------------------------------------------------
# chart types
# --------------------------------------------------------------------------
def bar_chart(path, title, cats, series, ylabel, W, H, theme, font, log=False,
              ref=None, ref_label=None, color_fn=None, label_fmt=fmt_int,
              subtitle=None, xlabel="Block size (W\u00d7H)", legend_items=None,
              max_bw=48, rm=28):
    """series = [(name, colour, [values or None per category])]"""
    svg = Svg(W, H, theme, font)
    pl, pr, pt, pb = chart_frame(svg, W, H, title, ylabel, xlabel, subtitle, rm)
    vals = [v for _, _, vs in series for v in vs if v is not None]
    if log:
        lo = 10 ** math.floor(math.log10(min(vals)))
        hi = 10 ** math.ceil(math.log10(max(vals)))
        if hi <= lo:
            hi = lo * 10
        ticks = [10 ** k for k in range(int(math.log10(lo)), int(math.log10(hi)) + 1)]
    else:
        lo = 0
        ticks, hi = nice_ticks(max(vals) * 1.1)
    ymap = y_grid(svg, pl, pr, pt, pb, lo, hi, ticks, log)

    if ref is not None:  # behind the bars
        y = ymap(ref)
        svg.line(pl, y, pr, y, INK, 1.2, "5,4")
        if ref_label:
            svg.text(pr + 8, y + 4, ref_label, 11, fill=INK)

    gw = (pr - pl) / len(cats)
    ns = len(series)
    bw = min(max_bw, gw * 0.8 / ns)
    for ci, cat in enumerate(cats):
        cx = pl + gw * (ci + 0.5)
        svg.text(cx, pb + 22, cat, 12, "middle")
        x0 = cx - bw * ns / 2
        for si, (_, col, vs) in enumerate(series):
            v = vs[ci]
            if v is None:
                continue
            c = color_fn(si, v) if color_fn else col
            y = ymap(v)
            svg.rect(x0 + si * bw + 1.5, y, bw - 3, pb - y, c, rx=4)
            tc = C_INK if c == C_COL else (R_INK if c == R_COL else (BAD if c == BAD else INK))
            ly = y - 7
            if ref is not None and abs((ly - 4) - ymap(ref)) < 12:
                ly = ymap(ref) - 10   # keep the label clear of the break-even line
            svg.text(x0 + si * bw + bw / 2, ly, label_fmt(v), 11, "middle",
                     fill=tc, weight="600")
    x_axis(svg, pl, pr, pb)
    items = legend_items or [(n, c) for n, c, _ in series]
    if len(series) > 1 or legend_items:
        legend(svg, items, W - 28, 34)
    svg.save(path)


def line_chart(path, title, cats, series, ylabel, W, H, theme, font,
               label_fmt=fmt_2, subtitle=None, xlabel="Block size (W\u00d7H)"):
    svg = Svg(W, H, theme, font)
    pl, pr, pt, pb = chart_frame(svg, W, H, title, ylabel, xlabel, subtitle)
    vals = [v for _, _, vs in series for v in vs if v is not None]
    ticks, hi = nice_ticks(max(vals) * 1.15)
    ymap = y_grid(svg, pl, pr, pt, pb, 0, hi, ticks, False)
    x_axis(svg, pl, pr, pb)
    gw = (pr - pl) / len(cats)
    for ci, cat in enumerate(cats):
        svg.text(pl + gw * (ci + 0.5), pb + 22, cat, 12, "middle")
    for name, col, vs in series:
        pts = [(pl + gw * (i + 0.5), ymap(v)) for i, v in enumerate(vs) if v is not None]
        svg.polyline(pts, col)
    for name, col, vs in series:
        for i, v in enumerate(vs):
            if v is not None:
                svg.circle(pl + gw * (i + 0.5), ymap(v), 5, col)
    for ci in range(len(cats)):
        cv = [(vs[ci], si) for si, (_, _, vs) in enumerate(series) if vs[ci] is not None]
        if not cv:
            continue
        top = max(v for v, _ in cv)
        for v, si in cv:
            x = pl + gw * (ci + 0.5)
            dy = -13 if v == top else 22
            if ymap(v) + dy > pb - 6:   # keep labels off the x-axis
                dy = -13
            col = R_INK if series[si][1] == R_COL else C_INK
            svg.text(x, ymap(v) + dy, label_fmt(v), 11, "middle", fill=col,
                     weight="600")
    legend(svg, [(n, c) for n, c, _ in series], W - 28, 34)
    svg.save(path)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


RED, WHITE, BLUE = (239, 68, 68), (255, 255, 255), (37, 99, 235)
LO_SAT, HI_SAT = 0.5, 4.0   # colour saturates at 0.5x (C faster) and 4x (RVV faster)


def heat_color(s):
    if s < 1:
        t = min(1.0, math.log2(s) / math.log2(LO_SAT))
        return "#%02x%02x%02x" % lerp(WHITE, RED, t), t
    t = min(1.0, math.log2(s) / math.log2(HI_SAT))
    return "#%02x%02x%02x" % lerp(WHITE, BLUE, t), t


def heatmap(path, title, ws, hs, grid, theme, font, W=None, H=None, subtitle=None):
    """W / H = None -> size from the number of rows and columns."""
    mt = 118
    cw, ch = 84, 50
    if W is None:
        W = max(560, cw * len(ws) + 200)
    else:
        cw = max(20, (W - 200) / len(ws))
    if H is None:
        H = mt + ch * len(hs) + 100
    else:
        ch = max(16, (H - mt - 100) / len(hs))
    ml = (W - cw * len(ws)) / 2 + 14
    svg = Svg(W, H, theme, font)
    svg.text(28, 34, title, 17, weight="bold")
    if subtitle:
        svg.text(28, 54, subtitle, 12, fill=MUTED)
    svg.text(ml + cw * len(ws) / 2, 90, "Width", 12, "middle", fill=MUTED)
    svg.text(ml - 58, mt + ch * len(hs) / 2, "Height", 12, "middle", fill=MUTED, rot=-90)
    for j, w in enumerate(ws):
        svg.text(ml + cw * (j + 0.5), mt - 12, w, 13, "middle", weight="600")
    for i, h in enumerate(hs):
        svg.text(ml - 14, mt + ch * (i + 0.5) + 5, h, 13, "end", weight="600")
        for j, w in enumerate(ws):
            x, y = ml + cw * j, mt + ch * i
            s = grid.get((w, h))
            if s is None:
                svg.text(x + cw / 2, y + ch / 2 + 5, "\u2013", 13, "middle", fill=MUTED)
                continue
            col, strength = heat_color(s)
            svg.rect(x + 2, y + 2, cw - 4, ch - 4, col, rx=6)
            svg.text(x + cw / 2, y + ch / 2 + 5, fmt_x(s), 13, "middle",
                     fill=CELL_LIGHT if strength > 0.62 else CELL_DARK,
                     weight="bold" if s < 1 else "500")
    # colour bar, log axis from 0.5x to 4x (1x sits at one third)
    by = mt + ch * len(hs) + 26
    bx, bwid = ml, cw * len(ws)
    svg.add('<defs><linearGradient id="hg" x1="0" x2="1" y1="0" y2="0">'
            f'<stop offset="0" stop-color="rgb{RED}"/>'
            f'<stop offset="0.3333" stop-color="rgb{WHITE}"/>'
            f'<stop offset="1" stop-color="rgb{BLUE}"/></linearGradient></defs>')
    svg.add(f'<rect x="{bx:.1f}" y="{by:.1f}" width="{bwid:.1f}" height="12" rx="6" '
            f'style="fill:url(#hg);stroke:{AXIS}"/>')
    svg.text(bx, by + 32, "\u2264 0.5\u00d7  C faster", 11, fill=MUTED)
    svg.text(bx + bwid / 3, by + 32, "1\u00d7", 11, "middle", fill=MUTED)
    svg.text(bx + bwid, by + 32, "RVV faster  \u2265 4\u00d7", 11, "end", fill=MUTED)
    svg.save(path)


# --------------------------------------------------------------------------
# data
# --------------------------------------------------------------------------
def read_rows(path):
    rows = []
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            rows.append({
                "w": int(r["w"]), "h": int(r["h"]),
                "pattern": int(r["pattern"]) if r.get("pattern", "") != "" else 0,
                "c": int(r["c_cycles"]), "r": int(r["rvv_cycles"]),
                "status": r["status"].strip().upper(),
            })
    return rows


def fit_line(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    return slope, my - slope * mx


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("-i", "--input", required=True,
                    help="input: path to results.csv, or a directory containing results.csv")
    ap.add_argument("-o", "--output",
                    help="output directory for the SVGs (default: the input's dir if it is "
                         "named 'res', else <input dir>/res)")
    ap.add_argument("-k", "--kernel", help="filename prefix (default: kernel folder name)")
    ap.add_argument("-p", "--pattern", type=int, help="pattern to plot (default: highest present)")
    ap.add_argument("-W", "--width", type=int,
                    help="figure width in px, all figures (default 760; heatmap: automatic)")
    ap.add_argument("-H", "--height", type=int,
                    help="figure height in px, all figures (default 440; heatmap: automatic)")
    ap.add_argument("--theme", choices=["auto", "light", "dark"], default="auto",
                    help="auto = follow the viewer's light/dark setting (default); "
                         "light/dark = fixed palette")
    ap.add_argument("--font", default=DEFAULT_FONT,
                    help="CSS font-family for all text (default: the viewer's system UI font)")
    a = ap.parse_args()

    for name, v in (("width", a.width), ("height", a.height)):
        if v is not None and v < 200:
            sys.exit(f"--{name} {v} is too small (minimum 200)")
    W, H = a.width or 760, a.height or 440
    if W < 480 or H < 320:
        print(f"warning: {W}x{H} is small; labels may crowd", file=sys.stderr)

    p = Path(a.input).resolve()
    if p.is_dir():
        p = p / "results.csv"
    if not p.is_file():
        sys.exit(f"input not found: {p}")
    d = p.parent
    kernel = a.kernel or (d.parent.name if d.name == "res" else d.name)
    out = Path(a.output) if a.output else (d if d.name == "res" else d / "res")
    out.mkdir(parents=True, exist_ok=True)
    th, ft = a.theme, a.font

    rows = read_rows(p)
    bad = [r for r in rows if r["status"] != "PASS"]
    for r in bad:
        print(f"warning: {r['w']}x{r['h']} pattern {r['pattern']} status "
              f"{r['status']} -> excluded from figures", file=sys.stderr)
    pats = sorted({r["pattern"] for r in rows})
    pat = a.pattern if a.pattern is not None else pats[-1]
    sel = {(r["w"], r["h"]): r for r in rows if r["pattern"] == pat and r["status"] == "PASS"}
    if not sel:
        sys.exit("no PASS rows for the selected pattern")
    sub = f"{kernel} (8bpc), pattern {pat}"

    sizes = sorted(sel, key=lambda k: (k[0] * k[1], k[0]))
    sq = [(w, h) for (w, h) in sizes if w == h]
    if not sq:
        print("warning: no square sizes; skipping square-block figures", file=sys.stderr)

    if sq:
        cats = [f"{w}\u00d7{h}" for w, h in sq]
        c = [float(sel[s]["c"]) for s in sq]
        r = [float(sel[s]["r"]) for s in sq]
        spd = [ci / ri for ci, ri in zip(c, r)]
        bar_chart(out / f"{kernel}_results.svg", "Speedup (C / RVV), square blocks",
                  cats, [("Speedup", R_COL, spd)], "Speedup (C cycles \u00f7 RVV cycles)",
                  W, H, th, ft,
                  ref=1.0, ref_label="break-even",
                  color_fn=lambda si, v: BAD if v < 1 else R_COL,
                  label_fmt=fmt_x, subtitle=sub, max_bw=72, rm=84,
                  legend_items=[("RVV faster", R_COL), ("C faster", BAD)])
        bar_chart(out / f"{kernel}_cpc.svg", "Cycles per call, square blocks",
                  cats, [("C", C_COL, c), ("RVV", R_COL, r)], "Cycles per call (log scale)",
                  W, H, th, ft, log=True, subtitle=sub)
        line_chart(out / f"{kernel}_cpp.svg", "Cycles per pixel, square blocks", cats,
                   [("C", C_COL, [ci / (w * h) for ci, (w, h) in zip(c, sq)]),
                    ("RVV", R_COL, [ri / (w * h) for ri, (w, h) in zip(r, sq)])],
                   "Cycles per pixel", W, H, th, ft, subtitle=sub)

    ws = sorted({w for w, _ in sel})
    hs = sorted({h for _, h in sel})
    heatmap(out / f"{kernel}_heatmap.svg", "Speedup (C / RVV) over W\u00d7H", ws, hs,
            {k: v["c"] / v["r"] for k, v in sel.items()}, th, ft,
            W=a.width, H=a.height, subtitle=sub)

    # cost per row: cycles = fixed + per_row * H, widths with >= 3 heights
    fits = []
    for w in ws:
        hh = sorted(h for (ww, h) in sel if ww == w)
        if len(hh) >= 3:
            cs, cf = fit_line(hh, [sel[(w, h)]["c"] for h in hh])
            rs, rf = fit_line(hh, [sel[(w, h)]["r"] for h in hh])
            fits.append((w, hh, cs, cf, rs, rf))
    if fits:
        bar_chart(out / f"{kernel}_cpr.svg", "Cost per row (slope of cycles vs height)",
                  [f"W={f[0]}" for f in fits],
                  [("C", C_COL, [f[2] for f in fits]), ("RVV", R_COL, [f[4] for f in fits])],
                  "Cycles per row", W, H, th, ft, subtitle=sub, xlabel="Block width")
        print("\n| Width | Heights used | C per row | C fixed | RVV per row | RVV fixed |")
        print("|---:|---|---:|---:|---:|---:|")
        for w, hh, cs, cf, rs, rf in fits:
            print(f"| {w} | {', '.join(map(str, hh))} | {cs:.0f} | {cf:.0f} | {rs:.0f} | {rf:.0f} |")
    else:
        print("note: no width has >= 3 heights; skipped cpr figure", file=sys.stderr)

    print(f"\nwrote figures for '{kernel}' (pattern {pat}, {W}x{H}, theme {th}) to {out}")


if __name__ == "__main__":
    main()
