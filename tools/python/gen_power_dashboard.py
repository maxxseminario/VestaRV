#!/usr/bin/env python3
"""
gen_power_dashboard.py — regenerate power_dashboard.html from the NEWEST
post-genus and post-innovus power reports on disk.

Sources scanned (nothing is rerun — this only scrapes existing reports):
  genus/rpt/<block>.genus.power.rpt            report_power -by_hierarchy -levels 4 (units W)
  innovus/common/timingReports/<design>_postCTS.power / _postRoute.power
                                               report_power [-leakage]      (units mW)
  innovus/common/rpt/<tag>_era/power_all.rpt   full report_power at signoff (units mW)
  innovus/common/rpt/<tag>_era/inst_power.rpt  report_power -instances      (units mW)

Usage:
  python3 tools/python/gen_power_dashboard.py [-o power_dashboard.html]

Run it after any genus or Innovus rerun; the page is rebuilt from whatever is
newest, and every card shows the source file + its report date so staleness is
visible. Known caveats are printed on the page itself (ETM tiles report ~0
power at assembly level; the flow's postCTS/postRoute reports are leakage-only;
activity is statistical 0.2; the corner is ss_0p9v_125c, i.e. leakage at 125C).
"""

import argparse
import html
import json
import os
import re
import sys
import time

REPO = os.path.expanduser(os.environ.get("VESTA_ROOT", "~/vestarv"))
GENUS_RPT = os.path.join(REPO, "genus", "rpt")
INNOVUS = os.path.join(REPO, "innovus", "common")

# genus report basename -> (family, human label). Basenames not listed are
# shown under "Other"; Myshkin's frozen MCU synth report is skipped outright.
GENUS_BLOCKS = {
    "hart_tile":       ("Castalia", "hart_tile (RISC-V corner tile)"),
    "MCU_MP":          ("Castalia", "MCU assembly — flat synth"),
    "MCU_MP_hier":     ("Castalia", "MCU assembly — hierarchical"),
    "MCU_WOUND":       ("Castalia", "MCU (wound config) — flat synth, chip-level QSPI/I3C/NFC"),
    "hart_tile_argus": ("Argus", "hart_tile_argus (Argus tile)"),
    "MCU_ARGUS_hier":  ("Argus", "MCU_ARGUS assembly — hierarchical"),
    "QSPI":            ("Peripherals", "QSPI (quad-SPI controller)"),
    "I3C":             ("Peripherals", "I3C (I3C bus controller)"),
    "NFC":             ("Peripherals", "NFC (digital front-end; RF is off-die)"),
    "RTC":             ("Peripherals", "RTC (real-time clock)"),
    "PWM":             ("Peripherals", "PWM (2-channel buffered PWM)"),
    "OneWire":         ("Peripherals", "OneWire (1-Wire master)"),
}
GENUS_SKIP = {"MCU"}  # frozen Myshkin tape-out synth report

INNOVUS_DESIGNS = {
    "hart_tile":     ("Castalia", "hart_tile (hardened tile)"),
    "MCU":           ("Castalia", "MCU assembly (tiles as ETM macros)"),
    "MCU_MP":        ("Castalia", "MCU assembly — full-power report"),
    "chip_top":      ("Castalia", "chip_top (C0 connected chip)"),
    "chip_top_quad": ("Castalia", "chip_top_quad (CQ 4-corner chip)"),
    "MCU_ARGUS":     ("Argus", "MCU_ARGUS assembly"),
    "hart_tile_argus": ("Argus", "hart_tile_argus (hardened tile)"),
    "chip_top_argus": ("Argus", "chip_top_argus (Argus chip)"),
}

ERA_DIRS = {
    "cq5_era": ("Castalia", "chip_top_quad — CQ5 ERA full power"),
    "a7_era":  ("Argus", "Argus chip — A7 ERA per-instance power"),
}

FAMILY_ORDER = ["Castalia", "Argus", "Peripherals", "Other"]

NUM = r"[-+0-9.eE]+"


def esc(s):
    return html.escape(str(s), quote=True)


def fmt_mw(mw):
    """3-sig-fig power with an auto unit."""
    if mw is None:
        return "—"
    a = abs(mw)
    if a >= 1000.0:
        return "%.3g W" % (mw / 1000.0)
    if a >= 0.1:
        return "%.3g mW" % mw
    if a >= 0.0001:
        return "%.3g µW" % (mw * 1000.0)
    return "%.3g nW" % (mw * 1e6)


def fmt_pct(x, tot):
    if not tot:
        return "—"
    return "%.1f%%" % (100.0 * x / tot)


def file_meta(path):
    st = os.stat(path)
    return {
        "path": os.path.relpath(path, REPO),
        "mtime": st.st_mtime,
        "mtime_str": time.strftime("%Y-%m-%d %H:%M", time.localtime(st.st_mtime)),
    }


# ---------------------------------------------------------------- genus ----

