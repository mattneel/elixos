/*
 * Elixos coprocessor firmware: DesignWare I2C master (k230_i2c.h).
 *
 * LilyGO's RT-Smart I2C driver's register sequence (LT-RT =
 * Xinyuan-LilyGO/T-Display-K230_canmv_rt @ abb07090,
 * canmv_k230/src/rtsmart/rtsmart/kernel/bsp/maix3/drivers/interdrv/i2c/):
 *   drv_i2c.c 934-946      dw_i2c_init: IC_CON = SD | RE | FS | MM, both
 *                          FIFO thresholds 0, STOP_DET unmasked
 *   drv_i2c.c 462-545      the bus speed: fast mode, HCNT = IC_CLK x 600 ns,
 *                          LCNT = IC_CLK x 1300 ns (drv_i2c.h 178-187), no
 *                          SDA hold (the speed is set with no scl_sda_cfg)
 *   drv_i2c.c 117-137      enabling and disabling, polled 101 times
 *   drv_i2c.c 553-641      target address, bus-idle wait, the end of a read
 *   drv_i2c.c 656-695      a read: a command per byte, RESTART on the first
 *                          of a repeated-start message, STOP on the last
 *   drv_i2c.c 870-927      a write: STOP on the last byte of the last
 *                          message, then TX FIFO empty in 100 x 100 us
 *   drv_i2c.c 1070-1107    messages: START on the first, RESTART on the
 *                          others, STOP on the last
 * with its timeouts (drv_i2c.h 193-196: 4 ms a byte and for STOP_DET, 64 ms
 * for the bus) counted in 1 us waits. IC_CLK is the vendor's constant 100
 * MHz (drv_i2c.h 178-180); here it is the clock the CMU is programmed for,
 * which is what the vendor's commented-out sysctl_clk_get_leaf_freq call
 * (drv_i2c.c 1205) would give. Elixos addition: a TX abort (the target did
 * not acknowledge) ends the transfer with K230_I2C_NACK; the vendor's check
 * is commented out (drv_i2c.c 919-924) and it runs into its timeouts.
 */
#include "k230_i2c.h"
#include "k230_mmio.h"

#define IC_CON 0x00u
#define IC_TAR 0x04u
#define IC_DATA_CMD 0x10u
#define IC_FS_SCL_HCNT 0x1cu
#define IC_FS_SCL_LCNT 0x20u
#define IC_INTR_MASK 0x30u
#define IC_RAW_INTR_STAT 0x34u
#define IC_RX_TL 0x38u
#define IC_TX_TL 0x3cu
#define IC_CLR_TX_ABRT 0x54u
#define IC_CLR_STOP_DET 0x60u
#define IC_ENABLE 0x6cu
#define IC_STATUS 0x70u
#define IC_ENABLE_STATUS 0x9cu

#define IC_CON_SD 0x40u
#define IC_CON_RE 0x20u
#define IC_CON_SPD_MSK 0x06u
#define IC_CON_SPD_FS 0x04u
#define IC_CON_MM 0x01u
#define IC_CMD 0x100u
#define IC_STOP 0x200u
#define IC_RESTART 0x400u
#define IC_STOP_DET 0x200u
#define IC_TX_ABRT 0x40u
#define IC_STATUS_MA 0x20u
#define IC_STATUS_RFNE 0x08u
#define IC_STATUS_TFE 0x04u
#define IC_STATUS_TFNF 0x02u

#define MIN_FS_SCL_HIGHTIME 600u
#define MIN_FS_SCL_LOWTIME 1300u
#define BYTE_TIMEOUT_US 4000u
#define BUS_TIMEOUT_US (16u * BYTE_TIMEOUT_US)

static void wr(uintptr_t base, uintptr_t reg, uint32_t value)
{
    k230_mmio_write32(base + reg, value);
}

static uint32_t rd(uintptr_t base, uintptr_t reg)
{
    return k230_mmio_read32(base + reg);
}

static void enable(uintptr_t base, uint32_t on)
{
    for (int timeout = 100; timeout >= 0; timeout--) {
        wr(base, IC_ENABLE, on);
        if ((rd(base, IC_ENABLE_STATUS) & 1u) == on) {
            return;
        }
    }
}

void k230_i2c_init(uintptr_t base, uint64_t clk_hz)
{
    uint32_t ic_clk_mhz = (uint32_t) (clk_hz / 1000000u);

    enable(base, 0);
    wr(base, IC_CON, IC_CON_SD | IC_CON_RE | IC_CON_SPD_FS | IC_CON_MM);
    wr(base, IC_RX_TL, 0);
    wr(base, IC_TX_TL, 0);
    wr(base, IC_INTR_MASK, IC_STOP_DET);
    enable(base, 1);

    enable(base, 0);
    uint32_t con = (rd(base, IC_CON) & ~IC_CON_SPD_MSK) | IC_CON_SPD_FS;
    wr(base, IC_FS_SCL_HCNT, ic_clk_mhz * MIN_FS_SCL_HIGHTIME / 1000u);
    wr(base, IC_FS_SCL_LCNT, ic_clk_mhz * MIN_FS_SCL_LOWTIME / 1000u);
    wr(base, IC_CON, con);
    enable(base, 1);
}

