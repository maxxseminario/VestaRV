/*
 * platform_fix.h - Workaround for MemoryMap.h macro/struct conflicts
 * 
 * The platform-generated MemoryMap.h has bugs where macros and struct 
 * bitfield names conflict (e.g., #define EN vs struct field EN : 1).
 * 
 * This header includes MemoryMap.h but prevents compilation errors by
 * undefining problematic macros that we don't need in our code.
 */

#ifndef PLATFORM_FIX_H
#define PLATFORM_FIX_H

// Include the platform header first
#include "MemoryMap.h"

// Now undefine the problematic macros that conflict with struct fields
// These are bitfield masks we don't actually need in the blinky application
#undef EN       // Conflicts with struct bitfield EN : 1
#undef OVF      // Conflicts with struct bitfield OVF : 1
#undef TEIE     // If this also causes issues
#undef DCO1BIAS // If this also causes issues

#endif /* PLATFORM_FIX_H */
