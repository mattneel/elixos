/*
 * Elixos coprocessor firmware: AtomVM's sys_* platform interface on bare
 * metal (single scheduler, AVM_NO_SMP; see docs/notes/coproc-firmware.md).
 * Structure after AtomVM's rp2 and stm32 platforms.
 */
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <avmpack.h>
#include <defaultatoms.h>
#include <globalcontext.h>
#include <otp_socket.h>
#include <portnifloader.h>
#include <sys_mbedtls.h>
#include <mbedtls/platform_time.h>
#include <utils.h>

#include "coproc_sys.h"
#include "hw.h"
#include "otp_socket_platform.h"

void sys_init_platform(GlobalContext *glb)
{
    struct CoprocPlatformData *platform = calloc(1, sizeof(struct CoprocPlatformData));
    if (IS_NULL_PTR(platform)) {
        AVM_ABORT();
    }
    glb->platform_data = platform;
    otp_socket_init(glb);
}

void sys_free_platform(GlobalContext *glb)
{
    struct CoprocPlatformData *platform = glb->platform_data;
    if (platform->random_is_initialized) {
        mbedtls_ctr_drbg_free(&platform->random_ctx);
    }
    if (platform->entropy_is_initialized) {
        mbedtls_entropy_free(&platform->entropy_ctx);
    }
    free(platform);
    glb->platform_data = NULL;
}

/*
 * The scheduler calls this between time slices (timeout 0) and when every
 * process waits (until its next timer, or forever). Network work wakes it:
 * any lwIP event handled may have made a process ready, so it returns. While
 * waiting it checks the incoming ring at least every millisecond (§11).
 */
void sys_poll_events(GlobalContext *glb, int timeout_ms)
{
    UNUSED(glb);
    uint64_t start = hw_now_us();
    uint64_t limit = timeout_ms > 0 ? (uint64_t) timeout_ms * 1000 : 0;
    for (;;) {
        if (coproc_net_poll() || timeout_ms == SYS_POLL_EVENTS_DO_NOT_WAIT) {
            return;
        }
        uint64_t slice = 1000;
        if (timeout_ms > 0) {
            uint64_t elapsed = hw_now_us() - start;
            if (elapsed >= limit) {
                return;
            }
            if (limit - elapsed < slice) {
                slice = limit - elapsed;
            }
        }
        hw_idle(slice);
    }
}

void sys_register_select_event(GlobalContext *global, ErlNifEvent event, bool is_write)
{
    UNUSED(global);
    UNUSED(event);
    UNUSED(is_write);
}

void sys_unregister_select_event(GlobalContext *global, ErlNifEvent event, bool is_write)
{
    UNUSED(global);
    UNUSED(event);
    UNUSED(is_write);
}

void sys_register_listener(GlobalContext *global, struct EventListener *listener)
{
    struct ListHead *listeners = synclist_wrlock(&global->listeners);
    list_append(listeners, &listener->listeners_list_head);
    synclist_unlock(&global->listeners);
}

void sys_unregister_listener(GlobalContext *global, struct EventListener *listener)
{
    struct ListHead *listeners = synclist_wrlock(&global->listeners);
    UNUSED(listeners);
    list_remove(&listener->listeners_list_head);
    synclist_unlock(&global->listeners);
}

void sys_listener_destroy(struct ListHead *item)
{
    free(GET_LIST_ENTRY(item, EventListener, listeners_list_head));
}

/* There is no RTC: the wall clock starts at the epoch on boot. */
void sys_time(struct timespec *t)
{
    sys_monotonic_time(t);
}

void sys_monotonic_time(struct timespec *t)
{
    uint64_t us = hw_now_us();
    t->tv_sec = (time_t) (us / 1000000);
    t->tv_nsec = (long) ((us % 1000000) * 1000);
}

uint64_t sys_monotonic_time_u64(void)
{
    return hw_now_us();
}

uint64_t sys_monotonic_time_ms_to_u64(uint64_t ms)
{
    return ms * 1000;
}

uint64_t sys_monotonic_time_u64_to_ms(uint64_t t)
{
    return t / 1000;
}

enum OpenAVMResult sys_open_avm_from_file(GlobalContext *global, const char *path, struct AVMPackData **data)
{
    UNUSED(global);
    UNUSED(path);
    UNUSED(data);
    return AVM_OPEN_NOT_SUPPORTED;
}

Module *sys_load_module_from_file(GlobalContext *global, const char *path)
{
    UNUSED(global);
    UNUSED(path);
    return NULL;
}

Context *sys_create_port(GlobalContext *glb, const char *driver_name, term opts)
{
    return port_driver_create_port(driver_name, glb, opts);
}

