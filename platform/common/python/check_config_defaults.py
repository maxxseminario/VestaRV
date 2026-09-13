#!/usr/bin/env python3
"""VestaRV: assert every knob's two default literals in generate.py agree.

_CONFIG_SCHEMA drives the configurator, the TRM tables and validation; the _cfg() literal
drives every generated artifact, and _cfg() never consults the schema, so a one-sided change
is silent. generate.py is import-unsafe (importing it runs a generation), so the source is
parsed textually and a key whose two sites are not both found fails rather than being skipped.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GENERATE = os.path.join(HERE, 'generate.py')

# chipName is the one deliberate asymmetry: the schema documents the shipped
# name ('Castalia') for the configurator/TRM, while _cfg('chipName', None) uses
# None as a sentinel meaning "no override -- keep the generator's built-in
# name". Two different questions, two different answers, on purpose.
EXEMPT = {'chipName': "schema documents the shipped name; _cfg uses None as the "
                      "no-override sentinel (two different questions)"}

# Both sites live at one tab of indentation inside their dict literal.
RE_SCHEMA = re.compile(r"^\t'([\w.]+)':\s*\{[^}]*'default':\s*([^,}]+)", re.M)
RE_CFG = re.compile(r"_cfg\('([\w.]+)',\s*([^)]+)\)")


def norm(v):
    return v.strip().rstrip(',').strip()


def main(argv):
    if not os.path.isfile(GENERATE):
        print('check_config_defaults: FATAL -- %s not found' % GENERATE)
        return 2
    src = open(GENERATE).read()

    schema = {}
    for m in RE_SCHEMA.finditer(src):
        schema[m.group(1)] = norm(m.group(2))
    cfg = {}
    for m in RE_CFG.finditer(src):
        cfg.setdefault(m.group(1), []).append(norm(m.group(2)))

    # An empty parse is the failure mode this check must never survive: a
    # regex that stopped matching would otherwise report perfect agreement.
    if not schema or not cfg:
        print('check_config_defaults: FATAL -- parsed %d schema default(s) and '
              '%d _cfg site(s). The source shape changed; fix the patterns '
              'rather than trusting this result.' % (len(schema), len(cfg)))
        return 2

    if '--list' in argv:
        for k in sorted(schema):
            print('  %-32s schema=%-12s _cfg=%s'
                  % (k, schema[k], cfg.get(k, ['<NONE>'])))
        print('  %d schema key(s), %d with a _cfg site' % (len(schema),
              sum(1 for k in schema if k in cfg)))
        return 0

    problems = []
    for k in sorted(schema):
        if k in EXEMPT:
            continue
        if k not in cfg:
            problems.append('  %s: in _CONFIG_SCHEMA (default %s) but NO _cfg() '
                            'site -- the schema default reaches the docs and '
                            'nothing else' % (k, schema[k]))
            continue
        for site in cfg[k]:
            if site != schema[k]:
                problems.append('  %s: SCHEMA default %s but _cfg() default %s -- '
                                'the docs/configurator and the generated '
                                'artifacts would disagree' % (k, schema[k], site))
    for k in sorted(cfg):
        if k not in schema and k not in EXEMPT:
            problems.append('  %s: has a _cfg() site (default %s) but no '
                            '_CONFIG_SCHEMA entry -- unsettable and undocumented'
                            % (k, cfg[k][0]))

    if problems:
        print('  %d config-default disagreement(s) in generate.py:'
              % len(problems))
        for p in problems:
            print(p)
        print('  Every knob states its default TWICE; both sites must carry the '
              'same value. See F-K7-1.')
        return 1

    print('  config defaults: OK (%d schema key(s) agree with their _cfg() '
          'site; %d exempt)' % (len(schema) - len(EXEMPT), len(EXEMPT)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
