/*
 * Elixos coprocessor firmware: lwIP's compiler/platform port header.
 */
#ifndef COPROC_ARCH_CC_H
#define COPROC_ARCH_CC_H

#include <limits.h>
#include <sys/types.h>
/* picolibc's ssize_t is long; without SSIZE_MAX lwIP would typedef int. */
#ifndef SSIZE_MAX
#define SSIZE_MAX LONG_MAX
#endif
#include <stdio.h>
#include <stdlib.h>

#define LWIP_PLATFORM_DIAG(x) \
    do {                      \
        printf x;             \
    } while (0)

#define LWIP_PLATFORM_ASSERT(x)                                                               \
    do {                                                                                      \
        printf("elixos coproc: lwIP assertion \"%s\" failed at %s:%d\n", x, __FILE__, __LINE__); \
        abort();                                                                              \
    } while (0)

#endif
