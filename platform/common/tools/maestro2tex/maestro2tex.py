#!/usr/bin/env python3
"""maestro2tex -- turn a Cadence Maestro (ADE Assembler) run into TRM-ready LaTeX.

Reads a Maestro results directory, pulls the waveforms out through OCEAN (the only
reader that handles binary PSF *and* PSFXL), and writes a self-contained directory of
pgfplots figures, booktabs tables and .dat files that the LaTeX TRM can \\input
directly.

    maestro2tex.py --results <.../results/maestro/Interactive.32> \
                   --config configs/BiasGenCascWideSwing_tb.json \
                   --outdir <.../latex/analog>

Stage 1 (extract) shells out to OCEAN and needs a Virtuoso licence; it writes plain
two-column CSVs under <outdir>/data/raw. Stage 2 (render) is pure Python 3.6 stdlib and
reads only those CSVs, so you can iterate on the LaTeX with --no-extract and never
take a licence again.

Requires: Python 3.6+, and for --extract, an OCEAN binary (see --ocean/--setup).
"""

import argparse
import json
import os
import re
import subprocess
import sys

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

DEFAULT_OCEAN = '/opt/cadence/IC618/tools.lnx86/dfII/bin/ocean'
DEFAULT_SETUP = os.path.expanduser('~/chips/castalia/cdspaths.sh')

# Process corners we know how to name, longest first so 'tt' never eats 'tt_bip'.
KNOWN_CORNERS = ['tt', 'ff', 'ss', 'sf', 'fs']

# The only values pgfplots accepts for 'legend pos'. Anything else is a hard
# compile error, so a typo in a config must not reach the .tex.
LEGEND_POS = ('south west', 'south east', 'north west', 'north east',
              'outer north east')

# Categorical palette: slots 1-5 of the validated reference palette, in order.
# Documented as passing every hard gate in light mode on the adjacent pairlist
# (worst adjacent CVD dE 9.1, normal-vision 19.6). Do not re-order or re-step:
# the ordering is what the validation is against. Dash patterns are a secondary
# encoding so the curves survive greyscale printing and photocopying.
PALETTE = [
    ('mtxA', '2a78d6', 'solid'),                 # blue
    ('mtxB', 'eb6834', 'dashed'),                # orange
    ('mtxC', '1baf7a', 'dotted'),                # aqua
    ('mtxD', 'eda100', 'dashdotted'),            # yellow
    ('mtxE', 'e87ba4', 'densely dashed'),        # magenta
]

# Diverging map for signed heatmaps: the documented blue<->red pair with the
# documented neutral gray midpoint (never a hue at the midpoint, never a
# rainbow). The red arm is not eyeballed -- each step is the blue step of the
# same OKLab lightness re-hued to the categorical red's hue angle, so the two
# arms are perceptually symmetric about the midpoint (residual dL < 0.001).
#   blue 600/450/200  ->  #184F95 #2A78D6 #9EC5F4   L = .433 .575 .812
#   red  matched      ->  #911E22 #D2383A #F8AAA3   L = .432 .575 .811
DIVERGING = ['184F95', '2A78D6', '9EC5F4', 'F0EFEC', 'F8AAA3', 'D2383A', '911E22']

# Cell count above which a heatmap starts to threaten TeX main memory in a
# full-size document. Measured on this TRM: 26x161 builds, 26x321 does not.
HEATMAP_CELL_WARN = 5000

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def die(msg):
    sys.stderr.write('maestro2tex: error: %s\n' % msg)
    sys.exit(1)


def info(msg):
    sys.stdout.write('  %s\n' % msg)


def texesc(s):
    """Escape a plain string for LaTeX text."""
    for a, b in (('\\', r'\textbackslash{}'), ('_', r'\_'), ('%', r'\%'),
                 ('&', r'\&'), ('#', r'\#'), ('$', r'\$')):
        s = s.replace(a, b)
    return s


def slug(s):
    return re.sub(r'[^A-Za-z0-9]+', '_', s).strip('_')


def fmt(x, digits):
    """Fixed-point format that never emits '-0.00'.

    Negative values are wrapped in math mode so they typeset with a real minus
    sign rather than the hyphen a table cell would otherwise give them.
    """
    if x is None:
        return '--'
    # Spectre writes nan for a margin that does not exist (a loop whose phase
    # never reaches -180 has no gain margin). That is a real result, but "nan"
    # in a manual reads as a broken extraction -- show it as absent.
    if x != x or x in (float('inf'), float('-inf')):
        return '--'
    s = '%.*f' % (digits, x)
    if float(s) == 0.0:
        s = '%.*f' % (digits, 0.0)
    return ('$%s$' % s) if s.startswith('-') else s


# ---------------------------------------------------------------------------
# Discovery: corners and tests in a Maestro run directory
# ---------------------------------------------------------------------------


def expand_points(spec):
    """['1-130', '136'] -> {'1', '2', ..., '130', '136'}.

    One Maestro run now routinely holds several unrelated sweeps -- a 130-point
    2-D map followed by two groups of five-corner single-point benches. Scoping
    a config to its own points keeps the corner labels clean: 136-140 alone are
    tt/ff/fs/sf/ss, while all 140 together would de-duplicate into tt1, tt131,
    tt136 and legends would read like directory numbers.
    """
    if not spec:
        return None
    out = set()
    for item in spec:
        item = str(item).strip()
        if '-' in item:
            lo, hi = item.split('-', 1)
            out.update(str(n) for n in range(int(lo), int(hi) + 1))
        else:
            out.add(item)
    return out


def discover_corners(results_dir, points=None):
    """Return [(dirname, label, vars)] for each numeric point/corner subdirectory.

    Maestro names the per-corner run directories 1, 2, 3 ... The process corner
    itself is recovered from the netlist's .modelFiles (section=ff, section=tt_bip,
    ...) by majority vote over the section prefixes, and the design variables from
    the PSF variables_file.
    """
    out = []
    for name in sorted(os.listdir(results_dir), key=lambda s: (len(s), s)):
        if not name.isdigit():
            continue
        if points is not None and name not in points:
            continue
        cdir = os.path.join(results_dir, name)
        if not os.path.isdir(cdir):
            continue
        label, dvars = None, {}
        for test in sorted(os.listdir(cdir)):
            mf = os.path.join(cdir, test, 'netlist', '.modelFiles')
            if label is None and os.path.isfile(mf):
                label = _corner_from_modelfiles(mf)
            vf = os.path.join(cdir, test, 'psf', 'variables_file')
            if not dvars and os.path.isfile(vf):
                dvars = _vars_from_file(vf)
            if label and dvars:
                break
        out.append([name, label or ('pt%s' % name), dvars])

    # Labels become filenames and legend entries, so they must be unique -- a
    # collision would silently overwrite one corner's data with another's.
    seen = {}
    for row in out:
        seen[row[1]] = seen.get(row[1], 0) + 1
    dup = set(k for k, n in seen.items() if n > 1)
    for row in out:
        if row[1] in dup:
            row[1] = '%s%s' % (row[1], row[0])
    return [tuple(r) for r in out]


