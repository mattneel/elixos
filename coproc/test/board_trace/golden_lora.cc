/*
 * The LoRa golden trace: LilyGO's RadioLib build (LT-RT lora_lib, pinned by
 * sha256 in vendor.lock) compiled on the build host against the SX1262
 * model (coproc/test/models/sx1262_model.c) through a host RadioLibHal, and
 * driven exactly as LilyGO's phone app drives the SX1262 (Lora.cpp, the
 * USING_SX1262 branches):
 *   Lora.cpp 669-676   IO44 (the module's LDO) high
 *   Lora.cpp 788-805   begin(915, 125, 10, 6, 0x12, 22, 16, 3.3, false),
 *                      setCRC(false); Module(14, NC, 5, 19) at 43
 *   Lora.cpp 286-317   startReceive(640000, RX_DEFAULT, RX_DONE | TIMEOUT |
 *                      HEADER_VALID, 0), a packet, getIrqStatus, readData,
 *                      getSNR, getRSSI(true)
 *   Lora.cpp 117-130   startTransmit, the packet sent, getIrqStatus
 *
 *   golden_lora <trace-file>
 *
 * The trace is the model's: every CS-framed command and reset pulse. The
 * decoded results go to stdout for board_k230_test.c to compare with.
 */
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "modules/SX126x/SX1262.h"
#include "k230Hal.h"

extern "C" {
#include "sx1262_model.h"
}

static uint64_t clock_us;

static uint64_t now(void)
{
    return clock_us;
}

class HostHal : public RadioLibHal {
  public:
    HostHal() : RadioLibHal(0, 1, 0, 1, 1, 2) {}
    void pinMode(uint32_t, uint32_t) override {}
    void digitalWrite(uint32_t pin, uint32_t value) override
    {
        if (pin == 14) {
            sx1262_model_select(value == 0);
        } else if (pin == 5) {
            sx1262_model_nreset(value != 0);
        }
    }
    uint32_t digitalRead(uint32_t pin) override
    {
        if (pin == 19) {
            return sx1262_model_busy();
        }
        if (pin == 20) {
            return sx1262_model_dio1();
        }
        return 0;
    }
    void attachInterrupt(uint32_t, void (*)(void), uint32_t) override {}
    void detachInterrupt(uint32_t) override {}
    void delay(RadioLibTime_t ms) override { clock_us += ms * 1000; }
    void delayMicroseconds(RadioLibTime_t us) override { clock_us += us; }
    RadioLibTime_t millis() override { return clock_us / 1000; }
    RadioLibTime_t micros() override { return clock_us; }
    long pulseIn(uint32_t, uint32_t, RadioLibTime_t) override { return 0; }
    void spiBegin() override {}
    void spiBeginTransaction() override {}
    void spiTransfer(uint8_t *out, size_t len, uint8_t *in) override
    {
        for (size_t i = 0; i < len; i++) {
            in[i] = sx1262_model_exchange(out[i]);
        }
    }
    void spiEndTransaction() override {}
    void spiEnd() override {}
    /* k230Hal::yield() busy-waits 1 ms (k230Hal.cpp 385-391). */
    void yield() override { clock_us += 1000; }
};

/* Module.cpp's default constructor names LilyGO's RT-Smart HAL; this test
 * only uses the one that takes a HAL. */
k230Hal::k230Hal() : RadioLibHal(0, 1, 0, 1, 1, 2) { std::abort(); }
void k230Hal::pinMode(uint32_t, uint32_t) { std::abort(); }
void k230Hal::digitalWrite(uint32_t, uint32_t) { std::abort(); }
uint32_t k230Hal::digitalRead(uint32_t) { std::abort(); }
void k230Hal::attachInterrupt(uint32_t, void (*)(void), uint32_t) { std::abort(); }
void k230Hal::detachInterrupt(uint32_t) { std::abort(); }
void k230Hal::delay(RadioLibTime_t) { std::abort(); }
void k230Hal::delayMicroseconds(RadioLibTime_t) { std::abort(); }
RadioLibTime_t k230Hal::millis() { std::abort(); }
RadioLibTime_t k230Hal::micros() { std::abort(); }
long k230Hal::pulseIn(uint32_t, uint32_t, RadioLibTime_t) { std::abort(); }
void k230Hal::spiBegin() { std::abort(); }
void k230Hal::spiBeginTransaction() { std::abort(); }
void k230Hal::spiTransfer(uint8_t *, size_t, uint8_t *) { std::abort(); }
void k230Hal::spiEndTransaction() { std::abort(); }
void k230Hal::spiEnd() { std::abort(); }
void k230Hal::init() { std::abort(); }
void k230Hal::term() { std::abort(); }
void k230Hal::tone(uint32_t, unsigned int, RadioLibTime_t) { std::abort(); }
void k230Hal::noTone(uint32_t) { std::abort(); }
void k230Hal::yield() { std::abort(); }
uint32_t k230Hal::pinToInterrupt(uint32_t) { std::abort(); }

int main(int argc, char **argv)
{
    if (argc != 2) {
        std::fprintf(stderr, "usage: golden_lora <trace-file>\n");
        return 2;
    }
    sx1262_model_init(now);
    sx1262_model_power(1);

    HostHal hal;
    Module module(&hal, 14, RADIOLIB_NC, 5, 19);
    SX1262 radio(&module);

    int state = radio.begin(915, 125, 10, 6, 0x12, 22, 16, 3.3, false);
    int crc = radio.setCRC(false);
    std::printf("golden lora: begin %d setCRC %d\n", state, crc);

    state = radio.startReceive(640000, RADIOLIB_SX126X_IRQ_RX_DEFAULT,
                               RADIOLIB_SX126X_IRQ_RX_DONE | RADIOLIB_SX126X_IRQ_TIMEOUT
                                   | RADIOLIB_SX126X_IRQ_HEADER_VALID,
                               0);
    static const uint8_t hello[] = "hello, deck";
    /* RssiPkt 0x50, SnrPkt 0x1c (7 dB), SignalRssiPkt 0x52. */
    sx1262_model_receive(hello, sizeof hello - 1, 0x50, 0x1c, 0x52);
    unsigned irq = radio.getIrqStatus();
    uint8_t data[20] = {0};
    int read = radio.readData(data, 20);
    float snr = radio.getSNR();
    float rssi = radio.getRSSI(true);
    std::printf("golden lora: startReceive %d irq 0x%04x readData %d packet \"%s\" snr %.2f rssi %.1f\n", state, irq,
                read, data, snr, rssi);

    static const uint8_t ping[] = "ping";
    state = radio.startTransmit((uint8_t *) ping, 4);
    sx1262_model_finish_tx();
    irq = radio.getIrqStatus();
    uint8_t sent[256];
    size_t sent_len = sx1262_model_sent(sent);
    std::printf("golden lora: startTransmit %d irq 0x%04x sent %zu \"%.*s\"\n", state, irq, sent_len, (int) sent_len,
                (const char *) sent);

    return sx1262_model_write_trace(argv[1]) == 0 ? 0 : 1;
}
