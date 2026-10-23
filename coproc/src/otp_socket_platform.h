/*
 * Elixos coprocessor firmware: what AtomVM's otp_socket.c (lwIP raw API
 * variant) needs from the platform. Modelled on AtomVM's rp2 platform
 * (src/platforms/rp2/src/lib/otp_socket_platform.h); lwIP runs NO_SYS on the
 * scheduler's own thread here, so it needs no lock.
 */
#ifndef COPROC_OTP_SOCKET_PLATFORM_H
#define COPROC_OTP_SOCKET_PLATFORM_H

#include <stdbool.h>
#include <stdio.h>

#include <lwip/err.h>
#include <lwip/opt.h> /* lwipopts.h: tcpip_callback_fn */

#define AVM_LOGD(tag, format, ...) ;

#define AVM_LOGI(tag, format, ...) \
    printf("I %s: " format " (%s:%i)\n", tag, ##__VA_ARGS__, __FILE__, __LINE__);

#define AVM_LOGW(tag, format, ...) \
    printf("W %s: " format " (%s:%i)\n", tag, ##__VA_ARGS__, __FILE__, __LINE__);

#define AVM_LOGE(tag, format, ...) \
    printf("E %s: " format " (%s:%i)\n", tag, ##__VA_ARGS__, __FILE__, __LINE__);

#define LWIP_BEGIN()
#define LWIP_END()

/* Runs every queued lwIP event (otp_socket_lwip_enqueue); true if any ran. */
bool otp_socket_platform_drain(void);

#endif
