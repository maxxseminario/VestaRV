#!/usr/bin/python3.6
"""VestaRV: read one Xcelium coverage database through the UCIS API, no IMC.

Xcelium 20.09 on this host ships without IMC (the vManager product was never
installed; the only imc on the host is the IUS 15.2 one, which rejects a 20.09
database with `serialization exception`). What the install does ship is
libucis.so and its header, which is the Accellera read API. This module binds it
with ctypes, because the host has no C compiler, and walks the same scope kinds
as Cadence's own example (tools/ucd/examples/ucis/read/traverse_itr/src/main.c).

    ucis_dump.py path/to/icc_xxxx.ucd out.json.gz

Output: {"tool":..., "items": {instance_path: {metric: {item_key: count}}}}
Metrics: block, branch, expr, toggle, fsm_state, fsm_trans. Keeping the item key
stable across runs is what lets merge_cov.py merge by summation: every test shares
one model, because the snapshot is elaborated once.
"""

import ctypes as C
import gzip
import json
import os
import sys

XCELIUM = os.environ.get('XCELIUM_HOME', '/opt/cadence/XCELIUM2009')
TOOLS = os.path.join(XCELIUM, 'tools.lnx86')

# ucis.h scope and coveritem type bits. Each iterator is given its exact type:
# the Cadence implementation returns nothing for an all-ones mask.
INSTANCE = 0x10
TOGGLE = 0x1
BRANCH = 0x2
EXPR = 0x4
FSM = 0x400000
FSM_STATES = 0x20000000
FSM_TRANS = 0x40000000
COVBLOCK = 0x80000000

BRANCHBIN = 0x40
EXPRBIN = 0x80
TOGGLEBIN = 0x200
FSMBIN = 0x800
BLOCKBIN = 0x1000000

STR_SCOPE_NAME = 1
STR_SCOPE_HIER_NAME = 2
INT_IS_UNREACHABLE = 13033


class SourceInfo(C.Structure):
    _fields_ = [('filehandle', C.c_void_p), ('line', C.c_int), ('token', C.c_int)]


class CoverValue(C.Union):
    _fields_ = [('int64', C.c_uint64), ('int32', C.c_uint32), ('bytevector', C.c_void_p)]


class CoverData(C.Structure):
    _fields_ = [('type', C.c_uint64), ('flags', C.c_uint32), ('data', CoverValue),
                ('goal', C.c_int), ('weight', C.c_int), ('limit', C.c_int),
                ('bitlen', C.c_int)]


def load_library():
    C.CDLL(os.path.join(TOOLS, 'lib/64bit/libz_sh.so'), mode=C.RTLD_GLOBAL)
    u = C.CDLL(os.path.join(TOOLS, 'ucd/lib/64bit/libucis.so'), mode=C.RTLD_GLOBAL)
    vp = C.c_void_p
    u.ucis_Open.restype = vp
    u.ucis_Open.argtypes = [C.c_char_p]
    u.ucis_Close.argtypes = [vp]
    u.ucis_ScopeIterate.restype = vp
    u.ucis_ScopeIterate.argtypes = [vp, vp, C.c_uint64]
    u.ucis_ScopeScan.restype = vp
    u.ucis_ScopeScan.argtypes = [vp, vp]
    u.ucis_FreeIterator.argtypes = [vp, vp]
    u.ucis_CoverIterate.restype = vp
    u.ucis_CoverIterate.argtypes = [vp, vp, C.c_uint64]
    u.ucis_CoverScan.restype = C.c_int
    u.ucis_CoverScan.argtypes = [vp, vp]
    u.ucis_GetStringProperty.restype = C.c_char_p
    u.ucis_GetStringProperty.argtypes = [vp, vp, C.c_int, C.c_int]
    u.ucis_GetInternalIntProperty.restype = C.c_int
    u.ucis_GetInternalIntProperty.argtypes = [vp, vp, C.c_int, C.c_int]
    u.ucis_GetCoverData.restype = C.c_int
    u.ucis_GetCoverData.argtypes = [vp, vp, C.c_int, C.POINTER(C.c_char_p),
                                    C.POINTER(CoverData), C.POINTER(SourceInfo)]
    u.ucis_GetScopeSourceInfo.restype = C.c_int
    u.ucis_GetScopeSourceInfo.argtypes = [vp, vp, C.POINTER(SourceInfo)]
    u.ucis_GetFileName.restype = C.c_char_p
    u.ucis_GetFileName.argtypes = [vp, vp]
    return u