def _corner_from_modelfiles(path):
    """Recover the process corner from a netlist .modelFiles list.

    Maestro always includes the PDK master .scs (whose sections are all tt_*) and
    then *overrides* it with cor_*.scs corner files, so a plain majority vote over
    section prefixes always answers 'tt'. The corner is whatever the standard-MOS
    override says; fall back to the other cor_* overrides, and only then to a vote.
    """
    std, override, allsec = None, {}, {}

    def bucket(sec):
        for c in KNOWN_CORNERS:
            if sec == c or sec.startswith(c + '_'):
                return c
        return None

    with open(path) as f:
        for line in f:
            m = re.search(r'section=([A-Za-z0-9_]+)', line)
            if not m:
                continue
            c = bucket(m.group(1))
            if not c:
                continue
            allsec[c] = allsec.get(c, 0) + 1
            if 'cor_' in line:
                override[c] = override.get(c, 0) + 1
                if 'cor_std_mos' in line:
                    std = c
    if std:
        return std
    for table in (override, allsec):
        if table:
            return max(table.items(), key=lambda kv: kv[1])[0]
    return None


def _vars_from_file(path):
    """Parse a PSF variables_file: '"temp" "variable" ( 27 ) PROP( )'."""
    dvars = {}
    with open(path) as f:
        for line in f:
            m = re.match(r'\s*"([^"]+)"\s+"variable"\s*\(\s*([-0-9.eE+]+)\s*\)', line)
            if m:
                try:
                    dvars[m.group(1)] = float(m.group(2))
                except ValueError:
                    pass
    return dvars


def corner_cache_path(rawdir, block):
    return os.path.join(rawdir, 'corners_%s.json' % slug(block))


def save_corners(rawdir, block, corners):
    """Persist the discovered corners next to the CSVs.

    Maestro rotates its run directories, so the results a block was extracted
    from will not be there forever -- the CSVs outlive them. Without this the
    render stage could not run once the run was gone, which would defeat the
    point of committing the CSVs at all.
    """
    with open(corner_cache_path(rawdir, block), 'w') as f:
        json.dump([{'dir': c[0], 'label': c[1], 'vars': c[2]} for c in corners],
                  f, indent=2, sort_keys=True)


def load_corners(rawdir, block):
    path = corner_cache_path(rawdir, block)
    if not os.path.isfile(path):
        return None
    with open(path) as f:
        rows = json.load(f)
    return [(r['dir'], r['label'], r['vars']) for r in rows]


def discover_tests(results_dir, corners):
    tests = []
    for cdirname, _, _ in corners:
        cdir = os.path.join(results_dir, cdirname)
        for t in sorted(os.listdir(cdir)):
            if t not in tests and os.path.isdir(os.path.join(cdir, t, 'psf')):
                tests.append(t)
    return tests


# ---------------------------------------------------------------------------
# Stage 1: extraction through OCEAN
# ---------------------------------------------------------------------------


def build_ocn(results_dir, corners, cfg, rawdir):
    """Emit a fully-unrolled OCEAN script -- no loops, so one bad signal cannot
    derail the rest of the run and every failure is attributable to a line."""
    L = []
    L.append(';; generated by maestro2tex -- do not edit')
    L.append('procedure(mtxDump(fname wv)')
    L.append('  let((xs ys n p)')
    L.append('    p = outfile(fname "w")')
    L.append('    cond(')
    L.append('      (null(wv) fprintf(p "#nil\\n"))')
    L.append('      (drIsWaveform(wv)')
    L.append('        xs = drGetWaveformXVec(wv)')
    L.append('        ys = drGetWaveformYVec(wv)')
    L.append('        n = drVectorLength(xs)')
    L.append('        for(i 0 n-1')
    L.append('          fprintf(p "%.10g %.10g\\n" drGetElem(xs i) drGetElem(ys i)))')
    L.append('      )')
    L.append('      (t fprintf(p "#scalar %.10g\\n" float(wv)))')
    L.append('    )')
    L.append('    close(p)')
    L.append('    t))')
    L.append('')

    tests = cfg['tests']
    for cdirname, label, _ in corners:
        for tname, tspec in sorted(tests.items()):
            psf = os.path.join(results_dir, cdirname, test_dir(tname, tspec), 'psf')
            res = tspec.get('result', 'dc')
            L.append(';; ---- corner %s (%s) / test %s' % (cdirname, label, tname))
            L.append('when(isDir("%s")' % psf)
            L.append('  openResults("%s")' % psf)
            L.append("  when(member('%s results())" % res)
            L.append("    selectResult('%s)" % res)
            meta = os.path.join(rawdir, '%s__%s.meta' % (tname, label))
            L.append('    mtxP = outfile("%s" "w")' % meta)
            L.append('    fprintf(mtxP "sweep %%L\\n" car(errset(sweepNames())))')
            L.append('    close(mtxP)')
            for sname, sspec in sorted(_signals_for(cfg, tspec).items()):
                csv = os.path.join(rawdir, '%s__%s__%s.csv' % (tname, label, sname))
                L.append('    errset(mtxDump("%s" %s))' % (csv, sspec['expr']))
            L.append('  )')
            L.append(')')
            L.append('')

    L.append('printf("MTX_EXTRACT_DONE\\n")')
    L.append('exit(0)')
    return '\n'.join(L) + '\n'


def test_dir(tname, tspec):
    """Results subdirectory a config test reads from.

    A single Maestro test often holds several analyses (ac, dc, stb, noise, ...)
    and each needs its own signal set, x-axis and figures. The config therefore
    names *logical* tests, and 'dir' says which run directory each one reads;
    it defaults to the test name, which is what a one-analysis bench wants.
    """
    return tspec.get('dir', tname)


