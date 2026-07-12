#!/usr/bin/env python3
"""Convert a diagram SVG to a cropped PDF without inkscape.

The source SVGs contain literal LaTeX macros in their text labels (they were
authored for inkscape's LaTeX-export flow). This script resolves those macros
to plain text (\textoverline -> Unicode combining overlines), converts via
LibreOffice headless, and crops to content with ghostscript.

Usage: python3 svg2pdf.py <figure-name-without-extension> [...]
Run from this directory. Requires: soffice, gs.
"""
import re, os, sys, subprocess, tempfile

def overline(txt):
    return ''.join(c + '̅' for c in txt)

def preprocess(svg):
    prev = None
    while prev != svg:
        prev = svg
        svg = re.sub(r'\\(?:texttt|textrm|bitfield|register|pin|peripheral)\{([^{}]*)\}', r'\1', svg)
        svg = re.sub(r'\\textoverline\{([^{}]*)\}', lambda m: overline(m.group(1)), svg)
    svg = svg.replace('$', '')
    leftovers = set(re.findall(r'\\[a-zA-Z]+', svg))
    if leftovers:
        print('  WARNING: unresolved macros:', leftovers)
    return svg

for name in sys.argv[1:]:
    print(name)
    with tempfile.TemporaryDirectory() as td:
        open(os.path.join(td, name + '.svg'), 'w', encoding='utf-8').write(
            preprocess(open(name + '.svg', encoding='utf-8').read()))
        subprocess.run(['soffice', '--headless', '--convert-to', 'pdf',
                        os.path.join(td, name + '.svg'), '--outdir', td],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        pdf = os.path.join(td, name + '.pdf')
        out = subprocess.run(['gs', '-q', '-dBATCH', '-dNOPAUSE', '-sDEVICE=bbox', pdf],
                             stderr=subprocess.PIPE).stderr.decode()
        m = re.search(r'%%HiResBoundingBox: ([\d.+-]+) ([\d.+-]+) ([\d.+-]+) ([\d.+-]+)', out)
        x0, y0, x1, y1 = (float(v) for v in m.groups())
        x0, y0 = max(0, x0 - 3), max(0, y0 - 3)
        w, h = x1 - x0 + 3, y1 - y0 + 3
        subprocess.run(['gs', '-q', '-dBATCH', '-dNOPAUSE', '-sDEVICE=pdfwrite',
                        '-dDEVICEWIDTHPOINTS=%g' % w, '-dDEVICEHEIGHTPOINTS=%g' % h,
                        '-dFIXEDMEDIA', '-o', name + '.pdf',
                        '-c', '<</BeginPage {-%g -%g translate}>> setpagedevice' % (x0, y0),
                        '-f', pdf], check=True)
        print('  -> %s.pdf (%.0fx%.0f pt)' % (name, w, h))
