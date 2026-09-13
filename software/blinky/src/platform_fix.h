// VestaRV: MemoryMap.h name-collision workaround for blinky
// The generated MemoryMap.h defines bit-mask macros whose names collide with struct bitfield names of the same spelling. This header includes it and undefines the four blinky does not use.

#ifndef PLATFORM_FIX_H
#define PLATFORM_FIX_H

#include "MemoryMap.h"

#undef EN
#undef OVF
#undef TEIE
#undef DCO1BIAS

#endif /* PLATFORM_FIX_H */
