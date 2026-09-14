#!/usr/bin/env python3
"""VestaRV: the hermetic CDC manifest gate.

Parses the live VHDL for every `entity work.sync` instantiation and every clocked
process, freezes the result in cdc_manifest.json and fails when an instance
disappears or changes shape, when a clock that no process used before appears with no
sync instance on it, or when an instance name does not read u_sync_<signal>.
It is a text gate and sees no netlist: a hand-rolled chain on the block's main clock
is invisible to it, which is what the Genus census in genus/common/tcl/cdc_census.tcl
is for.
"""

import argparse
import json
import os
import re
import sys

# One VHDL comment stripper for the whole file.  VHDL string literals hold no "--",
# so a line-based strip cannot eat code, and block comments are not used in this tree.
_COMMENT = re.compile(r"--[^\n]*")

# `<label> : entity work.sync` -- the only instantiation form the tree uses
# (direct entity instantiation; there is no component declaration for sync).
_SYNC = re.compile(r"([A-Za-z]\w*)\s*:\s*entity\s+work\.sync\b", re.IGNORECASE)

# A clocked process is `rising_edge(x)`, `falling_edge(x)` or the `x'event and x = '1'`
# spelling.  The signal inside is the clock of every flop that process infers.
_EDGE = re.compile(r"\b(?:rising_edge|falling_edge)\s*\(\s*([A-Za-z]\w*)\s*\)",
                   re.IGNORECASE)
_EVENT = re.compile(r"\b([A-Za-z]\w*)\s*'\s*event", re.IGNORECASE)

# The entity port list, read only to say whether a clock is a port or a signal the
# block derives itself, and to break the main-clock tie in port order.
_ENTITY = re.compile(r"\bentity\s+(\w+)\s+is\b(.*?)\bend\b", re.IGNORECASE | re.DOTALL)
_PORT_DECL = re.compile(r"\bport\s*\((.*)", re.IGNORECASE | re.DOTALL)

_NAME_OK = re.compile(r"^u_sync_[A-Za-z]\w*$")

UPDATE_CMD = "tools/bin/bazel run //hdl/common/cdc:cdc_manifest_update"

# One waiver per element of cdc_waiver_list's `return` list, `{<instance glob>
# "<justification>"}`.  The list is parsed HERE THE WAY TCL PARSES IT, element by
# element, and not line by line, because the two disagree in the one place that matters:
# a `#` line inside a braced list is DATA, not a comment.  Tcl hands every word of it to
# the census as a waiver glob, so a sentence naming an instance waives that instance.
# W5b hit exactly that: a comment saying `spi?/s_spi_teif_reg (2) are DEFECTS` waived
# both endpoints it declared unwaivable.  Any element that is not a well-formed
# {glob "reason"} pair therefore FAILS this gate.  Commentary goes above the proc.
_TCL_SPACE = " \t\n\r\f\v"


def tcl_brace_word(text, start):
    """The braced word that starts at text[start] == '{', as (inner, index past the
    closing brace).  Backslash escapes are skipped whole, which is what stops a `\{` from
    opening a level, and the count is over real braces only, exactly as Tcl's parser does.
    """
    depth = 0
    i = start
    while i < len(text):
        char = text[i]
        if char == "\\":
            i += 2
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i], i + 1
        i += 1
    return None, len(text)


def tcl_list_elements(text):
    """The elements of a Tcl list, each as (kind, raw), kind being brace, quote or bare.
    Enough of Tcl's list grammar for this file: whitespace separates, braces and double
    quotes group, and a backslash escapes the next character anywhere.
    """
    out = []
    i = 0
    end = len(text)
    while i < end:
        while i < end and text[i] in _TCL_SPACE:
            i += 1
        if i >= end:
            break
        if text[i] == "{":
            inner, i = tcl_brace_word(text, i)
            if inner is None:
                raise ValueError("unbalanced brace")
            out.append(("brace", inner))
            continue
        if text[i] == '"':
            j = i + 1
            buf = ""
            while j < end and text[j] != '"':
                if text[j] == "\\":
                    buf += text[j:j + 2]
                    j += 2
                    continue
                buf += text[j]
                j += 1
            if j >= end:
                raise ValueError("unbalanced quote")
            out.append(("quote", buf))
            i = j + 1
            continue
        j = i
        buf = ""
        while j < end and text[j] not in _TCL_SPACE:
            if text[j] == "\\":
                buf += text[j:j + 2]
                j += 2
                continue
            buf += text[j]
            j += 1
        out.append(("bare", buf))
        i = j
    return out


