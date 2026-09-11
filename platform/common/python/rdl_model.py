#!/usr/bin/env python3
"""rdl_model.py -- compile a VestaRV .rdl description into the generator's own
register objects.

This is the whole of the SystemRDL integration. Every emitter in this repo
(rdl_latex, rdl_cheader, rdl_vhdl, rdl_configurator) consumes RegisterTemplate /
BitField objects, exactly as LatexUserGuide.py and ChipGenerator.py already do,
so an .rdl description reaches the TRM, the C header, the RTL package and the
configurator through code that is already proven rather than through four new
formatters. The consequence is that a peripheral moved onto SystemRDL emits
byte-identical output, which is what //platform/common:rdl_vs_generator_test
asserts.

Since report R5 this is not only a cross-check but THE SOURCE: generate.py builds
eighteen of the twenty-two peripheral templates by calling registerTemplatesFor()
and carries no register data of its own for them. config/rdl.json's registerSource
field says which, and why the other four are still hand-written.

Two properties are not inferred from SystemRDL semantics but read from
hdl/common/regs/rdl/vesta_udp.rdl:

  vesta_access        the generator's access code (rw, r, rw1, w1, ...). It is
                      re-derived here from sw/hw/onwrite/singlepulse and a
                      mismatch is an error, so the redundancy cannot rot.
  vesta_named_values  whether the field's enum member identifiers are emitted as
                      value-description names (and therefore become C macros).

Reserved bits are NOT written in SystemRDL -- they are simply absent. The
generator requires every bit of a register to belong to a BitField, so the gaps
are filled here with `unused=True` fields, which is also the check that an .rdl
register is fully specified.
"""

import ast
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from BitField import BitField
from Register import RegisterTemplate

RDL_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))),
    'hdl', 'common', 'regs', 'rdl')

# The generator's access codes, as a function of the SystemRDL properties.
# (sw, hw, onwrite, singlepulse) -> code. sw/hw are the AccessType names.
_ACCESS_FROM_RDL = {
    ('rw', 'r', None, False): 'rw',
    ('rw', 'na', None, False): 'rw',
    ('r', 'w', None, False): 'r',
    ('r', 'na', None, False): 'r',
    ('rw', 'w', 'woclr', False): 'rw1',
    ('rw', 'rw', 'woclr', False): 'rw1',
    ('rw', 'w', 'woset', False): 'rw0',
    ('w', 'r', None, True): 'w1',
    ('w', 'r', None, False): 'w',
    ('w', 'na', None, False): 'w',
    # --- added by the 20-block sweep (R2, 2026-09-10) -------------------------
    # A plain read/write register the HARDWARE ALSO WRITES. The generator has no
    # separate code for it -- it is still 'rw' to software -- but hw=r would be
    # a lie about GPIO's PxOUT (the event fabric's task_outset/task_outclr write
    # it), TIMER's TIMxCR.TEN (task_start/task_stop), TIMxVAL and CLINT's mtime
    # halves (free-running counters), NPU's NPUTHINK (NpuDone clears it),
    # SPIxTX / RTCxSEC / RTCxSUB (staged into another clock domain), DMAxCRC
    # (the engine is the accumulator's only driver), MUTEXn (a read claims it)
    # and IRQROUTER's CLAIM (a read sets in_service).
    ('rw', 'rw', None, False): 'rw',
    # GPIO's PxOUTS / PxOUTT and EVFAB's EVFCHENSET are write-one-to-SET and
    # write-one-to-TOGGLE aliases of a register the hardware also writes. The
    # generator spells all three of PxOUTS / PxOUTC / PxOUTT 'rw1' -- its code
    # says "a written 1 acts", not which direction -- so woset and wot land on
    # 'rw1' exactly as woclr already does. The hw=w and hw=rw forms are both
    # here because EVFCHENSET's storage is software-only while PxOUT's is not.
    ('rw', 'rw', 'woset', False): 'rw1',
    ('rw', 'rw', 'wot', False): 'rw1',
    ('rw', 'w', 'wot', False): 'rw1',
}

