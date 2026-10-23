/*
 * Elixos coprocessor firmware: the SX1262 LoRa module of the T-Display K230
 * on QSPI0 (lora_k230.c, docs/notes/coproc-firmware.md "Board drivers").
 */
#ifndef LORA_K230_H
#define LORA_K230_H

#include <stddef.h>
#include <stdint.h>

#define LORA_K230_OK 0
/* Built without the board's devices (COPROC_K230_DEVICES=0: QEMU virt). */
#define LORA_K230_NO_DEVICE (-1)
/* The version register does not read "SX1261" (LilyGO's SX1262 string). */
#define LORA_K230_NOT_FOUND (-2)
/* BUSY stayed high for 1 s. */
#define LORA_K230_BUSY_TIMEOUT (-3)
/* The SPI controller's FIFOs stopped moving. */
#define LORA_K230_SPI_TIMEOUT (-4)
/* The radio answered a command with a failure status. */
#define LORA_K230_FAILED (-5)
/* lora_k230_send/poll before a successful lora_k230_open. */
#define LORA_K230_NOT_OPEN (-6)
/* A transmission is still on the air. */
#define LORA_K230_BUSY (-7)
/* Frequency outside 150-960 MHz, or a packet of 0 or more than 255 bytes. */
#define LORA_K230_BADARG (-8)

#define LORA_K230_MAX_PACKET 255

enum lora_k230_event_kind {
    LORA_K230_NOTHING = 0,
    LORA_K230_PACKET = 1, /* data/len, rssi_pkt, snr_pkt */
    LORA_K230_SENT = 2, /* the transmission ended; receiving again */
    LORA_K230_CRC_ERROR = 3, /* a packet with a bad CRC or header, dropped */
};

struct lora_k230_event {
    enum lora_k230_event_kind kind;
    size_t len;
    uint8_t data[LORA_K230_MAX_PACKET];
    /* GetPacketStatus as RadioLib reads it: RSSI = -signal_rssi / 2 dBm,
     * SNR = snr_pkt (signed) / 4 dB. */
    uint8_t signal_rssi;
    int8_t snr_pkt;
};

/*
 * Powers the module, brings the SPI controller and the radio up with
 * LilyGO's SX1262 configuration on `freq_hz` and starts receiving
 * (continuously). Once open, a call with the same frequency returns at once
 * and the radio keeps receiving; another frequency sets the radio up again.
 */
int lora_k230_open(uint32_t freq_hz);

/* Starts transmitting `packet`; lora_k230_poll reports LORA_K230_SENT when
 * it is out, after which the radio receives again. */
int lora_k230_send(const uint8_t *packet, size_t len);

/* What happened since the last poll: reads DIO1 and only talks to the radio
 * when it is raised. Returns LORA_K230_OK or an error. */
int lora_k230_poll(struct lora_k230_event *event);

#endif
