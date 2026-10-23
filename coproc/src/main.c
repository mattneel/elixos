/*
 * Elixos coprocessor firmware: AtomVM on bare metal for the K230's little
 * core (M32; docs/notes/coproc-firmware.md).
 *
 * Boot: console, clock, the payload (environment, files, AVM packs), the
 * ring link, then AtomVM on the payload's first pack's start module (the
 * coprocessor runtime, os/src/elixos_coproc.erl). AtomVM has no halt: the
 * runtime ends its start function to restart on a new bundle (ADR-099), so
 * the firmware runs the VM again, as the Unix stand-in's launcher does. The
 * RAM file system, and with it the new bundle and the drivers' handoff,
 * survives the restart.
 */
#include <stdio.h>
#include <stdlib.h>

#include <avm_version.h>
#include <avmpack.h>
#include <context.h>
#include <globalcontext.h>
#include <iff.h>
#include <module.h>
#include <portnifloader.h>

#include "board.h"
#include "coproc_sys.h"
#include "hw.h"
#include "payload.h"

extern uint8_t __payload_start[], __payload_end[], __image_end[];

static void park(void)
{
    for (;;) {
        __asm__ volatile("wfi");
    }
}

static bool add_pack(GlobalContext *glb, const struct PayloadAVM *avm)
{
    if (!avmpack_is_valid(avm->data, (uint32_t) avm->size)) {
        printf("elixos coproc: %s is not an AVM pack\n", avm->name);
        return false;
    }
    struct ConstAVMPack *pack = malloc(sizeof(struct ConstAVMPack));
    if (pack == NULL) {
        return false;
    }
    avmpack_data_init(&pack->base, &const_avm_pack_info);
    pack->base.data = avm->data;
    pack->base.in_use = true;
    synclist_append(&glb->avmpack_data, &pack->base.avmpack_head);
    return true;
}

static int run_vm(const struct Payload *payload)
{
    GlobalContext *glb = globalcontext_new();
    if (glb == NULL) {
        printf("elixos coproc: cannot create the VM\n");
        return -1;
    }
    port_driver_init_all(glb);
    nif_collection_init_all(glb);

    for (int i = 0; i < payload->avm_count; i++) {
        if (!add_pack(glb, &payload->avms[i])) {
            return -1;
        }
    }

    const void *beam;
    uint32_t beam_size;
    const char *name;
    if (!avmpack_find_section_by_flag(payload->avms[0].data, BEAM_START_FLAG, BEAM_START_FLAG, &beam, &beam_size, &name)) {
        printf("elixos coproc: %s has no start module\n", payload->avms[0].name);
        return -1;
    }
    Module *mod = module_new_from_iff_binary(glb, beam, beam_size);
    if (mod == NULL) {
        printf("elixos coproc: cannot load %s\n", name);
        return -1;
    }
    globalcontext_insert_module(glb, mod);
    printf("elixos coproc: starting %s (heap %zu of %zu KiB used)\n", name, hw_heap_used() / 1024,
        hw_heap_size() / 1024);

    run_result_t result = globalcontext_run(glb, mod, stdout, 0, NULL);

    nif_collection_destroy_all(glb);
    port_driver_destroy_all(glb);
    globalcontext_destroy(glb);
    return (int) result;
}

int main(void)
{
    hw_console_init();
    hw_clock_init();
    printf("elixos coproc: AtomVM %s on %s, mhartid %llu, marchid 0x%llx, image %zu KiB\n",
        ATOMVM_VERSION, COPROC_BOARD, (unsigned long long) hw_mhartid(),
        (unsigned long long) hw_marchid(), (size_t) (__image_end - (uint8_t *) COPROC_LOAD_ADDR) / 1024);

    struct Payload payload;
    if (!payload_load(__payload_start, (size_t) (__payload_end - __payload_start), &payload)
        || payload.avm_count == 0) {
        printf("elixos coproc: no usable payload, parking\n");
        park();
    }
    printf("elixos coproc: payload %zu bytes, %d AVM packs\n", payload.size, payload.avm_count);

    if (!coproc_net_init()) {
        printf("elixos coproc: no network, parking\n");
        park();
    }

    for (unsigned run = 1;; run++) {
        int result = run_vm(&payload);
        printf("elixos coproc: VM run %u ended (%d), restarting\n", run, result);
        if (result < 0) {
            park();
        }
    }
}
