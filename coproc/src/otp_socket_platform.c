/*
 * Elixos coprocessor firmware: the event queue between lwIP's callbacks and
 * AtomVM's otp_socket.c, after AtomVM's rp2 platform
 * (src/platforms/rp2/src/lib/otp_socket_platform.c, Apache-2.0 OR
 * LGPL-2.1-or-later).
 *
 * lwIP calls back from inside sys_poll_events (packet input, timers) or from
 * a NIF (loopback output); otp_socket.c never handles an event inside the
 * callback, it enqueues it. sys_poll_events drains the queue after every
 * lwIP call. Everything runs on the one scheduler thread, so the queue needs
 * no lock; it grows instead of dropping events, since a lost event leaves a
 * socket waiting forever.
 */
#include <stdlib.h>
#include <string.h>

#include <nifs.h>
#include <otp_socket.h>
#include <portnifloader.h>

#include "otp_socket_platform.h"

static struct LWIPEvent *queue;
static size_t capacity;
static size_t first;
static size_t count;

void otp_socket_lwip_enqueue(struct LWIPEvent *event)
{
    if (count == capacity) {
        size_t bigger = capacity ? capacity * 2 : 64;
        struct LWIPEvent *grown = malloc(bigger * sizeof(*grown));
        if (grown == NULL) {
            fprintf(stderr, "elixos coproc: out of memory queueing a socket event\n");
            abort();
        }
        for (size_t i = 0; i < count; i++) {
            grown[i] = queue[(first + i) % capacity];
        }
        free(queue);
        queue = grown;
        capacity = bigger;
        first = 0;
    }
    queue[(first + count) % capacity] = *event;
    count++;
}

bool otp_socket_platform_drain(void)
{
    bool ran = false;
    while (count > 0) {
        struct LWIPEvent event = queue[first];
        first = (first + 1) % capacity;
        count--;
        event.handler(&event);
        ran = true;
    }
    return ran;
}

REGISTER_NIF_COLLECTION(otp_socket, NULL, NULL, otp_socket_nif_get_nif)