static int aborted(uintptr_t base)
{
    if (rd(base, IC_RAW_INTR_STAT) & IC_TX_ABRT) {
        (void) rd(base, IC_CLR_TX_ABRT);
        return 1;
    }
    return 0;
}

static int wait_for_bus(uintptr_t base)
{
    for (uint32_t waited = 0;; waited++) {
        uint32_t status = rd(base, IC_STATUS);
        if (!(status & IC_STATUS_MA) && (status & IC_STATUS_TFE)) {
            return K230_I2C_OK;
        }
        if (waited >= BUS_TIMEOUT_US) {
            return K230_I2C_TIMEOUT;
        }
        k230_delay_us(1);
    }
}

static int start(uintptr_t base, uint8_t addr)
{
    if (wait_for_bus(base) != K230_I2C_OK) {
        return K230_I2C_TIMEOUT;
    }
    enable(base, 0);
    wr(base, IC_TAR, addr);
    enable(base, 1);
    return K230_I2C_OK;
}

static int write_message(uintptr_t base, uint8_t addr, const uint8_t *data, size_t len, int stop)
{
    if (start(base, addr) != K230_I2C_OK) {
        return K230_I2C_TIMEOUT;
    }
    uint32_t idle = 0;
    for (size_t i = 0; i < len;) {
        if (rd(base, IC_STATUS) & IC_STATUS_TFNF) {
            uint32_t cmd = data[i];
            if (i + 1 == len && stop) {
                cmd |= IC_STOP;
            }
            wr(base, IC_DATA_CMD, cmd);
            i++;
            idle = 0;
        } else if (++idle > len * BYTE_TIMEOUT_US) {
            return K230_I2C_TIMEOUT;
        } else {
            k230_delay_us(1);
        }
    }
    if (!stop) {
        return K230_I2C_OK;
    }
    for (int tries = 0; (rd(base, IC_STATUS) & IC_STATUS_TFE) == 0; tries++) {
        if (tries >= 100) {
            return K230_I2C_TIMEOUT;
        }
        k230_delay_us(100);
    }
    return aborted(base) ? K230_I2C_NACK : K230_I2C_OK;
}

static int finish(uintptr_t base)
{
    for (uint32_t waited = 0;; waited++) {
        if (rd(base, IC_RAW_INTR_STAT) & IC_STOP_DET) {
            (void) rd(base, IC_CLR_STOP_DET);
            break;
        }
        if (waited >= BYTE_TIMEOUT_US) {
            break;
        }
        k230_delay_us(1);
    }
    if (wait_for_bus(base) != K230_I2C_OK) {
        return K230_I2C_TIMEOUT;
    }
    while (rd(base, IC_STATUS) & IC_STATUS_RFNE) {
        (void) rd(base, IC_DATA_CMD);
    }
    return K230_I2C_OK;
}

/* The read message of a write-read: always after a write, so RESTART. */
static int read_message(uintptr_t base, uint8_t *data, size_t len)
{
    uint32_t restart = IC_RESTART;
    size_t sent = 0;
    size_t received = 0;
    uint32_t idle = 0;
    while (sent < len || received < len) {
        if (sent < len && (rd(base, IC_STATUS) & IC_STATUS_TFNF)) {
            uint32_t cmd = IC_CMD | restart;
            if (sent + 1 == len) {
                cmd |= IC_STOP;
            }
            wr(base, IC_DATA_CMD, cmd);
            restart = 0;
            sent++;
        }
        if (rd(base, IC_STATUS) & IC_STATUS_RFNE) {
            data[received++] = (uint8_t) rd(base, IC_DATA_CMD);
            idle = 0;
        } else if (aborted(base)) {
            (void) finish(base);
            return K230_I2C_NACK;
        } else if (++idle > BYTE_TIMEOUT_US) {
            return K230_I2C_TIMEOUT;
        } else {
            k230_delay_us(1);
        }
    }
    return finish(base);
}

int k230_i2c_write(uintptr_t base, uint8_t addr, const uint8_t *data, size_t len)
{
    return write_message(base, addr, data, len, 1);
}

int k230_i2c_write_read(uintptr_t base, uint8_t addr, const uint8_t *out, size_t out_len, uint8_t *in, size_t in_len)
{
    int result = write_message(base, addr, out, out_len, 0);
    if (result != K230_I2C_OK) {
        return result;
    }
    return read_message(base, in, in_len);
}