def parse_genus(path):
    """report_power -by_hierarchy: Cells Pct Leakage Internal Switching Total Lvl Instance (W)."""
    rows = []
    rx = re.compile(
        r"^\s*(\d+)\s+([\d.]+)%\s+(" + NUM + r")\s+(" + NUM + r")\s+(" + NUM +
        r")\s+(" + NUM + r")\s+(\d+)\s+(\S+)\s*$")
    with open(path) as f:
        for line in f:
            m = rx.match(line)
            if not m:
                continue
            rows.append({
                "cells": int(m.group(1)),
                "leak": float(m.group(3)) * 1000.0,   # W -> mW
                "int": float(m.group(4)) * 1000.0,
                "sw": float(m.group(5)) * 1000.0,
                "total": float(m.group(6)) * 1000.0,
                "lvl": int(m.group(7)),
                "inst": m.group(8),
            })
    if not rows:
        return None
    d = file_meta(path)
    d["rows"] = rows
    d["top"] = rows[0]
    return d


# -------------------------------------------------------------- innovus ----

def parse_innovus_power(path):
    """Innovus report_power text (leakage-only or full). Units mW."""
    d = file_meta(path)
    d.update({"design": None, "date": None, "libs": [], "cmd": None,
              "tot_leak": None, "tot_int": None, "tot_sw": None, "tot_all": None,
              "groups": [], "clocks": [], "libsplit": [], "insts": [],
              "n_inst": None})
    grp_rx = re.compile(r"^(\S(?:.*?\S)?)\s+(" + NUM + r")\s+(" + NUM + r")\s*$")
    grp4_rx = re.compile(r"^(\S(?:.*?\S)?)\s+(" + NUM + r")\s+(" + NUM + r")\s+("
                         + NUM + r")\s+(" + NUM + r")\s+(" + NUM + r")\s*$")
    inst_rx = re.compile(r"^(\S+)\s+(" + NUM + r")\s+(" + NUM + r")\s+(" + NUM +
                         r")\s+(" + NUM + r")\s+(" + NUM + r")\s+(" + NUM +
                         r")\s+(" + NUM + r")\s+(\S+)\s*$")
    section = None
    with open(path, errors="replace") as f:
        for line in f:
            s = line.rstrip("\n")
            t = s.strip()
            m = re.match(r"\*\s*Design:\s*(\S+)", t)
            if m:
                d["design"] = m.group(1)
                continue
            m = re.match(r"\*\s*Date & Time:\s*(\S+ \S+)", t)
            if m:
                d["date"] = m.group(1)
                continue
            m = re.search(r"setup_analysis_view:\s*(\S+\.lib)", t)
            if m:
                d["libs"].append(os.path.basename(m.group(1)))
                continue
            m = re.match(r"\*\s*(report_power\s.*)$", t)
            if m:
                d["cmd"] = m.group(1).strip()
                continue
            m = re.match(r"Total Leakage Power:\s*(" + NUM + r")", t)
            if m:
                d["tot_leak"] = float(m.group(1))
                continue
            m = re.match(r"Total Internal Power:\s*(" + NUM + r")", t)
            if m:
                d["tot_int"] = float(m.group(1))
                continue
            m = re.match(r"Total Switching Power:\s*(" + NUM + r")", t)
            if m:
                d["tot_sw"] = float(m.group(1))
                continue
            m = re.match(r"Total Power:\s*(" + NUM + r")", t)
            if m:
                d["tot_all"] = float(m.group(1))
                continue
            m = re.match(r"\*\s*Total instances in design:\s*(\d+)", t)
            if m:
                d["n_inst"] = int(m.group(1))
                continue
            m = re.match(r"Library (\S+) , (\d+) cells .* , (" + NUM + r") mW", t)
            if m:
                d["libsplit"].append({"lib": m.group(1), "cells": int(m.group(2)),
                                      "mw": float(m.group(3))})
                continue

            # section tracking for the Group / Clock tables
            if t.startswith("Group "):
                section = "group"
                continue
            if t.startswith("Clock ") and "Percentage" in t:
                section = "clock"
                continue
            if t.startswith("Rail "):
                section = None
                continue
            if t.startswith("Total (excluding duplicates)") or t.startswith("Total  "):
                section = None
                continue
            if section in ("group", "clock") and t and not t.startswith(("-", "Power", "(%)")):
                if t.startswith("Total"):
                    section = None
                    continue
                m = grp4_rx.match(t)
                if m and section == "group":
                    d["groups"].append({"name": m.group(1),
                                        "int": float(m.group(2)), "sw": float(m.group(3)),
                                        "leak": float(m.group(4)), "total": float(m.group(5))})
                    continue
                m = grp_rx.match(t)
                if m:
                    row = {"name": m.group(1), "leak": float(m.group(2)),
                           "pct": float(m.group(3))}
                    d["groups" if section == "group" else "clocks"].append(row)
                continue

            # per-instance rows (report_power -instances):
            #   name  freq  toggle  internal  switching  leakage  total  pct  cell
            m = inst_rx.match(t)
            if m and "/" in m.group(1) and not t.startswith("*"):
                d["insts"].append({
                    "inst": m.group(1),
                    "int": float(m.group(4)), "sw": float(m.group(5)),
                    "leak": float(m.group(6)), "total": float(m.group(7)),
                    "pct": float(m.group(8)), "cell": m.group(9)})
    d["leakage_only"] = d["cmd"] is not None and "-leakage" in d["cmd"]
    d["etm"] = [l for l in d["libs"] if "etm" in l]
    return d


