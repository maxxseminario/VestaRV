#!/usr/bin/env python3
"""VestaRV: the package model's ball-number gate, and the negative control that fails on a
swapped pair.

A package model may be built from a DIE-ROW pad list: a separate file saying which pad sits
where on the die and which ball, if any, it bonds to. Two descriptions of one ring drift, and
the ball number is the column that drifts silently -- a model can name every pad correctly, in
the right count, with the right bonded/unbonded split, and still put two of them on each
other's balls. That is a bonding diagram which shorts two rails together and it is invisible to
every check that compares names or counts.

Package.CheckDieRowBallMap is the gate, generate.py's _buildPackageData raises on it, and this
is its negative control: an otherwise valid die row with ONE pair of balls transposed must be
reported, and the same die row untransposed must pass in the same run, so the failure is
attributable to the transposition and not to the fixture.

Nothing here names a real package, a real net or a real chip: the fixture is a synthetic
16-pin part.
"""

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import Package


def _fixture():
	"""A synthetic 16-pin part, four balls a side, and the die row it is derived from.

	Ball numbers run counter-clockwise, W 1-4, S 5-8, E 9-12, N 13-16, so the north row's
	balls DECREASE with increasing die x -- the property that decides which of two adjacent
	supply pads takes which ball, and the one a transposition breaks.
	"""
	pkg = Package.PackageData(
		packageType='QFN', pinCount=16, units='mm', dimensions=[3, 3],
		pinsOnEachSide={'W': 4, 'S': 4, 'E': 4, 'N': 4},
		pinPitch=0.5, pinWidth=0.25, pinDepth=0.4)
	core = pkg.AddPowerDomain(
		powerDomainName='Core', positiveVoltage=1.0, negativeVoltage=0.0,
		positiveRailPinNumber=1, positiveRailPinName='VDD',
		negativeRailPinNumber=2, negativeRailPinName='VSS',
		positiveRailExtraPins=[(9, 'VDD')], negativeRailExtraPins=[(10, 'VSS')])
	aux = pkg.AddPowerDomain(
		powerDomainName='Aux', positiveVoltage=2.5, negativeVoltage=0.0,
		positiveRailPinNumber=16, positiveRailPinName='AUXP',
		negativeRailPinNumber=15, negativeRailPinName='AUXN')
	for (ball, name) in ((14, 'SIG_A'), (13, 'SIG_B')):
		pkg.AddPin(packagePinNumber=ball, name=name, ioType='io', powerDomain=aux)
	for (ball, name) in ((3, 'RESETN'), (4, 'POC'), (5, 'IN_0'), (6, 'IN_1')):
		pkg.AddPin(packagePinNumber=ball, name=name, ioType='i', powerDomain=core)
	for ball in (7, 8, 11, 12):
		pkg.AddPin(packagePinNumber=ball, name='NC', ioType='', noConnect=True)
	# The die row: one island of four, west to east, plus one pad that exists on the die and
	# has no package finger at all.
	dieRow = [
		{'inst': 'PAD_AUXP', 'net': 'AUXP',  'packagePin': 16, 'side': 'N'},
		{'inst': 'PAD_AUXN', 'net': 'AUXN',  'packagePin': 15, 'side': 'N'},
		{'inst': 'PAD_SIG_A', 'net': 'SIG_A', 'packagePin': 14, 'side': 'N'},
		{'inst': 'PAD_SIG_B', 'net': 'SIG_B', 'packagePin': 13, 'side': 'N'},
		{'inst': 'PAD_SIG_C', 'net': 'SIG_C', 'packagePin': None, 'side': 'N'},
		{'inst': 'PAD_VDD_1', 'net': 'VDD',   'packagePin': 9,  'side': 'E'},
	]
	return pkg, dieRow


