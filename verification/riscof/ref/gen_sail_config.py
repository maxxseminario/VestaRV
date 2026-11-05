#!/usr/bin/python3.6
"""Write a Sail config for one Castalia hart class.

Starts from the model's own default RV32 config (`--rv32 --print-default-config`)
and narrows it to what the hart implements: named extensions only, M-mode only, no
PMP, direct-mode mtvec, misaligned data traps, one RAM region matching the Spike
plugin's. Anything left at the default would let a test pass or fail against a
machine that is not this one.
Usage: gen_sail_config.py <sail_riscv_sim> <tile|orch> <out.json>
"""
import json
import subprocess
import sys

KEEP = {
    'tile': {'A', 'C', 'Zca', 'Zaamo', 'Zalrsc', 'Zicsr', 'Zifencei'},
    'orch': {'M', 'A', 'C', 'Zca', 'Zmmul', 'Zaamo', 'Zalrsc', 'Zba', 'Zbb', 'Zbs',
             'Zbc', 'Zicsr', 'Zifencei'},
}
RAM_BASE = 0x8000
RAM_SIZE = 0x200000


def main():
    sim, cls, out = sys.argv[1:4]
    text = subprocess.check_output([sim, '--rv32', '--print-default-config'],
                                   universal_newlines=True)
    c = json.loads('\n'.join(l for l in text.split('\n')
                             if not l.strip().startswith('//')))
    keep = KEEP[cls]
    for name, ext in c['extensions'].items():
        if isinstance(ext, dict) and 'supported' in ext:
            ext['supported'] = name in keep
    c['extensions']['V']['support_level'] = 'Disabled'
    c['extensions']['C']['mutable_misa'] = False
    c['extensions']['Stateen']['Smstateen']['supported'] = False
    c['extensions']['Stateen']['Ssstateen']['supported'] = False
    c['base']['hpmevent_width_bits'] = 32
    mem = c['memory']
    mem['physaddr_bits'] = 32
    mem['pmp']['count'] = 0
    mem['pmp']['usable_count'] = 0
    mem['misaligned']['exceptions']['load_store'] = {'Some': 'AlignmentException'}
    region = mem['regions'][-1]
    region['base']['value'] = hex(RAM_BASE)
    region['size']['value'] = hex(RAM_SIZE)
    region['attributes']['misaligned_exceptions']['load_store'] = {'Some': 'AlignmentException'}
    mem['regions'] = [region]
    c['base']['mtvec']['vectored']['supported'] = False
    c['base']['mstatus']['fs_legal_states'] = 'ExtContext_Off'
    c['base']['mstatus']['vs_legal_states'] = 'ExtContext_Off'
    c['platform']['clint']['supported'] = False
    c['platform']['simple_interrupt_generator']['supported'] = False
    with open(out, 'w') as f:
        json.dump(c, f, indent=1)


if __name__ == '__main__':
    main()