# ----------------------------------------------------------------- scan ----

def scan():
    families = {}   # family -> {"genus": [...], "innovus": {design: {stage: rpt}}, "era": [...]}

    def fam(name):
        return families.setdefault(name, {"genus": [], "innovus": {}, "era": []})

    if os.path.isdir(GENUS_RPT):
        for fn in sorted(os.listdir(GENUS_RPT)):
            m = re.match(r"(.+)\.genus\.power\.rpt$", fn)
            if not m or m.group(1) in GENUS_SKIP:
                continue
            base = m.group(1)
            rpt = parse_genus(os.path.join(GENUS_RPT, fn))
            if not rpt:
                continue
            family, label = GENUS_BLOCKS.get(base, ("Other", base))
            rpt["block"] = base
            rpt["label"] = label
            fam(family)["genus"].append(rpt)

    tr = os.path.join(INNOVUS, "timingReports")
    if os.path.isdir(tr):
        cands = {}   # (design, stage) -> {is_full: rpt}
        for fn in sorted(os.listdir(tr)):
            m = re.match(r"(.+)_(postCTS|postRoute)(_full)?\.power$", fn)
            if not m:
                continue
            design, stage, is_full = m.group(1), m.group(2), bool(m.group(3))
            rpt = parse_innovus_power(os.path.join(tr, fn))
            rpt["stage"] = stage
            cands.setdefault((design, stage), {})[is_full] = rpt
        for (design, stage), c in cands.items():
            # a full report and its leakage-only twin come from the same run;
            # prefer the full one unless the leakage-only file is decisively
            # newer (older full report left over from a pre-full-flow run)
            if True in c and False in c:
                full, lo = c[True], c[False]
                rpt = full if full["mtime"] >= lo["mtime"] - 3600 else lo
                other = lo if rpt is full else full
                rpt["alt"] = ("%s report ignored: %s (%s)"
                              % ("leakage-only" if rpt is full else "stale full",
                                 other["path"], other["mtime_str"]))
            else:
                rpt = list(c.values())[0]
            family, label = INNOVUS_DESIGNS.get(design, ("Other", design))
            rpt["label"] = label
            fam(family)["innovus"].setdefault(design, {})[stage] = rpt

    rptdir = os.path.join(INNOVUS, "rpt")
    if os.path.isdir(rptdir):
        for tag in sorted(os.listdir(rptdir)):
            if tag not in ERA_DIRS:
                continue
            family, label = ERA_DIRS[tag]
            era = {"tag": tag, "label": label, "all": None, "inst": None}
            p = os.path.join(rptdir, tag, "power_all.rpt")
            if os.path.isfile(p):
                era["all"] = parse_innovus_power(p)
            p = os.path.join(rptdir, tag, "inst_power.rpt")
            if os.path.isfile(p):
                era["inst"] = parse_innovus_power(p)
            if era["all"] or era["inst"]:
                fam(family)["era"].append(era)

    return families


# ----------------------------------------------------------------- html ----

