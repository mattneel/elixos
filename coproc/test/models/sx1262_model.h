/*
 * Test model of an SX1262 on SPI: the subset of the command set the
 * Elixos driver (coproc/src/lora_k230.c) and LilyGO's RadioLib build use,
 * with BUSY, DIO1, NRESET and the module's power switch.
 *
 * Every CS-framed command is recorded ("C 80 00"), as is every reset pulse
 * ("RESET"), so the command stream of two drivers can be compared. Opcodes,
 * the status byte layout and the IRQ bits are RadioLib's definitions
 * (SX126x.h of LilyGO's copy); the timings are the model's own (BUSY stays
 * high 5 us after a command, 3.5 ms after Calibrate, 1 ms after a reset).
 */
#ifndef SX1262_MODEL_H
#define SX1262_MODEL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SX_IRQ_TX_DONE 0x0001u
#define SX_IRQ_RX_DONE 0x0002u
#define SX_IRQ_HEADER_VALID 0x0010u
#define SX_IRQ_HEADER_ERR 0x0020u
#define SX_IRQ_CRC_ERR 0x0040u
#define SX_IRQ_TIMEOUT 0x0200u

/* Forgets everything; `now` is the clock BUSY timing runs on (us). */
void sx1262_model_init(uint64_t (*now)(void));
/* Wires the model to the GPIO model: NRESET IO5, power IO44 (listened),
 * BUSY IO19 and DIO1 IO20 (driven). */
void sx1262_model_wire_gpio(void);

void sx1262_model_power(int on);
void sx1262_model_nreset(int level);
/* CS asserted (1) or released (0): a command is the bytes in between. */
void sx1262_model_select(int asserted);
uint8_t sx1262_model_exchange(uint8_t mosi);
int sx1262_model_busy(void);
int sx1262_model_dio1(void);

/* A packet from the air, if the radio is receiving: RX_DONE (and
 * HEADER_VALID) as masked; GetPacketStatus answers the three bytes. */
void sx1262_model_receive(const uint8_t *packet, size_t len, uint8_t rssi_pkt, uint8_t snr_pkt, uint8_t signal_rssi);
/* A packet with a bad CRC. */
void sx1262_model_receive_crc_error(const uint8_t *packet, size_t len);
/* Ends a transmission: TX_DONE as masked; returns 0 if not transmitting. */
int sx1262_model_finish_tx(void);
/* The last transmitted packet's length and bytes. */
size_t sx1262_model_sent(uint8_t *packet);

/* 2 STBY_RC, 3 STBY_XOSC, 4 FS, 5 RX, 6 TX. */
int sx1262_model_mode(void);
uint8_t sx1262_model_register(uint16_t addr);
uint32_t sx1262_model_frequency(void);
uint16_t sx1262_model_irq(void);
size_t sx1262_model_commands(void);
/* A command's bytes (index from 0), NULL past the end. */
const uint8_t *sx1262_model_command(size_t index, size_t *len);

int sx1262_model_write_trace(const char *path);

#ifdef __cplusplus
}
#endif

#endif