/*
 * erlang:system_info(coproc_heap): {Used, Size} of the malloc arena in bytes,
 * Used being sbrk's high-water mark (picolibc's malloc never shrinks it).
 */
term sys_get_info(Context *ctx, term key)
{
    if (key != globalcontext_make_atom(ctx->global, ATOM_STR("\xb", "coproc_heap"))) {
        return UNDEFINED_ATOM;
    }
    if (memory_ensure_free(ctx, TUPLE_SIZE(2) + 2 * BOXED_INT64_SIZE) != MEMORY_GC_OK) {
        return OUT_OF_MEMORY_ATOM;
    }
    term info = term_alloc_tuple(2, &ctx->heap);
    term_put_tuple_element(info, 0, term_make_maybe_boxed_int64((int64_t) hw_heap_used(), &ctx->heap));
    term_put_tuple_element(info, 1, term_make_maybe_boxed_int64((int64_t) hw_heap_size(), &ctx->heap));
    return info;
}

/* ---- entropy for crypto:strong_rand_bytes/1 and the dist challenge ----
 *
 * There is no verified hardware RNG on the little core (the K230's TRNG is
 * not mapped or characterised here). The pool takes the low bits of the
 * cycle and time counters around variable work, plus ELIXOS_COPROC_SEED
 * from the payload (hex, fresh per payload). Weak by construction; see
 * docs/notes/coproc-firmware.md.
 */
static int jitter_source(void *data, unsigned char *output, size_t len, size_t *olen)
{
    UNUSED(data);
    for (size_t i = 0; i < len; i++) {
        uint64_t cycles, time;
        __asm__ volatile("csrr %0, mcycle" : "=r"(cycles));
        __asm__ volatile("rdtime %0" : "=r"(time));
        volatile unsigned spin = (unsigned) (cycles ^ time) & 0x3f;
        while (spin--) {
        }
        output[i] = (unsigned char) (cycles ^ (cycles >> 8) ^ time ^ (time >> 8));
    }
    *olen = len;
    return 0;
}

static void add_payload_seed(mbedtls_entropy_context *ctx)
{
    const char *seed = getenv("ELIXOS_COPROC_SEED");
    if (seed == NULL) {
        return;
    }
    unsigned char bytes[64];
    size_t n = 0;
    for (; n < sizeof(bytes) && seed[2 * n] && seed[2 * n + 1]; n++) {
        char pair[3] = { seed[2 * n], seed[2 * n + 1], '\0' };
        bytes[n] = (unsigned char) strtoul(pair, NULL, 16);
    }
    mbedtls_entropy_update_manual(ctx, bytes, n);
}

int sys_mbedtls_entropy_func(void *entropy, unsigned char *buf, size_t size)
{
    return mbedtls_entropy_func(entropy, buf, size);
}

mbedtls_entropy_context *sys_mbedtls_get_entropy_context_lock(GlobalContext *global)
{
    struct CoprocPlatformData *platform = global->platform_data;
    if (!platform->entropy_is_initialized) {
        mbedtls_entropy_init(&platform->entropy_ctx);
        mbedtls_entropy_add_source(&platform->entropy_ctx, jitter_source, NULL, 32, MBEDTLS_ENTROPY_SOURCE_STRONG);
        add_payload_seed(&platform->entropy_ctx);
        platform->entropy_is_initialized = true;
    }
    return &platform->entropy_ctx;
}

void sys_mbedtls_entropy_context_unlock(GlobalContext *global)
{
    UNUSED(global);
}

mbedtls_ctr_drbg_context *sys_mbedtls_get_ctr_drbg_context_lock(GlobalContext *global)
{
    struct CoprocPlatformData *platform = global->platform_data;
    if (!platform->random_is_initialized) {
        mbedtls_ctr_drbg_init(&platform->random_ctx);
        mbedtls_entropy_context *entropy_ctx = sys_mbedtls_get_entropy_context_lock(global);
        static const char personalization[] = "elixos coprocessor";
        if (mbedtls_ctr_drbg_seed(&platform->random_ctx, sys_mbedtls_entropy_func, entropy_ctx,
                (const unsigned char *) personalization, sizeof(personalization) - 1)
            != 0) {
            AVM_ABORT();
        }
        platform->random_is_initialized = true;
    }
    return &platform->random_ctx;
}

void sys_mbedtls_ctr_drbg_context_unlock(GlobalContext *global)
{
    UNUSED(global);
}

/* MBEDTLS_PLATFORM_MS_TIME_ALT: milliseconds since boot. */
mbedtls_ms_time_t mbedtls_ms_time(void)
{
    return (mbedtls_ms_time_t) (hw_now_us() / 1000);
}

/* defaultatoms.c calls it; this platform has no atoms of its own. */
void platform_defaultatoms_init(GlobalContext *glb)
{
    UNUSED(glb);
}
