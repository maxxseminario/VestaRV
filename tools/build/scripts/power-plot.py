#!/usr/bin/env python3

import numpy as np
import matplotlib.pyplot as plt

plt.style.use('ieee.mplstyle')

Ps_smrv32 = 1.41670e-3	# W
Ps_picorv32 = 1.42241e-3	# W
Pd_smrv32 = 36.9618e-6/1e6	# W/Hz
Pd_picorv32 = 16.03064e-6/1e6	# W/Hz

NumInsnsLZW = 1194168
LzwCC_smrv32 = 2388336
LzwCC_picorv32 = 5537844

CPI_smrv32 = LzwCC_smrv32 / NumInsnsLZW
CPI_picorv32 = LzwCC_picorv32 / NumInsnsLZW

IPC_smrv32 = 1 / CPI_smrv32
IPC_picorv32 = 1 / CPI_picorv32

IPSperHz_smrv32 = IPC_smrv32
IPSperHz_picorv32 = IPC_picorv32

f = 1
Efficiency_smrv32 = (IPSperHz_smrv32 * f) / (Pd_smrv32 * f)	# Insns/sec/W
Efficiency_picorv32 = (IPSperHz_picorv32 * f) / (Pd_picorv32 * f)	# Insns/sec/W

print('Efficiency (smrv32):', Efficiency_smrv32*1e-3/1e6, 'MIPS/mW')
print('Efficiency (picorv32):', Efficiency_picorv32*1e-3/1e6, 'MIPS/mW')

print('Efficiency @ 1 MHz (smrv32): ', (IPSperHz_smrv32 * 1 * 1e6/1e6) / ((Pd_smrv32 * 1 * 1e6 + Ps_smrv32) * 1e3), 'MIPS/mW')
print('Efficiency @ 1 MHz (picorv32):', (IPSperHz_picorv32 * 1 * 1e6/1e6) / ((Pd_picorv32 * 1 * 1e6 + Ps_picorv32) * 1e3), 'MIPS/mW')


print('Efficiency @ 100 MHz (smrv32): ', (IPSperHz_smrv32 * 100 * 1e6/1e6) / ((Pd_smrv32 * 100 * 1e6 + Ps_smrv32) * 1e3), 'MIPS/mW')
print('Efficiency @ 100 MHz (picorv32):', (IPSperHz_picorv32 * 100 * 1e6/1e6) / ((Pd_picorv32 * 100 * 1e6 + Ps_picorv32) * 1e3), 'MIPS/mW')

print('Efficiency @ fmax MHz (smrv32): ', (IPSperHz_smrv32 * 153.9 * 1e6/1e6) / ((Pd_smrv32 * 153.9 * 1e6 + Ps_smrv32) * 1e3), 'MIPS/mW')
print('Efficiency @ fmax MHz (picorv32):', (IPSperHz_picorv32 * 191.2 * 1e6/1e6) / ((Pd_picorv32 * 191.2 * 1e6 + Ps_picorv32) * 1e3), 'MIPS/mW')

exit()

# Power per MHz
MHz = np.linspace(0, 100, 1001)
P_smrv32 = (Pd_smrv32 * MHz * 1e6 + Ps_smrv32) / 1e-3
P_picorv32 = (Pd_picorv32 * MHz * 1e6 + Ps_picorv32) / 1e-3

plt.plot(MHz, P_smrv32, label='smrv32')
plt.plot(MHz, P_picorv32, label='picorv32')
plt.xlim(0, 100)
plt.ylim((0, np.ceil(plt.ylim()[1])))
plt.xlabel('Clock Frequency (MHz)')
plt.ylabel('Total Power Consumption (mW)')
plt.grid(True)
plt.legend(loc='upper left')
plt.savefig('power.pgf')
plt.savefig('power.png')

# Efficiency
plt.clf()
MHz = np.linspace(0, 100, 1001)
Eff_smrv32 = (IPSperHz_smrv32 * MHz * 1e6/1e6) / ((Pd_smrv32 * MHz * 1e6 + Ps_smrv32) * 1e3)
Eff_picorv32 = (IPSperHz_picorv32 * MHz * 1e6/1e6) / ((Pd_picorv32 * MHz * 1e6 + Ps_picorv32) * 1e3)

plt.plot(MHz, Eff_smrv32, label='smrv32')
plt.plot(MHz, Eff_picorv32, label='picorv32')
plt.xlim(0, 100)
plt.ylim((0, np.ceil(plt.ylim()[1])))
plt.xlabel('Clock Frequency (MHz)')
plt.ylabel('Total Power Efficiency (MIPS/mW)')
plt.grid(True)
plt.legend(loc='upper left')
plt.savefig('efficiency.pgf')
plt.savefig('efficiency.png')