def _signals_for(cfg, tspec):
    """Signals visible to a test: the global set, overridden per test."""
    sigs = dict(cfg.get('signals', {}))
    sigs.update(tspec.get('signals', {}))
    only = tspec.get('use')
    if only:
        sigs = dict((k, v) for k, v in sigs.items() if k in only)
    return sigs


def run_ocean(ocn_path, ocean, setup, log_path):
    cmd = ocn_path
    if setup and os.path.isfile(setup):
        sh = 'source "%s" >/dev/null 2>&1; exec "%s" -nograph < "%s"' % (setup, ocean, cmd)
    else:
        sh = 'exec "%s" -nograph < "%s"' % (ocean, cmd)
    with open(log_path, 'w') as log:
        p = subprocess.Popen(['bash', '-c', sh], stdout=log, stderr=subprocess.STDOUT)
        p.wait()
    with open(log_path) as f:
        txt = f.read()
    if 'MTX_EXTRACT_DONE' not in txt:
        die('OCEAN extraction did not complete -- see %s' % log_path)
    return txt


# ---------------------------------------------------------------------------
# Stage 2: read the CSVs back
# ---------------------------------------------------------------------------


def read_csv(path):
    """Return ('wave', [(x, y)...]) or ('scalar', value) or None."""
    if not os.path.isfile(path):
        return None
    pts = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('#nil'):
                return None
            if line.startswith('#scalar'):
                try:
                    return ('scalar', float(line.split()[1]))
                except (IndexError, ValueError):
                    return None
            parts = line.split()
            if len(parts) >= 2:
                try:
                    pts.append((float(parts[0]), float(parts[1])))
                except ValueError:
                    pass
    if not pts:
        return None
    return ('wave', pts)


def read_meta(path):
    if not os.path.isfile(path):
        return {}
    out = {}
    with open(path) as f:
        for line in f:
            if line.startswith('sweep '):
                m = re.search(r'"([^"]+)"', line)
                if m:
                    out['sweep'] = m.group(1)
    return out


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------