# A field named RESERVED (or RESERVED<n>) is the SystemRDL spelling of a
# generator `unused` BitField. SystemRDL leaves reserved bits IMPLICIT and
# _fillReserved below puts them back, which works everywhere except a register
# that is reserved in its ENTIRETY -- PWMxDTY2/DTY3/DT, OWxSPU, RTCxTRIM,
# DMAxDESC, EVFIE and EVFAB's dead CH8CFG..CH15CFG half. Such a register has no
# fields at all, and systemrdl-compiler refuses it outright ("Register 'X' does
# not contain any fields"). Writing one explicit RESERVED field keeps the
# description legal and still reaches the generator as `unused`.
_RESERVED_RE = 'RESERVED'


def _rdlAccess(field):
    """(sw, hw, onwrite, onread, singlepulse) as SystemRDL spells them.

       The generator access code below collapses this tuple: `rw` is the answer
       for hw=r, hw=na AND hw=rw, and `rw1` for woclr, woset and wot alike. That
       is right for a published access column and wrong for a decode, which has
       to know which side owns the flop and which direction a written 1 acts in.
       The tuple is carried on the BitField as RdlAccess so an emitter can ask.
    """
    onwrite = field.get_property('onwrite')
    onread = field.get_property('onread')
    return (field.get_property('sw').name,
            field.get_property('hw').name,
            onwrite.name if onwrite is not None else None,
            onread.name if onread is not None else None,
            bool(field.get_property('singlepulse')))


def _accessCode(field):
    """The generator access code implied by a field's SystemRDL properties."""
    sw, hw, onwrite, _onread, sp = _rdlAccess(field)
    key = (sw, hw, onwrite, sp)
    if key not in _ACCESS_FROM_RDL:
        raise Exception('rdl_model: no generator access code for SystemRDL '
                        'sw=%s hw=%s onwrite=%s singlepulse=%s on field %s. Add the '
                        'combination to _ACCESS_FROM_RDL, or write the field the way '
                        'the existing peripherals write it.' % (sw, hw, onwrite, sp,
                                                                field.get_path()))
    return _ACCESS_FROM_RDL[key]


# ---------------------------------------------------------------------------
# PARAMETERISED BLOCKS (report R7). Four blocks -- CLINT, MUTEX, IRQROUTER and
# PWRCTRL -- size their register SET and their FIELD GEOMETRY off the
# configuration, so they are written as SystemRDL components with parameters and
# register arrays and elaborated here with the generator's own values. SystemRDL
# carries the structure. It has no syntax for three things the generator's
# published map needs, and hdl/common/regs/rdl/vesta_udp.rdl carries those:
#
#   vesta_name / desc {expression}   a register array is MSIP[0], not MSIP0, and
#                                    has ONE desc; the published names are MSIP0
#                                    and the prose says "hart 0"
#   vesta_live                       a field that exists only above a hart count
#   vesta_values_*                   an enumeration whose member COUNT is a
#                                    parameter (a SystemRDL enum is static, and
#                                    its values must fit the field)
#
# All three act only inside an addrmap that sets `vesta_indexed = true`, so the
# other eighteen descriptions are loaded character for character as before --
# which matters, because their prose contains braces of its own ({SRC,DST,LEN},
# "{4,8}", "{seconds, subsecond}").
# ---------------------------------------------------------------------------

_BRACE_RE = re.compile(r'\{([^{}]+)\}')

_EXPR_FUNCS = {'min': min, 'max': max}


