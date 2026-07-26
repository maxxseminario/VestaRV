#!/usr/bin/env python3
'''check_intro_names.py — cross-check the register/bitfield names used in the
hand-written peripheral intro chapters against the names the generator actually
emits.

WHY: the intros are prose, so nothing forces their \\register{}/\\bitfield{}
spellings to match the generated register tables that sit a page later in the
SAME chapter. The 2026-07-25 TIMER bug (31 references to TCAP0IF/TCMP2RST, which
exist nowhere — the real bitfields are CAP0IF/CMP2RST) shipped in the TRM for
that reason.

NAME MODEL. Two spellings are legitimate in prose:
  * a CONCRETE name, exactly as emitted for an instance    (TIM0CMP0, SPI0CR)
  * a TEMPLATE name carrying a placeholder letter          (TIMxCMP0, SPIxCR)
    - x = peripheral instance number
    - y = sub-unit index within a peripheral (capture/compare unit, e.g. CAPyIF)
    - n = channel index (DMA/EVFAB channels, e.g. EVFCHnCFG)
    - h = hart index (CLINT, e.g. MSIPh)
A token matches if it is known verbatim, or if substituting digits for its
placeholder letters yields a known name.

Run from platform/common/. Exit 0 = clean, 1 = unmatched names found.
Reads config/MemoryMap.json (concrete names) + python/generate.py (template
names), so `make generate` must have run at least once.
'''

import json
import os
import re
import sys

PLACEHOLDERS = 'xynh'


def concrete_names(path):
    '''Names as actually emitted, from the generated memory map.'''
    names = set()
    with open(path) as f:
        mm = json.load(f)
    for p in mm.get('Peripherals', []):
        for key in ('PeripheralName', 'PeripheralTemplateName'):
            v = p.get(key)
            if isinstance(v, str):
                names.add(v)
        for r in p.get('Registers', []):
            v = r.get('RegisterName')
            if isinstance(v, str):
                names.add(v)
            for b in r.get('BitFields', []):
                v = b.get('BitFieldName')
                if isinstance(v, str):
                    names.add(v)
    return names


def template_names(path):
    '''Template spellings (the ones carrying an "x"), straight from the
       generator source — these never appear in the resolved memory map.'''
    names = set()
    with open(path) as f:
        src = f.read()
    for pat in (r"nameTemplate\s*=\s*'([^']+)'",
                r"registerPrefix\s*=\s*'([^']+)'",
                r"bitFieldPrefix\s*=\s*'([^']+)'",
                r"BitField\(\s*name\s*=\s*'([^']+)'",
                r"RegisterTemplate\([^)]*?nameTemplate\s*=\s*'([^']+)'"):
        names.update(re.findall(pat, src))
    return names


def expansions(tok):
    '''Every digit substitution of the placeholder letters in tok.'''
    out = {tok}
    for ch in PLACEHOLDERS:
        if ch not in tok:
            continue
        nxt = set()
        for t in out:
            nxt.add(t)
            for d in '0123456789':
                nxt.add(t.replace(ch, d))
        out = nxt
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    mmPath = os.path.join(root, 'config', 'MemoryMap.json')
    genPath = os.path.join(root, 'python', 'generate.py')
    introDir = os.path.join(root, 'latex', 'PeripheralIntroductions')
    if not os.path.isfile(mmPath):
        print('check_intro_names: %s missing — run `make generate` first.' % mmPath)
        return 1

    known = concrete_names(mmPath) | template_names(genPath)
    # Placeholder-expanded closure, so a template name in the model also
    # matches a concrete spelling in prose and vice versa.
    knownAll = set()
    for k in known:
        knownAll |= expansions(k)

    # Only judge chapters whose peripheral this build actually instantiates.
    # An absent peripheral contributes NO names to the model, so every token in
    # its chapter would flag — pure noise, not drift. (Optional blocks are
    # generated programmatically in places, so parsing generate.py does not
    # recover them either.)
    with open(mmPath) as f:
        present = set()
        for p in json.load(f).get('Peripherals', []):
            for key in ('PeripheralName', 'PeripheralTemplateName'):
                v = p.get(key)
                if isinstance(v, str):
                    present.add(re.sub(r'[0-9x]+$', '', v).upper())

    # Tokens that are legitimately not memory-mapped register names.
    EXEMPT = {
        # CSRs and RTL signal names (the macro is only a monospace wrapper)
        'mhartid', 'mtime', 'mclk', 'req', 'done', 'rdata', 'meip', 'msip', 'mtip',
        's_en', 's_addr', 's_rdata', 'gnt', 'level', 'in_service', 'need_release',
        # deliberate references to RETIRED registers (M19 killed the SYSTEM
        # vectored controller; the prose names them to say they are gone)
        'IRQENU', 'IRQENx', 'IRQPRIx', 'IRQCR',
        # conceptual 64-bit CLINT names; the registers are MTIMEL/MTIMEH pairs
        'MTIME', 'MTIMECMP', 'MTIMECMP0', 'MTIMECMPx',
        # PENDL/M/U and INSVCL/M/U written with an x standing for the L/M/U
        # word suffix — the placeholder model only substitutes digits
        'PENDx', 'INSVCx',
        # EVFAB 'OWNER' — reads as a concept, not a register in the EVFAB map.
        # Left as-is pending a human read of that paragraph.
        'OWNER',
        # generic field shorthands used mid-sentence ("seizes the DIR/OUT/REN
        # controls"), where the per-port spelling would be noise
        'DIR', 'OUT', 'REN', 'LEN', 'EN',
    }

    skipped = []
    bad = []
    for fn in sorted(os.listdir(introDir)):
        if not fn.endswith('.tex'):
            continue
        stem = fn.split('-')[0].upper()
        # intro filename stem -> peripheral name in the memory map, where the
        # chapter is named for the protocol but the block for its registers
        stem = {'ONEWIRE': 'OW', 'I2CT': 'I2CT', 'IRQROUTER': 'IRQROUTER'}.get(stem, stem)
        if stem not in ('MULTICORE',) and stem not in present:
            skipped.append(fn.split('-')[0])
            continue
        with open(os.path.join(introDir, fn)) as f:
            text = f.read()
        seen = set()
        for m in re.finditer(r'\\(register|bitfield)\{([^{}]*)\}', text):
            tok = m.group(2).replace('\\_', '_').strip()
            if not tok or '\\' in tok:
                continue           # macro-valued, e.g. \MutexBaseAddress
            if not re.match(r'^[A-Za-z][A-Za-z0-9_]*$', tok):
                continue           # not an identifier (prose slipped into the macro)
            if tok in EXEMPT:
                continue
            if tok in knownAll or expansions(tok) & knownAll:
                continue
            if tok in seen:
                continue
            seen.add(tok)
            bad.append((fn, m.group(1), tok))

    if skipped:
        print('check_intro_names: skipped %d chapter(s) whose peripheral is not in this '
              'configuration: %s' % (len(skipped), ', '.join(sorted(set(skipped)))))
    if not bad:
        print('check_intro_names: OK — every \\register{}/\\bitfield{} name in the '
              'intro chapters matches a generated name.')
        return 0

    print('check_intro_names: %d name(s) in the intro chapters match NOTHING the '
          'generator emits:' % len(bad))
    cur = None
    for fn, kind, tok in bad:
        if fn != cur:
            print('  %s' % fn)
            cur = fn
        print('      \\%-9s %s' % (kind, tok))
    print('\nEach is either a typo in the prose or a name the generator should be '
          'emitting. The register tables in the same chapter are generated, so the '
          'prose is usually the side that is wrong.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
