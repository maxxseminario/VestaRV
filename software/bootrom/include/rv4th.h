// VestaRV: rv4th monitor interface for the boot ROM.
// rv4th_processLoop runs until the `bye` word sets the exit flag, then returns the top of the
// math stack; main() re-enters it. The GCC_DIAG_OFF/ON macros below exist because the callX
// words dispatch through function pointers, which the compiler warns about at the call sites.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void rv4th_init();
int16_t rv4th_processLoop();



/* Suppress specific warnings (callX words use function pointers)
 *
 * from:
 * Suppressing GCC Warnings, by Patrick Horgan
 * http://dbp-consulting.com/tutorials/SuppressingGCCWarnings.html
 */

#if !defined(MSP430) && ((__GNUC__ * 100) + __GNUC_MINOR__) >= 402
#define GCC_DIAG_STR(s) #s
#define GCC_DIAG_JOINSTR(x,y) GCC_DIAG_STR(x ## y)
# define GCC_DIAG_DO_PRAGMA(x) _Pragma (#x)
# define GCC_DIAG_PRAGMA(x) GCC_DIAG_DO_PRAGMA(GCC diagnostic x)
# if ((__GNUC__ * 100) + __GNUC_MINOR__) >= 406
#  define GCC_DIAG_OFF(x) GCC_DIAG_PRAGMA(push) \
		GCC_DIAG_PRAGMA(ignored GCC_DIAG_JOINSTR(-W,x))
#  define GCC_DIAG_ON(x) GCC_DIAG_PRAGMA(pop)
# else
#  define GCC_DIAG_OFF(x) GCC_DIAG_PRAGMA(ignored GCC_DIAG_JOINSTR(-W,x))
#  define GCC_DIAG_ON(x)  GCC_DIAG_PRAGMA(warning GCC_DIAG_JOINSTR(-W,x))
# endif
#else
# define GCC_DIAG_OFF(x)
# define GCC_DIAG_ON(x)
#endif



#ifdef __cplusplus
}
#endif
