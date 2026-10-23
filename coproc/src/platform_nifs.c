/*
 * Elixos coprocessor firmware: platform NIFs. atomvm:platform/0 answers
 * elixos_coproc; everything else (socket, net, crypto) comes from the NIF
 * collections registered in otp_*_platform.c.
 */
#include <string.h>

#include <defaultatoms.h>
#include <nifs.h>
#include <otp_crypto.h>
#include <platform_nifs.h>
#include <portnifloader.h>
#include <term.h>

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

const struct Nif *platform_nifs_get_nif(const char *nifname)
{
    if (strcmp("atomvm:platform/0", nifname) == 0) {
        return &atomvm_platform_nif;
    }
    return nif_collection_resolve_nif(nifname);
}

REGISTER_NIF_COLLECTION(otp_crypto, NULL, NULL, otp_crypto_nif_get_nif)