class Reader:
    def __init__(self, path):
        self.u = load_library()
        self.db = self.u.ucis_Open(path.encode())
        if not self.db:
            raise SystemExit('ucis_Open failed: %s (give it the .ucd file itself)' % path)

    def close(self):
        self.u.ucis_Close(self.db)

    def scopes(self, parent, kind):
        it = self.u.ucis_ScopeIterate(self.db, parent, kind)
        if not it:
            return []
        out = []
        while True:
            s = self.u.ucis_ScopeScan(self.db, it)
            if not s:
                break
            out.append(s)
        self.u.ucis_FreeIterator(self.db, it)
        return out

    def name(self, scope):
        v = self.u.ucis_GetStringProperty(self.db, scope, -1, STR_SCOPE_NAME)
        return v.decode('utf-8', 'replace') if v else ''

    def covers(self, scope, kind):
        """(name, count, line) of every coveritem of the scope."""
        it = self.u.ucis_CoverIterate(self.db, scope, kind)
        if not it:
            return []
        out = []
        while True:
            i = self.u.ucis_CoverScan(self.db, it)
            if i == -1:
                break
            nm = C.c_char_p()
            cd = CoverData()
            si = SourceInfo()
            self.u.ucis_GetCoverData(self.db, scope, i, C.byref(nm), C.byref(cd), C.byref(si))
            out.append(((nm.value or b'').decode('utf-8', 'replace'), cd.data.int32, si.line, i))
        self.u.ucis_FreeIterator(self.db, it)
        return out


def walk(r, parent, path, items):
    for inst in r.scopes(parent, INSTANCE):
        p = path + '.' + r.name(inst) if path else r.name(inst)
        rec = {}
        collect(r, inst, rec)
        if rec:
            items[p] = rec
        walk(r, inst, p, items)


def collect(r, inst, rec):
    for b in r.scopes(inst, COVBLOCK):
        bn = r.name(b)
        for nm, n, line, i in r.covers(b, BLOCKBIN):
            rec.setdefault('block', {})['%s|%s|%d|%d' % (bn, nm, line, i)] = n
    for b in r.scopes(inst, BRANCH):
        bn = r.name(b)
        for nm, n, line, i in r.covers(b, BRANCHBIN):
            rec.setdefault('branch', {})['%s|%s|%d|%d' % (bn, nm, line, i)] = n
    for e in r.scopes(inst, EXPR):
        en = r.name(e)
        for nm, n, line, i in r.covers(e, EXPRBIN):
            rec.setdefault('expr', {})['%s|%s|%d|%d' % (en, nm, line, i)] = n
    for t in r.scopes(inst, TOGGLE):
        tn = r.name(t)
        for nm, n, _line, _i in r.covers(t, TOGGLEBIN):
            rec.setdefault('toggle', {})['%s|%s' % (tn, nm)] = n
        for b in r.scopes(t, TOGGLE):
            bn = r.name(b)
            for nm, n, _line, _i in r.covers(b, TOGGLEBIN):
                rec.setdefault('toggle', {})['%s|%s|%s' % (tn, bn, nm)] = n
    for f in r.scopes(inst, FSM):
        fn = r.name(f)
        for s in r.scopes(f, FSM_STATES):
            for nm, n, _line, _i in r.covers(s, FSMBIN):
                rec.setdefault('fsm_state', {})['%s|%s' % (fn, nm or r.name(s))] = n
        for s in r.scopes(f, FSM_TRANS):
            for nm, n, _line, _i in r.covers(s, FSMBIN):
                rec.setdefault('fsm_trans', {})['%s|%s' % (fn, nm or r.name(s))] = n


def dump(path):
    r = Reader(path)
    items = {}
    walk(r, None, '', items)
    r.close()
    return items


def main():
    items = dump(sys.argv[1])
    if len(sys.argv) > 2:
        with gzip.open(sys.argv[2], 'wt') as f:
            json.dump({'ucd': sys.argv[1], 'items': items}, f)
    else:
        print(json.dumps(items, indent=1)[:6000])


if __name__ == '__main__':
    main()