def tcl_unescape(word):
    """Backslash substitution, the step between the raw list element and the string the
    census's `string match` actually receives: `\\[` in the file reaches Tcl as `\[`,
    which matches a literal bracket.
    """
    out = ""
    i = 0
    while i < len(word):
        if word[i] == "\\" and i + 1 < len(word):
            out += word[i + 1]
            i += 2
            continue
        out += word[i]
        i += 1
    return out


def waiver_failures(path, text):
    """The waiver file is graded here because Genus is not in the hermetic tier and a
    waiver with no reason, or one that covers a whole block, is how a CDC gate quietly
    stops being one.
    """
    head = re.search(r"proc\s+cdc_waiver_list\s*\{\s*\}\s*\{", text)
    if not head:
        return ["%s: proc cdc_waiver_list is missing or has moved" % path]
    body, _ = tcl_brace_word(text, head.end() - 1)
    if body is None:
        return ["%s: proc cdc_waiver_list's body has an unbalanced brace" % path]
    ret = re.search(r"\breturn\s*\{", body)
    if not ret:
        return ["%s: proc cdc_waiver_list has no `return {...}` list" % path]
    listbody, _ = tcl_brace_word(body, ret.end() - 1)
    if listbody is None:
        return ["%s: cdc_waiver_list's return list has an unbalanced brace" % path]

    out = []
    try:
        elements = tcl_list_elements(listbody)
    except ValueError as err:
        return ["%s: cdc_waiver_list's return list is not a Tcl list (%s)" % (path, err)]

    seen = set()
    for kind, raw in elements:
        if kind != "brace":
            out.append(
                "%s: stray list element %r in cdc_waiver_list. A `#` line inside the "
                "braced list is NOT a Tcl comment: every word of it becomes an element "
                "and its first word becomes a live waiver glob. Put commentary above "
                "`proc cdc_waiver_list`." % (path, tcl_unescape(raw)))
            continue
        try:
            parts = tcl_list_elements(raw)
        except ValueError as err:
            out.append("%s: waiver entry {%s} is not a Tcl list (%s)" % (path, raw, err))
            continue
        if len(parts) != 2:
            out.append("%s: waiver entry is not {<glob> \"<justification>\"}: {%s}"
                       % (path, raw.strip()))
            continue
        glob = tcl_unescape(parts[0][1])
        reason = tcl_unescape(parts[1][1])
        if glob in seen:
            out.append("%s: waiver %s is listed twice" % (path, glob))
        seen.add(glob)
        if glob in ("*", "*/*") or glob.rstrip("/*") == "" or glob.endswith("/*"):
            out.append("%s: waiver %s is a blanket pattern; name the instances"
                       % (path, glob))
        if len(reason) < 24:
            out.append("%s: waiver %s has no justification worth the name" % (path, glob))
        for index, char in enumerate(glob):
            if char in "[]" and (index == 0 or glob[index - 1] != "\\"):
                out.append("%s: waiver %s must escape its brackets as \\[*\\]; "
                           "Tcl reads a bare [*] as a character class and matches nothing"
                           % (path, glob))
                break
    return out


def strip_comments(text):
    return _COMMENT.sub("", text)


def balanced_tail(text, start):
    """The instantiation body from `start` to the semicolon that closes it: a scan that
    counts parentheses, because the generic and port maps hold commas and parentheses but
    the statement ends at the first top-level `;`.
    """
    depth = 0
    for i in range(start, len(text)):
        char = text[i]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == ";" and depth <= 0:
            return text[start:i]
    return text[start:]