def decimate(pts, maxpts):
    """Stride-decimate, always keeping the endpoints and the global extrema so the
    plotted envelope still shows overshoot."""
    if maxpts <= 0 or len(pts) <= maxpts:
        return pts
    keep = {0, len(pts) - 1}
    keep.add(max(range(len(pts)), key=lambda i: pts[i][1]))
    keep.add(min(range(len(pts)), key=lambda i: pts[i][1]))
    stride = max(1, len(pts) // maxpts)
    keep.update(range(0, len(pts), stride))
    return [pts[i] for i in sorted(keep)]


def stats(pts, scale=1.0):
    ys = [p[1] * scale for p in pts]
    xs = [p[0] for p in pts]
    n = len(ys)
    mean = sum(ys) / n
    lo, hi = min(ys), max(ys)
    span = (max(xs) - min(xs)) or 1.0
    s = {
        'min': lo, 'max': hi, 'mean': mean,
        'spread': hi - lo,
        'first': ys[0], 'last': ys[-1],
        'xmin': min(xs), 'xmax': max(xs),
    }
    # Fractional variation per unit of the sweep variable.
    s['sens_pct_per_x'] = (hi - lo) / abs(mean) / span * 100.0 if mean else None
    s['ppm_per_x'] = (hi - lo) / abs(mean) / span * 1e6 if mean else None
    return s


def value_at(pts, x0):
    """Linear interpolation, clamped to the sweep ends."""
    if not pts:
        return None
    if x0 <= pts[0][0]:
        return pts[0][1]
    if x0 >= pts[-1][0]:
        return pts[-1][1]
    for i in range(1, len(pts)):
        x1, y1 = pts[i]
        if x1 >= x0:
            x0_, y0_ = pts[i - 1]
            if x1 == x0_:
                return y1
            return y0_ + (y1 - y0_) * (x0 - x0_) / (x1 - x0_)
    return pts[-1][1]


def settle_time(pts, tol=0.01):
    """Time after which the signal stays within tol of its final value."""
    if len(pts) < 2:
        return None
    final = pts[-1][1]
    if final == 0:
        return None
    band = abs(final) * tol
    t = pts[-1][0]
    for x, y in reversed(pts):
        if abs(y - final) > band:
            return t
        t = x
    return pts[0][0]


# ---------------------------------------------------------------------------
# Stage 3: LaTeX emission
# ---------------------------------------------------------------------------

AXIS_STYLE = (
    'width=%(w)s, height=%(h)s,\n'
    '      xlabel={%(xlabel)s}, ylabel={%(ylabel)s},\n'
    '      grid=both,\n'
    '      major grid style={line width=0.2pt, draw=black!14},\n'
    '      minor grid style={line width=0.2pt, draw=black!7},\n'
    '      minor tick num=1,\n'
    '      axis line style={line width=0.4pt, draw=black!45},\n'
    '      tick style={line width=0.4pt, draw=black!45},\n'
    '      tick align=outside,\n'
    '      label style={font=\\small}, tick label style={font=\\small},\n'
    '      enlarge x limits=0.02, enlarge y limits=0.10,\n'
    '      every axis plot/.append style={line join=round, no marks},\n'
    '      %(legend)s,\n'
    '      %(ticks)s'
)

# Decade axes label themselves as 10^n and must not be forced into the
# fixed-point format the linear axes use -- that would print every tick of a
# five-decade axis as "0.0".
TICKS_FIXED_Y = ('y tick label style={/pgf/number format/fixed,\n'
                 '                          /pgf/number format/precision=%(yprec)s}')
# Both axes linear is by far the common case; keep it on the historical two
# lines so re-running an existing config produces a byte-identical figure.
TICKS_LINEAR = 'scaled y ticks=false, scaled x ticks=false,\n      ' + TICKS_FIXED_Y

# Default legend placement: a single un-boxed row above the axis. With five
# corner curves spanning the full plot width there is no in-axis position that
# does not sit on top of data -- a boxed legend at "south east" landed squarely
# on the tt curve. Above the axis it can never collide, and it reads the same way
# in every figure of the chapter.
LEGEND_ABOVE = (
    'legend style={font=\\footnotesize, draw=none, fill=none,\n'
    '                    at={(0.5,1.02)}, anchor=south, legend columns=-1,\n'
    '                    /tikz/every even column/.append style={column sep=9pt}},\n'
    '      legend cell align=left'
)

LEGEND_INSIDE = (
    'legend style={font=\\footnotesize, draw=black!25, fill=white,\n'
    '                    fill opacity=0.9, text opacity=1, row sep=1pt},\n'
    '      legend cell align=left, legend pos=%s'
)


def emit_palette(f):
    f.write('% Categorical palette: slots 1-5 of the validated reference palette,\n')
    f.write('% in documented order. Dash patterns are a secondary encoding for print.\n')
    for name, hexv, _ in PALETTE:
        f.write('\\providecolor{%s}{HTML}{%s}\n' % (name, hexv.upper()))
    f.write('\n')


def curve_style(idx, lw='1.1pt'):
    name, _, dash = PALETTE[idx % len(PALETTE)]
    return '%s, line width=%s, %s' % (name, lw, dash)


def write_dat(path, pts, xscale, yscale):
    with open(path, 'w') as f:
        f.write('# x y  (written by maestro2tex)\n')
        for x, y in pts:
            f.write('%.10g %.10g\n' % (x * xscale, y * yscale))


def emit_figure(outdir, texroot, figid, spec, series, caption, xlabel, ylabel,
                yprec, maxpts):
    """series: [(legend, pts, xscale, yscale)] -- one entry per plotted curve."""
    datrel = []
    for i, (legend, pts, xs_, ys_) in enumerate(series):
        base = 'data/%s_%02d.dat' % (figid, i)
        write_dat(os.path.join(outdir, base), decimate(pts, maxpts), xs_, ys_)
        datrel.append((legend, base))

    # Omit legendpos (the default) to get the row above the axis; name one of the
    # pgfplots positions only when a figure genuinely reads better with it inside.
    legendpos = spec.get('legendpos')
    if legendpos is None:
        legend = LEGEND_ABOVE
    else:
        if legendpos not in LEGEND_POS:
            info('figure %s: legendpos %r is not a pgfplots choice, putting the '
                 'legend above the axis' % (figid, legendpos))
            legend = LEGEND_ABOVE
        else:
            legend = LEGEND_INSIDE % legendpos

    path = os.path.join(outdir, 'fig_%s.tex' % figid)
    with open(path, 'w') as f:
        f.write('%% maestro2tex -- generated figure; do not edit by hand.\n')
        f.write('\\providecommand{\\MaestroRoot}{%s}\n' % texroot)
        f.write('\\begin{figure}[htbp]\n  \\centering\n')
        # Group-local compat so this figure cannot disturb other pgfplots in the
        # document, which set no compat level of their own.
        f.write('  {\\pgfplotsset{compat=1.18}%\n')
        f.write('  \\begin{tikzpicture}\n')
        f.write('    \\begin{axis}[\n      ')
        xlog, ylog = spec.get('xlog'), spec.get('ylog')
        if not xlog and not ylog:
            ticks = [TICKS_LINEAR % {'yprec': yprec}]
        else:
            ticks = ['xmode=log' if xlog else 'scaled x ticks=false',
                     'ymode=log' if ylog else
                     'scaled y ticks=false,\n      ' + TICKS_FIXED_Y % {'yprec': yprec}]
        f.write(AXIS_STYLE % {
            'w': spec.get('width', '0.82\\linewidth'),
            'h': spec.get('height', '6.2cm'),
            'xlabel': xlabel, 'ylabel': ylabel,
            'legend': legend,
            'ticks': ',\n      '.join(ticks),
        })
        extra = spec.get('axis_extra')
        if extra:
            f.write(',\n      %s' % extra)
        f.write('\n    ]\n')
        for i, (legend, rel) in enumerate(datrel):
            f.write('      \\addplot[%s] table {\\MaestroRoot %s};\n'
                    % (curve_style(i), rel))
            f.write('      \\addlegendentry{%s}\n' % legend)
        f.write('    \\end{axis}\n  \\end{tikzpicture}}\n')
        f.write('  \\caption{%s}\n' % caption)
        f.write('  \\label{fig:%s}\n' % figid.replace('_', '-'))
        f.write('\\end{figure}\n')
    return path


def emit_heatmap(outdir, texroot, figid, spec, cols, overlays, caption):
    """A 2-D map: one design variable across the corners on x, the analysis
    sweep on y, a signal as colour.

    `cols` is [(xvalue, [(y, z) ...])] already sorted, scaled and decimated;
    every column must carry the same y grid. `overlays` is
    [(legend, [(x, y) ...])] -- scalar-per-corner curves drawn on top, which is
    how a compliance envelope goes onto the map it was measured from.
    """
    nx = len(cols)
    ny = len(cols[0][1])
    datrel = 'data/%s.dat' % figid
    with open(os.path.join(outdir, datrel), 'w') as f:
        f.write('x y z\n')
        for xv, pts in cols:                      # column-major: all y, then next x
            for yv, zv in pts:
                f.write('%.10g %.10g %.10g\n' % (xv, yv, zv))

    ovrel = []
    for i, (legend, pts) in enumerate(overlays):
        rel = 'data/%s_ov%02d.dat' % (figid, i)
        with open(os.path.join(outdir, rel), 'w') as f:
            f.write('# x y  (written by maestro2tex)\n')
            for xv, yv in pts:
                f.write('%.10g %.10g\n' % (xv, yv))
        ovrel.append((legend, rel))

    path = os.path.join(outdir, 'fig_%s.tex' % figid)
    with open(path, 'w') as f:
        f.write('%% maestro2tex -- generated heatmap; do not edit by hand.\n')
        f.write('\\providecommand{\\MaestroRoot}{%s}\n' % texroot)
        f.write('\\begin{figure}[htbp]\n  \\centering\n')
        f.write('  {\\pgfplotsset{compat=1.18}%\n')
        f.write('  \\begin{tikzpicture}\n')
        f.write('    \\begin{axis}[\n')
        f.write('      width=%s, height=%s,\n' % (spec.get('width', '0.82\\linewidth'),
                                                  spec.get('height', '7.0cm')))
        f.write('      xlabel={%s}, ylabel={%s},\n'
                % (spec.get('xlabel', 'x'), spec.get('ylabel', 'y')))
        f.write('      axis on top, enlarge x limits=false, enlarge y limits=false,\n')
        # The raster defines the y range. Overlay curves routinely run far past
        # it -- an envelope stops being an envelope outside the tracking range
        # and shoots off -- and without an explicit limit they drag the axis out
        # until the map itself is a sliver.
        ylo, yhi = cols[0][1][0][0], cols[0][1][-1][0]
        f.write('      ymin=%.10g, ymax=%.10g,\n' % (min(ylo, yhi), max(ylo, yhi)))
        f.write('      axis line style={line width=0.4pt, draw=black!45},\n')
        f.write('      tick style={line width=0.4pt, draw=black!45},\n')
        f.write('      tick align=outside,\n')
        f.write('      label style={font=\\small}, tick label style={font=\\small},\n')
        f.write('      scaled x ticks=false, scaled y ticks=false,\n')
        f.write('      colormap={mtxdiv}{%s},\n'
                % ' '.join('rgb255=(%d,%d,%d)' % (int(h[0:2], 16), int(h[2:4], 16),
                                                  int(h[4:6], 16)) for h in DIVERGING))
        f.write('      point meta min=%s, point meta max=%s,\n'
                % (spec['zmin'], spec['zmax']))
        f.write('      colorbar,\n')
        f.write('      colorbar style={ylabel={%s}, ylabel style={font=\\small},\n'
                % spec.get('zlabel', 'z'))
        f.write('                      tick label style={font=\\small}, width=0.28cm},\n')
        if ovrel:
            f.write('      legend style={font=\\footnotesize, draw=none, fill=none,\n')
            f.write('                    at={(0.5,1.02)}, anchor=south, legend columns=-1,\n')
            f.write('                    /tikz/every even column/.append style={column sep=9pt}},\n')
            f.write('      legend cell align=left,\n')
        extra = spec.get('axis_extra')
        if extra:
            f.write('      %s,\n' % extra)
        f.write('    ]\n')
        # forget plot: the raster is described by the colorbar, not the legend --
        # without it the matrix plot swallows the first overlay's legend entry.
        f.write('      \\addplot[matrix plot*, point meta=explicit, forget plot,\n')
        f.write('               mesh/cols=%d, mesh/rows=%d, mesh/ordering=colwise]\n' % (nx, ny))
        f.write('        table[x=x, y=y, meta=z] {\\MaestroRoot %s};\n' % datrel)
        for i, (legend, rel) in enumerate(ovrel):
            name, _, dash = PALETTE[i % len(PALETTE)]
            f.write('      \\addplot[black, line width=1.1pt, %s, no marks]\n' % dash)
            f.write('        table {\\MaestroRoot %s};\n' % rel)
            f.write('      \\addlegendentry{%s}\n' % legend)
        f.write('    \\end{axis}\n  \\end{tikzpicture}}\n')
        f.write('  \\caption{%s}\n' % caption)
        f.write('  \\label{fig:%s}\n' % figid.replace('_', '-'))
        f.write('\\end{figure}\n')
    return path


def emit_table(outdir, tabid, header, rows, caption, colspec=None):
    path = os.path.join(outdir, 'tab_%s.tex' % tabid)
    ncol = len(header)
    if colspec is None:
        colspec = 'l' + 'r' * (ncol - 1)
    with open(path, 'w') as f:
        f.write('%% maestro2tex -- generated table; do not edit by hand.\n')
        f.write('\\begin{table}[htbp]\n  \\centering\n')
        f.write('  \\caption{%s}\n' % caption)
        f.write('  \\label{tab:%s}\n' % tabid.replace('_', '-'))
        f.write('  \\begin{tabular}{%s}\n    \\toprule\n' % colspec)
        f.write('    %s \\\\\n    \\midrule\n' % ' & '.join(header))
        for r in rows:
            f.write('    %s \\\\\n' % ' & '.join(r))
        f.write('    \\bottomrule\n  \\end{tabular}\n\\end{table}\n')
    return path


# ---------------------------------------------------------------------------
# Rendering driver
# ---------------------------------------------------------------------------


def render(cfg, corners, rawdir, outdir, texroot, maxpts):
    """Build every figure and table declared in the config."""
    written = []
    block = cfg.get('block', 'block')
    labels = [c[1] for c in corners]
    nominal = cfg.get('nominal_corner', labels[0] if labels else 'tt')

    def load(test, corner, signame):
        return read_csv(os.path.join(rawdir, '%s__%s__%s.csv' % (test, corner, signame)))

    def sigspec(test, name):
        return _signals_for(cfg, cfg['tests'][test]).get(name, {})

    def corner_axis(spec, test, match=None):
        """[(xvalue, corner_label)] for the corners a map/by-corner spec spans,
        ordered by the design variable that distinguishes them.

        `match` selects one corner family out of a multi-corner sweep: with five
        corners the labels are tt1..tt26, ff27..ff52, ... and a map can only show
        one of them, so '^tt' picks that family and leaves the ordering by the
        design variable intact.
        """
        var = spec.get('xvar') or spec.get('sortvar')
        want = spec.get('corners', 'all')
        want = labels if want == 'all' else want
        rx = re.compile(match) if match else None
        rows = []
        for cdirname, label, dvars in corners:
            if label not in want:
                continue
            if var not in dvars:
                continue
            if rx and not rx.search(label):
                continue
            rows.append((dvars[var], label))
        rows.sort()
        return rows

    # ---------------- scalar-vs-design-variable line figures ----------------
    for spec in cfg.get('figures', []):
        if spec.get('kind') != 'sweepline':
            continue
        figid = spec['id']
        test = spec['test']
        tspec = cfg['tests'][test]
        series = []
        for sname in spec['signals']:
            ss = sigspec(test, sname)
            for ser in spec.get('series', [{'match': None, 'legend': None}]):
                pts = []
                for xval, label in corner_axis(spec, test, ser.get('match')):
                    d = load(test, label, sname)
                    if d and d[0] == 'scalar':
                        pts.append((xval, d[1] * ss.get('scale', 1.0)))
                if not pts:
                    info('sweepline %s: no data for %s / %s'
                         % (figid, sname, ser.get('legend', ser.get('match'))))
                    continue
                if len(spec['signals']) > 1 and ser.get('legend'):
                    legend = '%s, %s' % (ss.get('label', sname), ser['legend'])
                else:
                    legend = ser.get('legend') or ss.get('label', sname)
                series.append((legend, pts, 1.0, 1.0))
        if not series:
            info('skip sweepline %s (no data)' % figid)
            continue
        written.append(emit_figure(
            outdir, texroot, figid, spec, series, spec.get('caption', figid),
            spec.get('xlabel', 'x'), spec.get('ylabel', 'y'),
            spec.get('yprec', 1), 0))
        info('sweepline %-25s %d curve(s)' % (figid, len(series)))

    # ---------------- heatmaps ----------------
    for spec in cfg.get('figures', []):
        if spec.get('kind') != 'heatmap':
            continue
        figid = spec['id']
        test = spec['test']
        tspec = cfg['tests'][test]
        signame = spec['signal']
        ss = sigspec(test, signame)
        yscale = spec.get('yscale', tspec.get('xscale', 1.0))
        zscale = spec.get('zscale', ss.get('scale', 1.0))
        ylim = spec.get('ylimit')
        ystep = max(1, int(spec.get('ystep', 1)))

        cols, ny, skipped = [], None, []
        for xval, label in corner_axis(spec, test, spec.get('corner_match')):
            d = load(test, label, signame)
            if not d or d[0] != 'wave':
                skipped.append(label)
                continue
            pts = d[1]
            if ylim:
                pts = [p for p in pts if ylim[0] <= p[0] <= ylim[1]]
            pts = pts[::ystep]
            if not pts:
                skipped.append(label)
                continue
            if ny is None:
                ny = len(pts)
            elif len(pts) != ny:
                # A ragged column would silently shear the whole matrix.
                info('heatmap %s: corner %s has %d sweep points, expected %d -- dropped'
                     % (figid, label, len(pts), ny))
                skipped.append(label)
                continue
            cols.append((xval, [(y * yscale, z * zscale) for y, z in pts]))
        if not cols:
            info('skip heatmap %s (no usable columns)' % figid)
            continue
        if skipped:
            info('heatmap %s: skipped %s' % (figid, ', '.join(skipped)))

        overlays = []
        for ov in spec.get('overlay', []):
            osc = ov.get('scale', 1.0)
            pts = []
            for xval, label in corner_axis(spec, test, spec.get('corner_match')):
                d = load(test, label, ov['signal'])
                if d and d[0] == 'scalar':
                    pts.append((xval, d[1] * osc))
            if pts:
                overlays.append((ov.get('legend', ov['signal']), pts))
            else:
                info('heatmap %s: overlay %s has no scalar data' % (figid, ov['signal']))

        written.append(emit_heatmap(outdir, texroot, figid, spec, cols, overlays,
                                    spec.get('caption', figid)))
        info('heatmap %-26s %d x %d cells, %d overlay(s)'
             % (figid, len(cols), ny, len(overlays)))
        # pgfplots builds one TeX path per cell. A standalone proof sheet
        # swallows far more than a 200-page manual does: 26x321 compiled fine
        # alone and blew main memory inside the TRM. Warn here rather than let
        # it surface as "TeX capacity exceeded" halfway through a chip build.
        if len(cols) * ny > HEATMAP_CELL_WARN:
            info('  ^ %d cells is above the %d that fits comfortably in a large '
                 'document -- raise `ystep` or narrow `ylimit` if the TRM build '
                 'runs out of TeX main memory'
                 % (len(cols) * ny, HEATMAP_CELL_WARN))

    # ---------------- figures ----------------
    for spec in cfg.get('figures', []):
        if spec.get('kind') in ('heatmap', 'sweepline'):
            continue
        figid = spec['id']
        test = spec['test']
        tspec = cfg['tests'][test]
        want_corners = spec.get('corners', [nominal])
        if want_corners == 'all':
            want_corners = labels
        series, missing = [], []
        for signame in spec['signals']:
            ss = sigspec(test, signame)
            for corner in want_corners:
                d = load(test, corner, signame)
                if not d or d[0] != 'wave':
                    missing.append('%s/%s' % (signame, corner))
                    continue
                if len(spec['signals']) > 1 and len(want_corners) > 1:
                    legend = '%s, %s' % (ss.get('label', signame), corner)
                elif len(spec['signals']) > 1:
                    legend = ss.get('label', signame)
                else:
                    legend = corner
                series.append((legend, d[1],
                               tspec.get('xscale', 1.0), ss.get('scale', 1.0)))
        if not series:
            info('skip figure %s (no data: %s)' % (figid, ', '.join(missing) or 'none'))
            continue
        if missing:
            info('figure %s: missing %s' % (figid, ', '.join(missing)))
        ylabel = spec.get('ylabel') or _axis_label(sigspec(test, spec['signals'][0]))
        p = emit_figure(outdir, texroot, figid, spec, series,
                        spec.get('caption', figid),
                        spec.get('xlabel', tspec.get('xlabel', 'x')),
                        ylabel, spec.get('yprec', 1), maxpts)
        written.append(p)
        info('figure %-28s %d curve(s)' % (figid, len(series)))

    # ---------------- tables ----------------
    for spec in cfg.get('tables', []):
        tabid = spec['id']
        ttype = spec.get('type', 'matrix')
        test = spec['test']
        tspec = cfg['tests'][test]
        want_corners = spec.get('corners', 'all')
        if want_corners == 'all':
            want_corners = labels

        if ttype == 'matrix':
            stat = spec.get('stat', 'value')
            header = ['Parameter', 'Unit'] + [texesc(c) for c in want_corners]
            if spec.get('spread_column', True):
                header.append('Spread')
            rows = []
            for signame in spec['signals']:
                ss = sigspec(test, signame)
                dig = spec.get('digits', ss.get('digits', 1))
                vals = []
                for corner in want_corners:
                    d = load(test, corner, signame)
                    vals.append(_stat_value(d, stat, ss, tspec, spec))
                row = [ss.get('label', signame),
                       spec.get('unit_tex', ss.get('unit_tex', ''))]
                row += [fmt(v, dig) for v in vals]
                if spec.get('spread_column', True):
                    good = [v for v in vals if v is not None]
                    row.append(fmt(max(good) - min(good), dig) if len(good) > 1 else '--')
                rows.append(row)
            if rows:
                written.append(emit_table(outdir, tabid, header, rows,
                                          spec.get('caption', tabid)))
                info('table  %-28s %d row(s)' % (tabid, len(rows)))

        elif ttype == 'bycorner':
            # Transposed matrix table: corners are rows, signals are columns.
            # A sweep across a design variable has too many corners to be a
            # column each -- 26 of them would be an unreadable 26-wide table.
            var = spec.get('sortvar')
            header = [spec.get('sortvar_label', var),
                      spec.get('sortvar_unit', '')]
            for signame in spec['signals']:
                ss = sigspec(test, signame)
                header.append('%s%s' % (
                    ss.get('label', signame),
                    ('~[%s]' % ss['unit_tex']) if ss.get('unit_tex') else ''))
            rows = []
            for xval, label in corner_axis(spec, test, spec.get('corner_match')):
                row = [fmt(xval, spec.get('sortvar_digits', 2)),
                       spec.get('sortvar_unit_cell', '')]
                for signame in spec['signals']:
                    ss = sigspec(test, signame)
                    d = load(test, label, signame)
                    row.append(fmt(_stat_value(d, spec.get('stat', 'value'), ss,
                                               tspec, spec),
                                   spec.get('digits', ss.get('digits', 2))))
                rows.append(row)
            if rows:
                # The unit column is redundant once every header carries units.
                header = [header[0]] + header[2:]
                rows = [[r[0]] + r[2:] for r in rows]
                written.append(emit_table(outdir, tabid, header, rows,
                                          spec.get('caption', tabid)))
                info('table  %-28s %d row(s)' % (tabid, len(rows)))

        elif ttype == 'stats':
            cols = spec.get('stats', ['min', 'mean', 'max', 'spread'])
            header = ['Parameter', 'Unit'] + [_stat_header(c, tspec) for c in cols]
            rows = []
            corner = spec.get('corner', nominal)
            for signame in spec['signals']:
                ss = sigspec(test, signame)
                dig = spec.get('digits', ss.get('digits', 1))
                d = load(test, corner, signame)
                row = [ss.get('label', signame), ss.get('unit_tex', '')]
                for c in cols:
                    v = _stat_value(d, c, ss, tspec, spec)
                    row.append(fmt(v, 0 if c in ('ppm_per_x',) else dig))
                rows.append(row)
            if rows:
                written.append(emit_table(outdir, tabid, header, rows,
                                          spec.get('caption', tabid)))
                info('table  %-28s %d row(s)' % (tabid, len(rows)))

    # ---------------- corner legend table ----------------
    if cfg.get('emit_corner_table', True):
        header = ['Point', 'Process', 'Temperature', 'Supply']
        rows = []
        for cdirname, label, dvars in corners:
            rows.append([
                cdirname, texesc(label),
                ('%g\\,\\si{\\celsius}' % dvars['temp']) if 'temp' in dvars else '--',
                ('%g\\,\\si{\\volt}' % dvars[cfg['supply_var']])
                if cfg.get('supply_var') in dvars else '--',
            ])
        written.append(emit_table(outdir, '%s_corners' % slug(block), header, rows,
                                  cfg.get('corner_table_caption',
                                          'Simulated process/temperature/supply points.')))
        info('table  %-28s %d row(s)' % ('%s_corners' % slug(block), len(rows)))

    return written


def _axis_label(ss):
    lab = ss.get('label', '')
    unit = ss.get('unit_tex', '')
    return ('%s~[%s]' % (lab, unit)) if unit else lab


def _stat_header(c, tspec):
    xu = tspec.get('xunit_tex', '')
    return {
        'min': 'Min', 'max': 'Max', 'mean': 'Mean', 'spread': 'Spread',
        'first': 'Start', 'last': 'Final', 'value': 'Value',
        'settle': 'Settling', 'nominal': 'Nominal',
        'sens_pct_per_x': 'Sens.\\ [\\%%/%s]' % xu if xu else 'Sens.',
        'ppm_per_x': 'Coeff.\\ [ppm/%s]' % xu if xu else 'Coeff.',
    }.get(c, c)


def _stat_value(d, stat, ss, tspec, spec):
    """One cell: reduce a signal's data to a single number."""
    if not d:
        return None
    scale = ss.get('scale', 1.0)
    if d[0] == 'scalar':
        return d[1] * scale
    pts = d[1]
    if stat == 'value':
        return pts[-1][1] * scale
    if stat == 'nominal':
        x0 = spec.get('at', tspec.get('nominal_x'))
        if x0 is None:
            return None
        return value_at(pts, x0) * scale
    if stat == 'settle':
        t = settle_time(pts, spec.get('tol', 0.01))
        return t * tspec.get('xscale', 1.0) if t is not None else None
    s = stats(pts, scale)
    return s.get(stat)


# ---------------------------------------------------------------------------
# Master include file
# ---------------------------------------------------------------------------


def emit_master(cfg, outdir, texroot, written, corners):
    block = cfg.get('block', 'block')
    path = os.path.join(outdir, '%s.tex' % block)
    figs = [os.path.basename(p)[:-4] for p in written if
            os.path.basename(p).startswith('fig_')]
    tabs = [os.path.basename(p)[:-4] for p in written if
            os.path.basename(p).startswith('tab_')]
    order = cfg.get('order')
    with open(path, 'w') as f:
        f.write('%% maestro2tex -- generated master include for %s.\n' % block)
        f.write('%% Regenerate with tools/maestro2tex; do not edit by hand.\n')
        f.write('%%\n%% Usage from the TRM (which builds with cwd = latex/TRM/):\n')
        f.write('%%     \\input{%s%s.tex}\n%%\n' % (texroot, block))
        f.write('%% Needs pgfplots, booktabs, siunitx and placeins -- all already in\n')
        f.write('%% packages-commands.tex. \\providecolor needs xcolor (also present).\n\n')
        f.write('\\providecommand{\\MaestroRoot}{%s}\n\n' % texroot)
        emit_palette(f)
        # A block is a dozen-odd floats in a row, so LaTeX's queue runs several
        # pages behind the text and one block's figures surface inside the next
        # block's prose. Barriers at both ends keep each block's floats inside
        # it, whatever order the chapter inputs them in.
        f.write('% Keep this block\'s floats inside this block (see placeins).\n')
        f.write('\\FloatBarrier\n\n')
        intro = cfg.get('intro_tex')
        if intro:
            f.write(intro.rstrip() + '\n\n')
        names = order if order else (tabs + figs)
        for n in names:
            if os.path.isfile(os.path.join(outdir, n + '.tex')):
                f.write('\\input{\\MaestroRoot %s.tex}\n' % n)
        f.write('\n\\FloatBarrier\n')
    return path


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def emit_preview(cfg, outdir):
    """A standalone wrapper so the fragments can be proofed without the TRM.

    Compile with `pdflatex preview_<block>.tex` from inside outdir. Redefining
    \\MaestroRoot to empty is also the live test that the path indirection works
    -- the same hook the TRM uses to reach these files from latex/TRM/.

    The name carries the block because a chip's blocks all render into one
    outdir; a fixed "preview.tex" meant generating the second block silently
    replaced the first block's proof sheet.
    """
    block = cfg.get('block', 'block')
    path = os.path.join(outdir, 'preview_%s.tex' % slug(block))
    with open(path, 'w') as f:
        f.write('%% maestro2tex -- standalone proof sheet. Build with:\n')
        f.write('%%     cd %s && pdflatex %s\n' % (outdir, os.path.basename(path)))
        f.write('%% The TRM does NOT use this file; it inputs %s.tex directly.\n'
                % block)
        f.write('\\documentclass[11pt]{article}\n')
        f.write('\\usepackage[margin=1in]{geometry}\n')
        for p in ('graphicx', 'booktabs', 'caption', 'pgfplots', 'xcolor',
                  'siunitx', 'amsmath', 'placeins'):
            f.write('\\usepackage{%s}\n' % p)
        f.write('\\def\\MaestroRoot{}\n')
        f.write('\\begin{document}\n')
        f.write('\\section*{%s --- generated characterisation}\n' % texesc(block))
        f.write('\\input{%s.tex}\n' % block)
        f.write('\\end{document}\n')
    return path


def main():
    ap = argparse.ArgumentParser(
        description='Turn a Cadence Maestro run into TRM-ready LaTeX.')
    ap.add_argument('--results', required=True,
                    help='Maestro run directory (…/results/maestro/Interactive.NN)')
    ap.add_argument('--config', required=True, help='JSON description of the testbench')
    ap.add_argument('--outdir', required=True, help='output directory for LaTeX + data')
    ap.add_argument('--tex-root', default=None,
                    help='path prefix the TRM uses to reach outdir '
                         '(default: taken from the config, else ../analog/)')
    ap.add_argument('--ocean', default=DEFAULT_OCEAN, help='OCEAN binary')
    ap.add_argument('--setup', default=DEFAULT_SETUP,
                    help='shell script sourced before OCEAN (licences, PATH)')
    ap.add_argument('--no-extract', action='store_true',
                    help='skip OCEAN and re-render from the CSVs already in outdir')
    ap.add_argument('--max-points', type=int, default=400,
                    help='decimate curves to at most this many points (0 = keep all)')
    args = ap.parse_args()

    results = os.path.abspath(os.path.expanduser(args.results))
    outdir = os.path.abspath(os.path.expanduser(args.outdir))
    with open(os.path.expanduser(args.config)) as f:
        cfg = json.load(f)
    texroot = args.tex_root or cfg.get('tex_root', '../analog/')
    block = cfg.get('block', 'block')

    rawdir = os.path.join(outdir, 'data', 'raw')
    for d in (outdir, os.path.join(outdir, 'data'), rawdir):
        if not os.path.isdir(d):
            os.makedirs(d)

    print('maestro2tex: %s' % block)
    have_results = os.path.isdir(results)
    if not have_results and not args.no_extract:
        die('results directory not found: %s' % results)

    if have_results:
        corners = discover_corners(results, expand_points(cfg.get('points')))
        if not corners:
            die('no corner directories (1, 2, 3, ...) under %s' % results)
        save_corners(rawdir, block, corners)
    else:
        # --no-extract with the run gone: render from the CSVs and the corner
        # list cached beside them.
        corners = load_corners(rawdir, block)
        if not corners:
            die('results directory not found and no cached corner list at %s\n'
                '       (re-extract once from a live run to write the cache)'
                % corner_cache_path(rawdir, block))
        info('results directory is gone; using the corner list cached with the CSVs')
    print('  corners: %s' % ', '.join('%s=%s' % (c[0], c[1]) for c in corners))
    if have_results:
        found = discover_tests(results, corners)
        print('  tests in run: %s' % ', '.join(found))
        unknown = sorted(set(test_dir(t, s) for t, s in cfg['tests'].items()
                             if test_dir(t, s) not in found))
        if unknown:
            info('config names test directories absent from this run: %s'
                 % ', '.join(unknown))

    if not args.no_extract:
        ocn = build_ocn(results, corners, cfg, rawdir)
        # Per block, for the same reason preview.tex is: one outdir, many blocks.
        stem = os.path.join(outdir, 'data', 'extract_%s' % slug(cfg.get('block', 'block')))
        ocn_path = stem + '.ocn'
        with open(ocn_path, 'w') as f:
            f.write(ocn)
        log_path = stem + '.log'
        print('  extracting through OCEAN (%s)' % args.ocean)
        run_ocean(ocn_path, args.ocean, args.setup, log_path)
        n = len([x for x in os.listdir(rawdir) if x.endswith('.csv')])
        print('  extracted %d signal file(s)' % n)
    else:
        print('  --no-extract: reusing CSVs in %s' % rawdir)

    print('  rendering LaTeX')
    written = render(cfg, corners, rawdir, outdir, texroot, args.max_points)
    # A companion config contributes fragments to a block that another config
    # already owns -- it needs a different --results (a different Maestro run),
    # but its figures belong in the owner's section. It emits no master of its
    # own; the owner lists the fragment names in its `order`.
    if cfg.get('emit_master', True):
        master = emit_master(cfg, outdir, texroot, written, corners)
        emit_preview(cfg, outdir)
        print('  wrote %d fragment(s) + %s + preview_%s.tex'
              % (len(written), os.path.basename(master), slug(cfg.get('block', 'block'))))
        print('\nInclude in the TRM with:\n    \\input{%s%s.tex}\n'
              % (texroot, cfg.get('block', 'block')))
    else:
        print('  wrote %d fragment(s); no master (emit_master=false)' % len(written))
        print('\nAdd these to the owning block\'s `order`:\n    %s\n'
              % '\n    '.join(sorted(os.path.basename(p)[:-4] for p in written)))


if __name__ == '__main__':
    main()
