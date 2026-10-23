/*
 * Elixos coprocessor firmware: platform NIFs. atomvm:platform/0 answers
 * elixos_coproc; everything else (socket, net, crypto) comes from the NIF
 * collections registered in otp_*_platform.c.
 *
 * The deck (M33, os/src/coproc_display_k230.erl) adds coproc_k230:
 *   fb_read(Offset, Length) -> binary     the §12 framebuffer region at
 *   fb_write32(Offset, Value) -> ok       COPROC_FB_ADDR (header and pixels)
 *   panel_open() -> ok | {error, no_panel | power_domain_timeout | dphy_timeout}
 *                                         brings the panel up; from then on
 *                                         the VO scans the region out itself
 *   panel_status(Pixels) -> ok | {error, not_open}
 *                                         the status band over rows 0-27
 *                                         (568 x 28 RGB565), <<>> removes it
 * (panel_k230.c; on QEMU virt panel_open/0 answers {error, no_panel}), and
 * the other board devices (os/src/coproc_*_k230.erl; on QEMU virt every
 * open answers {error, no_device}):
 *   touch_open() -> ok | {error, no_answer | confirm_failed | ...}
 *   touch_read() -> [{down | move | up, X, Y}] | {error, Reason}
 *                                         the GT9895 (touch_k230.c)
 *   lora_open(FrequencyHz) -> ok | {error, not_found | busy_timeout | ...}
 *   lora_send(Packet) -> ok | {error, busy | not_open | ...}
 *   lora_poll() -> none | sent | crc_error
 *                | {packet, Packet, RssiDbm, SnrQuarterDb} | {error, Reason}
 *                                         the SX1262 (lora_k230.c)
 *   power_open() -> ok | {error, no_device}
 *   power_poll() -> none | pressed | released | {error, Reason}
 *   power_off() -> {error, still_on | no_device}   (no return on success)
 *                                         the PMU (power_k230.c)
 *   console_read() -> Bytes               what UART3 received (hw.c)
 *   console_write(Bytes) -> ok            to UART3, as stdout
 */
#include <stdint.h>
#include <string.h>

#include <defaultatoms.h>
#include <nifs.h>
#include <otp_crypto.h>
#include <platform_nifs.h>
#include <portnifloader.h>
#include <term.h>

#include "board.h"
#include "hw.h"
#include "lora_k230.h"
#include "panel_k230.h"
#include "power_k230.h"
#include "touch_k230.h"

static term nif_atomvm_platform(Context *ctx, int argc, term argv[])
{
    (void) argc;
    (void) argv;
    return globalcontext_make_atom(ctx->global, ATOM_STR("\xd", "elixos_coproc"));
}

static const struct Nif atomvm_platform_nif = {
    .base.type = NIFFunctionType,
    .nif_ptr = nif_atomvm_platform
};

/* An offset and length inside the framebuffer region, or false. */
static bool fb_range(term offset, term length, uintptr_t *start, size_t *size)
{
    if (!term_is_integer(offset) || !term_is_integer(length)) {
        return false;
    }
    avm_int_t o = term_to_int(offset);
    avm_int_t n = term_to_int(length);
    if (o < 0 || n < 0 || (uintptr_t) o > (uintptr_t) COPROC_FB_SIZE
        || (uintptr_t) n > (uintptr_t) COPROC_FB_SIZE - (uintptr_t) o) {
        return false;
    }
    *start = (uintptr_t) COPROC_FB_ADDR + (uintptr_t) o;
    *size = (size_t) n;
    return true;
}