def parse_assoc(body, keyword):
    """The association list of `generic map` / `port map` as (formal, actual) pairs, in
    source order.  Formals carry their index when the caller associated one bit at a time
    (`d(0) => trig_uart0_rc`), which is the form a WIDTH>1 instance of unrelated scalars
    uses.
    """
    match = re.search(r"\b%s\s+map\s*\(" % keyword, body, re.IGNORECASE)
    if not match:
        return []
    start = match.end() - 1
    inner = balanced_tail(body, start)
    inner = inner[inner.find("(") + 1:]
    depth = 0
    items = []
    current = ""
    for char in inner:
        if char == "(":
            depth += 1
        elif char == ")":
            if depth == 0:
                break
            depth -= 1
        if char == "," and depth == 0:
            items.append(current)
            current = ""
            continue
        current += char
    items.append(current)

    pairs = []
    for item in items:
        if "=>" not in item:
            continue
        formal, actual = item.split("=>", 1)
        pairs.append((" ".join(formal.split()), " ".join(actual.split())))
    return pairs


def formal_base(formal):
    return formal.split("(")[0].strip().lower()


def parse_sync_instances(text):
    out = []
    for match in _SYNC.finditer(text):
        body = balanced_tail(text, match.end())
        generics = dict((formal_base(f), a) for f, a in parse_assoc(body, "generic"))
        ports = parse_assoc(body, "port")
        row = {
            "name": match.group(1),
            "line": text.count("\n", 0, match.start()) + 1,
            "width": generics.get("width", "1"),
            "depth": generics.get("depth", "2"),
            "rst_val": generics.get("rst_val", ""),
            "clk": "",
            "areset": "",
            "d": [],
            "q": [],
        }
        for formal, actual in ports:
            base = formal_base(formal)
            if base in ("clk", "areset"):
                row[base] = actual
            elif base in ("d", "q"):
                row[base].append(actual)
        out.append(row)
    return out


def parse_ports(text):
    """The entity's port names in declaration order.  Only the first entity in the file is
    read: every live block in hdl/common declares exactly one.
    """
    match = _ENTITY.search(text)
    if not match:
        return []
    port_match = _PORT_DECL.search(match.group(2))
    if not port_match:
        return []
    names = []
    for line in port_match.group(1).splitlines():
        decl = line.split(":")
        if len(decl) < 2:
            continue
        if not re.search(r"\b(in|out|inout|buffer)\b", decl[1], re.IGNORECASE):
            continue
        for name in decl[0].split(","):
            name = name.strip().lstrip("(").strip()
            if re.match(r"^[A-Za-z]\w*$", name):
                names.append(name)
    return names


def parse_clocks(text):
    """Clock signal -> number of clocked processes that use it, keyed lower case because
    VHDL identifiers are case insensitive and the tree spells ClkMem both ways.
    """
    counts = {}
    for match in _EDGE.finditer(text):
        key = match.group(1).lower()
        counts[key] = counts.get(key, 0) + 1
    for match in _EVENT.finditer(text):
        key = match.group(1).lower()
        counts[key] = counts.get(key, 0) + 1
    return counts


def main_clock(counts, ports):
    """The block's main clock: the one the most processes use, ties broken by entity port
    order and then alphabetically.  Descriptive only -- it names the secondary domains in
    the report and no gate decision rests on it.
    """
    if not counts:
        return ""
    order = dict((name.lower(), i) for i, name in enumerate(ports))
    ranked = sorted(counts,
                    key=lambda c: (-counts[c], order.get(c, len(order)), c))
    return ranked[0]


def scan(path, text):
    text = strip_comments(text)
    syncs = parse_sync_instances(text)
    ports = parse_ports(text)
    counts = parse_clocks(text)
    main = main_clock(counts, ports)
    port_set = set(name.lower() for name in ports)
    synced = set(row["clk"].lower() for row in syncs if row["clk"])

    clocks = {}
    for name in sorted(counts):
        clocks[name] = {
            "processes": counts[name],
            "port": name in port_set,
            "main": name == main,
            "sync": name in synced,
        }
    return {
        "main_clock": main,
        "clocks": clocks,
        "syncs": sorted(syncs, key=lambda r: r["name"]),
    }