CSS = """
:root {
  color-scheme: light;
  --surface: #fcfcfb; --plane: #f9f9f7;
  --ink: #0b0b0b; --ink2: #52514e; --muted: #898781;
  --grid: #e1e0d9; --axis: #c3c2b7; --ring: rgba(11,11,11,0.10);
  --c-int: #2a78d6; --c-sw: #008300; --c-leak: #e87ba4;
  --s1: #2a78d6; --s2: #008300; --s3: #e87ba4; --s4: #eda100; --s5: #1baf7a; --s6: #eb6834;
  --warn-bg: #fdf3e0; --warn-ink: #7a5200;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    color-scheme: dark;
    --surface: #1a1a19; --plane: #0d0d0d;
    --ink: #ffffff; --ink2: #c3c2b7; --muted: #898781;
    --grid: #2c2c2a; --axis: #383835; --ring: rgba(255,255,255,0.10);
    --c-int: #3987e5; --c-sw: #008300; --c-leak: #d55181;
    --s1: #3987e5; --s2: #008300; --s3: #d55181; --s4: #c98500; --s5: #199e70; --s6: #d95926;
    --warn-bg: #33290e; --warn-ink: #eda100;
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --surface: #1a1a19; --plane: #0d0d0d;
  --ink: #ffffff; --ink2: #c3c2b7; --muted: #898781;
  --grid: #2c2c2a; --axis: #383835; --ring: rgba(255,255,255,0.10);
  --c-int: #3987e5; --c-sw: #008300; --c-leak: #d55181;
  --s1: #3987e5; --s2: #008300; --s3: #d55181; --s4: #c98500; --s5: #199e70; --s6: #d95926;
  --warn-bg: #33290e; --warn-ink: #eda100;
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--plane); color: var(--ink);
       font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
.wrap { max-width: 1200px; margin: 0 auto; padding: 24px 20px 80px; }
h1 { font-size: 22px; margin: 0 0 4px; }
h2 { font-size: 17px; margin: 34px 0 10px; border-bottom: 1px solid var(--grid); padding-bottom: 6px; }
h3 { font-size: 15px; margin: 0 0 2px; }
.sub { color: var(--ink2); font-size: 13px; }
.mut { color: var(--muted); font-size: 12px; }
.card { background: var(--surface); border: 1px solid var(--ring); border-radius: 10px;
        padding: 16px 18px; margin: 14px 0; }
.cardhead { display: flex; flex-wrap: wrap; gap: 4px 14px; align-items: baseline; margin-bottom: 10px; }
.badge { display: inline-block; font-size: 11px; padding: 1px 8px; border-radius: 9px;
         border: 1px solid var(--ring); color: var(--ink2); }
.badge.warn { background: var(--warn-bg); color: var(--warn-ink); border-color: transparent; }
.tiles { display: flex; flex-wrap: wrap; gap: 10px; margin: 10px 0 14px; }
.tile { border: 1px solid var(--ring); border-radius: 8px; padding: 8px 14px; min-width: 128px; }
.tile .v { font-size: 20px; font-weight: 600; }
.tile .k { font-size: 12px; color: var(--ink2); }
.flexrow { display: flex; flex-wrap: wrap; gap: 24px; align-items: flex-start; }
.legend { display: flex; flex-wrap: wrap; gap: 4px 16px; margin: 6px 0 10px; font-size: 12px; color: var(--ink2); }
.legend .sw { display: inline-block; width: 10px; height: 10px; border-radius: 3px;
              margin-right: 5px; vertical-align: -1px; }
table { border-collapse: collapse; font-size: 13px; width: 100%; }
th { text-align: right; color: var(--ink2); font-weight: 600; padding: 4px 10px;
     border-bottom: 1px solid var(--axis); white-space: nowrap; }
th:first-child, td:first-child { text-align: left; }
td { padding: 3px 10px; border-bottom: 1px solid var(--grid); text-align: right;
     font-variant-numeric: tabular-nums; white-space: nowrap; }
td.inst { font-family: ui-monospace, monospace; font-size: 12px; text-align: left; }
tr.lvl1 > td { font-weight: 600; }
.tblwrap { overflow-x: auto; }
.bars { margin: 8px 0 4px; }
.barrow { display: grid; grid-template-columns: 220px 1fr 90px; gap: 10px;
          align-items: center; margin: 3px 0; }
.barrow .nm { font-size: 12px; color: var(--ink2); overflow: hidden;
              text-overflow: ellipsis; white-space: nowrap; text-align: right;
              font-family: ui-monospace, monospace; }
.barrow .val { font-size: 12px; color: var(--ink); font-variant-numeric: tabular-nums; }
.stack { display: flex; height: 14px; border-radius: 4px; overflow: hidden; background: transparent; }
.seg { height: 100%; margin-right: 2px; border-radius: 2px; min-width: 1px; }
.seg:last-child { margin-right: 0; }
.donutbox { display: flex; gap: 14px; align-items: center; }
.toggle { cursor: pointer; user-select: none; color: var(--ink2); }
.toggle::before { content: "▾ "; font-size: 10px; }
tr.collapsed .toggle::before { content: "▸ "; }
.ctl { font-size: 12px; margin: 6px 0; }
.ctl button { font: inherit; margin-right: 8px; padding: 2px 10px; border-radius: 6px;
              border: 1px solid var(--ring); background: var(--surface); color: var(--ink2); cursor: pointer; }
.ctl button:hover { color: var(--ink); }
#tip { position: fixed; pointer-events: none; z-index: 10; background: var(--surface);
       border: 1px solid var(--ring); border-radius: 6px; padding: 6px 10px; font-size: 12px;
       box-shadow: 0 2px 10px rgba(0,0,0,0.25); display: none; max-width: 340px; }
#tip .t1 { font-weight: 600; }
.note { background: var(--surface); border: 1px solid var(--ring); border-left: 3px solid var(--s4);
        border-radius: 8px; padding: 10px 14px; margin: 14px 0; font-size: 13px; color: var(--ink2); }
.note ul { margin: 6px 0 0 18px; padding: 0; }
.themebtn { float: right; font: inherit; font-size: 12px; padding: 3px 10px; border-radius: 6px;
            border: 1px solid var(--ring); background: var(--surface); color: var(--ink2); cursor: pointer; }
"""

