/*
 * Elixos coprocessor firmware: lwIP over the §11 ring (docs/PROTOCOL.md).
 *
 * The little side reads ring A and writes ring B of the region at
 * COPROC_RING_OFFSET. It never initialises a ring: it waits until the big
 * core has (both magics valid), then opens them as a restarting side does
 * (reader: epoch + 1, tail = head; writer: epoch + 1, continue at head).
 * Each frame is one bare IPv4 packet; the netif is point-to-point, so there
 * is no link layer. A full outgoing ring drops the packet (TCP retransmits),
 * as elixos-link does on the other side.
 *
 * Configuration, from the payload's environment:
 *   ELIXOS_COPROC_ADDRESS  this side's address/prefix (default 10.0.3.9/24)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <lwip/init.h>
#include <lwip/ip4_addr.h>
#include <lwip/netif.h>
#include <lwip/pbuf.h>
#include <lwip/timeouts.h>

#include "board.h"
#include "coproc_sys.h"
#include "hw.h"
#include "otp_socket_platform.h"
#include "ring.h"

extern uint8_t __ring_start[];

static struct netif ring_netif;
static struct RingReader reader;
static struct RingWriter writer;
static uint8_t frame[RING_MAX_LEN];
static uint8_t outgoing[RING_MAX_LEN];

/* Frames taken per poll, so a flood cannot starve the scheduler. */
#define FRAMES_PER_POLL 64

u32_t sys_now(void)
{
    return (u32_t) (hw_now_us() / 1000);
}

static err_t ring_output(struct netif *netif, struct pbuf *p, const ip4_addr_t *ipaddr)
{
    (void) netif;
    (void) ipaddr;
    if (p->tot_len > ring_max_len(writer.capacity)) {
        return ERR_OK;
    }
    const uint8_t *bytes = p->payload;
    if (p->len != p->tot_len) {
        pbuf_copy_partial(p, outgoing, p->tot_len, 0);
        bytes = outgoing;
    }
    ring_write(&writer, bytes, p->tot_len);
    return ERR_OK;
}

static err_t ring_netif_init(struct netif *netif)
{
    netif->name[0] = 'r';
    netif->name[1] = 'g';
    netif->output = ring_output;
    netif->mtu = 1500;
    netif->flags = NETIF_FLAG_UP | NETIF_FLAG_LINK_UP;
    return ERR_OK;
}

static bool parse_address(const char *text, ip4_addr_t *address, ip4_addr_t *netmask)
{
    char copy[32];
    if (strlen(text) >= sizeof(copy)) {
        return false;
    }
    strcpy(copy, text);
    char *slash = strchr(copy, '/');
    unsigned prefix = 32;
    if (slash) {
        *slash = '\0';
        prefix = (unsigned) strtoul(slash + 1, NULL, 10);
    }
    if (prefix > 32 || !ip4addr_aton(copy, address)) {
        return false;
    }
    ip4_addr_set_u32(netmask, lwip_htonl(prefix ? 0xffffffffu << (32 - prefix) : 0));
    return true;
}

bool coproc_net_init(void)
{
    const char *config = getenv("ELIXOS_COPROC_ADDRESS");
    if (config == NULL) {
        config = "10.0.3.9/24";
    }
    ip4_addr_t address, netmask, gateway;
    if (!parse_address(config, &address, &netmask)) {
        printf("elixos coproc: bad ELIXOS_COPROC_ADDRESS %s\n", config);
        return false;
    }
    ip4_addr_set_zero(&gateway);

    struct RingHalf a = ring_half(__ring_start, COPROC_RING_SIZE, false);
    struct RingHalf b = ring_half(__ring_start, COPROC_RING_SIZE, true);
    if (!ring_valid(a) || !ring_valid(b)) {
        printf("elixos coproc: waiting for the big core to initialise the ring at %p (%u bytes)\n",
            (void *) __ring_start, (unsigned) COPROC_RING_SIZE);
        while (!ring_valid(a) || !ring_valid(b)) {
            hw_idle(1000);
        }
    }
    reader = ring_reader_open(a);
    writer = ring_writer_open(b);

    lwip_init();
    netif_add(&ring_netif, &address, &netmask, &gateway, NULL, ring_netif_init, netif_input);
    netif_set_default(&ring_netif);
    netif_set_up(&ring_netif);
    netif_set_link_up(&ring_netif);
    printf("elixos coproc: link up %s on the ring at %p (%u bytes, capacity %u)\n", config,
        (void *) __ring_start, (unsigned) COPROC_RING_SIZE, (unsigned) reader.capacity);
    return true;
}

bool coproc_net_poll(void)
{
    bool ran = otp_socket_platform_drain();
    for (int i = 0; i < FRAMES_PER_POLL; i++) {
        uint32_t seq, len;
        enum RingReadResult result = ring_read(&reader, frame, &seq, &len);
        if (result == RING_READ_EMPTY) {
            break;
        }
        if (result == RING_READ_DROPPED) {
            continue;
        }
        struct pbuf *p = pbuf_alloc(PBUF_RAW, (u16_t) len, PBUF_RAM);
        if (p == NULL) {
            continue;
        }
        pbuf_take(p, frame, (u16_t) len);
        if (ring_netif.input(p, &ring_netif) != ERR_OK) {
            pbuf_free(p);
        }
        ran |= otp_socket_platform_drain();
    }
    sys_check_timeouts();
    ran |= otp_socket_platform_drain();
    return ran;
}
