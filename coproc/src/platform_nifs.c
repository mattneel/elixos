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
 * (panel_k230.c; on QEMU virt panel_open/0 answers {error, no_panel}).
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
#include "panel_k230.h"

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
    if (UNLIKELY(memory_ensure_free(ctx, TUPLE_SIZE(2)) != MEMORY_GC_OK)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    term error = term_alloc_tuple(2, &ctx->heap);
    term_put_tuple_element(error, 0, ERROR_ATOM);
    term_put_tuple_element(error, 1, reason);
    return error;
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

static const struct Nif fb_read_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_fb_read };
static const struct Nif fb_write32_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_fb_write32 };
static const struct Nif panel_open_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_panel_open };
static const struct Nif panel_status_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_panel_status };

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
    return nif_collection_resolve_nif(nifname);
}

REGISTER_NIF_COLLECTION(otp_crypto, NULL, NULL, otp_crypto_nif_get_nif)