JS = """
(function () {
  var tip = document.getElementById('tip');
  document.addEventListener('mousemove', function (e) {
    var el = e.target.closest('[data-tip]');
    if (!el) { tip.style.display = 'none'; return; }
    tip.innerHTML = el.getAttribute('data-tip');
    tip.style.display = 'block';
    var x = e.clientX + 14, y = e.clientY + 14;
    var r = tip.getBoundingClientRect();
    if (x + r.width > window.innerWidth - 8) x = e.clientX - r.width - 10;
    if (y + r.height > window.innerHeight - 8) y = e.clientY - r.height - 10;
    tip.style.left = x + 'px'; tip.style.top = y + 'px';
  });

  // hierarchy trees: rows carry data-id / data-parent / data-lvl
  function applyVis(tbl) {
    var rows = tbl.querySelectorAll('tr[data-id]');
    var collapsed = {};
    rows.forEach(function (r) { if (r.classList.contains('collapsed')) collapsed[r.dataset.id] = 1; });
    rows.forEach(function (r) {
      var p = r.dataset.parent, hide = false;
      while (p) {
        if (collapsed[p]) { hide = true; break; }
        var pr = tbl.querySelector('tr[data-id="' + p + '"]');
        p = pr ? pr.dataset.parent : null;
      }
      r.style.display = hide ? 'none' : '';
    });
  }
  document.querySelectorAll('table.tree').forEach(function (tbl) {
    tbl.addEventListener('click', function (e) {
      var tg = e.target.closest('.toggle');
      if (!tg) return;
      tg.closest('tr').classList.toggle('collapsed');
      applyVis(tbl);
    });
    // default: collapse below level 1
    tbl.querySelectorAll('tr[data-haskids="1"]').forEach(function (r) {
      if (+r.dataset.lvl >= 1) r.classList.add('collapsed');
    });
    applyVis(tbl);
  });
  document.querySelectorAll('.ctl').forEach(function (ctl) {
    var tbl = document.getElementById(ctl.dataset.for);
    ctl.querySelectorAll('button').forEach(function (b) {
      b.addEventListener('click', function () {
        var d = +b.dataset.depth;
        tbl.querySelectorAll('tr[data-haskids="1"]').forEach(function (r) {
          r.classList.toggle('collapsed', +r.dataset.lvl >= d);
        });
        applyVis(tbl);
      });
    });
  });

  var btn = document.getElementById('themebtn');
  btn.addEventListener('click', function () {
    var root = document.documentElement;
    var cur = root.getAttribute('data-theme') ||
      (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    root.setAttribute('data-theme', cur === 'dark' ? 'light' : 'dark');
  });
})();
"""

COMPONENTS = [("Internal", "int", "--c-int"), ("Switching", "sw", "--c-sw"),
              ("Leakage", "leak", "--c-leak")]
GROUP_SLOTS = ["--s1", "--s2", "--s3", "--s4", "--s5", "--s6"]


def tipdata(title, lines):
    body = "<div class='t1'>%s</div>" % esc(title)
    for k, v in lines:
        body += "<div>%s: %s</div>" % (esc(k), esc(v))
    return html.escape(body, quote=True)


def stack_bar(name, row, scale_total, tip_title=None):
    """One stacked horizontal bar: internal | switching | leakage."""
    segs = []
    tot = row["total"] or 1e-30
    width_pct = 100.0 * row["total"] / scale_total if scale_total else 0
    for label, key, var in COMPONENTS:
        w = 100.0 * row[key] / tot
        if w <= 0:
            continue
        t = tipdata(tip_title or name,
                    [(label, fmt_mw(row[key])),
                     ("share of block", fmt_pct(row[key], tot)),
                     ("block total", fmt_mw(row["total"]))])
        segs.append("<div class='seg' style='width:%.2f%%;background:var(%s)' data-tip=\"%s\"></div>"
                    % (w, var, t))
    return ("<div class='barrow'><div class='nm' title='%s'>%s</div>"
            "<div class='stack' style='width:%.2f%%'>%s</div>"
            "<div class='val'>%s</div></div>"
            % (esc(name), esc(name), max(width_pct, 0.5), "".join(segs), fmt_mw(row["total"])))


def component_legend():
    return ("<div class='legend'>" +
            "".join("<span><span class='sw' style='background:var(%s)'></span>%s</span>"
                    % (var, label) for label, key, var in COMPONENTS) +
            "</div>")


def donut(items, title):
    """items: list of (name, value, css-var). Returns an SVG donut with hover tips."""
    total = sum(v for _, v, _ in items)
    if total <= 0:
        return ""
    C = 2 * 3.14159265 * 42
    off = 0.0
    arcs = []
    for name, v, var in items:
        frac = v / total
        dash = max(frac * C - 2, 0.01)   # 2px surface gap between segments
        t = tipdata(title, [(name, fmt_mw(v)), ("share", "%.1f%%" % (100 * frac))])
        arcs.append("<circle r='42' cx='60' cy='60' fill='none' stroke='var(%s)' stroke-width='16' "
                    "stroke-dasharray='%.2f %.2f' stroke-dashoffset='%.2f' data-tip=\"%s\"/>"
                    % (var, dash, C - dash, -off, t))
        off += frac * C
    legend = "".join("<div><span class='sw' style='background:var(%s)'></span>%s "
                     "<span class='mut'>%s · %s</span></div>"
                     % (var, esc(name), fmt_mw(v), fmt_pct(v, total))
                     for name, v, var in items)
    return ("<div class='donutbox'><svg width='120' height='120' viewBox='0 0 120 120' "
            "style='transform:rotate(-90deg)'>%s</svg>"
            "<div style='font-size:12px'>%s</div></div>" % ("".join(arcs), legend))


