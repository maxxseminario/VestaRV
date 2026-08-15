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
        # CPR3/R3 TCM apertures (MULTICORE chapter, 2026-08). RTL signal names,
        # same class as the arbiter's s_* group above: the tile's external TCM
        # read port (hart_tile.vhd:319-322) and the arbiter's stall input
        # (mp_arbiter.vhd:108). Verified free of collision with every generated
        # name at the time of writing; the chapter uses tcm_ext_done and s_stall
        # today and the rest of the port is listed with them.
        'tcm_ext_req', 'tcm_ext_addr', 'tcm_ext_rdata', 'tcm_ext_done', 's_stall',
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
        # P-series privileged architecture (PRIVARCH chapter). These are CORE
        # CSRs and CSR FIELDS, not memory-mapped registers: they live in the
        # CPU's control/status register file, so the generator's memory map
        # cannot know them and never will. Listed literally because the
        # checker matches literally (no wildcard, and the x/y/n/h placeholder
        # model only substitutes digits).
        'mstatus', 'mstatush', 'mtvec', 'mie', 'mip', 'mscratch', 'mepc',
        'mcause', 'mtval', 'mtrapctl', 'mcounteren', 'misa',
        # ID-series (2026-08-04): the machine INFORMATION registers, same
        # reason as the block above -- core CSRs, not memory-mapped ones.
        # mhartid (0xF14) is already listed with the CSR group at the top;
        # these are its four neighbours, 0xF11-0xF13 and 0xF15, which ID3
        # admitted to the decode map (they read zero and never trap).
        'mvendorid', 'marchid', 'mimpid', 'mconfigptr',
        'pmpcfg', 'pmpcfg0', 'pmpcfg1', 'pmpcfg2', 'pmpcfg3',
        'pmpaddr', 'pmpaddr0', 'pmpaddr1', 'pmpaddr2', 'pmpaddr3',
        'pmpaddr4', 'pmpaddr5', 'pmpaddr6', 'pmpaddr7', 'pmpaddr8',
        'pmpaddr9', 'pmpaddr10', 'pmpaddr11', 'pmpaddr12', 'pmpaddr13',
        'pmpaddr14', 'pmpaddr15',
        # ...and the fields inside those CSRs, same reason
        'MIE', 'MPIE', 'MPP', 'MPRV', 'TW', 'MSIE', 'MTIE', 'MEIE',
        'MSIP', 'MTIP', 'MEIP', 'BASE', 'MODE', 'LEGACY',
        'CY', 'TM', 'IR', 'HPM3', 'HPM4',
        # D-series debug (DEBUG chapter, 2026-08). Three families, none of them
        # memory-mapped and none of them ever knowable to the generator's
        # memory map: the hart's Debug-Mode CSRs, the Debug Module's registers
        # (which live behind the 7-bit DMI, not in the 32-bit address space),
        # and the JTAG transport's data registers. Verified at the time of
        # writing that NONE of these collides with a real generated name, so
        # this block exempts nothing the checker was previously judging.
        # Debug-Mode CSRs (0x7B0-0x7B3) and the fields of dcsr
        'dcsr', 'dpc', 'dscratch0', 'dscratch1',
        'xdebugver', 'ebreakm', 'ebreaku', 'cause', 'step', 'prv',
        # Debug Module registers, at their DMI addresses
        'data0', 'dmcontrol', 'dmstatus', 'hartinfo', 'haltsum0', 'haltsum1',
        'abstractcs', 'command', 'abstractauto', 'progbuf0', 'progbuf1',
        'dmcs2',
        # ...dmcontrol fields
        'dmactive', 'ndmreset', 'hartreset', 'hasel', 'haltreq', 'resumereq',
        'hartsel', 'setresethaltreq', 'clrresethaltreq',
        # ...dmstatus fields (the any/all pairs, and the capability bits)
        'version', 'authenticated', 'hasresethaltreq', 'impebreak',
        'allhalted', 'anyhalted', 'allrunning', 'anyrunning',
        'allunavail', 'anyunavail', 'allnonexistent', 'anynonexistent',
        'allresumeack', 'anyresumeack', 'allhavereset', 'anyhavereset',
        # ...abstractcs and command fields
        'busy', 'cmderr', 'datacount', 'progbufsize',
        'aarsize', 'transfer', 'write', 'postexec', 'regno',
        # JTAG transport: dtmcs fields and the dmi data-register fields
        'abits', 'dmistat', 'idle', 'dmireset', 'dmihardreset',
        'address', 'data', 'op',
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
        # MULTICORE, PRIVARCH and DEBUG are concept chapters, not peripheral
        # chapters: no peripheral of that name exists, so the "is this block in
        # the configuration?" skip would silently retire their gate. Judge them
        # always (their non-memory-mapped names are covered by EXEMPT above).
        # DEBUG joined at the D-series TRM chapter (2026-08) -- and note it
        # would have been SKIPPED, silently and with a reassuring message, had
        # it not been added here. That is the failure mode this list exists for.
        if stem not in ('MULTICORE', 'PRIVARCH', 'DEBUG') and stem not in present:
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
