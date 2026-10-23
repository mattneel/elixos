/*
 * Elixos coprocessor firmware: AtomVM's platform header (the bare-metal
 * counterpart of generic_unix_sys.h / rp2_sys.h).
 */
#ifndef COPROC_SYS_H
#define COPROC_SYS_H

#include <list.h>
#include <sys.h>

#include <mbedtls/ctr_drbg.h>
#include <mbedtls/entropy.h>

/*
 * Nothing in this platform produces listener events (no port drivers), but
 * sys.h's listener API is part of the platform contract.
 */
typedef void *listener_event_t;

struct EventListener
{
    struct ListHead listeners_list_head;
    event_handler_t handler;
    listener_event_t event;
};

struct CoprocPlatformData
{
    mbedtls_entropy_context entropy_ctx;
    mbedtls_ctr_drbg_context random_ctx;
    bool entropy_is_initialized;
    bool random_is_initialized;
};

/* Brings the network up (main.c, before the first VM); false if it cannot. */
bool coproc_net_init(void);

/* Polls the link and lwIP's timers; true if any lwIP event was handled. */
bool coproc_net_poll(void);

#endif