def name_failures(path, text, row):
    """The naming rule.  Shape is graded on every instance; the <signal> half is graded
    only on a WIDTH=1 instance, where the suffix must be an identifier the file declares.
    A WIDTH>1 instance bundles several unrelated signals and is named after the bundle,
    and a glue vector between the crossing signal and the port means the actual on `d` is
    not the signal's own name, so the actuals are recorded but not graded.
    """
    out = []
    if not _NAME_OK.match(row["name"]):
        out.append("%s: instance %s does not read u_sync_<signal>"
                   % (path, row["name"]))
        return out
    suffix = row["name"][len("u_sync_"):]
    if row["width"].strip() == "1":
        others = re.sub(r"\bu_sync_\w+", "", text)
        if not re.search(r"\b%s\b" % re.escape(suffix), others, re.IGNORECASE):
            out.append("%s: instance %s names %s, which the file declares nowhere"
                       % (path, row["name"], suffix))
    return out


def compare(frozen, live):
    failures = []
    for path in sorted(set(frozen) | set(live)):
        want = frozen.get(path)
        got = live.get(path)
        if want is None:
            failures.append("%s: not in the frozen manifest (new file)" % path)
            continue
        if got is None:
            failures.append("%s: frozen but no longer scanned (file gone or renamed)"
                            % path)
            continue

        want_syncs = dict((r["name"], r) for r in want["syncs"])
        got_syncs = dict((r["name"], r) for r in got["syncs"])
        for name in sorted(set(want_syncs) - set(got_syncs)):
            failures.append("%s: sync instance %s has disappeared" % (path, name))
        for name in sorted(set(got_syncs) - set(want_syncs)):
            failures.append("%s: sync instance %s is new" % (path, name))
        for name in sorted(set(want_syncs) & set(got_syncs)):
            for field in ("width", "depth", "rst_val", "clk", "areset", "d", "q"):
                if want_syncs[name].get(field) != got_syncs[name].get(field):
                    failures.append("%s: sync %s %s %s -> %s"
                                    % (path, name, field,
                                       want_syncs[name].get(field),
                                       got_syncs[name].get(field)))

        for clock in sorted(set(got["clocks"]) - set(want["clocks"])):
            row = got["clocks"][clock]
            if row["main"] or row["sync"]:
                failures.append("%s: new clock %s (%d process(es)) -- bless it"
                                % (path, clock, row["processes"]))
            else:
                failures.append(
                    "%s: new clocked process on %s with no sync instance on that clock"
                    % (path, clock))
        for clock in sorted(set(want["clocks"]) - set(got["clocks"])):
            failures.append("%s: clock %s no longer drives any process" % (path, clock))
        for clock in sorted(set(want["clocks"]) & set(got["clocks"])):
            if want["clocks"][clock] != got["clocks"][clock]:
                failures.append("%s: clock %s %s -> %s"
                                % (path, clock, want["clocks"][clock],
                                   got["clocks"][clock]))
        if want.get("main_clock") != got.get("main_clock"):
            failures.append("%s: main clock %s -> %s"
                            % (path, want.get("main_clock"), got.get("main_clock")))
    return failures


FROZEN_HEADER = {
    "_comment": [
        "hdl/common/cdc/cdc_manifest.json -- the FROZEN CDC manifest.",
        "",
        "One row per live VHDL file: the block's clocked-process clocks and every",
        "`entity work.sync` instance with its generics and its clk/areset/d/q actuals.",
        "//hdl/common/cdc:cdc_manifest_test fails when a sync instance disappears or",
        "changes shape, when a clock appears that no process used before and no sync",
        "instance carries it, or when an instance name does not read u_sync_<signal>.",
        "",
        "LIMITS. This gate reads text, not a netlist. It cannot see a hand-rolled",
        "two-flop chain written on the block's main clock, it does not know which",
        "clocks are asynchronous to each other, and a clock listed here with",
        "sync=false is a domain the RTL crosses by some other means. The structural",
        "check is the Genus census, genus/common/tcl/cdc_census.tcl.",
        "",
        "Regenerating this file is a DELIBERATE ACT.",
        "Run  tools/bin/bazel run //hdl/common/cdc:cdc_manifest_update",
        "and commit the result in the SAME commit as the RTL change it blesses.",
    ],
}