static term nif_fb_read(Context *ctx, int argc, term argv[])
{
    (void) argc;
    uintptr_t start;
    size_t size;
    if (!fb_range(argv[0], argv[1], &start, &size)) {
        RAISE_ERROR(BADARG_ATOM);
    }
    if (UNLIKELY(memory_ensure_free_opt(ctx, term_binary_heap_size(size), MEMORY_CAN_SHRINK) != MEMORY_GC_OK)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    /* The region is shared with the big core and must be read as it is now:
     * the copy goes through volatile word loads where aligned. */
    const volatile uint8_t *source = (const volatile uint8_t *) start;
    term binary = term_create_uninitialized_binary(size, &ctx->heap, ctx->global);
    uint8_t *target = (uint8_t *) term_binary_data(binary);
    for (size_t i = 0; i < size; i++) {
        target[i] = source[i];
    }
    return binary;
}

static term nif_fb_write32(Context *ctx, int argc, term argv[])
{
    (void) ctx;
    (void) argc;
    uintptr_t start;
    size_t size;
    if (!fb_range(argv[0], term_from_int(4), &start, &size) || (start & 3) != 0
        || !term_is_any_integer(argv[1])) {
        RAISE_ERROR(BADARG_ATOM);
    }
    avm_int64_t value = term_maybe_unbox_int64(argv[1]);
    if (value < 0 || value > (avm_int64_t) UINT32_MAX) {
        RAISE_ERROR(BADARG_ATOM);
    }
    __asm__ volatile("fence rw, w" ::: "memory");
    *(volatile uint32_t *) start = (uint32_t) value;
    return OK_ATOM;
}

static term make_atom(Context *ctx, const char *name)
{
    return globalcontext_make_atom(ctx->global, name);
}

/* {error, Reason}, or the badarg/out-of-memory exceptions. */
static term error_tuple(Context *ctx, term reason)
{
    if (UNLIKELY(memory_ensure_free(ctx, TUPLE_SIZE(2)) != MEMORY_GC_OK)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    term error = term_alloc_tuple(2, &ctx->heap);
    term_put_tuple_element(error, 0, ERROR_ATOM);
    term_put_tuple_element(error, 1, reason);
    return error;
}

static term panel_result(Context *ctx, int result)
{
    term reason;
    switch (result) {
        case PANEL_K230_OK:
            return OK_ATOM;
        case PANEL_K230_NO_PANEL:
            reason = globalcontext_make_atom(ctx->global, ATOM_STR("\x8", "no_panel"));
            break;
        case PANEL_K230_POWER_TIMEOUT:
            reason = globalcontext_make_atom(ctx->global, ATOM_STR("\x14", "power_domain_timeout"));
            break;
        case PANEL_K230_DPHY_TIMEOUT:
            reason = globalcontext_make_atom(ctx->global, ATOM_STR("\xc", "dphy_timeout"));
            break;
        case PANEL_K230_NOT_OPEN:
            reason = globalcontext_make_atom(ctx->global, ATOM_STR("\x8", "not_open"));
            break;
        default:
            RAISE_ERROR(BADARG_ATOM);
    }
    return error_tuple(ctx, reason);
}

static term nif_panel_open(Context *ctx, int argc, term argv[])
{
    (void) argc;
    (void) argv;
    return panel_result(ctx, panel_k230_open());
}

static term nif_panel_status(Context *ctx, int argc, term argv[])
{
    (void) argc;
    if (!term_is_binary(argv[0])) {
        RAISE_ERROR(BADARG_ATOM);
    }
    size_t size = term_binary_size(argv[0]);
    if (size != 0 && size != PANEL_K230_STATUS_BYTES) {
        RAISE_ERROR(BADARG_ATOM);
    }
    return panel_result(ctx, panel_k230_status(term_binary_data(argv[0]), size));
}

static term touch_result(Context *ctx, int result)
{
    switch (result) {
        case TOUCH_K230_OK: return OK_ATOM;
        case TOUCH_K230_NO_DEVICE: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x9", "no_device")));
        case TOUCH_K230_NO_ANSWER: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x9", "no_answer")));
        case TOUCH_K230_CONFIRM_FAILED: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\xe", "confirm_failed")));
        case TOUCH_K230_NOT_OPEN: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x8", "not_open")));
        case TOUCH_K230_BUS_ERROR: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x9", "bus_error")));
        default: RAISE_ERROR(BADARG_ATOM);
    }
}

static term nif_touch_open(Context *ctx, int argc, term argv[])
{
    (void) argc;
    (void) argv;
    return touch_result(ctx, touch_k230_open());
}

static term nif_touch_read(Context *ctx, int argc, term argv[])
{
    (void) argc;
    (void) argv;
    struct touch_k230_event event;
    int n = touch_k230_poll(&event);
    if (n < 0) {
        return touch_result(ctx, n);
    }
    if (n == 0) {
        return term_nil();
    }
    if (UNLIKELY(memory_ensure_free(ctx, TUPLE_SIZE(3) + CONS_SIZE) != MEMORY_GC_OK)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    term action;
    switch (event.action) {
        case TOUCH_K230_DOWN: action = make_atom(ctx, ATOM_STR("\x4", "down")); break;
        case TOUCH_K230_MOVE: action = make_atom(ctx, ATOM_STR("\x4", "move")); break;
        default: action = make_atom(ctx, ATOM_STR("\x2", "up")); break;
    }
    term touch = term_alloc_tuple(3, &ctx->heap);
    term_put_tuple_element(touch, 0, action);
    term_put_tuple_element(touch, 1, term_from_int(event.x));
    term_put_tuple_element(touch, 2, term_from_int(event.y));
    return term_list_prepend(touch, term_nil(), &ctx->heap);
}

static term lora_result(Context *ctx, int result)
{
    switch (result) {
        case LORA_K230_OK: return OK_ATOM;
        case LORA_K230_NO_DEVICE: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x9", "no_device")));
        case LORA_K230_NOT_FOUND: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x9", "not_found")));
        case LORA_K230_BUSY_TIMEOUT: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\xc", "busy_timeout")));
        case LORA_K230_SPI_TIMEOUT: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\xb", "spi_timeout")));
        case LORA_K230_FAILED: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x6", "failed")));
        case LORA_K230_NOT_OPEN: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x8", "not_open")));
        case LORA_K230_BUSY: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x4", "busy")));
        case LORA_K230_BADARG: return error_tuple(ctx, BADARG_ATOM);
        default: RAISE_ERROR(BADARG_ATOM);
    }
}

static term nif_lora_open(Context *ctx, int argc, term argv[])
{
    (void) argc;
    if (!term_is_integer(argv[0])) {
        RAISE_ERROR(BADARG_ATOM);
    }
    avm_int_t hz = term_to_int(argv[0]);
    if (hz < 0 || hz > (avm_int_t) UINT32_MAX) {
        RAISE_ERROR(BADARG_ATOM);
    }
    return lora_result(ctx, lora_k230_open((uint32_t) hz));
}

static term nif_lora_send(Context *ctx, int argc, term argv[])
{
    (void) argc;
    if (!term_is_binary(argv[0])) {
        RAISE_ERROR(BADARG_ATOM);
    }
    return lora_result(
        ctx, lora_k230_send((const uint8_t *) term_binary_data(argv[0]), term_binary_size(argv[0])));
}

static term nif_lora_poll(Context *ctx, int argc, term argv[])
{
    (void) argc;
    (void) argv;
    static struct lora_k230_event event;
    int result = lora_k230_poll(&event);
    if (result != LORA_K230_OK) {
        return lora_result(ctx, result);
    }
    switch (event.kind) {
        case LORA_K230_NOTHING: return make_atom(ctx, ATOM_STR("\x4", "none"));
        case LORA_K230_SENT: return make_atom(ctx, ATOM_STR("\x4", "sent"));
        case LORA_K230_CRC_ERROR: return make_atom(ctx, ATOM_STR("\x9", "crc_error"));
        default: break;
    }
    if (UNLIKELY(memory_ensure_free(ctx, TUPLE_SIZE(4) + term_binary_heap_size(event.len)) != MEMORY_GC_OK)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    term packet = term_from_literal_binary(event.data, event.len, &ctx->heap, ctx->global);
    term tuple = term_alloc_tuple(4, &ctx->heap);
    term_put_tuple_element(tuple, 0, make_atom(ctx, ATOM_STR("\x6", "packet")));
    term_put_tuple_element(tuple, 1, packet);
    /* RadioLib's getRSSI(true) and getSNR (SX126x.cpp 1326-1354). */
    term_put_tuple_element(tuple, 2, term_from_int(-(avm_int_t) (event.signal_rssi / 2)));
    term_put_tuple_element(tuple, 3, term_from_int(event.snr_pkt));
    return tuple;
}

static term power_result(Context *ctx, int result)
{
    switch (result) {
        case POWER_K230_OK: return OK_ATOM;
        case POWER_K230_NO_DEVICE: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x9", "no_device")));
        case POWER_K230_NOT_OPEN: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x8", "not_open")));
        case POWER_K230_STILL_ON: return error_tuple(ctx, make_atom(ctx, ATOM_STR("\x8", "still_on")));
        default: RAISE_ERROR(BADARG_ATOM);
    }
}

static term nif_power_open(Context *ctx, int argc, term argv[])
{
    (void) argc;
    (void) argv;
    return power_result(ctx, power_k230_open());
}

static term nif_power_poll(Context *ctx, int argc, term argv[])
{
    (void) argc;
    (void) argv;
    enum power_k230_key key;
    int result = power_k230_poll(&key);
    if (result < 0) {
        return power_result(ctx, result);
    }
    if (result == 0) {
        return make_atom(ctx, ATOM_STR("\x4", "none"));
    }
    return key == POWER_K230_PRESSED ? make_atom(ctx, ATOM_STR("\x7", "pressed"))
                                     : make_atom(ctx, ATOM_STR("\x8", "released"));
}

static term nif_power_off(Context *ctx, int argc, term argv[])
{
    (void) argc;
    (void) argv;
    return power_result(ctx, power_k230_off());
}

static term nif_console_read(Context *ctx, int argc, term argv[])
{
    (void) argc;
    (void) argv;
    char bytes[256];
    size_t n = hw_console_read(bytes, sizeof bytes);
    if (UNLIKELY(memory_ensure_free(ctx, term_binary_heap_size(n)) != MEMORY_GC_OK)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    return term_from_literal_binary(bytes, n, &ctx->heap, ctx->global);
}

static term nif_console_write(Context *ctx, int argc, term argv[])
{
    (void) ctx;
    (void) argc;
    if (!term_is_binary(argv[0])) {
        RAISE_ERROR(BADARG_ATOM);
    }
    hw_console_write(term_binary_data(argv[0]), term_binary_size(argv[0]));
    return OK_ATOM;
}

static const struct Nif fb_read_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_fb_read };
static const struct Nif fb_write32_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_fb_write32 };
static const struct Nif panel_open_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_panel_open };
static const struct Nif panel_status_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_panel_status };

/* The board devices, by name. */
static const struct {
    const char *name;
    struct Nif nif;
} device_nifs[] = {
    { "coproc_k230:touch_open/0", { .base.type = NIFFunctionType, .nif_ptr = nif_touch_open } },
    { "coproc_k230:touch_read/0", { .base.type = NIFFunctionType, .nif_ptr = nif_touch_read } },
    { "coproc_k230:lora_open/1", { .base.type = NIFFunctionType, .nif_ptr = nif_lora_open } },
    { "coproc_k230:lora_send/1", { .base.type = NIFFunctionType, .nif_ptr = nif_lora_send } },
    { "coproc_k230:lora_poll/0", { .base.type = NIFFunctionType, .nif_ptr = nif_lora_poll } },
    { "coproc_k230:power_open/0", { .base.type = NIFFunctionType, .nif_ptr = nif_power_open } },
    { "coproc_k230:power_poll/0", { .base.type = NIFFunctionType, .nif_ptr = nif_power_poll } },
    { "coproc_k230:power_off/0", { .base.type = NIFFunctionType, .nif_ptr = nif_power_off } },
    { "coproc_k230:console_read/0", { .base.type = NIFFunctionType, .nif_ptr = nif_console_read } },
    { "coproc_k230:console_write/1", { .base.type = NIFFunctionType, .nif_ptr = nif_console_write } },
};

const struct Nif *platform_nifs_get_nif(const char *nifname)
{
    if (strcmp("atomvm:platform/0", nifname) == 0) {
        return &atomvm_platform_nif;
    }
    if (strcmp("coproc_k230:fb_read/2", nifname) == 0) {
        return &fb_read_nif;
    }
    if (strcmp("coproc_k230:fb_write32/2", nifname) == 0) {
        return &fb_write32_nif;
    }
    if (strcmp("coproc_k230:panel_open/0", nifname) == 0) {
        return &panel_open_nif;
    }
    if (strcmp("coproc_k230:panel_status/1", nifname) == 0) {
        return &panel_status_nif;
    }
    for (size_t i = 0; i < sizeof device_nifs / sizeof device_nifs[0]; i++) {
        if (strcmp(device_nifs[i].name, nifname) == 0) {
            return &device_nifs[i].nif;
        }
    }
    return nif_collection_resolve_nif(nifname);
}

REGISTER_NIF_COLLECTION(otp_crypto, NULL, NULL, otp_crypto_nif_get_nif)
