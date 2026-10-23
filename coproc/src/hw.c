/*
 * Elixos coprocessor firmware: console, clock, heap and the libc hooks
 * picolibc needs on bare metal (docs/notes/coproc-firmware.md).
 */
#include <errno.h>
#include <picotls.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <unistd.h>

#include "board.h"
#include "hw.h"
#if COPROC_UART_K230
#include "uart_k230.h"
#endif

/* ---- console: a 16550-compatible UART, polled ------------------------ */

#define UART_THR 0
#define UART_RBR 0
#define UART_LSR 5
#define LSR_DR 0x01
#define LSR_THRE 0x20

static inline void uart_out(unsigned reg, uint32_t value)
{
    uintptr_t addr = (uintptr_t) COPROC_UART_BASE + ((uintptr_t) reg << COPROC_UART_SHIFT);
#if COPROC_UART_WORD
    *(volatile uint32_t *) addr = value;
#else
    *(volatile uint8_t *) addr = (uint8_t) value;
#endif
}

static inline uint32_t uart_in(unsigned reg)
{
    uintptr_t addr = (uintptr_t) COPROC_UART_BASE + ((uintptr_t) reg << COPROC_UART_SHIFT);
#if COPROC_UART_WORD
    return *(volatile uint32_t *) addr;
#else
    return *(volatile uint8_t *) addr;
#endif
}

void hw_console_init(void)
{
#if COPROC_UART_K230
    // U-Boot never sets UART3 up: its clock, divisor and pads from scratch.
    (void) uart_k230_init();
#endif
}

static void uart_putc(char c)
{
    while (!(uart_in(UART_LSR) & LSR_THRE)) {
    }
    uart_out(UART_THR, (uint8_t) c);
}

void hw_console_write(const char *bytes, size_t len)
{
    for (size_t i = 0; i < len; i++) {
        if (bytes[i] == '\n') {
            uart_putc('\r');
        }
        uart_putc(bytes[i]);
    }
}

size_t hw_console_read(char *bytes, size_t max)
{
    size_t n = 0;
    while (n < max && (uart_in(UART_LSR) & LSR_DR)) {
        bytes[n++] = (char) uart_in(UART_RBR);
    }
    return n;
}

static int stdio_put(char c, FILE *file)
{
    (void) file;
    hw_console_write(&c, 1);
    return (unsigned char) c;
}

static int stdio_get(FILE *file)
{
    (void) file;
    return EOF;
}

static FILE console = FDEV_SETUP_STREAM(stdio_put, stdio_get, NULL, _FDEV_SETUP_RW);
FILE *const stdin = &console;
FILE *const stdout = &console;
FILE *const stderr = &console;

/* ---- clock: the CLINT's mtime, or the time CSR that shadows it --------- */

static uint64_t clock_origin;

static inline uint64_t mtime(void)
{
#if COPROC_MTIME_ADDR
    return *(volatile uint64_t *) (uintptr_t) COPROC_MTIME_ADDR;
#else
    uint64_t now;
    __asm__ volatile("rdtime %0" : "=r"(now));
    return now;
#endif
}

void hw_clock_init(void)
{
    clock_origin = mtime();
}

uint64_t hw_now_us(void)
{
    uint64_t ticks = mtime() - clock_origin;
    return ticks / (COPROC_TIMEBASE_HZ / 1000000ULL);
}

#if COPROC_MTIMECMP_ADDR
static void set_mtimecmp(uint64_t value)
{
    // 32-bit halves (the T-Head CLINT has no 64-bit MMIO): high word first
    // set to all ones so no intermediate value lies in the past.
    volatile uint32_t *cmp = (volatile uint32_t *) (uintptr_t) COPROC_MTIMECMP_ADDR;
    cmp[1] = 0xffffffff;
    cmp[0] = (uint32_t) value;
    cmp[1] = (uint32_t) (value >> 32);
}
#endif

