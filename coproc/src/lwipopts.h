/*
 * Elixos coprocessor firmware: lwIP configuration (lwIP 2.2.1, raw API,
 * NO_SYS). One point-to-point netif over the §11 ring carrying bare IPv4
 * packets (the big side is a TUN device, IFF_NO_PI), plus loopback: AtomVM's
 * distribution registers with an epmd on 127.0.0.1. Memory comes from the
 * C heap (MEM_LIBC_MALLOC, MEMP_MEM_MALLOC). Socket options follow AtomVM's
 * rp2 lwipopts.h where otp_socket.c depends on them.
 */
#ifndef COPROC_LWIPOPTS_H
#define COPROC_LWIPOPTS_H

#define NO_SYS 1
#define SYS_LIGHTWEIGHT_PROT 0
#define LWIP_SOCKET 0
#define LWIP_NETCONN 0

#define MEM_LIBC_MALLOC 1
#define MEMP_MEM_MALLOC 1
#define MEM_ALIGNMENT 8

#define LWIP_IPV4 1
#define LWIP_IPV6 0
#define LWIP_ARP 0
#define LWIP_ETHERNET 0
#define LWIP_ICMP 1
#define LWIP_RAW 0
#define LWIP_UDP 1
#define LWIP_TCP 1
#define LWIP_DNS 1
#define LWIP_DHCP 0
#define LWIP_IGMP 1 /* otp_socket.c does not build without it */
#define LWIP_SINGLE_NETIF 0

/* The ring carries packets up to the TUN device's default MTU. */
#define TCP_MSS 1460
#define TCP_WND (32 * TCP_MSS)
#define TCP_SND_BUF (32 * TCP_MSS)
#define TCP_SND_QUEUELEN ((4 * (TCP_SND_BUF) + (TCP_MSS - 1)) / (TCP_MSS))
#define MEMP_NUM_TCP_SEG TCP_SND_QUEUELEN
#define MEMP_NUM_TCP_PCB 16
#define MEMP_NUM_TCP_PCB_LISTEN 8
#define MEMP_NUM_UDP_PCB 8
#define PBUF_POOL_SIZE 64
#define LWIP_TCP_KEEPALIVE 1
#define TCP_LISTEN_BACKLOG 1
#define SO_REUSE 1

#define LWIP_NETIF_LOOPBACK 1
#define LWIP_HAVE_LOOPIF 1
/*
 * Loopback output is queued and the loop interface polled through
 * tcpip_try_callback, which AtomVM's otp_socket.c implements on its event
 * queue (as on rp2): the next sys_poll_events delivers it.
 */
#define LWIP_NETIF_LOOPBACK_MULTITHREADING 1
struct netif;
void netif_poll(struct netif *netif);
typedef void (*tcpip_callback_fn)(void *ctx);
int tcpip_try_callback(tcpip_callback_fn function, void *ctx);

#define LWIP_CHKSUM_ALGORITHM 3
#define LWIP_STATS 0
#define LWIP_NETIF_STATUS_CALLBACK 0
#define LWIP_NETIF_LINK_CALLBACK 0

#define MEMP_NUM_SYS_TIMEOUT (LWIP_NUM_SYS_TIMEOUT_INTERNAL + 1)

#include <stdlib.h>
#define LWIP_RAND() ((u32_t) rand())

#endif