def genus_card(rpt):
    top = rpt["top"]
    rows = rpt["rows"]
    # tree ids/parents from DFS order + lvl
    stack = []
    for i, r in enumerate(rows):
        r["id"] = "r%d" % i
        while stack and rows[stack[-1]]["lvl"] >= r["lvl"]:
            stack.pop()
        r["parent"] = rows[stack[-1]]["id"] if stack else ""
        if stack:
            rows[stack[-1]]["haskids"] = True
        stack.append(i)

    lvl1 = sorted([r for r in rows if r["lvl"] == 1], key=lambda r: -r["total"])
    dyn = top["int"] + top["sw"]
    tiles = "".join(
        "<div class='tile'><div class='v'>%s</div><div class='k'>%s</div></div>" % (v, k)
        for v, k in [
            (fmt_mw(top["total"]), "total power"),
            (fmt_mw(dyn) + " · " + fmt_pct(dyn, top["total"]), "dynamic (int + sw)"),
            (fmt_mw(top["leak"]) + " · " + fmt_pct(top["leak"], top["total"]), "leakage"),
            ("{:,}".format(top["cells"]), "cells"),
        ])

    dn = donut([("Internal", top["int"], "--c-int"), ("Switching", top["sw"], "--c-sw"),
                ("Leakage", top["leak"], "--c-leak")], top["inst"])

    shown = lvl1[:14]
    scale = max((r["total"] for r in shown), default=1)
    bars = "".join(stack_bar(r["inst"].split("/")[-1], r, scale, tip_title=r["inst"])
                   for r in shown)
    more = ("<div class='mut'>+ %d smaller blocks (see table)</div>" % (len(lvl1) - len(shown))
            if len(lvl1) > len(shown) else "")

    tid = "tree_%s" % rpt["block"]
    trs = []
    for r in rows:
        kids = "1" if r.get("haskids") else "0"
        name = r["inst"].split("/")[-1] or r["inst"]
        pad = 14 * r["lvl"]
        nm = ("<span class='toggle'>%s</span>" % esc(name)) if r.get("haskids") else esc(name)
        trs.append(
            "<tr class='lvl%d' data-id='%s' data-parent='%s' data-lvl='%d' data-haskids='%s'>"
            "<td class='inst' style='padding-left:%dpx' title='%s'>%s</td>"
            "<td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>"
            % (r["lvl"], r["id"], r["parent"], r["lvl"], kids, 10 + pad, esc(r["inst"]), nm,
               "{:,}".format(r["cells"]), fmt_mw(r["leak"]), fmt_mw(r["int"]),
               fmt_mw(r["sw"]), fmt_mw(r["total"]), fmt_pct(r["total"], top["total"])))
    table = ("<div class='ctl' data-for='%s'>expand to depth: "
             "<button data-depth='1'>1</button><button data-depth='2'>2</button>"
             "<button data-depth='3'>3</button><button data-depth='99'>all</button></div>"
             "<div class='tblwrap'><table class='tree' id='%s'>"
             "<tr><th>instance</th><th>cells</th><th>leakage</th><th>internal</th>"
             "<th>switching</th><th>total</th><th>%% of top</th></tr>%s</table></div>"
             % (tid, tid, "".join(trs)))

    return ("<div class='card'><div class='cardhead'><h3>%s</h3>"
            "<span class='badge'>genus · report_power -by_hierarchy</span>"
            "<span class='mut'>%s · %s</span></div>"
            "<div class='tiles'>%s</div>"
            "<div class='flexrow'><div style='flex:0 0 auto'>%s</div>"
            "<div style='flex:1 1 420px;min-width:340px'>%s<div class='bars'>%s</div>%s</div></div>"
            "%s</div>"
            % (esc(rpt["label"]), esc(rpt["path"]), rpt["mtime_str"], tiles, dn,
               component_legend(), bars, more, table))


