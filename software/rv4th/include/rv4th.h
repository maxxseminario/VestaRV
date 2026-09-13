// VestaRV: rv4th Forth interpreter public interface
// GCC_DIAG_OFF/ON wrap the function-pointer casts the callX words need; the push/pop form is only available from GCC 4.6, so older compilers get the non-nesting variant and MSP430 gets no-ops.
// After Patrick Horgan, "Suppressing GCC Warnings", http://dbp-consulting.com/tutorials/SuppressingGCCWarnings.html

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void rv4th_init();
int16_t rv4th_processLoop();



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
