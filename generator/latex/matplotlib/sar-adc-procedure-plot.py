#!/usr/bin/env python3

import numpy as np
import matplotlib.pyplot as plt

plt.style.use('pgf.mplstyle')
#plt.rcParams.update({
#	'figure.subplot.left': 0.2,
#})

def adcSarSearch(Vin, Vmax, bits):
	adcValues = [None for i in range(bits + 1)]
	adcValues[-1] = 2**(bits - 1) - 1

	for i in reversed(range(bits)):
		Vguess = Vmax * adcValues[i + 1] / 2**bits
		adcValues[i] = adcValues[i + 1]
		if Vguess >= Vin:
			adcValues[i] &= ~(1 << i)
		else:
			adcValues[i] |= 1 << i
		if i > 0:
			adcValues[i] &= ~(1 << (i - 1))
	
	return list(reversed(adcValues))

Vmax = 2.5
Vin = 0.687
bits = 10

t = list(range(0, bits + 2))
adcValues = adcSarSearch(Vin, Vmax, bits)
print(adcValues[-1], bin(adcValues[-1]))

y = [Vmax * adcValues[i // 2] / 2**bits for i in range(2*len(adcValues))]
x = [(i + 1) // 2 for i in range(len(y))]	


plt.plot([0, max(x)], [Vin, Vin], 'b-', label='$V_{in}$')
plt.plot(x, y, 'r-', label='ADC DAC')

ax = plt.gca()
ax.set_xlabel('ADC Clock')
ax.set_xticks(list(range(0, max(x))))
ax.set_xlim(0, max(x))
ax.set_ylabel('Voltage')
ax.set_ylim(0, Vmax)
ax.grid()
ax.legend(loc='upper right')

fig = plt.gcf()
fig.set_size_inches(5, 2.625)

#plt.show()
plt.savefig('../figures/sar-adc-procedure-plot.pgf')
