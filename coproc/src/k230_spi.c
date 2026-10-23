/*
 * Elixos coprocessor firmware: DesignWare SSI master (k230_spi.h).
 *
 * The register setup is LilyGO's RT-Smart SPI driver's (LT-RT
 * canmv_k230/src/rtsmart/rtsmart/kernel/bsp/maix3/drivers/interdrv/spi/
 * drv_spi.c @ abb07090): kd_spi_setup_device 42-63 with the values
 * kd_spi_initialize 85-110 and drv_spi_configure 140-180 give LilyGO's
 * `spi1` (mode 0, 8-bit, chip select mask 0xF, RX sample delay 2, baud
 * divider = input clock / max_hz rounded up to even), and a transfer is
 * drv_spi_xfer's send-then-receive (184-347, 394-398): select, CTRLR1 =
 * frames - 1, enable, data, deselect, disable. The DW master drops chip
 * select when its TX FIFO runs empty (Canaan, kendryte/k230_sdk @ 7e302f73,
 * src/little/linux/drivers/spi/spi-dw-mmio-k230.c 58-61), so the data loop
 * is Canaan's Linux driver's (spi-dw-core-k230.c: the FIFO depth probed as
 * at 1371-1382, at most depth - TXFLR and depth - (sent - received) frames
 * written at a time as at 113-131, RXFLR frames read as at 133-140) instead
 * of drv_spi_xfer's write-everything-then-read, which assumes 256-entry
 * FIFOs.
 */
#include "k230_mmio.h"
#include "k230_spi.h"

#define CTRLR0 0x00u
#define CTRLR1 0x04u
#define SSIENR 0x08u
#define SER 0x10u
#define BAUDR 0x14u
#define TXFTLR 0x18u
#define RXFTLR 0x1cu
#define TXFLR 0x20u
#define RXFLR 0x24u
#define IMR 0x2cu
#define DR 0x60u
#define RX_SAMPLE_DELAY 0xf0u

/* drv_spi.c 54: (mode 0 << 8) | (standard frame format << 22) | (8 - 1). */
#define CTRLR0_MODE0_8BIT 0x07u
/* drv_spi.c 434: kd_spi_initialize(..., 0xf, 8). */
#define CHIP_SELECT_MASK 0xfu
#define IDLE_LIMIT_US 10000u

static void wr(struct k230_spi *spi, uintptr_t reg, uint32_t value)
{
    k230_mmio_write32(spi->base + reg, value);
}

static uint32_t rd(struct k230_spi *spi, uintptr_t reg)
{
    return k230_mmio_read32(spi->base + reg);
}

void k230_spi_init(struct k230_spi *spi, uintptr_t base, uint64_t clk_hz, uint32_t max_hz)
{
    spi->base = base;
    wr(spi, SSIENR, 0);

    /* spi-dw-core-k230.c 1371-1382. */
    unsigned fifo;
    for (fifo = 1; fifo < 256; fifo++) {
        wr(spi, TXFTLR, fifo);
        if (fifo != rd(spi, TXFTLR)) {
            break;
        }
    }
    wr(spi, TXFTLR, 0);
    spi->fifo = fifo == 1 ? 0 : fifo;

    /* drv_spi.c 153-155. */
    uint32_t div = (uint32_t) (clk_hz / max_hz);
    if (div & 1) {
        div++;
    }
    /* drv_spi.c 45-60. */
    wr(spi, BAUDR, div);
    wr(spi, RX_SAMPLE_DELAY, 2);
    wr(spi, IMR, 0);
    wr(spi, SER, 0);
    wr(spi, SSIENR, 0);
    wr(spi, CTRLR0, CTRLR0_MODE0_8BIT);
    wr(spi, TXFTLR, 0);
    wr(spi, RXFTLR, 128);
}

int k230_spi_transfer(struct k230_spi *spi, const uint8_t *tx, uint8_t *rx, size_t len)
{
    if (len == 0) {
        return K230_SPI_OK;
    }
    if (spi->fifo == 0) {
        return K230_SPI_TIMEOUT;
    }
    wr(spi, SER, CHIP_SELECT_MASK);
    wr(spi, CTRLR1, (uint32_t) (len - 1));
    wr(spi, SSIENR, 1);

    size_t sent = 0;
    size_t received = 0;
    uint32_t idle = 0;
    int result = K230_SPI_OK;
    while (received < len) {
        size_t moved = 0;
        if (sent < len) {
            size_t room = spi->fifo - rd(spi, TXFLR);
            size_t gap = spi->fifo - (sent - received);
            size_t n = room < gap ? room : gap;
            if (n > len - sent) {
                n = len - sent;
            }
            for (size_t i = 0; i < n; i++) {
                wr(spi, DR, tx[sent++]);
            }
            moved += n;
        }
        size_t n = rd(spi, RXFLR);
        if (n > len - received) {
            n = len - received;
        }
        for (size_t i = 0; i < n; i++) {
            rx[received++] = (uint8_t) rd(spi, DR);
        }
        moved += n;
        if (moved) {
            idle = 0;
        } else if (++idle > IDLE_LIMIT_US) {
            result = K230_SPI_TIMEOUT;
            break;
        } else {
            k230_delay_us(1);
        }
    }

    /* drv_spi.c 394-398. */
    wr(spi, SER, 0);
    wr(spi, SSIENR, 0);
    return result;
}