def _evalExpr(expr, scope, where):
    """One {expression}: integer arithmetic over the block's parameters and `i`.

       Deliberately not eval(): an AST walk over a fixed node set, so a
       description cannot reach anything but the numbers it is given."""
    try:
        tree = ast.parse(expr.strip(), mode='eval')
    except SyntaxError:
        raise Exception('rdl_model: %s: "{%s}" is not an expression' % (where, expr))

    def walk(node):
        if isinstance(node, ast.Expression):
            return walk(node.body)
        if isinstance(node, ast.Num):                      # py3.6 compatibility
            return node.n
        if isinstance(node, ast.Constant) and isinstance(node.value, int):
            return node.value
        if isinstance(node, ast.Name):
            if node.id not in scope:
                raise Exception('rdl_model: %s: "{%s}" reads %s, which is neither a '
                                'parameter of this block nor the index `i`. The names in '
                                'scope are %s.'
                                % (where, expr, node.id, ', '.join(sorted(scope))))
            return scope[node.id]
        if isinstance(node, ast.BinOp):
            a, b = walk(node.left), walk(node.right)
            if isinstance(node.op, ast.Add):
                return a + b
            if isinstance(node.op, ast.Sub):
                return a - b
            if isinstance(node.op, ast.Mult):
                return a * b
            if isinstance(node.op, (ast.Div, ast.FloorDiv)):
                return a // b
            if isinstance(node.op, ast.Mod):
                return a % b
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            return -walk(node.operand)
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id in _EXPR_FUNCS and not node.keywords):
            return _EXPR_FUNCS[node.func.id](*[walk(a) for a in node.args])
        raise Exception('rdl_model: %s: "{%s}" uses something this renderer does not '
                        'allow. Permitted: the block parameters, `i`, integers, '
                        '+ - * / %% ( ) and min/max.' % (where, expr))

    return walk(tree)


def _render(text, scope, where):
    """Substitute every {expression} in a name or a description."""
    if not text or '{' not in text:
        return text

    def one(m):
        value = _evalExpr(m.group(1), scope, where)
        return value if isinstance(value, str) else str(value)

    return _BRACE_RE.sub(one, text)


def _blockParameters(node):
    """{name: value} of an elaborated addrmap's own parameters, ints and strings."""
    out = {}
    for param in getattr(node.inst, 'parameters', []) or []:
        value = param.get_value()
        if isinstance(value, bool):
            continue
        if isinstance(value, (int, str)):
            out[param.name] = value
    return out


def _componentIndex(node, top):
    """`i` for a register: its array index, plus the vesta_index its declaration
       (or its enclosing regfile's) gives the first element."""
    base = None
    arr = None
    walk = node
    topPath = top.get_path()
    while walk is not None and walk.get_path() != topPath:
        if arr is None and walk.current_idx:
            arr = walk.current_idx[0]
        if base is None:
            try:
                base = walk.get_property('vesta_index')
            except LookupError:
                base = None
        walk = walk.parent
    return (base or 0) + (arr or 0)


def _live(node):
    """vesta_live, defaulting to live where the property is not set."""
    try:
        value = node.get_property('vesta_live')
    except LookupError:
        return True
    return True if value is None else bool(value)


def _valueDescriptions(field, scope=None, where=None):
    """The generator's (value, description, name) tuples for an encoded field.

    These are assigned to BitField.ValueDescriptions DIRECTLY rather than passed
    to the constructor, because the constructor's third tuple element is a name
    SUFFIX that it concatenates onto the field name: handing it a finished name
    such as SPIDL_8 produces SPIDLSPIDL_8. The .rdl enum member identifier is the
    emitted name, whole, exactly as vesta_udp.rdl's vesta_named_values says --
    unless the member sets SystemRDL's own `name` property, which a
    parameterised block uses to render the index into it (MTXOWN{i}_FREE).

    A parameterised block may then APPEND a run of value descriptions whose
    count is a parameter (vesta_values_*), which is the only way to enumerate
    "one owner marker per hart" for a field that is 4 bits wide here and 6 on
    argus: a SystemRDL enum is a static type whose member values must fit the
    field, and the compiler rejects the widest one on the narrowest field.
    """
    named = bool(field.get_property('vesta_named_values'))
    out = []
    enc = field.get_property('encode')
    if enc is not None:
        for member in enc:
            name = ''
            if named:
                name = getattr(member, 'rdl_name', None) or member.name
                if scope is not None:
                    name = _render(name, scope, where)
            desc = member.rdl_desc or ''
            if scope is not None:
                desc = _render(desc, scope, where)
            out.append((int(member.value), desc, name))
    if scope is None:
        return out
    count = field.get_property('vesta_values_count')
    if count:
        first = field.get_property('vesta_values_first') or 0
        nameT = field.get_property('vesta_values_name')
        descT = field.get_property('vesta_values_desc')
        for v in range(int(count)):
            vs = dict(scope)
            vs['v'] = v
            out.append((int(first) + v,
                        _render(descT or '', vs, where),
                        _render(nameT, vs, where) if (nameT and named) else ''))
    return out