class DieRowBallMapTest(unittest.TestCase):

	def testNoDieRowIsANoOp(self):
		pkg, _ = _fixture()
		self.assertEqual(pkg.CheckDieRowBallMap(), [])

	def testConsistentDieRowPasses(self):
		pkg, dieRow = _fixture()
		pkg.AttachDieRow(dieRow, 'fixture')
		self.assertEqual(pkg.CheckDieRowBallMap(), [])

	def testSwappedPairIsReported(self):
		'''THE NEGATIVE CONTROL. Transpose the two balls of one supply pair in the die row and
		nothing else: same pads, same count, same names, same bonded/unbonded split.'''
		pkg, dieRow = _fixture()
		clean = pkg.CheckDieRowBallMap()
		swapped = [dict(row) for row in dieRow]
		swapped[0]['packagePin'], swapped[1]['packagePin'] = (
			swapped[1]['packagePin'], swapped[0]['packagePin'])
		pkg.AttachDieRow(swapped, 'fixture')
		complaints = pkg.CheckDieRowBallMap()
		self.assertEqual(clean, [], 'the untransposed fixture must pass in the same run')
		self.assertTrue(complaints, 'a transposed supply pair must be reported')
		joined = ' | '.join(complaints)
		self.assertIn('AUXP', joined)
		self.assertIn('AUXN', joined)
		self.assertIn('15', joined)
		self.assertIn('16', joined)

	def testEverySwappableAdjacentPairIsCaught(self):
		'''Not just the one pair: every adjacent transposition in the die row's bonded rows is
		reported, so the gate is a ball-by-ball comparison and not a lucky assertion.'''
		pkg, dieRow = _fixture()
		bonded = [i for i, row in enumerate(dieRow) if row['packagePin'] is not None]
		for a, b in zip(bonded, bonded[1:]):
			swapped = [dict(row) for row in dieRow]
			swapped[a]['packagePin'], swapped[b]['packagePin'] = (
				swapped[b]['packagePin'], swapped[a]['packagePin'])
			pkg.AttachDieRow(swapped, 'fixture')
			self.assertTrue(pkg.CheckDieRowBallMap(),
				'transposing %s and %s was not reported' % (dieRow[a]['net'], dieRow[b]['net']))

	def testBondingToANoConnectBallIsReported(self):
		pkg, dieRow = _fixture()
		moved = [dict(row) for row in dieRow]
		moved[3]['packagePin'] = 12	# a ball the model declares no-connect
		pkg.AttachDieRow(moved, 'fixture')
		complaints = pkg.CheckDieRowBallMap()
		self.assertTrue(any('NO-CONNECT' in c for c in complaints), complaints)

	def testWrongEdgeIsReported(self):
		pkg, dieRow = _fixture()
		moved = [dict(row) for row in dieRow]
		moved[0]['side'] = 'S'
		pkg.AttachDieRow(moved, 'fixture')
		complaints = pkg.CheckDieRowBallMap()
		self.assertTrue(any('edge' in c for c in complaints), complaints)

	def testUnbondedDiePadIsAccepted(self):
		'''A die pad with no package finger is the un-bonded case: the gate must not invent a
		ball for it, and must not fail because the model has no pin of that name.'''
		pkg, dieRow = _fixture()
		pkg.AttachDieRow(dieRow, 'fixture')
		self.assertEqual(pkg.CheckDieRowBallMap(), [])
		self.assertIsNone([r for r in pkg.DieRow if r['net'] == 'SIG_C'][0]['packagePin'])

	def testDeferredPadIsSkippedNotFailed(self):
		'''Pads that join the ring after the model is built (GPIO) have no pin when the gate
		first runs. Their rows are skipped, not failed, and are compared on the second call.'''
		pkg, dieRow = _fixture()
		later = list(dieRow) + [{'inst': 'PAD_LATE', 'net': 'LATE', 'packagePin': None, 'side': 'S'}]
		pkg.AttachDieRow(later, 'fixture')
		self.assertEqual(pkg.CheckDieRowBallMap(), [])

	def testOffPackageBallIsRejectedAtAttach(self):
		pkg, dieRow = _fixture()
		bad = [dict(row) for row in dieRow]
		bad[0]['packagePin'] = 17
		self.assertRaises(Exception, pkg.AttachDieRow, bad, 'fixture')

	def testMultiPadRailIsASubsetNotAnEquality(self):
		'''A rail the model bonds on several balls may appear on one of them in a die row that
		describes a single island. That is a subset, not a disagreement.'''
		pkg, dieRow = _fixture()
		pkg.AttachDieRow(dieRow, 'fixture')
		self.assertEqual(pkg.CheckDieRowBallMap(), [])
		moved = [dict(row) for row in dieRow]
		moved[5]['packagePin'] = 1	# VDD's OTHER ball, on the other edge
		moved[5]['side'] = 'W'
		pkg.AttachDieRow(moved, 'fixture')
		self.assertEqual(pkg.CheckDieRowBallMap(), [],
			'either of a multi-pad rail\'s own balls is a legal die-row entry')
		wrong = [dict(row) for row in dieRow]
		wrong[5]['packagePin'] = 5	# a ball that belongs to another pad entirely
		pkg.AttachDieRow(wrong, 'fixture')
		self.assertTrue(pkg.CheckDieRowBallMap())


