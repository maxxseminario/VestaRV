#!/usr/bin/env python3

import numpy as np
import matplotlib.pyplot as plt

plt.style.use('pgf.mplstyle')
plt.rcParams.update({
	'figure.subplot.left': 0.2,
})

OVF = 1
TIMxCMP2 = 0.75
m = TIMxCMP2 / 0.25

t = [0, 0.25, 0.25, 0.5, 0.5, 0.75, 0.75, 1, 1]
y = [0, TIMxCMP2, 0, TIMxCMP2, 0, TIMxCMP2, 0, TIMxCMP2, 0]

plt.plot([0, 1], [TIMxCMP2, TIMxCMP2], 'k--')
plt.plot(t, y, 'r-')

ax = plt.gca()
ax.set_xlabel('Time')
ax.set_xticks([])
ax.set_xlim(0, 1)
ax.set_ylabel('Timer Value')
ax.set_yticks([0, TIMxCMP2, OVF])
ax.set_yticklabels(['0', 'TIMxCMP2', '$2^{32} - 1$ (max)'])
ax.set_ylim(0, 1)

fig = plt.gcf()
fig.set_size_inches(5, 2.625/2)

fig.savefig('../figures/timer-overflow-plot.pgf')