def _fillReserved(rt, size, claimed):
    """Add the `unused` BitFields SystemRDL leaves implicit, as maximal runs."""
    run = None
    for bit in range(size + 1):
        used = (bit < size) and (bit in claimed)
        if not used and bit < size:
            if run is None:
                run = [bit, bit]
            else:
                run[1] = bit
        else:
            if run is not None:
                rt.AddBitField(BitField(msb=run[1], lsb=run[0], unused=True))
                run = None


def _registerNodes(node):
    """Every register of one addrmap, arrays unrolled and regfiles flattened.

       A regfile is how a block whose registers INTERLEAVE on a stride is
       written: CLINT's MTIMECMPnL/H are one 8-byte pair per hart, and two
       interleaved REGISTER arrays are rejected outright ("Instance 'MTIMECMPH'
       at offset +0x34:0x5B overlaps with 'MTIMECMPL'"). The generator's map is
       flat, so the hierarchy is flattened back out here. No unparameterised
       block uses a regfile, so this yields exactly what node.registers() did.
    """
    from systemrdl.node import RegNode
    return [n for n in node.descendants(unroll=True) if isinstance(n, RegNode)]


def registerTemplatesFromNode(node, wordBase=0):
    """The RegisterTemplate list of one compiled addrmap node, slot-ordered."""
    templates = []
    indexed = bool(node.get_property('vesta_indexed'))
    params = _blockParameters(node) if indexed else {}
    base = node.absolute_address or 0
    for reg in _registerNodes(node):
        if indexed and not _live(reg):
            continue
        scope = None
        if indexed:
            scope = dict(params)
            scope['i'] = _componentIndex(reg, node)
        where = reg.get_path()
        offset = (reg.absolute_address or 0) - base
        if offset % 4 != 0:
            raise Exception('rdl_model: register %s is at byte offset %d, which is not a '
                            'word boundary; the generator addresses registers by 4-byte slot.'
                            % (where, offset))
        size = reg.get_property('regwidth')
        name = reg.inst_name
        if indexed:
            name = _render(reg.get_property('vesta_name') or name, scope, where)
        rt = RegisterTemplate(nameTemplate=name,
                              registerMemorySlot=offset // 4,
                              description=_render(reg.get_property('desc') or '', scope, where)
                              if indexed else (reg.get_property('desc') or ''),
                              size=size)
        claimed = set()
        for field in reg.fields():
            msb0, lsb0 = field.msb, field.lsb
            if msb0 < lsb0:
                msb0, lsb0 = lsb0, msb0
            if field.inst_name.rstrip('0123456789') == _RESERVED_RE:
                # Explicitly written reserved bits (see _RESERVED_RE above).
                rt.AddBitField(BitField(msb=msb0, lsb=lsb0, unused=True))
                claimed.update(range(lsb0, msb0 + 1))
                continue
            if indexed and not _live(field):
                # vesta_live false: the field does not exist in this
                # configuration and its bits fall into the reserved fill.
                continue
            code = _accessCode(field)
            declared = field.get_property('vesta_access')
            if declared is not None and declared != code:
                raise Exception('rdl_model: %s declares vesta_access "%s" but its SystemRDL '
                                'properties mean "%s". The two must agree; fix whichever is '
                                'wrong rather than deleting the property.'
                                % (field.get_path(), declared, code))
            msb, lsb = field.msb, field.lsb
            if msb < lsb:
                msb, lsb = lsb, msb
            reset = field.get_property('reset')
            fieldName = field.inst_name
            fieldDesc = field.get_property('desc') or ''
            if indexed:
                fieldName = _render(field.get_property('vesta_name') or fieldName, scope, where)
                fieldDesc = _render(fieldDesc, scope, where)
            bf = BitField(name=fieldName, msb=msb, lsb=lsb,
                          description=fieldDesc,
                          accessibility=code,
                          resetValue=int(reset) if reset is not None else 0)
            # The uncollapsed SystemRDL tuple, for emitters that need the half
            # the access code drops; see _rdlAccess.
            bf.RdlAccess = _rdlAccess(field)
            # see the docstring of _valueDescriptions
            bf.ValueDescriptions = _valueDescriptions(field, scope, where)
            rt.AddBitField(bf)
            claimed.update(range(lsb, msb + 1))
        _fillReserved(rt, size, claimed)
        rt.CheckBitFields()
        templates.append(rt)
    templates.sort(key=lambda t: t.RegisterMemorySlot)
    if wordBase and templates and templates[0].RegisterMemorySlot != wordBase:
        raise Exception('rdl_model: %s declares vesta_word_base %d but its first register is '
                        'at word %d' % (node.get_path(), wordBase, templates[0].RegisterMemorySlot))
    return templates


