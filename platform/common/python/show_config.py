#!/usr/bin/env python3
'''VestaRV: print a summary of the current resolved chip configuration.

Reads the artifacts `make generate` writes: ChipConfig.resolved.json (every knob and the
derived geometry), PadRing.json and config/MemoryMap.json. The first two come from
out/config/ when it holds them, which is the record of the last build whatever its CONFIG,
and from the tracked config/ pair otherwise. A script file on purpose, never an inline
python3 -c: this host's default python3 strips quotes.
'''

import json, os, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load(name):
	for path in (os.path.join(root, 'out', 'config', name), os.path.join(root, 'config', name)):
		if os.path.isfile(path):
			with open(path) as f:
				return json.load(f)
	return None

rc = load('ChipConfig.resolved.json')
pad = load('PadRing.json')
mm = load('MemoryMap.json')

print('==========================================')
print('Chip Configuration (resolved by make chip)')
print('==========================================')
if rc is None:
	print('')
	print('ChipConfig.resolved.json not found: run `make generate` first.')
	sys.exit(1)

drv = rc.get('derived', {})
mem = rc.get('memory', {})
print('')
print('Chip:          ' + str(rc.get('chipName')))
print('Config file:   ' + (rc.get('configFile') or '(none — Castalia defaults)'))
print('Harts:         ' + str(rc.get('numHarts')))
print('ISA:           ' + str(drv.get('isaString')))
print('Register file: ' + ('dual-port (ASIC)' if rc.get('registerFileDualPort') else 'single-port (FPGA)'))
print('HW mutexes:    ' + str(rc.get('numMutexes')))
print('NPU:           ' + ('present' if rc.get('peripherals', {}).get('npu') else 'absent'))
print('')
print('Memory:')
print('  Boot ROM:        ' + str(mem.get('romSize', 0) // 1024) + ' KiB @ 0x0 (shared, all harts reset here)')
print('  TCM per hart:    ' + str(mem.get('tcmSizePerHart', 0) // 1024) + ' KiB @ 0x8000 (private)')
if rc.get('peripherals', {}).get('npu'):
	print('  NPU staging RAM: ' + str(mem.get('npuStagingRamSize', 0) // 1024) + ' KiB @ 0xC000 (shared)')
print('  Shared bulk RAM: ' + str(mem.get('sharedBulkRamSize', 0) // 1024) + ' KiB @ 0x10000 ('
	+ str(drv.get('sharedRamBanks')) + ' banks) — ends ' + str(drv.get('sharedRamEndAddress')))
print('  Extended flash:  ' + str(drv.get('flashBaseAddress')) + '+ (XIP, hart 0 only)')
print('  Stack pointer:   ' + str(drv.get('stackPointerInit')) + ' (top of TCM)')
print('')
print('Interrupts: ' + str(drv.get('vectorsCount')) + ' vectors (CLINT msip='
	+ str(drv.get('clintMsipVector')) + ', mtip=' + str(drv.get('clintMtipVector')) + ')')
print('CLINT:      MSIP[h] @ ' + str(drv.get('clintLayout', {}).get('msipAddress'))
	+ ', MTIME @ ' + str(drv.get('clintLayout', {}).get('mtimeAddress'))
	+ ', MTIMECMP @ ' + str(drv.get('clintLayout', {}).get('mtimecmpBaseAddress')) + '+')
print('Bootrom:    tile loader rows @ ' + str(drv.get('bootromLoaderRowBase')))

if mm is not None:
	names = []
	for p in mm.get('Peripherals', []):
		if isinstance(p, dict) and 'PeripheralName' in p:
			names.append(p['PeripheralName'])
	if names:
		print('')
		print('Peripherals (' + str(len(names)) + '): ' + ', '.join(names))

if pad is not None:
	pk = pad.get('package', {})
	print('')
	print('Pad ring (derived from the package model; PadRing.json):')
	print('  ' + str(pk.get('type')) + '-' + str(pk.get('pinCount')) + ', '
		+ str(pk.get('dimensions', ['?', '?'])[0]) + 'x' + str(pk.get('dimensions', ['?', '?'])[1])
		+ ' ' + str(pk.get('units')) + ', ' + str(pk.get('pinPitch')) + ' ' + str(pk.get('units')) + ' pitch')
	for pd in pad.get('powerDomains', []):
		print('  ' + pd['name'] + ': ' + str(pd['voltage']) + ' V ('
			+ pd['positiveRail']['name'] + '/' + pd['negativeRail']['name'] + ')')

print('')
print('Source of truth: python/generate.py — regenerate with `make chip` (or `make generate`)')
print('==========================================')