def innovus_card(design, stages, label):
    parts = []
    warn = ""
    post_r = stages.get("postRoute")
    post_c = stages.get("postCTS")
    if post_r and post_c and post_c["mtime"] > post_r["mtime"] + 60:
        warn += ("<span class='badge warn'>postCTS is newer than postRoute — "
                 "a rerun may be in flight; postRoute below may be stale</span>")
    for stage in ("postRoute", "postCTS"):
        rpt = stages.get(stage)
        if not rpt:
            continue
        etm = ", ".join(rpt["etm"]) or "none"
        mism = ""
        if design in ("MCU", "chip_top", "chip_top_quad") and any("argus" in e for e in rpt["etm"]):
            mism = ("<span class='badge warn'>uses an ARGUS tile ETM (%s) — this report is "
                    "from an Argus-config run, not Castalia</span>" % esc(etm))
        tiles = ("<div class='tile'><div class='v'>%s</div><div class='k'>total leakage</div></div>"
                 % fmt_mw(rpt["tot_leak"]))
        if rpt["tot_all"] is not None:
            dyn = (rpt["tot_int"] or 0) + (rpt["tot_sw"] or 0)
            tiles += ("<div class='tile'><div class='v'>%s</div><div class='k'>total power</div></div>"
                      "<div class='tile'><div class='v'>%s · %s</div><div class='k'>dynamic</div></div>"
                      % (fmt_mw(rpt["tot_all"]), fmt_mw(dyn), fmt_pct(dyn, rpt["tot_all"])))
        if rpt["n_inst"]:
            tiles += ("<div class='tile'><div class='v'>{:,}</div>"
                      "<div class='k'>instances</div></div>").format(rpt["n_inst"])

        groups = [g for g in rpt["groups"] if g.get("leak", g.get("total", 0)) > 0]
        groups.sort(key=lambda g: -g.get("leak", g.get("total", 0)))
        items = [(g["name"], g.get("leak", g.get("total", 0)), GROUP_SLOTS[i % 6])
                 for i, g in enumerate(groups)]
        dn = donut(items, "%s %s — leakage by group" % (design, stage))

        libr = ""
        if rpt["libsplit"]:
            libr = ("<div class='mut' style='margin-top:8px'>" + " · ".join(
                "%s: %s (%s cells)" % (esc(l["lib"]), fmt_mw(l["mw"]), "{:,}".format(l["cells"]))
                for l in rpt["libsplit"]) + "</div>")

        alt = ("<div class='mut'>%s</div>" % esc(rpt["alt"])) if rpt.get("alt") else ""
        parts.append(
            "<div style='margin:12px 0'><div class='cardhead'><h3 style='font-size:14px'>%s</h3>"
            "<span class='badge'>%s</span>%s"
            "<span class='mut'>%s · report date %s</span></div>"
            "<div class='mut'>ETM: %s · corner: ss 0.9 V 125 °C%s</div>%s"
            "<div class='tiles'>%s</div>%s%s</div>"
            % (stage, "leakage-only report" if rpt["leakage_only"] else "full report_power",
               mism, esc(rpt["path"]), esc(rpt["date"] or rpt["mtime_str"]),
               esc(etm), " · statistical activity 0.2" if not rpt["leakage_only"] else "",
               alt, tiles, dn, libr))
    if not parts:
        return ""
    return ("<div class='card'><div class='cardhead'><h3>%s</h3>"
            "<span class='badge'>innovus · %s</span>%s</div>%s</div>"
            % (esc(label), esc(design), warn, "".join(parts)))


def era_card(era):
    parts = []
    rpt_all = era["all"]
    if rpt_all and rpt_all["tot_all"]:
        dyn = (rpt_all["tot_int"] or 0) + (rpt_all["tot_sw"] or 0)
        tiles = "".join(
            "<div class='tile'><div class='v'>%s</div><div class='k'>%s</div></div>" % (v, k)
            for v, k in [
                (fmt_mw(rpt_all["tot_all"]), "total power"),
                (fmt_mw(dyn) + " · " + fmt_pct(dyn, rpt_all["tot_all"]), "dynamic (int + sw)"),
                (fmt_mw(rpt_all["tot_leak"]) + " · " + fmt_pct(rpt_all["tot_leak"], rpt_all["tot_all"]),
                 "leakage")])
        dn = donut([("Internal", rpt_all["tot_int"], "--c-int"),
                    ("Switching", rpt_all["tot_sw"], "--c-sw"),
                    ("Leakage", rpt_all["tot_leak"], "--c-leak")],
                   rpt_all["design"] or era["tag"])
        parts.append("<div class='mut'>%s · report date %s · statistical activity 0.2</div>"
                     "<div class='tiles'>%s</div>%s"
                     % (esc(rpt_all["path"]), esc(rpt_all["date"] or rpt_all["mtime_str"]), tiles, dn))

    rpt_i = era["inst"]
    if rpt_i and rpt_i["insts"]:
        insts = sorted(rpt_i["insts"], key=lambda r: -r["total"])
        scale = max(r["total"] for r in insts) or 1
        bars = "".join(stack_bar(r["inst"], r, scale) for r in insts[:24])
        rows = "".join(
            "<tr><td class='inst'>%s</td><td class='inst'>%s</td><td>%s</td><td>%s</td>"
            "<td>%s</td><td>%s</td><td>%.2f%%</td></tr>"
            % (esc(r["inst"]), esc(r["cell"]), fmt_mw(r["leak"]), fmt_mw(r["int"]),
               fmt_mw(r["sw"]), fmt_mw(r["total"]), r["pct"])
            for r in insts)
        parts.append(
            "<div class='mut' style='margin-top:8px'>%s · report date %s · per-instance "
            "(tiles enter as ETMs — see caveats)</div>%s<div class='bars'>%s</div>"
            "<div class='tblwrap'><table><tr><th>instance</th><th>cell</th><th>leakage</th>"
            "<th>internal</th><th>switching</th><th>total</th><th>%%</th></tr>%s</table></div>"
            % (esc(rpt_i["path"]), esc(rpt_i["date"] or rpt_i["mtime_str"]),
               component_legend(), bars, rows))

    if not parts:
        return ""
    return ("<div class='card'><div class='cardhead'><h3>%s</h3>"
            "<span class='badge'>innovus signoff · full power</span></div>%s</div>"
            % (esc(era["label"]), "".join(parts)))