class RdlBlock(object):
    """One compiled .rdl addrmap: the peripheral template it belongs to, its
       register templates, and the block-level metadata the emitters need."""

    def __init__(self, node):
        self.Node = node
        self.Name = node.inst_name
        # A block that is not a memory-mapped peripheral (the Debug Module, whose
        # registers live in the DMI address space) declares no vesta_peripheral,
        # because there is no generate.py PeripheralTemplate for it. It still
        # needs a NAME for its table captions and labels, and SystemRDL's own
        # `name` property is it.
        self.PeripheralTemplateName = (node.get_property('vesta_peripheral')
                                       or node.get_property('name')
                                       or node.inst_name)
        self.Vector = node.get_property('vesta_vector')
        self.WordBase = node.get_property('vesta_word_base') or 0
        self.Description = node.get_property('desc') or ''
        self.RegisterTemplates = registerTemplatesFromNode(node, self.WordBase)


def compileFiles(paths, top=None, incdirs=None, parameters=None, defines=None):
    """Compile .rdl files and return the RdlBlock for `top` (or every addrmap
       that names a vesta_peripheral, when `top` is None).

       `parameters` are SystemRDL component parameter overrides applied at
       ELABORATION (numHarts, numMutexes, masterW(), vectorsCount ...).
       `defines` are preprocessor symbols applied at COMPILE, for the two things
       a parameter cannot do: instantiate a register conditionally and choose
       between two descriptions. Every guard is written so that NO defines is
       the default five-hart chip, which is what the block's own gates grade.
    """
    from systemrdl import RDLCompiler
    from systemrdl.messages import MessagePrinter

    class _Strict(MessagePrinter):
        """Warnings are errors here: a silent SystemRDL warning is how a field
           ends up one bit wide in a register the RTL made four."""

        def emit_message(self, lines):
            text = '\n'.join(lines)
            if 'warning' in text.lower():
                raise Exception('rdl_model: SystemRDL warning treated as an error:\n' + text)
            MessagePrinter.emit_message(self, lines)

    dirs = list(incdirs) if incdirs else []
    dirs.append(RDL_DIR)
    for p in paths:
        d = os.path.dirname(os.path.abspath(p))
        if d not in dirs:
            dirs.append(d)
    rdlc = RDLCompiler(message_printer=_Strict())
    for p in paths:
        rdlc.compile_file(p, incl_search_paths=dirs, defines=dict(defines or {}))
    blocks = []
    if top is not None:
        blocks.append(RdlBlock(rdlc.elaborate(top_def_name=top,
                                              parameters=dict(parameters or {})).top))
        return blocks
    for name in rdlc.root.comp_def_names():
        comp = rdlc.root.comp_defs[name]
        if 'vesta_peripheral' not in getattr(comp, 'properties', {}):
            continue
        blocks.append(RdlBlock(rdlc.elaborate(top_def_name=name).top))
    return blocks