def runfiles_root():
    for var in ("RUNFILES_DIR", "TEST_SRCDIR"):
        base = os.environ.get(var)
        if base:
            return base
    guess = os.path.abspath(sys.argv[0]) + ".runfiles"
    if os.path.isdir(guess):
        return guess
    return None


def data_path(rel):
    if os.path.exists(rel):
        return rel
    root = runfiles_root()
    if root:
        for candidate in (os.path.join(root, "_main", rel), os.path.join(root, rel)):
            if os.path.exists(candidate):
                return candidate
    return rel


def repo_path(staged):
    """The workspace-relative path a staged file came from. Bazel stages //hdl sources
    under a runfiles root, so the key in the manifest is the path from hdl/ down, which is
    stable whether the scan runs under `bazel test` or from the working tree.
    """
    staged = staged.replace("\\", "/")
    index = staged.rfind("/hdl/")
    if index >= 0:
        return staged[index + 1:]
    return staged


# The trees this gate does not read.  hdl/myshkin and hdl/argus are frozen records,
# hdl/common/tb and hdl/common/sim are benches and behavioural clock cells whose
# processes are not design logic, and hdl/fpga has no ASIC clock story.
EXCLUDED = (
    # Vendor memory models, present on this host and ignored by git (.gitignore
    # matches *ARM*), so a manifest that counted them would fail in any clone.
    "hdl/common/commune/ARM_IP_",
    "hdl/myshkin/",
    "hdl/argus/",
    "hdl/castalia/",
    "hdl/fpga/",
    "hdl/common/tb/",
    "hdl/common/sim/",
)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--frozen", required=True)
    parser.add_argument("--files-from", required=True)
    parser.add_argument("--waivers", default="")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args(argv)

    handle = open(data_path(args.files_from))
    try:
        staged = [line.strip() for line in handle if line.strip()]
    finally:
        handle.close()

    live = {}
    naming = []
    for path in staged:
        key = repo_path(path)
        if not key.endswith((".vhd", ".vhdl")):
            continue
        if any(key.startswith(tree) for tree in EXCLUDED):
            continue
        handle = open(data_path(path), errors="replace")
        try:
            text = handle.read()
        finally:
            handle.close()
        row = scan(key, text)
        if not row["clocks"] and not row["syncs"]:
            continue
        live[key] = row
        for sync in row["syncs"]:
            naming.extend(name_failures(key, text, sync))

    if not live:
        sys.stderr.write("ERROR: the scan found no VHDL to grade; the manifest is empty.\n")
        return 2

    if args.waivers:
        handle = open(data_path(args.waivers))
        try:
            naming.extend(waiver_failures("hdl/common/cdc/cdc_waivers.tcl", handle.read()))
        finally:
            handle.close()

    if args.update:
        root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
        if not root:
            sys.stderr.write(
                "ERROR: --update must run under `bazel run`, which is what\n"
                "       sets BUILD_WORKSPACE_DIRECTORY.  Use:\n"
                "       %s\n" % UPDATE_CMD)
            return 2
        if naming:
            print("REFUSED: the naming rule fails, so there is nothing to bless.")
            for line in naming:
                print("  %s" % line)
            return 1
        payload = dict(FROZEN_HEADER)
        payload["files"] = live
        out = os.path.join(root, args.frozen)
        handle = open(out, "w")
        try:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
        finally:
            handle.close()
        print("wrote %s: %d files, %d sync instances"
              % (out, len(live), sum(len(r["syncs"]) for r in live.values())))
        return 0

    frozen = json.load(open(data_path(args.frozen))).get("files", {})
    failures = naming + compare(frozen, live)
    if failures:
        print("FAIL: the CDC manifest moved.")
        for line in failures:
            print("  %s" % line)
        print("")
        print("A crossing that changed on purpose is blessed by regenerating the")
        print("manifest IN THE SAME COMMIT as the RTL change:")
        print("  %s" % UPDATE_CMD)
        return 1

    syncs = sum(len(r["syncs"]) for r in live.values())
    print("OK: CDC manifest unchanged - %d file(s), %d sync instance(s)."
          % (len(live), syncs))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