def build_html(families):
    now = time.strftime("%Y-%m-%d %H:%M:%S")
    body = []
    body.append("<button class='themebtn' id='themebtn'>toggle theme</button>")
    body.append("<h1>VestaRV power dashboard</h1>")
    body.append("<div class='sub'>Post-genus (synthesis) and post-Innovus (P&amp;R) power, "
                "per block — regenerated from the newest reports on disk.</div>")
    body.append("<div class='mut'>generated %s · by tools/python/gen_power_dashboard.py · "
                "rerun the script after any genus/Innovus run to refresh</div>" % now)
    body.append(
        "<div class='note'><b>Reading these numbers</b><ul>"
        "<li><b>Corner:</b> everything here is the signoff corner <b>ss 0.9 V 125 °C</b> — "
        "leakage at 125 °C is many times the room-temperature value; treat leakage numbers "
        "as worst-case, not typical.</li>"
        "<li><b>Activity:</b> dynamic power uses statistical activity (0.2 on sequential "
        "elements and primary inputs), not a simulation VCD — good for block-to-block "
        "comparison, not absolute accuracy.</li>"
        "<li><b>ETM caveat:</b> at assembly/chip level the four hart tiles enter as ETM "
        "macros with <i>no power model</i> — they report ~0 internal/leakage there. For true "
        "tile power read the <b>hart_tile</b> block cards; chip-level totals cover the "
        "SRAMs/ROM/fabric/pads only.</li>"
        "<li><b>Leakage-only vs full:</b> optDesign's implicit postCTS/postRoute reports "
        "are <code>report_power -leakage</code>; since 2026-07-16 every flow tcl also "
        "writes a <code>*_full.power</code> (leakage + dynamic) at the same points, which "
        "this page prefers when present. Cards still showing leakage-only predate that "
        "change — rerun the P&amp;R to upgrade them. ERA cards are full power too.</li>"
        "<li><b>Power gating:</b> these are all-tiles-ON numbers. Gating a tile (PWRCTRL "
        "@0x4B00, harts 1–3) removes that tile's switched-rail leakage entirely.</li>"
        "</ul></div>")

    for famname in FAMILY_ORDER + [f for f in families if f not in FAMILY_ORDER]:
        fam = families.get(famname)
        if not fam:
            continue
        if not (fam["genus"] or fam["innovus"] or fam["era"]):
            continue
        body.append("<h2>%s</h2>" % esc(famname))
        if fam["genus"]:
            body.append("<div class='sub' style='margin:8px 0'>Post-genus (synthesis netlist, "
                        "full leakage + dynamic per hierarchy)</div>")
            for rpt in fam["genus"]:
                body.append(genus_card(rpt))
        if fam["innovus"]:
            body.append("<div class='sub' style='margin:8px 0'>Post-Innovus (placed &amp; routed)</div>")
            for design, stages in sorted(fam["innovus"].items()):
                label = stages.get("postRoute", stages.get("postCTS"))["label"]
                body.append(innovus_card(design, stages, label))
        for era in fam["era"]:
            body.append(era_card(era))

    return ("<!DOCTYPE html><html><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width,initial-scale=1'>"
            "<title>VestaRV power dashboard</title><style>%s</style></head>"
            "<body><div class='wrap'>%s</div><div id='tip'></div>"
            "<script>%s</script></body></html>"
            % (CSS, "".join(body), JS))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("-o", "--out", default=os.path.join(REPO, "power_dashboard.html"))
    args = ap.parse_args()
    families = scan()
    n_rpt = sum(len(f["genus"]) + sum(len(s) for s in f["innovus"].values()) +
                len(f["era"]) for f in families.values())
    if n_rpt == 0:
        sys.exit("no power reports found under %s" % REPO)
    out = build_html(families)
    with open(args.out, "w") as f:
        f.write(out)
    print("wrote %s (%d source reports)" % (args.out, n_rpt))
    for famname in FAMILY_ORDER:
        fam = families.get(famname)
        if not fam:
            continue
        for rpt in fam["genus"]:
            print("  [genus  ] %-28s %s  (%s)" % (rpt["block"], rpt["mtime_str"], rpt["path"]))
        for design, stages in sorted(fam["innovus"].items()):
            for stage, rpt in sorted(stages.items()):
                print("  [innovus] %-28s %s  (%s)" % (design + "." + stage, rpt["mtime_str"], rpt["path"]))
        for era in fam["era"]:
            print("  [era    ] %-28s" % era["tag"])


if __name__ == "__main__":
    main()