def loadBlock(fileName, top, parameters=None, defines=None):
    """The RdlBlock of one tracked description, by file name and addrmap name.

       `parameters` / `defines` elaborate a PARAMETERISED block (CLINT, MUTEX,
       IRQROUTER, PWRCTRL) for the configuration in hand; omitting both gives
       the block's own defaults, which are the five-hart chip.

       Memoised on all four, because generate.py asks for one peripheral at a
       time and the gates ask repeatedly, and a SystemRDL compile is the
       expensive part of both."""
    key = (fileName, top,
           tuple(sorted((parameters or {}).items())),
           tuple(sorted((defines or {}).items())))
    if key not in _COMPILE_CACHE:
        _COMPILE_CACHE[key] = compileFiles([os.path.join(RDL_DIR, fileName)], top=top,
                                           parameters=parameters, defines=defines)[0]
    return _COMPILE_CACHE[key]


# The tracked descriptions come from platform/common/config/rdl.json, which is the
# ONE registry of them: which .rdl file, which addrmap, which generate.py
# PeripheralTemplate its registers belong to, and whether that template is BUILT
# from the description (registerSource "rdl") or still hand-written in generate.py
# (registerSource "generator"). Two blocks may name the same peripheral, which is
# how a block overlaid on another block's sub-slot is described.
CONFIG_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'config', 'rdl.json')

_BLOCKS_CACHE = {}
_COMPILE_CACHE = {}


def blocks(configPath=None):
    """[{file, top, peripheral, registerSource, name}] for every rdl:true entry.

       Read from rdl.json rather than restated here: a second list is a second
       place to forget a peripheral, which is the defect this whole toolchain
       exists to remove."""
    path = configPath or CONFIG_PATH
    if path not in _BLOCKS_CACHE:
        with open(path) as f:
            cfg = json.load(f)
        out = []
        for name, entry in sorted(cfg.get('peripherals', {}).items()):
            if not entry.get('rdl', False):
                continue
            out.append({'name': name,
                        'file': entry['source'],
                        'top': entry['top'],
                        'peripheral': entry.get('peripheral', name),
                        'registerSource': entry.get('registerSource', 'generator')})
        _BLOCKS_CACHE[path] = tuple(out)
    return _BLOCKS_CACHE[path]


def loadAll(configPath=None):
    """Every tracked block, in rdl.json order."""
    return [loadBlock(b['file'], b['top']) for b in blocks(configPath)]


def registerTemplatesFor(peripheralTemplateName, sources=None, configPath=None,
                        parameters=None, defines=None):
    """Every register template of one peripheral, from every block that feeds it,
       slot-ordered -- the shape generate.py's PeripheralTemplate carries.

       `sources` restricts the blocks to the named .rdl files, which is how a
       peripheral whose register file is assembled CONDITIONALLY is built.

       `parameters` / `defines` are the configuration a PARAMETERISED block is
       elaborated for -- generate.py passes its OWN numHarts, numMutexes,
       masterW() and vectorsCount, the same numbers it hands the RTL."""
    out = []
    for b in blocks(configPath):
        if b['peripheral'] != peripheralTemplateName:
            continue
        if sources is not None and b['file'] not in sources:
            continue
        out += loadBlock(b['file'], b['top'], parameters, defines).RegisterTemplates
    out.sort(key=lambda t: t.RegisterMemorySlot)
    if not out:
        raise Exception('rdl_model: no .rdl block feeds the peripheral template "%s"%s. '
                        'Every peripheral whose registers come from SystemRDL needs an '
                        'rdl.json entry with rdl:true and registerSource "rdl".'
                        % (peripheralTemplateName,
                           '' if sources is None else ' from ' + ', '.join(sorted(sources))))
    return out


def rdlSourced(peripheralTemplateName, configPath=None):
    """True when rdl.json says this peripheral's templates are BUILT from .rdl."""
    return any(b['peripheral'] == peripheralTemplateName
               and b['registerSource'] == 'rdl'
               for b in blocks(configPath))


if __name__ == '__main__':
    for blk in loadAll():
        print('%-12s peripheral=%-7s vector=%s words=%d' % (
            blk.Name, blk.PeripheralTemplateName, blk.Vector, len(blk.RegisterTemplates)))
        for rt in blk.RegisterTemplates:
            print('    0x%02X %-14s %2d bits reset=0x%08X  %d fields'
                  % (rt.Offset, rt.NameTemplate, rt.Size, rt.ResetValue, len(rt.BitFields)))
