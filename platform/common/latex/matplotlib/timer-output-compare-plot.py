#!/usr/bin/env python3

import numpy as np
import matplotlib.pyplot as plt

plt.style.use('pgf.mplstyle')
plt.rcParams.update({
	'figure.subplot.left': 0.3,
})

OVF = 1
TIMxCMP0 = 0.25
TIMxCMP2 = 0.75
m = TIMxCMP2 / 0.25

t1 = [0, 0.25, 0.25, 0.5, 0.5, 0.75, 0.75, 1, 1]
y1 = [0, TIMxCMP2, 0, TIMxCMP2, 0, TIMxCMP2, 0, TIMxCMP2, 0]

t2 = [0, 0.25/3, 0.25/3, 0.25, 0.25, 0.25 + 0.25/3, 0.25 + 0.25/3, 0.5, 0.5, 0.5 + 0.25/3, 0.5 + 0.25/3, 0.75, 0.75, 0.75 + 0.25/3, 0.75 + 0.25/3, 1, 1]
y2 = [0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0]
y3 = [1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1]

fig, axs = plt.subplots(3)
axs[2].set_xlabel('Time')
axs[0].set_xticks([])
axs[1].set_xticks([])
axs[2].set_xticks([])
axs[0].set_xlim(0, 1)
axs[1].set_xlim(0, 1)
axs[2].set_xlim(0, 1)
axs[0].set_ylabel('Timer Value')
axs[1].set_ylabel('Pin TxCMP0\nTIMCMP0H\n= 0')
axs[2].set_ylabel('Pin TxCMP0\nTIMCMP0H\n= 1')
axs[0].set_yticks([0, TIMxCMP0, TIMxCMP2, OVF])
axs[0].set_yticklabels(['0', 'TIMxCMP0', 'TIMxCMP2', '$2^{32} - 1$ (max)'])
axs[1].set_yticks([0, 1])
axs[1].set_yticklabels(['LOW', 'HIGH'])
axs[2].set_yticks([0, 1])
axs[2].set_yticklabels(['LOW', 'HIGH'])
axs[0].set_ylim(0, 1)
axs[1].set_ylim(-0.1, 1.1)
axs[2].set_ylim(-0.1, 1.1)

axs[0].plot([0, 1], [TIMxCMP2, TIMxCMP2], 'k--')
axs[0].plot([0, 1], [TIMxCMP0, TIMxCMP0], 'k--')
axs[0].plot(t1, y1, 'r-')

axs[1].plot(t2, y2, 'b-')
axs[2].plot(t2, y3, 'b-')



#fig = plt.gcf()
#fig.set_size_inches(5, 2.625)

fig.savefig('../figures/timer-output-compare-plot.pgf')
#fig.savefig('test.png')