class PadListRowsTest(unittest.TestCase):
	'''The third leg of the gate: the pad list the model emits. It must be ONE derivation,
	shared with the template emitter, or the gate grades a different list from the one that
	ships.'''

	def testSideOfPinMatchesTheSideWalk(self):
		pkg, _ = _fixture()
		self.assertEqual([pkg.SideOfPin(n) for n in (1, 4, 5, 8, 9, 12, 13, 16)],
			['W', 'W', 'S', 'S', 'E', 'E', 'N', 'N'])
		self.assertIsNone(pkg.SideOfPin(0))
		self.assertIsNone(pkg.SideOfPin(17))

	def testEmissionOrderIsGeometric(self):
		'''W and N run pin-descending, S and E ascending: placeInstance order on every edge.'''
		pkg, _ = _fixture()
		rows = pkg.PadListRows()
		order = {}
		for side, pin, inst in rows:
			order.setdefault(side, []).append(pin.PackagePinNumber)
		self.assertEqual(order['W'], [4, 3, 2, 1])
		self.assertEqual(order['S'], [5, 6, 7, 8])
		self.assertEqual(order['E'], [9, 10, 11, 12])
		self.assertEqual(order['N'], [16, 15, 14, 13])

	def testRepeatedPlaceholdersAreUniquified(self):
		'''A rail on two pads would otherwise emit one instance name twice, which is an illegal
		duplicate in the consuming netlist.'''
		pkg, _ = _fixture()
		insts = [inst for side, pin, inst in pkg.PadListRows() if inst is not None]
		self.assertEqual(len(insts), len(set(insts)))
		self.assertIn('PAD_VDD_0', insts)
		self.assertIn('PAD_VDD_1', insts)
		self.assertIn('PAD_RESETN', insts)	# occurs once, so it keeps its bare name

	def testNoConnectCarriesNoInstance(self):
		pkg, _ = _fixture()
		for side, pin, inst in pkg.PadListRows():
			self.assertEqual(inst is None, pin.NoConnect)


class GateIsWiredFatalTest(unittest.TestCase):
	'''The gate is only worth having if the generator RAISES on it. generate.py is a script and
	cannot be imported without running a whole generation, so this reads it.'''

	def testBuildPackageDataRaisesOnComplaints(self):
		src = open(os.path.join(HERE, 'generate.py')).read()
		self.assertIn('CheckDieRowBallMap()', src)
		head = src[:src.index('m.Package = _buildPackageData(packageModel)')]
		call = head.rindex('CheckDieRowBallMap()')
		self.assertIn('raise Exception', head[call:],
			'_buildPackageData must raise on a ball-map disagreement, not warn')

	def testEmitterAndGateShareOneDerivation(self):
		src = open(os.path.join(HERE, 'generate.py')).read()
		self.assertIn('m.Package.PadListRows()', src)
		self.assertNotIn('def _padInstName(', src,
			'the pad-instance derivation belongs to Package.py, where the gate can read it')


if __name__ == '__main__':
	unittest.main()