void hw_idle(uint64_t us)
{
#if COPROC_MTIMECMP_ADDR
    if (us == 0) {
        return;
    }
    // A pending, enabled interrupt ends wfi even with mstatus.MIE clear, so
    // no trap is taken: arm the timer, sleep, disarm.
    set_mtimecmp(mtime() + us * (COPROC_TIMEBASE_HZ / 1000000ULL));
    __asm__ volatile("csrs mie, %0" : : "r"(1UL << 7));
    __asm__ volatile("wfi");
    __asm__ volatile("csrc mie, %0" : : "r"(1UL << 7));
    set_mtimecmp(UINT64_MAX);
#else
    (void) us;
#endif
}

uint64_t hw_mhartid(void)
{
    uint64_t value;
    __asm__ volatile("csrr %0, mhartid" : "=r"(value));
    return value;
}

uint64_t hw_marchid(void)
{
    uint64_t value;
    __asm__ volatile("csrr %0, marchid" : "=r"(value));
    return value;
}

/* ---- heap: [__heap_start, __heap_end) in the reserved region ----------- */

extern char __heap_start[], __heap_end[];
static char *heap_brk = __heap_start;

void *sbrk(ptrdiff_t increment)
{
    if (increment > __heap_end - heap_brk || increment < __heap_start - heap_brk) {
        errno = ENOMEM;
        return (void *) -1;
    }
    char *previous = heap_brk;
    heap_brk += increment;
    return previous;
}

size_t hw_heap_used(void)
{
    return (size_t) (heap_brk - __heap_start);
}

size_t hw_heap_size(void)
{
    return (size_t) (__heap_end - __heap_start);
}

/* ---- time of day: there is no RTC, the epoch is the boot -------------- */

int gettimeofday(struct timeval *restrict tv, void *restrict tz)
{
    (void) tz;
    uint64_t now = hw_now_us();
    tv->tv_sec = (time_t) (now / 1000000);
    tv->tv_usec = (suseconds_t) (now % 1000000);
    return 0;
}

/* ---- process stubs: abort() and exit() end in a parked core ------------ */

pid_t getpid(void)
{
    return 1;
}

int kill(pid_t pid, int sig)
{
    (void) pid;
    fprintf(stderr, "elixos coproc: signal %d, parking\n", sig);
    for (;;) {
        __asm__ volatile("wfi");
    }
}

void _exit(int status)
{
    fprintf(stderr, "elixos coproc: exit %d, parking\n", status);
    for (;;) {
        __asm__ volatile("wfi");
    }
}

/* ---- start and traps (start.S) ----------------------------------------- */

extern char __tls_base[];
int main(void);
void __libc_init_array(void);
void coproc_start(void);
void coproc_trap(uint64_t mcause, uint64_t mepc, uint64_t mtval, uint64_t ra, uint64_t sp);

void coproc_start(void)
{
    _set_tls(__tls_base);
    __libc_init_array();
    exit(main());
}

void coproc_trap(uint64_t mcause, uint64_t mepc, uint64_t mtval, uint64_t ra, uint64_t sp)
{
    fprintf(stderr, "elixos coproc: trap mcause=0x%llx mepc=0x%llx mtval=0x%llx ra=0x%llx sp=0x%llx\n",
        (unsigned long long) mcause, (unsigned long long) mepc, (unsigned long long) mtval,
        (unsigned long long) ra, (unsigned long long) sp);
}

/* ---- libgcc gaps ----------------------------------------------------------
 *
 * Alpine's riscv-none-elf libgcc is built medlow: its __clzdi2 reaches its
 * table with lui, which cannot address an image above 2 GiB (QEMU virt runs
 * it at 0x80000000). This position-independent one replaces it.
 */
int __clzdi2(unsigned long value);
int __clzdi2(unsigned long value)
{
    int n = 0;
    for (unsigned long bit = 1UL << 63; bit && !(value & bit); bit >>= 1) {
        n++;
    }
    return n;
}
